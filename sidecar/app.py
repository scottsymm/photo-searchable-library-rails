"""Stateless ML inference sidecar. Owns model weights only."""
from __future__ import annotations

import base64
from collections import deque
import io
import math
import os
from typing import Annotated

import reverse_geocoder
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image
from pillow_heif import register_heif_opener

register_heif_opener()
from pydantic import BaseModel, Field, field_validator, model_validator

from .models import ClipEmbedder, StubEmbedder

MODEL_NAME = os.getenv("PICS_MODEL", "openai/clip-vit-base-patch32")
MODEL_VERSION = os.getenv("PICS_MODEL_VERSION", "clip-vit-base-patch32-v1")
SIDECAR_MODE = os.getenv("PICS_SIDECAR_MODE", "real")
MAX_UPLOAD_BYTES = int(os.getenv("PICS_MAX_UPLOAD_BYTES", 10 * 1024 * 1024))
MAX_IMAGE_DIMENSION = int(os.getenv("PICS_MAX_IMAGE_DIMENSION", 10_000))
MAX_IMAGE_PIXELS = int(os.getenv("PICS_MAX_IMAGE_PIXELS", 25_000_000))
MAX_CLUSTER_VECTORS = int(os.getenv("PICS_MAX_CLUSTER_VECTORS", 1_000))
MAX_CLUSTER_REQUEST_BYTES = int(os.getenv("PICS_MAX_CLUSTER_REQUEST_BYTES", 16 * 1024 * 1024))

app = FastAPI(title="pics-sidecar")
embedder: ClipEmbedder | StubEmbedder | None = None
face_analysis = None
FACE_READY = SIDECAR_MODE == "stub"


@app.middleware("http")
async def reject_oversized_upload(request: Request, call_next):
    if request.method == "POST" and request.url.path in { "/v1/detect-faces", "/v1/cluster-faces" }:
        content_length = request.headers.get("content-length")
        if content_length is not None:
            try:
                request_size = int(content_length)
            except ValueError:
                return JSONResponse({"detail": "invalid_content_length"}, status_code=400)
            limit = MAX_UPLOAD_BYTES if request.url.path == "/v1/detect-faces" else MAX_CLUSTER_REQUEST_BYTES
            if request_size > limit:
                return JSONResponse({"detail": "upload_too_large"}, status_code=413)
    return await call_next(request)


class ClusterRequest(BaseModel):
    embeddings: list[list[float]]
    eps: float = Field(default=0.35, gt=0)
    min_samples: int = Field(default=2, ge=1)

    @field_validator("embeddings")
    @classmethod
    def valid_embeddings(cls, value: list[list[float]]) -> list[list[float]]:
        if len(value) > MAX_CLUSTER_VECTORS:
            raise ValueError(f"at most {MAX_CLUSTER_VECTORS} embeddings are allowed")
        if any(len(vector) != 512 for vector in value):
            raise ValueError("every embedding must contain 512 floats")
        return value


class ClusterResponse(BaseModel):
    labels: list[int]

    @model_validator(mode="after")
    def labels_are_integers(self) -> "ClusterResponse":
        return self


class TextRequest(BaseModel):
    texts: list[str]


class ImageRequest(BaseModel):
    image_base64: str
    mime: str = "image/jpeg"


class GeoRequest(BaseModel):
    lat: float
    lon: float


@app.on_event("startup")
def load_model() -> None:
    global embedder
    if embedder is None:
        embedder = StubEmbedder() if SIDECAR_MODE == "stub" else ClipEmbedder(MODEL_NAME)


@app.get("/v1/status")
def status() -> dict:
    return {
        "ok": embedder is not None,
        "mode": SIDECAR_MODE,
        "model": MODEL_NAME if SIDECAR_MODE != "stub" else "stub",
        "version": MODEL_VERSION if SIDECAR_MODE != "stub" else "stub-v1",
        "faces": {"ready": FACE_READY, "mode": SIDECAR_MODE},
    }


def _cosine_distance(left: list[float], right: list[float]) -> float:
    product = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    return 1.0 - product / (left_norm * right_norm) if left_norm and right_norm else 1.0


def _cluster(embeddings: list[list[float]], eps: float, min_samples: int) -> list[int]:
    labels = [-2] * len(embeddings)
    cluster = 0

    def neighbors(index: int) -> list[int]:
        return [other for other in range(len(embeddings)) if _cosine_distance(embeddings[index], embeddings[other]) <= eps]

    for index in range(len(embeddings)):
        if labels[index] != -2:
            continue
        nearby = neighbors(index)
        if len(nearby) < min_samples:
            labels[index] = -1
            continue
        labels[index] = cluster
        queue = deque(nearby)
        queued = set(nearby)
        while queue:
            current = queue.popleft()
            if labels[current] == -1:
                labels[current] = cluster
            if labels[current] != -2:
                continue
            labels[current] = cluster
            current_neighbors = neighbors(current)
            if len(current_neighbors) >= min_samples:
                for item in current_neighbors:
                    if item not in queued:
                        queued.add(item)
                        queue.append(item)
        cluster += 1
    return labels


@app.post("/v1/detect-faces")
async def detect_faces(file: Annotated[UploadFile, File(...)]) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="face_model_unavailable")
    payload = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(payload) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="upload_too_large")
    try:
        with Image.open(io.BytesIO(payload)) as decoded:
            width, height = decoded.size
            if width > MAX_IMAGE_DIMENSION or height > MAX_IMAGE_DIMENSION or width * height > MAX_IMAGE_PIXELS:
                raise HTTPException(status_code=413, detail="image_dimensions_too_large")
            image = decoded.convert("RGB")
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=400, detail="invalid_image") from error

    if SIDECAR_MODE == "stub":
        width, height = image.size
        count = 2 if width >= 2 and height >= 2 else 1
        boxes = [[0, 0, max(1, width // 2), height], [width // 2, 0, width - width // 2, height]][:count]
        embeddings = embedder.face_embeddings(image, count=count)  # type: ignore[attr-defined]
    else:
        global face_analysis, FACE_READY
        try:
            from insightface.app import FaceAnalysis
            if face_analysis is None:
                face_analysis = FaceAnalysis(name=os.getenv("PICS_FACE_MODEL", "buffalo_l"))
                face_analysis.prepare(ctx_id=0, det_size=(640, 640))
            faces = face_analysis.get(__import__("numpy").array(image))
            FACE_READY = True
            boxes = [[float(face.bbox[0]), float(face.bbox[1]), float(face.bbox[2] - face.bbox[0]), float(face.bbox[3] - face.bbox[1])] for face in faces]
            embeddings = [face.embedding.astype(float).tolist() for face in faces]
        except ImportError as error:
            raise HTTPException(status_code=503, detail="face_model_unavailable") from error
        except Exception as error:
            raise HTTPException(status_code=503, detail="face_model_failed") from error
    return {"faces": [{"box": box, "embedding": embedding} for box, embedding in zip(boxes, embeddings)]}


@app.post("/v1/cluster-faces", response_model=ClusterResponse)
def cluster_faces(request: ClusterRequest) -> ClusterResponse:
    return ClusterResponse(labels=_cluster(request.embeddings, request.eps, request.min_samples))


@app.post("/v1/embed-text")
def embed_text(request: TextRequest) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="models_pending")
    return {
        "model": MODEL_NAME if SIDECAR_MODE != "stub" else "stub",
        "version": MODEL_VERSION if SIDECAR_MODE != "stub" else "stub-v1",
        "results": embedder.embed_text(request.texts),
    }


@app.post("/v1/embed-image")
def embed_image(request: ImageRequest) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="models_pending")
    image = Image.open(io.BytesIO(base64.b64decode(request.image_base64))).convert("RGB")
    return {
        "model": MODEL_NAME if SIDECAR_MODE != "stub" else "stub",
        "version": MODEL_VERSION if SIDECAR_MODE != "stub" else "stub-v1",
        "embed": embedder.embed_images([image])[0],
    }


@app.post("/v1/reverse-geocode")
def reverse_geocode(request: GeoRequest) -> dict:
    result = reverse_geocoder.search([(request.lat, request.lon)], mode=1)[0]
    return {"city": result["name"], "country": result["cc"]}
