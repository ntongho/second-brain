from __future__ import annotations

import os
import sys
from pathlib import Path

# Fail-fast secrets for the test process. Must run before Settings() is constructed.
os.environ.setdefault("JWT_SECRET", "test-jwt-secret-32-bytes-minimum-ok")
os.environ.setdefault("GEMINI_API_KEY", "test-gemini-not-used-phase0")
os.environ.setdefault("GROQ_API_KEY", "test-groq-not-used-phase0")
os.environ.setdefault("RESTORE_TOKEN", "test-restore-token-32b-minimum")
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("EMBED_MODEL", "text-embedding-004@PINNED")
os.environ.setdefault("GEN_MODEL", "gemini-2.5-flash@PINNED")

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.db import get_engine, init_db, reset_engine
from app.services.breaker import reset_breakers
from app.services.vector_store import reset_vector_store


@pytest.fixture
async def client(tmp_path, monkeypatch):
    db_path = tmp_path / "test.db"
    chroma = tmp_path / "chroma"
    chroma.mkdir()
    monkeypatch.setenv("DATABASE_URL", f"sqlite+aiosqlite:///{db_path}")
    monkeypatch.setenv("CHROMA_PATH", str(chroma))
    monkeypatch.setenv("FILES_PATH", str(tmp_path / "files"))
    monkeypatch.setenv("BACKUPS_PATH", str(tmp_path / "backups"))
    monkeypatch.setenv("RESTORE_TOKEN", "test-restore-token-32b-minimum")
    monkeypatch.setenv("APP_ENV", "test")
    get_settings.cache_clear()
    reset_engine()
    reset_vector_store()
    reset_breakers()
    limiter._hits.clear()

    from app.main import create_app

    application = create_app()
    await init_db()
    from app.services.jobs_sweep import mark_sweep

    mark_sweep(done=True, duration_ms=0, requeued=0)
    transport = ASGITransport(app=application)
    async with AsyncClient(transport=transport, base_url="http://test/v1") as ac:
        yield ac
    engine = get_engine()
    await engine.dispose()
    get_settings.cache_clear()
    reset_engine()
    reset_vector_store()
    reset_breakers()
    limiter._hits.clear()
