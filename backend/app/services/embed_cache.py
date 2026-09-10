from __future__ import annotations

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.ids import sha256_hex
from app.core.metrics import cache_dim_mismatch_total
from app.models.embedding_cache import EmbeddingCache
from app.services.embedder import Embedder, pack_f32, unpack_f32


async def embed_with_cache(db: AsyncSession, embedder: Embedder, texts: list[str]) -> list[list[float]]:
    """Cache key = (sha256(text), model). Dim mismatch → delete + re-embed + metric."""
    if not texts:
        return []
    model = embedder.model
    expected_dim = embedder.dim
    shas = [sha256_hex(t) for t in texts]
    found: dict[str, list[float]] = {}

    rows = (
        await db.execute(
            select(EmbeddingCache).where(
                EmbeddingCache.text_sha256.in_(set(shas)),
                EmbeddingCache.model == model,
            )
        )
    ).scalars().all()

    stale_ids: list[str] = []
    for row in rows:
        if row.dim != expected_dim:
            cache_dim_mismatch_total.inc()
            stale_ids.append(row.text_sha256)
            continue
        vec = unpack_f32(row.vector)
        if len(vec) != expected_dim:
            cache_dim_mismatch_total.inc()
            stale_ids.append(row.text_sha256)
            continue
        found[row.text_sha256] = vec

    if stale_ids:
        await db.execute(
            delete(EmbeddingCache).where(
                EmbeddingCache.model == model,
                EmbeddingCache.text_sha256.in_(stale_ids),
            )
        )
        await db.commit()

    missing_idx = [i for i, s in enumerate(shas) if s not in found]
    if missing_idx:
        to_embed = [texts[i] for i in missing_idx]
        fresh = await embedder.embed(to_embed)
        now = utcnow()
        for i, vec in zip(missing_idx, fresh, strict=True):
            if len(vec) != expected_dim:
                raise RuntimeError(f"embedder returned dim {len(vec)}, expected {expected_dim}")
            sha = shas[i]
            found[sha] = vec
            db.add(
                EmbeddingCache(
                    text_sha256=sha,
                    model=model,
                    vector=pack_f32(vec),
                    dim=expected_dim,
                    created_at=now,
                )
            )
        await db.commit()

    return [found[s] for s in shas]
