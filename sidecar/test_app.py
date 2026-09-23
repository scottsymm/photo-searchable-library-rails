import io
import unittest
from unittest.mock import MagicMock, patch

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

    def test_detection_rejects_oversized_uploads(self):
        old_embedder = sidecar.embedder
        sidecar.embedder = sidecar.StubEmbedder()
        try:
            class Upload:
                async def read(self, size=-1):
                    return b"x" * (sidecar.MAX_UPLOAD_BYTES + 1)

            with self.assertRaises(sidecar.HTTPException) as error:
                import asyncio
                asyncio.run(sidecar.detect_faces(Upload()))
            self.assertEqual(error.exception.status_code, 413)
        finally:
            sidecar.embedder = old_embedder

    def test_detection_rejects_oversized_dimensions_before_decode(self):
        old_embedder = sidecar.embedder
        sidecar.embedder = sidecar.StubEmbedder()
        decoded = MagicMock(size=(sidecar.MAX_IMAGE_DIMENSION + 1, 1))
        decoded.__enter__.return_value = decoded
        try:
            class Upload:
                async def read(self, size=-1):
                    return b"image"

            with patch.object(sidecar.Image, "open", return_value=decoded):
                with self.assertRaises(sidecar.HTTPException) as error:
                    import asyncio
                    asyncio.run(sidecar.detect_faces(Upload()))
            self.assertEqual(error.exception.status_code, 413)
            decoded.convert.assert_not_called()
        finally:
            sidecar.embedder = old_embedder


if __name__ == "__main__":
    unittest.main()
