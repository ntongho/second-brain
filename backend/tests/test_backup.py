from __future__ import annotations

from datetime import timedelta

from sqlalchemy import delete, select

from app.core.config import get_settings


def _restore_headers() -> dict[str, str]:
    return {"X-Restore-Token": get_settings().restore_token}


async def test_readyz_includes_backup_slot(client):
    r = await client.get("/readyz")
    assert r.status_code == 200
    assert "backup" in r.json()
    assert "last_ok" in r.json()["backup"]


async def test_admin_backup_requires_token(client):
    r = await client.post("/admin/backup/now")
    assert r.status_code == 401
    r = await client.post("/admin/backup/now", headers={"X-Restore-Token": "nope-nope-nope-nope-nope"})
    assert r.status_code == 401


async def test_snapshot_and_restore_refused_when_users_exist(client):
    reg = await client.post(
        "/auth/register",
        json={"email": "bak@example.com", "password": "correct-horse-10", "display_name": "B"},
    )
    assert reg.status_code == 201, reg.text
    headers = _restore_headers()
    snap = await client.post("/admin/backup/now", headers=headers)
    assert snap.status_code == 200, snap.text
    body = snap.json()
    assert body["sqlite_ok"] is True
    assert body["id"].startswith("bak_")

    listed = await client.get("/admin/backups", headers=headers)
    assert listed.status_code == 200
    assert listed.json()["data"][0]["id"] == body["id"]

    refused = await client.post("/admin/restore", headers=headers, json={})
    assert refused.status_code == 409
    assert refused.json()["error"]["code"] == "CONFLICT"


async def test_restore_when_users_empty(client):
    from app.db import get_sessionmaker
    from app.models.user import User
    from app.services.backup import restore, snapshot, users_empty

    await client.post(
        "/auth/register",
        json={"email": "keep@example.com", "password": "correct-horse-10", "display_name": "K"},
    )
    row = await snapshot()
    assert row.sqlite_ok == 1

    async with get_sessionmaker()() as db:
        await db.execute(delete(User))
        await db.commit()
    assert await users_empty()

    out = await restore(backup_id=row.id)
    assert out["restored"] is True
    login = await client.post(
        "/auth/login",
        json={"email": "keep@example.com", "password": "correct-horse-10"},
    )
    assert login.status_code == 200, login.text


async def test_stale_heartbeat_requeued(client):
    from app.core.clock import utcnow
    from app.core.ids import new_id
    from app.db import get_sessionmaker
    from app.models.job import Job
    from app.services.jobs_sweep import heartbeat_sweep

    jid = new_id("job")
    now = utcnow()
    async with get_sessionmaker()() as db:
        db.add(
            Job(
                id=jid,
                user_id="ops",
                document_id=None,
                kind="backup",
                status="processing",
                progress=0.2,
                attempts=1,
                max_attempts=3,
                worker_id="dead",
                heartbeat_at=now - timedelta(minutes=5),
                created_at=now,
                updated_at=now,
            )
        )
        await db.commit()

    stats = await heartbeat_sweep()
    assert stats["requeued"] >= 1
    async with get_sessionmaker()() as db:
        job = await db.scalar(select(Job).where(Job.id == jid))
        assert job is not None
        assert job.status == "queued"
        assert job.attempts == 1

    j2 = new_id("job")
    async with get_sessionmaker()() as db:
        db.add(
            Job(
                id=j2,
                user_id="ops",
                kind="ingest_text",
                status="processing",
                attempts=1,
                max_attempts=3,
                heartbeat_at=utcnow(),
                created_at=utcnow(),
                updated_at=utcnow(),
            )
        )
        await db.commit()
    await heartbeat_sweep()
    async with get_sessionmaker()() as db:
        job = await db.scalar(select(Job).where(Job.id == j2))
        assert job.status == "processing"
