import io
import unittest
from unittest.mock import patch

from PIL import Image

from . import app as sidecar


class FaceApiTest(unittest.TestCase):
    def test_cluster_accepts_512_vectors_and_empty_input(self):
        response = sidecar.cluster_faces(sidecar.ClusterRequest(embeddings=[]))
        self.assertEqual(response.labels, [])
        vector = [1.0] + [0.0] * 511
        response = sidecar.cluster_faces(sidecar.ClusterRequest(embeddings=[vector, vector]))
        self.assertEqual(response.labels, [0, 0])

    def test_cluster_rejects_invalid_dimensions(self):
        with self.assertRaises(ValueError):
            sidecar.ClusterRequest(embeddings=[[0.0]])

    def test_stub_detection_returns_two_faces(self):
        image = Image.new("RGB", (20, 10), "white")
        stream = io.BytesIO()
        image.save(stream, format="JPEG")
        old_mode, old_embedder = sidecar.SIDECAR_MODE, sidecar.embedder
        try:
            sidecar.SIDECAR_MODE = "stub"
            sidecar.embedder = sidecar.StubEmbedder()
            class Upload:
                async def read(self):
                    return stream.getvalue()

            upload = Upload()
            import asyncio
            response = asyncio.run(sidecar.detect_faces(upload))
            self.assertEqual(len(response["faces"]), 2)
            self.assertEqual(len(response["faces"][0]["embedding"]), 512)
        finally:
            sidecar.SIDECAR_MODE, sidecar.embedder = old_mode, old_embedder


if __name__ == "__main__":
    unittest.main()
