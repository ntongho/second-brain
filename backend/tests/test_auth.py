from __future__ import annotations

import statistics
import time
from datetime import timedelta

from freezegun import freeze_time

REGISTER = {
    "email": "ada@example.com",
    "password": "correct-horse-10",
    "display_name": "Ada",
}


async def test_register_me_refresh_logout_cycle(client):
    r = await client.post("/auth/register", json=REGISTER)
    assert r.status_code == 201, r.text
    pair = r.json()
    assert pair["token_type"] == "Bearer"
    assert pair["expires_in"] == 900
    assert pair["user"]["email"] == "ada@example.com"
    assert pair["user"]["display_name"] == "Ada"
    assert pair["user"]["id"].startswith("u_")
    at, rt = pair["access_token"], pair["refresh_token"]
    assert len(rt) >= 20

    me = await client.get("/auth/me", headers={"Authorization": f"Bearer {at}"})
    assert me.status_code == 200, me.text
    assert me.json()["email"] == "ada@example.com"

    refreshed = await client.post("/auth/refresh", json={"refresh_token": rt})
    assert refreshed.status_code == 200, refreshed.text
    pair2 = refreshed.json()
    assert pair2["refresh_token"] != rt
    at2, rt2 = pair2["access_token"], pair2["refresh_token"]

    lo = await client.post(
        "/auth/logout",
        headers={"Authorization": f"Bearer {at2}"},
        json={"refresh_token": rt2},
    )
    assert lo.status_code == 200, lo.text

    again = await client.post("/auth/refresh", json={"refresh_token": rt2})
    assert again.status_code == 401
    assert again.json()["error"]["code"] == "AUTH"


async def test_duplicate_email_409(client):
    assert (await client.post("/auth/register", json=REGISTER)).status_code == 201
    r = await client.post("/auth/register", json=REGISTER)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "CONFLICT"


async def test_short_password_400(client):
    r = await client.post("/auth/register", json={"email": "b@c.co", "password": "short"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION"


async def test_unauthenticated_documents_401(client):
    r = await client.get("/documents")
    assert r.status_code == 401
    body = r.json()
    assert "error" in body
    assert body["error"]["code"] == "AUTH"
    assert "request_id" in body["error"]


async def test_authenticated_documents_stub(client):
    pair = (await client.post("/auth/register", json=REGISTER)).json()
    r = await client.get("/documents", headers={"Authorization": f"Bearer {pair['access_token']}"})
    assert r.status_code == 200
    assert r.json()["data"] == []


async def test_lockout_auth02(client):
    await client.post("/auth/register", json=REGISTER)
    for i in range(5):
        r = await client.post(
            "/auth/login",
            json={"email": REGISTER["email"], "password": "wrong-password-xx"},
        )
        assert r.status_code == 401, (i, r.text)
        assert r.json()["error"]["message"] == "Incorrect email or password"

    locked = await client.post(
        "/auth/login",
        json={"email": REGISTER["email"], "password": REGISTER["password"]},
    )
    assert locked.status_code == 429, locked.text
    err = locked.json()["error"]
    assert err["code"] == "ACCOUNT_LOCKED"
    assert "locked_until" in err["details"]
    assert locked.headers.get("retry-after")

    with freeze_time() as frozen:
        frozen.tick(timedelta(minutes=16))
        ok = await client.post(
            "/auth/login",
            json={"email": REGISTER["email"], "password": REGISTER["password"]},
        )
    assert ok.status_code == 200, ok.text
    assert ok.json()["user"]["email"] == REGISTER["email"]


async def test_refresh_reuse_auth03(client):
    pair = (await client.post("/auth/register", json=REGISTER)).json()
    rt1 = pair["refresh_token"]
    rot = await client.post("/auth/refresh", json={"refresh_token": rt1})
    assert rot.status_code == 200
    rt2 = rot.json()["refresh_token"]
    at2 = rot.json()["access_token"]

    replay = await client.post("/auth/refresh", json={"refresh_token": rt1})
    assert replay.status_code == 401, replay.text
    err = replay.json()["error"]
    assert err["code"] == "AUTH"
    assert err["details"].get("reused") is True

    dead = await client.post("/auth/refresh", json={"refresh_token": rt2})
    assert dead.status_code == 401

    me = await client.get("/auth/me", headers={"Authorization": f"Bearer {at2}"})
    # Access JWT is stateless until expiry; reuse kills refresh chain, not current access.
    assert me.status_code == 200


async def test_login_oracle_auth04(client):
    await client.post("/auth/register", json=REGISTER)
    payload_unknown = {"email": "nope@example.com", "password": "correct-horse-10"}
    payload_wrong = {"email": REGISTER["email"], "password": "definitely-wrong-1"}

    async def timed(payload):
        t0 = time.perf_counter()
        r = await client.post("/auth/login", json=payload)
        dt = time.perf_counter() - t0
        return r, dt

    # Stay under lockout (5 fails) and IP limit. One warmup pair + three samples.
    await timed(payload_unknown)
    await timed(payload_wrong)

    unknown_samples = []
    wrong_samples = []
    last_unknown = last_wrong = None
    for _ in range(3):
        ru, tu = await timed(payload_unknown)
        rw, tw = await timed(payload_wrong)
        last_unknown, last_wrong = ru, rw
        unknown_samples.append(tu)
        wrong_samples.append(tw)

    assert last_unknown.status_code == 401
    assert last_wrong.status_code == 401
    assert last_unknown.json()["error"]["message"] == last_wrong.json()["error"]["message"]
    assert last_unknown.json()["error"]["code"] == last_wrong.json()["error"]["code"] == "AUTH"
    # Median gap — AUTH-04 budget is 50ms after dummy-hash path.
    gap = abs(statistics.median(unknown_samples) - statistics.median(wrong_samples))
    assert gap < 0.05, f"oracle timing gap {gap:.4f}s samples u={unknown_samples} w={wrong_samples}"


async def test_request_id_echo(client):
    r = await client.post(
        "/auth/login",
        json={"email": "z@z.co", "password": "abcdefghij"},
        headers={"X-Request-Id": "11111111-1111-1111-1111-111111111111"},
    )
    assert r.headers.get("x-request-id") == "11111111-1111-1111-1111-111111111111"
    assert r.json()["error"]["request_id"] == "11111111-1111-1111-1111-111111111111"


async def test_forgot_and_reset_password(client):
    await client.post("/auth/register", json=REGISTER)
    unknown = await client.post("/auth/forgot-password", json={"email": "nobody@example.com"})
    assert unknown.status_code == 200, unknown.text
    assert unknown.json()["ok"] is True
    assert unknown.json().get("dev_code") in (None, "")

    r = await client.post("/auth/forgot-password", json={"email": REGISTER["email"]})
    assert r.status_code == 200, r.text
    code = r.json().get("dev_code")
    assert code and len(code) == 6 and code.isdigit()

    bad = await client.post(
        "/auth/reset-password",
        json={"email": REGISTER["email"], "code": "000000", "password": "new-password-10"},
    )
    assert bad.status_code == 401

    ok = await client.post(
        "/auth/reset-password",
        json={"email": REGISTER["email"], "code": code, "password": "new-password-10"},
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["user"]["email"] == REGISTER["email"]

    old = await client.post("/auth/login", json={"email": REGISTER["email"], "password": REGISTER["password"]})
    assert old.status_code == 401
    fresh = await client.post("/auth/login", json={"email": REGISTER["email"], "password": "new-password-10"})
    assert fresh.status_code == 200, fresh.text


async def test_google_login_creates_and_reuses(client, monkeypatch):
    from app.services.auth import AuthService

    async def fake(self, token: str):
        assert token == "good-id-token-value-xx"
        return {"email": "ada@gmail.com", "name": "Ada Lovelace", "email_verified": True, "aud": "test"}

    monkeypatch.setattr(AuthService, "_google_userinfo", fake)
    r = await client.post("/auth/google", json={"id_token": "good-id-token-value-xx"})
    assert r.status_code == 200, r.text
    user = r.json()["user"]
    assert user["email"] == "ada@gmail.com"
    assert user["display_name"] == "Ada Lovelace"
    r2 = await client.post("/auth/google", json={"id_token": "good-id-token-value-xx"})
    assert r2.status_code == 200, r2.text
    assert r2.json()["user"]["id"] == user["id"]


async def test_extra_field_forbidden(client):
    r = await client.post("/auth/register", json={**REGISTER, "role": "admin"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION"
