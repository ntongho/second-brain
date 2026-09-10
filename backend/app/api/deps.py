from __future__ import annotations

from typing import Annotated

import jwt
from fastapi import Depends, Header, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import AppError
from app.core.security import decode_access_token
from app.db import get_db
from app.services.auth import AuthService

__all__ = ["get_db", "get_auth_service", "get_current_user_id", "client_ip"]


async def get_auth_service(db: Annotated[AsyncSession, Depends(get_db)]) -> AuthService:
    return AuthService(db)


def client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


async def get_current_user_id(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AppError(401, "AUTH", "Missing or invalid access token")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise AppError(401, "AUTH", "Missing or invalid access token")
    try:
        payload = decode_access_token(get_settings(), token)
    except jwt.ExpiredSignatureError:
        raise AppError(401, "AUTH", "Access token expired")
    except jwt.PyJWTError:
        raise AppError(401, "AUTH", "Missing or invalid access token")
    sub = payload.get("sub")
    if not sub or payload.get("typ") != "access":
        raise AppError(401, "AUTH", "Missing or invalid access token")
    request.state.user_id = sub
    return str(sub)
