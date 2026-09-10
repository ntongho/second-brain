from __future__ import annotations

from pydantic import ConfigDict, Field, field_validator

from app.schemas.common import StrictModel


class AskFilters(StrictModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    source_types: list[str] | None = None
    document_ids: list[str] | None = Field(default=None, max_length=20)
    tags: list[str] | None = Field(default=None, max_length=20)
    from_: str | None = Field(default=None, alias="from")
    to: str | None = None


class AskRequest(StrictModel):
    query: str = Field(min_length=1, max_length=2000)
    chat_id: str | None = None
    top_k: int = Field(default=6, ge=1, le=12)
    filters: AskFilters | None = None
    include_debug: bool = False

    @field_validator("query")
    @classmethod
    def not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("query must not be blank")
        return v


class CitationOut(StrictModel):
    chunk_id: str
    document_id: str
    title: str
    page: int | None = None
    start_char: int | None = None
    end_char: int | None = None
    score: float
    retrieval: str | None = None
    snippet: str
