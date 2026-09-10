from __future__ import annotations

import asyncio
import time

from sqlalchemy import func, select

from tests.pdf_util import make_pdf


async def _token(client, email="pdf@example.com"):
    r = await client.post("/auth/register", json={"email": email, "password": "correct-horse-10"})
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


async def _poll(client, token, job_id, timeout=20.0):
    headers = {"Authorization": f"Bearer {token}"}
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = await client.get(f"/jobs/{job_id}", headers=headers)
        body = r.json()
        if body["status"] in {"done", "failed"}:
            return body
        await asyncio.sleep(0.05)
    raise TimeoutError(job_id)


async def test_ingest_file_pdf_and_delete_cascade(client):
    token = await _token(client)
    headers = {"Authorization": f"Bearer {token}"}
    blob = make_pdf(["The Rule of 72 estimates doubling time"])
    files = {"file": ("rule72.pdf", blob, "application/pdf")}
    t0 = time.perf_counter()
    r = await client.post("/documents/ingest-file", files=files, data={"title": "Rule PDF"}, headers=headers)
    assert (time.perf_counter() - t0) * 1000 < 15_000
    assert r.status_code == 202, r.text
    job = await _poll(client, token, r.json()["job_id"])
    assert job["status"] == "done", job
    doc_id = r.json()["document_id"]
    got = await client.get(f"/documents/{doc_id}", headers=headers)
    assert got.status_code == 200
    body = got.json()
    assert body["source_type"] == "pdf"
    assert "72" in (body.get("text") or "")
    assert body["chunk_count"] >= 1
    assert body["page_count"] == 1

    from app.db import get_sessionmaker
    from app.models.chunk import Chunk
    from app.services.vector_store import get_vector_store

    async with get_sessionmaker()() as db:
        n = await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == doc_id))
    assert int(n) >= 1
    vs = get_vector_store()
    before = await vs.count()
    d = await client.delete(f"/documents/{doc_id}", headers=headers)
    assert d.status_code == 200
    assert d.json()["deleted"] is True
    gone = await client.get(f"/documents/{doc_id}", headers=headers)
    assert gone.status_code == 404
    async with get_sessionmaker()() as db:
        n2 = await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == doc_id))
    assert int(n2 or 0) == 0
    after = await vs.count()
    assert after == before - int(n)


async def test_ingest_file_rejects_non_pdf(client):
    token = await _token(client, "notpdf@example.com")
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("note.txt", b"hello world not a pdf", "text/plain")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 422


async def test_ingest_file_empty_pdf_422(client):
    token = await _token(client, "empty-pdf@example.com")
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("blank.pdf", make_pdf(["   "]), "application/pdf")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 422, r.text
    assert r.json()["error"]["details"].get("reason") == "empty"


async def test_ingest_file_too_large_413(client, monkeypatch):
    monkeypatch.setattr("app.services.pdf_extract.MAX_BYTES", 64)
    token = await _token(client, "big@example.com")
    blob = b"%PDF-1.4\n" + b"x" * 200
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("big.pdf", blob, "application/pdf")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 413, r.text


async def test_ingest_file_too_many_pages_413(client, monkeypatch):
    monkeypatch.setattr("app.services.pdf_extract.MAX_PAGES", 2)
    token = await _token(client, "pages@example.com")
    blob = make_pdf(["p1", "p2", "p3"])
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("long.pdf", blob, "application/pdf")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 413, r.text


async def test_highlight_offsets_match_chunk(client):
    token = await _token(client, "hl@example.com")
    headers = {"Authorization": f"Bearer {token}"}
    blob = make_pdf(["Alpha unique phrase about Kyoto food spend.", "Beta second page filler text."])
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("two.pdf", blob, "application/pdf")},
        data={"title": "Two pager"},
        headers=headers,
    )
    assert r.status_code == 202, r.text
    job = await _poll(client, token, r.json()["job_id"])
    assert job["status"] == "done", job
    doc_id = r.json()["document_id"]

    from app.db import get_sessionmaker
    from app.models.chunk import Chunk

    async with get_sessionmaker()() as db:
        ch = await db.scalar(select(Chunk).where(Chunk.document_id == doc_id).order_by(Chunk.ord))
        assert ch is not None
        cid, start, end, text = ch.id, ch.start_char, ch.end_char, ch.text
    got = await client.get(f"/documents/{doc_id}", params={"highlight": cid}, headers=headers)
    body = got.json()
    assert body["highlight_start"] == start
    assert body["highlight_end"] == end
    assert body["highlight_snippet"]
    raw = body["text"] or ""
    assert raw[start:end] == text or text[:50] in raw
    # chip tap lands ±50 chars of the span
    window = raw[max(0, start - 50) : min(len(raw), end + 50)]
    assert text[:40] in window or text in raw


async def test_retry_failed_pdf(client):
    token = await _token(client, "retry@example.com")
    headers = {"Authorization": f"Bearer {token}"}
    r = await client.post(
        "/documents/ingest-file",
        files={"file": ("ok.pdf", make_pdf(["Retryable document body with enough text." * 20]), "application/pdf")},
        data={"title": "Retry me"},
        headers=headers,
    )
    assert r.status_code == 202
    job = await _poll(client, token, r.json()["job_id"])
    assert job["status"] == "done"
    doc_id = r.json()["document_id"]
    again = await client.post(f"/documents/{doc_id}/retry", headers=headers)
    assert again.status_code == 202, again.text
    job2 = await _poll(client, token, again.json()["job_id"])
    assert job2["status"] == "done", job2
