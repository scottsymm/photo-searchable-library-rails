from __future__ import annotations

from collections.abc import Sequence
import hashlib
import math

import torch
from PIL import Image
from transformers import CLIPModel, CLIPProcessor


class ClipEmbedder:
    def __init__(self, model_name: str):
        self.name = model_name
        self.model = CLIPModel.from_pretrained(model_name)
        self.processor = CLIPProcessor.from_pretrained(model_name)
        self.model.eval()

    @staticmethod
    def _tensor(output):
        return output.pooler_output if hasattr(output, "pooler_output") else output

    @torch.no_grad()
    def embed_images(self, images: Sequence[Image.Image]) -> list[list[float]]:
        inputs = self.processor(images=list(images), return_tensors="pt")
        features = self._tensor(self.model.get_image_features(**inputs))
        features = features / features.norm(dim=-1, keepdim=True)
        return features.cpu().numpy().tolist()

    @torch.no_grad()
    def embed_text(self, texts: Sequence[str]) -> list[list[float]]:
        inputs = self.processor(text=list(texts), return_tensors="pt", padding=True, truncation=True)
        features = self._tensor(self.model.get_text_features(**inputs))
        features = features / features.norm(dim=-1, keepdim=True)
        return features.cpu().numpy().tolist()


class StubEmbedder:
    """Deterministic 512-dimensional vectors for local development and CI."""

    @staticmethod
    def _vector(seed: bytes) -> list[float]:
        values = []
        digest = seed
        while len(values) < 512:
            digest = hashlib.sha256(digest).digest()
            values.extend((byte / 127.5) - 1.0 for byte in digest)
        values = values[:512]
        norm = math.sqrt(sum(value * value for value in values))
        return [value / norm for value in values]

    def embed_text(self, texts: Sequence[str]) -> list[list[float]]:
        return [self._vector(text.encode("utf-8")) for text in texts]

    def embed_images(self, images: Sequence[Image.Image]) -> list[list[float]]:
        return [self._vector(image.tobytes() + repr(image.size).encode("ascii")) for image in images]
