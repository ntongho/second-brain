from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_id, get_db
from app.core.errors import AppError
from app.models.job import Job
from app.schemas.jobs import JobOut

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.get("/{job_id}", response_model=JobOut)
async def get_job(
    job_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> JobOut:
    job = await db.scalar(select(Job).where(Job.id == job_id, Job.user_id == user_id))
    if job is None:
        raise AppError(404, "NOT_FOUND", "Job not found")
    return JobOut(
        job_id=job.id,
        status=job.status,
        progress=float(job.progress or 0),
        attempts=int(job.attempts or 0),
        max_attempts=int(job.max_attempts or 3),
        document_id=job.document_id,
        error=job.error,
    )
