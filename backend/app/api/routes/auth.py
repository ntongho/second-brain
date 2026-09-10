from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request

from app.api.deps import client_ip, get_auth_service, get_current_user_id
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.schemas.auth import LoginRequest, LogoutRequest, RefreshRequest, RegisterRequest, TokenPair, UserOut
from app.services.auth import AuthService

public_router = APIRouter(prefix="/auth", tags=["auth"])
protected_router = APIRouter(prefix="/auth", tags=["auth"])


def _limit_auth(request: Request) -> None:
    s = get_settings()
    if s.app_env == "test":
        return
    ip = client_ip(request)
    limiter.check(f"auth:{ip}", s.auth_ip_limit_per_min, 60.0)


def _limit_refresh(request: Request) -> None:
    s = get_settings()
    if s.app_env == "test":
        return
    ip = client_ip(request)
    limiter.check(f"refresh:{ip}", s.refresh_ip_limit_per_min, 60.0)


@public_router.post("/register", status_code=201, response_model=TokenPair)
async def register(
    request: Request,
    body: RegisterRequest,
    svc: Annotated[AuthService, Depends(get_auth_service)],
) -> TokenPair:
    _limit_auth(request)
    return await svc.register(body.email, body.password, body.display_name)


@public_router.post("/login", response_model=TokenPair)
async def login(
    request: Request,
    body: LoginRequest,
    svc: Annotated[AuthService, Depends(get_auth_service)],
) -> TokenPair:
    _limit_auth(request)
    return await svc.login(body.email, body.password)


@public_router.post("/refresh", response_model=TokenPair)
async def refresh(
    request: Request,
    body: RefreshRequest,
    svc: Annotated[AuthService, Depends(get_auth_service)],
) -> TokenPair:
    _limit_refresh(request)
    return await svc.refresh(body.refresh_token)


@protected_router.post("/logout")
async def logout(
    svc: Annotated[AuthService, Depends(get_auth_service)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    body: LogoutRequest | None = None,
    all_devices: Annotated[bool, Query(alias="all")] = False,
) -> dict:
    token = body.refresh_token if body else None
    await svc.logout(user_id, token, all_devices=all_devices)
    return {"revoked": True}


@protected_router.get("/me", response_model=UserOut)
async def me(
    svc: Annotated[AuthService, Depends(get_auth_service)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> UserOut:
    return await svc.me(user_id)
