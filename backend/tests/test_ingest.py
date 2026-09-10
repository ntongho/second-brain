from __future__ import annotations

import asyncio
import time

REGISTER = {
    "email": "ingest@example.com",
    "password": "correct-horse-10",
    "display_name": "Ingest",
}

SAMPLE = {
    "title": "Japan notes",
    "text": "Kyoto food log. " * 80 + "Total Kyoto food: ¥10,300.",
    "tags": ["travel"],
}


async def _auth(client):
    r = await client.post("/auth/register", json=REGISTER)
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


async def _poll_job(client, token, job_id, timeout=15.0):
    headers = {"Authorization": f"Bearer {token}"}
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = await client.get(f"/jobs/{job_id}", headers=headers)
        assert r.status_code == 200, r.text
        body = r.json()
        if body["status"] in {"done", "failed"}:
            return body
        await asyncio.sleep(0.05)
    raise TimeoutError(job_id)


async def test_ingest_text_202_fast_and_completes(client):
    token = await _auth(client)
    headers = {"Authorization": f"Bearer {token}", "X-Idempotency-Key": "11111111-1111-1111-1111-111111111111"}
    t0 = time.perf_counter()
    r = await client.post("/documents/ingest-text", json=SAMPLE, headers=headers)
    elapsed_ms = (time.perf_counter() - t0) * 1000
    assert r.status_code == 202, r.text
    # ASGITransport awaits BackgroundTasks, so this is not the <250ms p95 gate.
    # That gate is curl against uvicorn (scripts/phase1_gate.sh).
    assert elapsed_ms < 15_000, f"ingest handler hung {elapsed_ms:.1f}ms"
    body = r.json()
    assert body["status"] == "queued"
    assert body["job_id"].startswith("job_")
    assert body["document_id"].startswith("doc_")

    job = await _poll_job(client, token, body["job_id"])
    assert job["status"] == "done", job
    assert job["attempts"] >= 1
    assert job["max_attempts"] == 3

    doc = await client.get(f"/documents/{body['document_id']}", headers={"Authorization": f"Bearer {token}"})
    assert doc.status_code == 200
    d = doc.json()
    assert d["status"] == "ready"
    assert d["chunk_count"] >= 1

    from app.db import get_sessionmaker
    from app.models.chunk import Chunk
    from app.services.vector_store import get_vector_store
    from sqlalchemy import func, select

    async with get_sessionmaker()() as db:
        n = await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == body["document_id"]))
    vs = get_vector_store()
    assert await vs.count() == int(n)


async def test_idempotency_replay(client):
    token = await _auth(client)
    headers = {"Authorization": f"Bearer {token}", "X-Idempotency-Key": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}
    r1 = await client.post("/documents/ingest-text", json=SAMPLE, headers=headers)
    r2 = await client.post("/documents/ingest-text", json=SAMPLE, headers=headers)
    assert r1.status_code == r2.status_code == 202
    assert r1.json()["job_id"] == r2.json()["job_id"]
    assert r1.json()["document_id"] == r2.json()["document_id"]


async def test_dedupe_same_text(client):
    token = await _auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    r1 = await client.post("/documents/ingest-text", json=SAMPLE, headers=headers)
    r2 = await client.post("/documents/ingest-text", json=SAMPLE, headers=headers)
    assert r1.status_code == r2.status_code == 202
    assert r1.json()["document_id"] == r2.json()["document_id"]


async def test_empty_text_422(client):
    token = await _auth(client)
    r = await client.post(
        "/documents/ingest-text",
        json={"title": "blank", "text": "   \n\t  "},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "VALIDATION"


async def test_unauthenticated_ingest_401(client):
    r = await client.post("/documents/ingest-text", json=SAMPLE)
    assert r.status_code == 401
