from __future__ import annotations

import respx
from httpx import Response

from app.services.embedder import GeminiEmbedder


@respx.mock
async def test_simulated_429_then_success():
    embedder = GeminiEmbedder(api_key="test-key", model="text-embedding-004@PINNED", dim=2)
    route = respx.post(url__regex=r"batchEmbedContents").mock(
        side_effect=[
            Response(429, json={"error": {"message": "rate"}}),
            Response(200, json={"embeddings": [{"values": [3.0, 4.0]}]}),
        ]
    )
    vecs = await embedder.embed(["hello"])
    assert route.call_count == 2
    assert len(vecs) == 1
    # L2-normalized 3-4-5 triangle
    assert abs(vecs[0][0] - 0.6) < 1e-5
    assert abs(vecs[0][1] - 0.8) < 1e-5
