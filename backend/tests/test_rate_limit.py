from __future__ import annotations

from app.core.config import get_settings
from app.core.rate_limit import limiter


async def test_auth_ip_limit_10_per_min(client, monkeypatch):
    # Force production limiter even though APP_ENV=test.
    monkeypatch.setenv("APP_ENV", "dev")
    get_settings.cache_clear()
    limiter._hits.clear()

    from app.api.routes import auth as auth_routes

    # Directly exercise limiter with the production path.
    class _Req:
        headers = {}
        client = type("C", (), {"host": "1.2.3.4"})()

    # 10 allowed
    for _ in range(10):
        auth_routes._limit_auth(_Req())  # type: ignore[arg-type]
    try:
        auth_routes._limit_auth(_Req())  # type: ignore[arg-type]
        raised = False
    except Exception as e:
        raised = True
        from app.core.errors import AppError

        assert isinstance(e, AppError)
        assert e.status_code == 429
        assert e.code == "RATE_LIMITED"
    assert raised
    get_settings.cache_clear()
    monkeypatch.setenv("APP_ENV", "test")
    get_settings.cache_clear()
