from __future__ import annotations

from datetime import datetime

from pydantic import Field, field_validator

from app.schemas.common import StrictModel


class IngestTextRequest(StrictModel):
    title: str = Field(min_length=1, max_length=200)
    text: str = Field(min_length=1, max_length=500000)
    tags: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("tags")
    @classmethod
    def tag_len(cls, v: list[str]) -> list[str]:
        if len(v) > 20:
            raise ValueError("max 20 tags")
        return v


class JobAccepted(StrictModel):
    job_id: str
    document_id: str
    status: str = "queued"


class DocumentOut(StrictModel):
    id: str
    title: str
    source_type: str
    tags: list[str]
    created_at: datetime
    status: str
    char_count: int = 0
    chunk_count: int = 0
    page_count: int | None = None
    error: str | None = None
    text: str | None = None
    highlight_start: int | None = None
    highlight_end: int | None = None
    highlight_page: int | None = None
    highlight_snippet: str | None = None
    job_id: str | None = None


class DocumentPatch(StrictModel):
    title: str | None = Field(default=None, max_length=200)
    tags: list[str] | None = Field(default=None, max_length=20)
    text: str | None = Field(default=None, max_length=500000)
