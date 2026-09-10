from __future__ import annotations

from app.schemas.common import StrictModel


class JobOut(StrictModel):
    job_id: str
    status: str
    progress: float
    attempts: int
    max_attempts: int
    document_id: str | None = None
    error: str | None = None
