from __future__ import annotations

import json

from sqlalchemy import delete, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.errors import AppError
from app.core.ids import new_id, sha256_hex
from app.models.chunk import Chunk
from app.models.document import Document
from app.models.job import Job
from app.services.vector_store import get_vector_store


async def get_owned_doc(db: AsyncSession, *, user_id: str, doc_id: str) -> Document:
    d = await db.scalar(select(Document).where(Document.id == doc_id, Document.user_id == user_id))
    if d is None:
        raise AppError(404, "NOT_FOUND", "Document not found")
    return d


async def delete_document(db: AsyncSession, *, user_id: str, doc_id: str) -> None:
    doc = await get_owned_doc(db, user_id=user_id, doc_id=doc_id)
    await db.execute(text("DELETE FROM chunks_fts WHERE document_id = :d"), {"d": doc.id})
    await db.execute(delete(Chunk).where(Chunk.document_id == doc.id))
    await db.execute(delete(Job).where(Job.document_id == doc.id))
    await db.execute(delete(Document).where(Document.id == doc.id, Document.user_id == user_id))
    await db.commit()
    try:
        from app.services.audio import delete_media_bytes

        delete_media_bytes(doc.id)
    except Exception:  # noqa: BLE001
        pass
    try:
        await get_vector_store().delete(where={"document_id": doc.id})
    except Exception:  # noqa: BLE001
        pass


async def patch_document(
    db: AsyncSession,
    *,
    user_id: str,
    doc_id: str,
    title: str | None,
    tags: list[str] | None,
    text: str | None = None,
) -> tuple[Document, Job | None]:
    doc = await get_owned_doc(db, user_id=user_id, doc_id=doc_id)
    if title is not None:
        t = title.strip()
        if not t:
            raise AppError(400, "VALIDATION", "Title must not be blank")
        doc.title = t[:200]
    if tags is not None:
        if len(tags) > 20:
            raise AppError(400, "VALIDATION", "max 20 tags")
        doc.tags = json.dumps(tags)

    reindex = False
    if text is not None:
        if doc.source_type != "text":
            raise AppError(400, "VALIDATION", "Only pasted notes can be edited")
        body = text.strip()
        if not body:
            raise AppError(400, "VALIDATION", "Note text must not be blank")
        if body != (doc.raw_text or "").strip():
            digest = sha256_hex(body)
            dup = await db.scalar(
                select(Document).where(
                    Document.user_id == user_id,
                    Document.file_sha256 == digest,
                    Document.id != doc.id,
                )
            )
            if dup is not None:
                raise AppError(409, "CONFLICT", "Another note already has this text")
            doc.raw_text = body
            doc.char_count = len(body)
            doc.file_sha256 = digest
            reindex = True

    doc.updated_at = utcnow()
    job: Job | None = None
    if reindex:
        job = await db.scalar(select(Job).where(Job.document_id == doc.id).order_by(Job.created_at.desc()))
        now = utcnow()
        if job is None:
            job = Job(
                id=new_id("job"),
                user_id=user_id,
                document_id=doc.id,
                kind="ingest_text",
                status="queued",
                progress=0.0,
                attempts=0,
                max_attempts=3,
                created_at=now,
                updated_at=now,
            )
            db.add(job)
        else:
            job.status = "queued"
            job.error = None
            job.progress = 0.0
            job.updated_at = now
            await db.execute(update(Job).where(Job.id == job.id).values(worker_id=None))
        doc.status = "queued"
        doc.error = None
    await db.commit()
    await db.refresh(doc)
    if job is not None:
        await db.refresh(job)
    return doc, job


async def retry_document(db: AsyncSession, *, user_id: str, doc_id: str) -> Job:
    doc = await get_owned_doc(db, user_id=user_id, doc_id=doc_id)
    job = await db.scalar(select(Job).where(Job.document_id == doc.id).order_by(Job.created_at.desc()))
    now = utcnow()
    if job is None:
        job = Job(
            id=new_id("job"),
            user_id=user_id,
            document_id=doc.id,
            kind="transcribe"
            if doc.source_type == "voice"
            else ("ingest_file" if doc.source_type == "pdf" else "ingest_text"),
            status="queued",
            progress=0.0,
            attempts=0,
            max_attempts=3,
            created_at=now,
            updated_at=now,
        )
        db.add(job)
    else:
        if int(job.attempts or 0) >= int(job.max_attempts or 3) and job.status == "failed":
            raise AppError(409, "CONFLICT", "Max retry attempts reached")
        job.status = "queued"
        job.error = None
        job.progress = 0.0
        job.updated_at = now
        await db.execute(update(Job).where(Job.id == job.id).values(worker_id=None))
    doc.status = "queued"
    doc.error = None
    doc.updated_at = now
    await db.commit()
    await db.refresh(job)
    return job
