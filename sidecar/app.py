"""Stateless ML inference sidecar. Owns model weights only."""
from __future__ import annotations

import base64
import io
import os

import reverse_geocoder
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel

from .models import ClipEmbedder, StubEmbedder

MODEL_NAME = "openai/clip-vit-base-patch32"
MODEL_VERSION = "clip-vit-base-patch32-v1"
SIDECAR_MODE = os.getenv("PICS_SIDECAR_MODE", "real")

app = FastAPI(title="pics-sidecar")
embedder: ClipEmbedder | StubEmbedder | None = None


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
        "model": "stub" if SIDECAR_MODE == "stub" else MODEL_NAME,
        "version": "stub-v1" if SIDECAR_MODE == "stub" else MODEL_VERSION,
    }


@app.post("/v1/embed-text")
def embed_text(request: TextRequest) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="models_pending")
    return {"model": MODEL_NAME, "version": MODEL_VERSION, "results": embedder.embed_text(request.texts)}


@app.post("/v1/embed-image")
def embed_image(request: ImageRequest) -> dict:
    if embedder is None:
        raise HTTPException(status_code=503, detail="models_pending")
    image = Image.open(io.BytesIO(base64.b64decode(request.image_base64))).convert("RGB")
    return {"model": MODEL_NAME, "version": MODEL_VERSION, "embed": embedder.embed_images([image])[0]}


@app.post("/v1/reverse-geocode")
def reverse_geocode(request: GeoRequest) -> dict:
    result = reverse_geocoder.search([(request.lat, request.lon)], mode=1)[0]
    return {"city": result["name"], "country": result["cc"]}
