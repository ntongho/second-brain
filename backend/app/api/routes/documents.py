from __future__ import annotations

import json
from typing import Annotated

from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, Header, Query, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import client_ip, get_current_user_id, get_db
from app.core.config import get_settings
from app.core.errors import AppError
from app.core.rate_limit import limiter
from app.models.chunk import Chunk
from app.models.document import Document
from app.schemas.documents import DocumentOut, DocumentPatch, IngestTextRequest, JobAccepted
from app.services.documents import delete_document, get_owned_doc, patch_document, retry_document
from app.services.ingest import enqueue_ingest_file, enqueue_ingest_text
from app.workers.ingest import process_ingest_job

router = APIRouter(prefix="/documents", tags=["documents"])


def _limit_ingest(request: Request) -> None:
    s = get_settings()
    if s.app_env == "test":
        return
    limiter.check(f"ingest:{client_ip(request)}", s.ingest_limit_per_min, 60.0)


async def _out(
    db: AsyncSession,
    d: Document,
    *,
    include_text: bool = False,
    highlight: str | None = None,
    count_chunks: bool = True,
) -> dict:
    nchunks = 0
    if count_chunks:
        nchunks = await db.scalar(select(func.count()).select_from(Chunk).where(Chunk.document_id == d.id))
    hs = he = hp = None
    snippet = None
    if highlight:
        ch = await db.scalar(select(Chunk).where(Chunk.id == highlight, Chunk.document_id == d.id))
        if ch is not None:
            hs, he = ch.start_char, ch.end_char
            hp = ch.page
            snippet = (ch.text or "")[:500]
            if hp is None and d.source_type == "pdf":
                from app.services.pdf_extract import page_for_char

                hp = page_for_char(d.raw_text, ch.start_char, d.source_type)
    return DocumentOut(
        id=d.id,
        title=d.title,
        source_type=d.source_type,
        tags=json.loads(d.tags or "[]"),
        created_at=d.created_at,
        status=d.status,
        char_count=d.char_count,
        chunk_count=int(nchunks or 0),
        page_count=d.page_count,
        error=d.error,
        text=d.raw_text if include_text else None,
        highlight_start=hs,
        highlight_end=he,
        highlight_page=hp,
        highlight_snippet=snippet,
    ).model_dump(mode="json")


@router.post("/ingest-text", status_code=202, response_model=JobAccepted)
async def ingest_text(
    request: Request,
    body: IngestTextRequest,
    background: BackgroundTasks,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    x_idempotency_key: Annotated[str | None, Header()] = None,
) -> JobAccepted:
    _limit_ingest(request)
    accepted = await enqueue_ingest_text(
        db,
        user_id=user_id,
        title=body.title,
        text=body.text,
        tags=body.tags,
        idempotency_key=x_idempotency_key,
    )
    background.add_task(process_ingest_job, accepted.job_id)
    return accepted


@router.post("/ingest-file", status_code=202, response_model=JobAccepted)
async def ingest_file(
    request: Request,
    background: BackgroundTasks,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    file: Annotated[UploadFile, File()],
    title: Annotated[str | None, Form()] = None,
    duration_seconds: Annotated[float | None, Form()] = None,
    x_idempotency_key: Annotated[str | None, Header()] = None,
) -> JobAccepted:
    _limit_ingest(request)
    blob = await file.read()
    accepted = await enqueue_ingest_file(
        db,
        user_id=user_id,
        title=title or (file.filename or "Upload"),
        blob=blob,
        tags=[],
        idempotency_key=x_idempotency_key,
        duration_hint=duration_seconds,
        filename=file.filename or "",
    )
    background.add_task(process_ingest_job, accepted.job_id)
    return accepted


@router.get("")
async def list_documents(
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    limit: int = 30,
    cursor: str | None = None,
    source_type: str | None = None,
    tag: str | None = None,
    from_: str | None = Query(default=None, alias="from"),
    to: str | None = None,
) -> dict:
    limit = min(max(limit, 1), 100)
    q = select(Document).where(Document.user_id == user_id)
    if source_type:
        q = q.where(Document.source_type == source_type)
    if tag:
        q = q.where(func.lower(Document.tags).like(f'%"{tag.lower()}"%'))
    if from_:
        raw = from_.strip()
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        start = datetime.fromisoformat(raw)
        if start.tzinfo is None:
            start = start.replace(tzinfo=timezone.utc)
        q = q.where(Document.created_at >= start)
    if to:
        raw = to.strip()
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        end = datetime.fromisoformat(raw)
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)
        q = q.where(Document.created_at <= end)
    q = q.order_by(Document.created_at.desc())
    rows = (await db.scalars(q.limit(limit + 1))).all()
    extra = rows[limit:]
    rows = rows[:limit]
    data = [await _out(db, d, count_chunks=False) for d in rows]
    return {"data": data, "next_cursor": extra[0].id if extra else None}


@router.get("/{doc_id}/audio")
async def document_audio(
    doc_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
):
    d = await get_owned_doc(db, user_id=user_id, doc_id=doc_id)
    if d.source_type != "voice":
        raise AppError(404, "NOT_FOUND", "Not a voice memo")
    from app.services.audio import load_media_bytes

    loaded = load_media_bytes(d.id)
    if loaded is None:
        raise AppError(404, "NOT_FOUND", "Audio file not stored")
    blob, ext = loaded
    mime = {
        "wav": "audio/wav",
        "webm": "audio/webm",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "ogg": "audio/ogg",
    }.get(ext, "application/octet-stream")
    return Response(content=blob, media_type=mime)


@router.get("/{doc_id}/pages/{page}")
async def document_page_png(
    doc_id: str,
    page: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
):
    d = await get_owned_doc(db, user_id=user_id, doc_id=doc_id)
    from app.services.pdf_extract import pdf_path, render_page_png

    path = pdf_path(d.id)
    if not path.exists():
        raise AppError(404, "NOT_FOUND", "Original PDF not stored for this document")
    png = render_page_png(path.read_bytes(), page)
    if not png:
        raise AppError(404, "NOT_FOUND", "Could not render page")
    return Response(content=png, media_type="image/png")


@router.get("/{doc_id}")
async def get_document(
    doc_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
    highlight: str | None = None,
) -> dict:
    d = await get_owned_doc(db, user_id=user_id, doc_id=doc_id)
    return await _out(db, d, include_text=True, highlight=highlight)


@router.patch("/{doc_id}")
async def patch_doc(
    doc_id: str,
    body: DocumentPatch,
    background: BackgroundTasks,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    d, job = await patch_document(
        db,
        user_id=user_id,
        doc_id=doc_id,
        title=body.title,
        tags=body.tags,
        text=body.text,
    )
    if job is not None:
        background.add_task(process_ingest_job, job.id)
    out = await _out(db, d)
    if job is not None:
        out["job_id"] = job.id
    return out


@router.delete("/{doc_id}")
async def delete_doc(
    doc_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict:
    await delete_document(db, user_id=user_id, doc_id=doc_id)
    return {"deleted": True}


@router.post("/{doc_id}/retry", status_code=202, response_model=JobAccepted)
async def retry_doc(
    doc_id: str,
    background: BackgroundTasks,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> JobAccepted:
    job = await retry_document(db, user_id=user_id, doc_id=doc_id)
    background.add_task(process_ingest_job, job.id)
    return JobAccepted(job_id=job.id, document_id=doc_id, status="queued")
