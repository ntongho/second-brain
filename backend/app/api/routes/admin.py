from __future__ import annotations

import asyncio
import secrets
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db, require_admin
from app.core.clock import utcnow
from app.core.config import get_settings
from app.core.errors import AppError
from app.core.ids import new_id
from app.db import get_sessionmaker
from app.models.job import Job
from app.services import admin_users as admin_users_svc
from app.services.backup import list_backups, restore, snapshot

router = APIRouter(prefix="/admin", tags=["admin"])


class RestoreBody(BaseModel):
    model_config = {"extra": "forbid"}

    backup_id: str | None = Field(default=None, min_length=3)


def _check_restore_token(token: str | None) -> None:
    expected = get_settings().restore_token
    given = token or ""
    if not given or not secrets.compare_digest(given.encode(), expected.encode()):
        raise AppError(401, "AUTH", "Missing or invalid restore token")


def _row(b) -> dict[str, Any]:
    return {
        "id": b.id,
        "path": b.path,
        "size_bytes": b.size_bytes,
        "sqlite_ok": bool(b.sqlite_ok),
        "chroma_ok": bool(b.chroma_ok),
        "error": b.error,
        "created_at": b.created_at.isoformat() if b.created_at else None,
    }


@router.get("/backups")
async def get_backups(
    x_restore_token: Annotated[str | None, Header()] = None,
) -> dict:
    _check_restore_token(x_restore_token)
    rows = await list_backups()
    return {"data": [_row(b) for b in rows]}


@router.post("/backup", status_code=202)
async def enqueue_backup(
    x_restore_token: Annotated[str | None, Header()] = None,
) -> dict:
    _check_restore_token(x_restore_token)
    Session = get_sessionmaker()
    now = utcnow()
    job_id = new_id("job")
    async with Session() as db:
        db.add(
            Job(
                id=job_id,
                user_id="ops",
                document_id=None,
                kind="backup",
                status="queued",
                progress=0,
                attempts=0,
                max_attempts=3,
                idempotency_key=job_id,
                created_at=now,
                updated_at=now,
            )
        )
        await db.commit()
    from app.workers.backup import process_backup_job

    asyncio.create_task(process_backup_job(job_id))
    return {"job_id": job_id, "status": "queued"}


@router.post("/backup/now")
async def backup_now(
    x_restore_token: Annotated[str | None, Header()] = None,
) -> dict:
    """Synchronous snapshot for tests / restore-drill (still token-gated)."""
    _check_restore_token(x_restore_token)
    row = await snapshot()
    if not row.sqlite_ok:
        raise AppError(500, "INTERNAL", row.error or "snapshot failed", retryable=True)
    return _row(row)


@router.post("/restore")
async def restore_backup(
    body: RestoreBody | None = None,
    x_restore_token: Annotated[str | None, Header()] = None,
) -> dict:
    _check_restore_token(x_restore_token)
    bid = body.backup_id if body else None
    try:
        return await restore(backup_id=bid)
    except PermissionError as e:
        raise AppError(409, "CONFLICT", str(e)) from e
    except FileNotFoundError as e:
        raise AppError(404, "NOT_FOUND", str(e)) from e


@router.get("/users")
async def list_users(
    _admin_id: Annotated[str, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    cursor: str | None = None,
    limit: int = 50,
) -> dict:
    return await admin_users_svc.list_users(
        db,
        admin_email=get_settings().admin_email_normalized,
        cursor=cursor,
        limit=limit,
    )


@router.post("/users/{user_id}/unlock")
async def unlock_user(
    user_id: str,
    _admin_id: Annotated[str, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    row = await admin_users_svc.unlock_user(
        db, user_id=user_id, admin_email=get_settings().admin_email_normalized
    )
    return row.model_dump(mode="json")


@router.post("/users/{user_id}/revoke-sessions")
async def revoke_user_sessions(
    user_id: str,
    admin_id: Annotated[str, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    row = await admin_users_svc.revoke_sessions(
        db,
        user_id=user_id,
        admin_id=admin_id,
        admin_email=get_settings().admin_email_normalized,
    )
    return row.model_dump(mode="json")


@router.post("/users/{user_id}/send-reset")
async def send_user_reset(
    user_id: str,
    _admin_id: Annotated[str, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    return await admin_users_svc.send_reset(db, user_id=user_id)


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str,
    admin_id: Annotated[str, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    return await admin_users_svc.delete_user(db, user_id=user_id, admin_id=admin_id)
