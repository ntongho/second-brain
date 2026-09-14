from __future__ import annotations

from app.core.config import get_settings

ADMIN = {
    "email": "ops@example.com",
    "password": "correct-horse-10",
    "display_name": "Ops",
}
USER = {
    "email": "ada@example.com",
    "password": "correct-horse-10",
    "display_name": "Ada",
}


async def _auth(client, body):
    r = await client.post("/auth/register", json=body)
    assert r.status_code == 201, r.text
    return r.json()


async def test_non_admin_cannot_list_users(client, monkeypatch):
    monkeypatch.setenv("ADMIN_EMAIL", "ops@example.com")
    get_settings.cache_clear()
    pair = await _auth(client, USER)
    r = await client.get("/admin/users", headers={"Authorization": f"Bearer {pair['access_token']}"})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"


async def test_admin_list_unlock_delete(client, monkeypatch):
    monkeypatch.setenv("ADMIN_EMAIL", ADMIN["email"])
    get_settings.cache_clear()
    ops = await _auth(client, ADMIN)
    ada = await _auth(client, USER)
    h = {"Authorization": f"Bearer {ops['access_token']}"}

    listed = await client.get("/admin/users", headers=h)
    assert listed.status_code == 200, listed.text
    emails = {row["email"] for row in listed.json()["data"]}
    assert ADMIN["email"] in emails
    assert USER["email"] in emails
    assert all("password" not in row and "password_hash" not in row for row in listed.json()["data"])

    me = await client.get("/auth/me", headers=h)
    assert me.status_code == 200
    assert me.json()["is_admin"] is True

    ada_me = await client.get("/auth/me", headers={"Authorization": f"Bearer {ada['access_token']}"})
    assert ada_me.json()["is_admin"] is False

    for _ in range(5):
        await client.post("/auth/login", json={"email": USER["email"], "password": "wrong-password-xx"})
    locked = await client.post("/auth/login", json={"email": USER["email"], "password": USER["password"]})
    assert locked.status_code == 429

    un = await client.post(f"/admin/users/{ada['user']['id']}/unlock", headers=h)
    assert un.status_code == 200, un.text
    assert un.json()["is_locked"] is False
    ok = await client.post("/auth/login", json={"email": USER["email"], "password": USER["password"]})
    assert ok.status_code == 200, ok.text

    self_del = await client.delete(f"/admin/users/{ops['user']['id']}", headers=h)
    assert self_del.status_code == 409

    gone = await client.delete(f"/admin/users/{ada['user']['id']}", headers=h)
    assert gone.status_code == 200, gone.text
    listed2 = await client.get("/admin/users", headers=h)
    emails2 = {row["email"] for row in listed2.json()["data"]}
    assert USER["email"] not in emails2
