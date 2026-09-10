from __future__ import annotations

import hashlib
import json
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.errors import AppError
from app.core.ids import new_id
from app.models.ask_replay import AskReplay
from app.schemas.ask import AskRequest

TTL = timedelta(hours=24)


def ask_request_hash(body: AskRequest) -> str:
    payload = {
        "query": body.query,
        "chat_id": body.chat_id,
        "top_k": body.top_k,
        "filters": body.filters.model_dump(by_alias=True, exclude_none=True) if body.filters else None,
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


async def get_ask_replay(db: AsyncSession, *, user_id: str, key: str, request_hash: str) -> dict | None:
    row = await db.scalar(
        select(AskReplay).where(AskReplay.user_id == user_id, AskReplay.idempotency_key == key)
    )
    if row is None:
        return None
    created = row.created_at
    if created.tzinfo is None:
        from datetime import timezone

        created = created.replace(tzinfo=timezone.utc)
    if utcnow() - created > TTL:
        await db.delete(row)
        await db.flush()
        return None
    if row.request_hash != request_hash:
        raise AppError(409, "CONFLICT", "Idempotency key reused with a different body")
    return json.loads(row.payload_json)


async def save_ask_replay(
    db: AsyncSession, *, user_id: str, key: str, request_hash: str, payload: dict
) -> None:
    db.add(
        AskReplay(
            id=new_id("idem"),
            user_id=user_id,
            idempotency_key=key,
            request_hash=request_hash,
            payload_json=json.dumps(payload),
            created_at=utcnow(),
        )
    )
    await db.commit()
