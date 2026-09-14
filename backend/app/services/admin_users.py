from __future__ import annotations

from datetime import datetime

from sqlalchemy import delete, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.errors import AppError
from app.core.logging import get_logger
from app.models.ask_replay import AskReplay
from app.models.chunk import Chunk
from app.models.document import Document
from app.models.job import Job
from app.models.password_reset import PasswordReset
from app.models.user import User
from app.schemas.common import StrictModel
from app.services.auth import AuthService, _aware
from app.services.documents import delete_document
from app.services.vector_store import get_vector_store

log = get_logger("admin_users")


class AdminUserOut(StrictModel):
    id: str
    email: str
    display_name: str = ""
    created_at: datetime
    failed_attempts: int = 0
    locked_until: datetime | None = None
    is_locked: bool = False
    is_admin: bool = False


def _out(user: User, *, admin_email: str) -> AdminUserOut:
    until = _aware(user.locked_until)
    locked = until is not None and until > utcnow()
    return AdminUserOut(
        id=user.id,
        email=user.email,
        display_name=user.display_name or "",
        created_at=_aware(user.created_at) or utcnow(),
        failed_attempts=int(user.failed_attempts or 0),
        locked_until=until,
        is_locked=locked,
        is_admin=bool(admin_email) and user.email.strip().lower() == admin_email,
    )


async def _get(db: AsyncSession, user_id: str) -> User:
    user = await db.scalar(select(User).where(User.id == user_id))
    if user is None:
        raise AppError(404, "NOT_FOUND", "Not found")
    return user


async def list_users(db: AsyncSession, *, admin_email: str, cursor: str | None, limit: int) -> dict:
    limit = max(1, min(limit, 100))
    q = select(User).order_by(User.created_at.desc(), User.id.desc())
    if cursor:
        cur = await db.scalar(select(User).where(User.id == cursor))
        if cur is not None:
            q = q.where(
                (User.created_at < cur.created_at)
                | ((User.created_at == cur.created_at) & (User.id < cur.id))
            )
    rows = list((await db.scalars(q.limit(limit + 1))).all())
    extra = rows[:limit]
    next_cursor = extra[-1].id if len(rows) > limit else None
    return {"data": [_out(u, admin_email=admin_email).model_dump(mode="json") for u in extra], "next_cursor": next_cursor}


async def unlock_user(db: AsyncSession, *, user_id: str, admin_email: str) -> AdminUserOut:
    user = await _get(db, user_id)
    user.failed_attempts = 0
    user.locked_until = None
    user.updated_at = utcnow()
    await db.commit()
    await db.refresh(user)
    log.info("admin_unlock", user_id=user.id)
    return _out(user, admin_email=admin_email)


async def revoke_sessions(db: AsyncSession, *, user_id: str, admin_id: str, admin_email: str) -> AdminUserOut:
    user = await _get(db, user_id)
    if user.id == admin_id:
        raise AppError(409, "CONFLICT", "You cannot sign out your own admin session this way")
    svc = AuthService(db)
    await svc._revoke_user_chain(user.id, "admin_revoke")
    await db.commit()
    await db.refresh(user)
    log.info("admin_revoke_sessions", user_id=user.id)
    return _out(user, admin_email=admin_email)


async def send_reset(db: AsyncSession, *, user_id: str) -> dict:
    user = await _get(db, user_id)
    svc = AuthService(db)
    result = await svc.request_password_reset(user.email)
    return {"ok": True, "emailed": result.emailed}


async def delete_user(db: AsyncSession, *, user_id: str, admin_id: str) -> dict:
    user = await _get(db, user_id)
    if user.id == admin_id:
        raise AppError(409, "CONFLICT", "You cannot delete your own admin account")
    docs = list((await db.scalars(select(Document).where(Document.user_id == user.id))).all())
    for doc in docs:
        await delete_document(db, user_id=user.id, doc_id=doc.id)
    await db.execute(text("DELETE FROM chunks_fts WHERE document_id IN (SELECT id FROM documents WHERE user_id = :u)"), {"u": user.id})
    await db.execute(delete(Chunk).where(Chunk.user_id == user.id))
    await db.execute(delete(Job).where(Job.user_id == user.id))
    await db.execute(delete(AskReplay).where(AskReplay.user_id == user.id))
    await db.execute(delete(PasswordReset).where(PasswordReset.email == user.email))
    email = user.email
    uid = user.id
    await db.execute(delete(User).where(User.id == uid))
    await db.commit()
    try:
        await get_vector_store().delete(where={"user_id": uid})
    except Exception:  # noqa: BLE001
        pass
    from app.core.ids import email_hash

    log.info("admin_delete_user", user_id=uid, email_hash=email_hash(email))
    return {"deleted": True}
