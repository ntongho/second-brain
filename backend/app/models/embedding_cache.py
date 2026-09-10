from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, Integer, LargeBinary, String, PrimaryKeyConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class EmbeddingCache(Base):
    __tablename__ = "embedding_cache"
    __table_args__ = (PrimaryKeyConstraint("text_sha256", "model", name="pk_embed_cache"),)

    text_sha256: Mapped[str] = mapped_column(String, nullable=False)
    model: Mapped[str] = mapped_column(String, nullable=False)
    vector: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    dim: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
