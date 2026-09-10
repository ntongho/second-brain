from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from pydantic import BaseModel, Field

from app.api.deps import get_current_user_id, get_db
from app.core.clock import utcnow
from app.core.errors import AppError
from app.core.ids import new_id
from app.models.chat import Chat
from app.models.message import Message

router = APIRouter(prefix="/chats", tags=["chats"])


class ChatPatch(BaseModel):
    model_config = {"extra": "forbid"}

    title: str = Field(min_length=1, max_length=80)


@router.post("")
async def create_chat(
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    chat = Chat(id=new_id("chat"), user_id=user_id, title="New chat", created_at=utcnow())
    db.add(chat)
    await db.commit()
    return {"id": chat.id, "title": chat.title, "created_at": chat.created_at.isoformat()}


@router.get("")
async def list_chats(
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    rows = (await db.scalars(select(Chat).where(Chat.user_id == user_id).order_by(Chat.created_at.desc()))).all()
    return {
        "data": [{"id": c.id, "title": c.title, "created_at": c.created_at.isoformat()} for c in rows],
        "next_cursor": None,
    }


@router.get("/{chat_id}/messages")
async def list_messages(
    chat_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    chat = await db.scalar(select(Chat).where(Chat.id == chat_id, Chat.user_id == user_id))
    if chat is None:
        raise AppError(404, "NOT_FOUND", "Chat not found")
    rows = (
        await db.scalars(select(Message).where(Message.chat_id == chat_id).order_by(Message.created_at.asc()))
    ).all()
    return {
        "data": [
            {
                "id": m.id,
                "role": m.role,
                "content": m.content,
                "degraded": bool(m.degraded),
                "created_at": m.created_at.isoformat(),
            }
            for m in rows
        ],
        "next_cursor": None,
    }


@router.patch("/{chat_id}")
async def patch_chat(
    chat_id: str,
    body: ChatPatch,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    chat = await db.scalar(select(Chat).where(Chat.id == chat_id, Chat.user_id == user_id))
    if chat is None:
        raise AppError(404, "NOT_FOUND", "Chat not found")
    chat.title = body.title.strip()[:80]
    await db.commit()
    return {"id": chat.id, "title": chat.title, "created_at": chat.created_at.isoformat()}


@router.delete("/{chat_id}")
async def delete_chat(
    chat_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    chat = await db.scalar(select(Chat).where(Chat.id == chat_id, Chat.user_id == user_id))
    if chat is None:
        raise AppError(404, "NOT_FOUND", "Chat not found")
    await db.execute(delete(Message).where(Message.chat_id == chat_id))
    await db.execute(delete(Chat).where(Chat.id == chat_id, Chat.user_id == user_id))
    await db.commit()
    return {"deleted": True}
