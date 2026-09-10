from __future__ import annotations

from app.core.clock import utcnow
from app.core.ids import sha256_hex
from app.core.metrics import cache_dim_mismatch_total
from app.db import get_sessionmaker
from app.models.embedding_cache import EmbeddingCache
from app.services.embed_cache import embed_with_cache
from app.services.embedder import FakeEmbedder, pack_f32


async def test_cache01_dim_mismatch_and_model_isolation(client):
    """CACHE-01: poisoned 768-d row for model B is dropped; A rows never served to B."""
    text = "compound interest is earned on interest"
    sha = sha256_hex(text)
    model_a = "text-embedding-004@PINNED"
    model_b = "other-embed-384@PINNED"
    now = utcnow()

    async with get_sessionmaker()() as db:
        db.add(
            EmbeddingCache(
                text_sha256=sha,
                model=model_a,
                vector=pack_f32([0.1] * 768),
                dim=768,
                created_at=now,
            )
        )
        db.add(
            EmbeddingCache(
                text_sha256=sha,
                model=model_b,
                vector=pack_f32([0.2] * 768),
                dim=768,
                created_at=now,
            )
        )
        await db.commit()

    before = cache_dim_mismatch_total._value.get()  # type: ignore[attr-defined]
    b = FakeEmbedder(model=model_b, dim=384)
    async with get_sessionmaker()() as db:
        vecs = await embed_with_cache(db, b, [text])
    assert len(vecs[0]) == 384
    assert cache_dim_mismatch_total._value.get() >= before + 1  # type: ignore[attr-defined]

    # Model A 768-d must not appear as B's output
    assert not any(abs(x - 0.2) < 1e-6 for x in vecs[0])

    a = FakeEmbedder(model=model_a, dim=768)
    async with get_sessionmaker()() as db:
        vecs_a = await embed_with_cache(db, a, [text])
    assert len(vecs_a[0]) == 768
