from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.middleware import RequestIdMiddleware
from app.api.routes import admin, ask, auth, chats, documents, health, jobs, search
from app.core.config import get_settings
from app.core.errors import (
    AppError,
    app_error_handler,
    http_exception_handler,
    unhandled_handler,
    validation_handler,
)
from app.core.logging import setup_logging
from app.db import init_db


@asynccontextmanager
async def lifespan(_app: FastAPI):
    settings = get_settings()
    setup_logging(settings.log_level)
    await init_db()
    from app.services.jobs_sweep import boot_sweep, mark_sweep, resume_queued_jobs
    from app.services.vector_store import get_vector_store

    mark_sweep(done=False)
    get_vector_store()
    await boot_sweep()
    await resume_queued_jobs()
    from app.services.scheduler import start_scheduler, stop_scheduler

    start_scheduler()
    yield
    stop_scheduler()


def create_app() -> FastAPI:
    settings = get_settings()
    application = FastAPI(
        title="AI Second Brain API",
        version="1.1.1",
        lifespan=lifespan,
        docs_url="/docs" if settings.app_env != "prod" else None,
        redoc_url=None,
    )
    application.add_middleware(RequestIdMiddleware)
    # CORS is not in the pack; enabled so Flutter web (requested) can hit localhost:8000.
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["X-Request-Id", "Retry-After"],
    )
    application.add_exception_handler(AppError, app_error_handler)
    application.add_exception_handler(RequestValidationError, validation_handler)
    application.add_exception_handler(StarletteHTTPException, http_exception_handler)
    application.add_exception_handler(Exception, unhandled_handler)

    # Ops both at root (Compose healthcheck) and under /v1 (OpenAPI servers url).
    application.include_router(health.router)
    application.include_router(health.router, prefix="/v1")
    application.include_router(auth.public_router, prefix="/v1")
    application.include_router(auth.protected_router, prefix="/v1")
    application.include_router(documents.router, prefix="/v1")
    application.include_router(jobs.router, prefix="/v1")
    application.include_router(ask.router, prefix="/v1")
    application.include_router(chats.router, prefix="/v1")
    application.include_router(search.router, prefix="/v1")
    application.include_router(admin.router, prefix="/v1")
    return application


# Uvicorn loads `app.main:app`. Tests import `create_app` after setting env
# (conftest) and build a separate instance against a tmp DB.
app = create_app()
