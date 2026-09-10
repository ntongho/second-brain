from __future__ import annotations

import json
import re
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


def _fts_query(q: str) -> str:
    toks = re.findall(r"[A-Za-z0-9]+", q)
    if not toks:
        return ""
    return " OR ".join(f'"{t}"' for t in toks[:32])


def as_utc(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def parse_dt(s: str | None) -> datetime | None:
    if not s:
        return None
    raw = s.strip()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return None
    return as_utc(dt)


def tags_of(doc_tags: str | None) -> list[str]:
    try:
        return [str(t) for t in json.loads(doc_tags or "[]")]
    except Exception:  # noqa: BLE001
        return []


async def bm25_search(
    db: AsyncSession,
    *,
    user_id: str,
    query: str,
    limit: int = 12,
    source_types: list[str] | None = None,
    document_ids: list[str] | None = None,
    tags: list[str] | None = None,
    from_dt: datetime | None = None,
    to_dt: datetime | None = None,
) -> list[dict]:
    match = _fts_query(query)
    if not match:
        return []
    sql = """
      SELECT f.chunk_id, f.document_id, f.user_id, f.text, c.start_char, c.end_char, c.page,
             d.title, d.source_type, d.tags, d.created_at,
             bm25(chunks_fts) AS rank_score
      FROM chunks_fts f
      JOIN chunks c ON c.id = f.chunk_id
      JOIN documents d ON d.id = f.document_id
      WHERE chunks_fts MATCH :q AND f.user_id = :uid
    """
    params: dict = {"q": match, "uid": user_id}
    if source_types:
        sql += " AND d.source_type IN ({})".format(",".join(f":st{i}" for i in range(len(source_types))))
        for i, st in enumerate(source_types):
            params[f"st{i}"] = st
    if document_ids:
        sql += " AND f.document_id IN ({})".format(",".join(f":d{i}" for i in range(len(document_ids))))
        for i, did in enumerate(document_ids):
            params[f"d{i}"] = did
    if from_dt is not None:
        sql += " AND d.created_at >= :from_dt"
        params["from_dt"] = as_utc(from_dt).replace(tzinfo=None)
    if to_dt is not None:
        sql += " AND d.created_at <= :to_dt"
        params["to_dt"] = as_utc(to_dt).replace(tzinfo=None)
    if tags:
        for i, tag in enumerate(tags[:8]):
            sql += f" AND lower(d.tags) LIKE :tag{i}"
            params[f"tag{i}"] = f'%"{tag.lower()}"%'
    sql += " ORDER BY rank_score ASC LIMIT :lim"
    params["lim"] = limit
    rows = (await db.execute(text(sql), params)).mappings().all()
    out = []
    for rank, row in enumerate(rows):
        out.append(
            {
                "chunk_id": row["chunk_id"],
                "document_id": row["document_id"],
                "title": row["title"],
                "text": row["text"],
                "page": row["page"],
                "start_char": row["start_char"],
                "end_char": row["end_char"],
                "source": "sparse",
                "rank": rank,
                "bm25": row["rank_score"],
            }
        )
    return out
