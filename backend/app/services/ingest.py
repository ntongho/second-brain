from __future__ import annotations

import asyncio
import json

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clock import utcnow
from app.core.errors import AppError
from app.core.ids import new_id, sha256_hex
from app.core.logging import get_logger
from app.models.document import Document
from app.models.job import Job
from app.schemas.documents import JobAccepted

log = get_logger("ingest")


def _empty_text(text: str) -> bool:
    return not text or not text.strip()


async def enqueue_ingest_text(
    db: AsyncSession,
    *,
    user_id: str,
    title: str,
    text: str,
    tags: list[str],
    idempotency_key: str | None,
) -> JobAccepted:
    if _empty_text(text):
        raise AppError(422, "VALIDATION", "Document text is empty", details={"reason": "empty"})

    if idempotency_key:
        existing = await db.scalar(
            select(Job).where(Job.user_id == user_id, Job.idempotency_key == idempotency_key)
        )
        if existing:
            return JobAccepted(
                job_id=existing.id,
                document_id=existing.document_id or "",
                status="queued",
            )

    digest = sha256_hex(text)
    dup = await db.scalar(
        select(Document).where(Document.user_id == user_id, Document.file_sha256 == digest)
    )
    if dup is not None:
        job = await db.scalar(
            select(Job)
            .where(Job.document_id == dup.id)
            .order_by(Job.created_at.desc())
        )
        now = utcnow()
        if job is None:
            ready = dup.status == "ready"
            job = Job(
                id=new_id("job"),
                user_id=user_id,
                document_id=dup.id,
                kind="ingest_text",
                status="done" if ready else "queued",
                progress=1.0 if ready else 0.0,
                attempts=0,
                max_attempts=3,
                idempotency_key=idempotency_key,
                created_at=now,
                updated_at=now,
            )
            db.add(job)
            await db.commit()
        elif dup.status != "ready" or job.status == "failed":
            dup.status = "queued"
            dup.error = None
            dup.updated_at = now
            job.status = "queued"
            job.error = None
            job.progress = 0.0
            job.updated_at = now
            await db.commit()
        return JobAccepted(job_id=job.id, document_id=dup.id, status=job.status)

    now = utcnow()
    doc = Document(
        id=new_id("doc"),
        user_id=user_id,
        title=title.strip()[:200],
        source_type="text",
        tags=json.dumps(tags or []),
        raw_text=text,
        char_count=len(text),
        page_count=None,
        language="en",
        status="queued",
        file_sha256=digest,
        created_at=now,
        updated_at=now,
    )
    job = Job(
        id=new_id("job"),
        user_id=user_id,
        document_id=doc.id,
        kind="ingest_text",
        status="queued",
        progress=0.0,
        attempts=0,
        max_attempts=3,
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
    )
    db.add(doc)
    db.add(job)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        # Race on hash or idempotency — replay the winner.
        return await enqueue_ingest_text(
            db,
            user_id=user_id,
            title=title,
            text=text,
            tags=tags,
            idempotency_key=idempotency_key,
        )
    log.info("ingest_enqueued", user_id=user_id, document_id=doc.id, job_id=job.id)
    return JobAccepted(job_id=job.id, document_id=doc.id, status="queued")


_GENERIC_TITLES = {"voice memo", "pdf", "upload", "file", "memo", "untitled", "note"}
_TEXT_EXTS = (".md", ".txt", ".text", ".markdown")


def _is_text_filename(name: str) -> bool:
    n = (name or "").lower()
    return any(n.endswith(ext) for ext in _TEXT_EXTS)


def _decode_text_blob(blob: bytes) -> str:
    data = blob[3:] if blob.startswith(b"\xef\xbb\xbf") else blob
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("utf-8", errors="replace")


def _nice_title(title: str, filename: str, source_type: str) -> str:
    from pathlib import Path

    t = (title or "").strip()
    lower = t.lower()
    for ext in (*_TEXT_EXTS, ".pdf", ".wav", ".webm", ".mp3", ".m4a", ".ogg"):
        if lower.endswith(ext):
            t = Path(t).stem.replace("_", " ").replace("-", " ").strip()
            lower = t.lower()
            break
    if t and lower not in _GENERIC_TITLES:
        return t[:200]
    stem = Path(filename or "").stem.replace("_", " ").replace("-", " ").strip()
    if stem and stem.lower() not in _GENERIC_TITLES:
        return stem[:200]
    if source_type == "voice":
        return utcnow().strftime("Voice memo · %d %b %Y, %H:%M")
    if source_type == "pdf":
        return "PDF"
    return (stem or "Note")[:200]


async def enqueue_ingest_file(
    db: AsyncSession,
    *,
    user_id: str,
    title: str,
    blob: bytes,
    tags: list[str],
    idempotency_key: str | None,
    duration_hint: float | None = None,
    filename: str = "",
) -> JobAccepted:
    import hashlib

    from app.services.audio import assert_audio, ext_for_blob, save_media_bytes, sniff_media

    kind = sniff_media(blob)
    if kind == "unknown" and _is_text_filename(filename):
        kind = "text"
    if kind == "unknown":
        raise AppError(
            422,
            "VALIDATION",
            "Not a PDF, audio, Markdown, or text file",
            details={"reason": "magic"},
        )

    raw_text = " "
    char_count = 0
    page_count = None
    ext: str | None = ext_for_blob(blob)

    if kind == "voice":
        source_type = "voice"
        job_kind = "transcribe"
        assert_audio(blob, duration_hint=duration_hint)
    elif kind == "text":
        source_type = "text"
        job_kind = "ingest_text"
        raw_text = _decode_text_blob(blob).strip()
        if not raw_text:
            raise AppError(422, "VALIDATION", "Document text is empty", details={"reason": "empty"})
        if len(raw_text) > 500_000:
            raise AppError(413, "VALIDATION", "Text too large (max 500,000 characters)")
        char_count = len(raw_text)
        ext = None
    else:
        source_type = "pdf"
        job_kind = "ingest_file"
        from app.services.pdf_extract import extract_pdf

        try:
            extracted = await asyncio.wait_for(asyncio.to_thread(extract_pdf, blob), 60.0)
        except TimeoutError:
            raise AppError(422, "VALIDATION", "PDF extract timed out (60s)", details={"reason": "timeout"})
        raw_text = extracted.text
        char_count = len(extracted.text)
        page_count = extracted.page_count
        ext = "pdf"

    digest = hashlib.sha256(blob).hexdigest()

    if idempotency_key:
        existing = await db.scalar(
            select(Job).where(Job.user_id == user_id, Job.idempotency_key == idempotency_key)
        )
        if existing:
            return JobAccepted(
                job_id=existing.id,
                document_id=existing.document_id or "",
                status=existing.status or "queued",
            )

    dup = await db.scalar(
        select(Document).where(Document.user_id == user_id, Document.file_sha256 == digest)
    )
    if dup is not None:
        if dup.status == "ready":
            raise AppError(
                409,
                "CONFLICT",
                "This file is already in your library",
                details={"document_id": dup.id, "title": dup.title},
            )
        job = await db.scalar(
            select(Job).where(Job.document_id == dup.id).order_by(Job.created_at.desc())
        )
        now = utcnow()
        if job is None:
            job = Job(
                id=new_id("job"),
                user_id=user_id,
                document_id=dup.id,
                kind=job_kind,
                status="queued",
                progress=0.0,
                attempts=0,
                max_attempts=3,
                idempotency_key=idempotency_key,
                created_at=now,
                updated_at=now,
            )
            db.add(job)
            await db.commit()
        else:
            dup.status = "queued"
            dup.error = None
            dup.updated_at = now
            job.status = "queued"
            job.error = None
            job.progress = 0.0
            job.updated_at = now
            await db.commit()
        return JobAccepted(job_id=job.id, document_id=dup.id, status=job.status)

    now = utcnow()
    doc = Document(
        id=new_id("doc"),
        user_id=user_id,
        title=_nice_title(title, filename, source_type),
        source_type=source_type,
        tags=json.dumps(tags or []),
        raw_text=raw_text,
        char_count=char_count,
        page_count=page_count,
        language="en",
        status="queued",
        file_sha256=digest,
        created_at=now,
        updated_at=now,
    )
    job = Job(
        id=new_id("job"),
        user_id=user_id,
        document_id=doc.id,
        kind=job_kind,
        status="queued",
        progress=0.0,
        attempts=0,
        max_attempts=3,
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
    )
    db.add(doc)
    db.add(job)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        return await enqueue_ingest_file(
            db,
            user_id=user_id,
            title=title,
            blob=blob,
            tags=tags,
            idempotency_key=idempotency_key,
            duration_hint=duration_hint,
            filename=filename,
        )
    if ext:
        save_media_bytes(doc.id, blob, ext)
    log.info(
        "ingest_file_enqueued",
        user_id=user_id,
        document_id=doc.id,
        source_type=source_type,
        pages=page_count,
    )
    return JobAccepted(job_id=job.id, document_id=doc.id, status="queued")
