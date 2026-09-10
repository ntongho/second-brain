from __future__ import annotations


async def test_healthz(client):
    r = await client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["ok"] is True
    assert "x-request-id" in r.headers


async def test_readyz_pinned_models(client):
    r = await client.get("/readyz")
    assert r.status_code == 200
    body = r.json()
    assert body["ready"] is True
    assert body["models"]["embed"].endswith("@PINNED")
    assert body["models"]["gen"].endswith("@PINNED")
    assert body["sweep"]["done"] is True


async def test_metrics(client):
    r = await client.get("/metrics")
    assert r.status_code == 200
    assert b"auth_failures_total" in r.content or r.headers["content-type"].startswith("text/plain")
