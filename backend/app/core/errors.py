from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

ERROR_CODES = {
    "VALIDATION",
    "AUTH",
    "ACCOUNT_LOCKED",
    "NOT_FOUND",
    "RATE_LIMITED",
    "UPSTREAM_429",
    "UPSTREAM_DEGRADED",
    "PROCESSING",
    "CONFLICT",
    "INTERNAL",
}


class AppError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        *,
        details: dict[str, Any] | None = None,
        retryable: bool = False,
        retry_after: int | None = None,
    ) -> None:
        if code not in ERROR_CODES:
            raise ValueError(f"unknown error code {code}")
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or {}
        self.retryable = retryable
        self.retry_after = retry_after
        super().__init__(message)


def envelope(request: Request, err: AppError) -> JSONResponse:
    rid = getattr(request.state, "request_id", None) or request.headers.get("x-request-id") or ""
    body = {
        "error": {
            "code": err.code,
            "message": err.message,
            "details": err.details,
            "request_id": rid,
            "retryable": err.retryable,
        }
    }
    headers = {"X-Request-Id": rid}
    if err.retry_after is not None:
        headers["Retry-After"] = str(err.retry_after)
    return JSONResponse(status_code=err.status_code, content=body, headers=headers)


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return envelope(request, exc)


async def validation_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    # Contract uses 400 VALIDATION, not FastAPI's default 422.
    return envelope(
        request,
        AppError(
            400,
            "VALIDATION",
            "Request validation failed",
            details={"errors": exc.errors()},
            retryable=False,
        ),
    )


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = "NOT_FOUND" if exc.status_code == 404 else "AUTH" if exc.status_code in (401, 403) else "INTERNAL"
    if exc.status_code == 429:
        code = "RATE_LIMITED"
    message = exc.detail if isinstance(exc.detail, str) else "Request failed"
    return envelope(
        request,
        AppError(exc.status_code, code if code in ERROR_CODES else "INTERNAL", message),
    )


async def unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
    return envelope(request, AppError(500, "INTERNAL", "Internal server error", retryable=True))
