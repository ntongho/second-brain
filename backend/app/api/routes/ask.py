from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import client_ip, get_current_user_id, get_db
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.schemas.ask import AskRequest
from app.services.idempotency import ask_request_hash, get_ask_replay, save_ask_replay
from app.services.rag import AskResult, ask as run_ask

router = APIRouter(tags=["ask"])


def _limit_ask(request: Request) -> None:
    s = get_settings()
    if s.app_env == "test":
        return
    limiter.check(f"ask:{client_ip(request)}:{getattr(request.state, 'user_id', '')}", 15, 60.0)


def _filters(body: AskRequest) -> dict | None:
    if not body.filters:
        return None
    return body.filters.model_dump(by_alias=True, exclude_none=True)


def _payload(result: AskResult) -> dict:
    return {
        "answer": result.answer,
        "citations": result.citations,
        "degraded": result.degraded,
        "mode": result.mode,
        "chat_id": result.chat_id,
        "message_id": result.message_id,
        "usage": {"prompt_tokens": result.prompt_tokens, "completion_tokens": result.completion_tokens},
        "latency_ms": result.latency_ms,
        "request_id": result.request_id,
    }


async def _resolve(
    *,
    request: Request,
    body: AskRequest,
    db: AsyncSession,
    user_id: str,
    x_idempotency_key: str | None,
    x_test_force_breaker: str | None,
) -> dict:
    _limit_ask(request)
    rid = getattr(request.state, "request_id", "")
    req_hash = ask_request_hash(body)
    if x_idempotency_key:
        replay = await get_ask_replay(db, user_id=user_id, key=x_idempotency_key, request_hash=req_hash)
        if replay is not None:
            replay["request_id"] = rid or replay.get("request_id")
            return replay
    result = await run_ask(
        db,
        user_id=user_id,
        query=body.query,
        chat_id=body.chat_id,
        top_k=body.top_k,
        filters=_filters(body),
        request_id=rid,
        force_degraded=(x_test_force_breaker or "").lower() == "open",
    )
    payload = _payload(result)
    if x_idempotency_key:
        await save_ask_replay(
            db, user_id=user_id, key=x_idempotency_key, request_hash=req_hash, payload=payload
        )
    return payload


@router.post("/ask")
async def ask(
    request: Request,
    body: AskRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    x_test_force_breaker: Annotated[str | None, Header()] = None,
    x_idempotency_key: Annotated[str | None, Header()] = None,
) -> dict:
    return await _resolve(
        request=request,
        body=body,
        db=db,
        user_id=user_id,
        x_idempotency_key=x_idempotency_key,
        x_test_force_breaker=x_test_force_breaker,
    )


@router.post("/ask/stream")
async def ask_stream(
    request: Request,
    body: AskRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    x_test_force_breaker: Annotated[str | None, Header()] = None,
    x_idempotency_key: Annotated[str | None, Header()] = None,
):
    rid = getattr(request.state, "request_id", "")
    payload = await _resolve(
        request=request,
        body=body,
        db=db,
        user_id=user_id,
        x_idempotency_key=x_idempotency_key,
        x_test_force_breaker=x_test_force_breaker,
    )

    async def events():
        try:
            yield ":ping\n\n"
            yield _sse(
                "meta",
                {
                    "chat_id": payload["chat_id"],
                    "message_id": payload["message_id"],
                    "request_id": payload.get("request_id") or rid,
                    "degraded": payload["degraded"],
                },
            )
            if not payload.get("degraded"):
                buf = payload.get("answer") or ""
                step = 24
                for i in range(0, len(buf), step):
                    yield _sse("token", {"delta": buf[i : i + step]})
            yield _sse("citation", {"citations": payload.get("citations") or []})
            yield _sse(
                "done",
                {
                    "usage": payload.get("usage") or {},
                    "latency_ms": payload.get("latency_ms"),
                    "mode": payload.get("mode"),
                },
            )
        except Exception as e:  # noqa: BLE001
            yield _sse(
                "error",
                {
                    "error": {
                        "code": "INTERNAL",
                        "message": str(e)[:200],
                        "details": {},
                        "request_id": rid,
                        "retryable": True,
                    }
                },
            )

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "X-Request-Id": rid,
        },
    )


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"
