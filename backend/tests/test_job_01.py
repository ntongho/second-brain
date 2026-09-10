from __future__ import annotations

import asyncio
import time

from sqlalchemy import delete, func, select, text, update

from tests.pdf_util import make_pdf


async def _token(client):
    r = await client.post(
        "/auth/register",
        json={"email": "job01@example.com", "password": "correct-horse-10", "display_name": "J1"},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


async def _poll(client, token, job_id, timeout=30.0):
    headers = {"Authorization": f"Bearer {token}"}
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = await client.get(f"/jobs/{job_id}", headers=headers)
        body = r.json()
        if body["status"] in {"done", "failed"}:
            return body
        await asyncio.sleep(0.05)
    raise TimeoutError(job_id)


async def test_job_01_kill_mid_pdf_sweep_no_dup_chunks(client):
    """JOB-01: processing leftover → boot sweep requeue → wipe → done once, no orphans."""
    token = await _token(client)
    headers = {"Authorization": f"Bearer {token}"}
    pages = [f"Page {i+1} of the kill-9 PDF. Unique token TOK{i:03d}." for i in range(8)]
    blob = make_pdf(pages)
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("kill9.pdf", blob, "application/pdf")},
        data={"title": "Kill9"},
        headers=headers,
    )
    assert r.status_code == 202, r.text
    job_id = r.json()["job_id"]
    doc_id = r.json()["document_id"]
    job = await _poll(client, token, job_id)
    assert job["status"] == "done", job

    from app.core.clock import utcnow
    from app.core.ids import new_id
    from app.db import get_sessionmaker
    from app.models.chunk import Chunk
    from app.models.document import Document
    from app.models.job import Job
    from app.services.jobs_sweep import boot_sweep
    from app.workers.ingest import process_ingest_job

    async with get_sessionmaker()() as db:
        expected = int(
            await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == doc_id)) or 0
        )
        assert expected >= 1
        now = utcnow()
        ghost = Chunk(
            id=new_id("chk"),
            document_id=doc_id,
            user_id=(await db.scalar(select(Document.user_id).where(Document.id == doc_id))),
            ord=expected + 50,
            text="orphan leftover from killed worker",
            start_char=0,
            end_char=12,
            page=1,
            token_count=3,
            created_at=now,
        )
        db.add(ghost)
        await db.flush()
        await db.execute(
            text(
                "INSERT INTO chunks_fts(chunk_id, document_id, user_id, text) "
                "VALUES (:cid, :did, :uid, :txt)"
            ),
            {"cid": ghost.id, "did": doc_id, "uid": ghost.user_id, "txt": ghost.text},
        )
        await db.execute(
            update(Job)
            .where(Job.id == job_id)
            .values(status="processing", worker_id="dead-worker", progress=0.5, updated_at=now)
        )
        await db.commit()
        inflated = int(
            await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == doc_id)) or 0
        )
        assert inflated == expected + 1

    stats = await boot_sweep()
    assert stats["requeued"] >= 1
    st = await client.get(f"/jobs/{job_id}", headers=headers)
    assert st.json()["status"] == "queued"

    await process_ingest_job(job_id)
    job = await _poll(client, token, job_id)
    assert job["status"] == "done", job
    assert int(job["attempts"]) >= 2

    async with get_sessionmaker()() as db:
        after = int(
            await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == doc_id)) or 0
        )
        ords = list((await db.scalars(select(Chunk.ord).where(Chunk.document_id == doc_id))).all())
        orphans = int(
            await db.scalar(
                select(func.count())
                .select_from(Chunk)
                .where(Chunk.document_id.notin_(select(Document.id)))
            )
            or 0
        )
        fts_orphans = int(
            (
                await db.execute(
                    text(
                        "SELECT COUNT(*) FROM chunks_fts WHERE document_id NOT IN (SELECT id FROM documents)"
                    )
                )
            ).scalar_one()
        )
    assert after == expected, (after, expected, ords)
    assert len(ords) == len(set(ords))
    assert orphans == 0
    assert fts_orphans == 0
