from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_id, get_db
from app.services.rag import hybrid_retrieve

router = APIRouter(tags=["search"])


@router.get("/search")
async def search(
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    q: str = Query(min_length=1),
    source_type: str | None = None,
    tag: str | None = None,
    from_: str | None = Query(default=None, alias="from"),
    to: str | None = None,
    limit: int = 10,
) -> dict:
    filters: dict = {}
    if source_type:
        filters["source_types"] = [source_type]
    if tag:
        filters["tags"] = [tag]
    if from_:
        filters["from"] = from_
    if to:
        filters["to"] = to
    hits = await hybrid_retrieve(
        db,
        user_id=user_id,
        query=q,
        top_k=min(max(limit, 1), 12),
        filters=filters or None,
    )
    return {
        "data": [
            {
                "chunk_id": h.chunk_id,
                "document_id": h.document_id,
                "title": h.title,
                "snippet": h.text[:400],
                "score": h.score,
                "source": h.source,
                "source_type": h.source_type,
                "page": h.page,
            }
            for h in hits
        ]
    }
