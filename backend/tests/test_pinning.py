import os

import pytest
from pydantic import ValidationError

from app.core.config import Settings, get_settings


def test_unpinned_embed_model_fails(monkeypatch):
    monkeypatch.setenv("EMBED_MODEL", "text-embedding-004")
    get_settings.cache_clear()
    with pytest.raises(ValidationError):
        Settings()  # type: ignore[call-arg]


def test_unpinned_gen_model_fails(monkeypatch):
    monkeypatch.setenv("GEN_MODEL", "gemini-2.0-flash")
    get_settings.cache_clear()
    with pytest.raises(ValidationError):
        Settings()  # type: ignore[call-arg]


def test_pinned_ok():
    get_settings.cache_clear()
    s = Settings()  # type: ignore[call-arg]
    assert "@PINNED" in s.embed_model
    assert "@PINNED" in s.gen_model
    os.environ.setdefault("EMBED_MODEL", "text-embedding-004@PINNED")
