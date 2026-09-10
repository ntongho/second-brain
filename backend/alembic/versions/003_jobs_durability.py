"""003_jobs_durability — documents, chunks, jobs, FTS5

Revision ID: 003_jobs
Revises: 002_auth
Create Date: 2026-09-07
"""

from typing import Sequence, Union

from alembic import op

revision: str = "003_jobs"
down_revision: Union[str, None] = "002_auth"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE documents (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          title TEXT NOT NULL CHECK(length(title)<=200),
          source_type TEXT NOT NULL CHECK(source_type IN ('pdf','text','voice')),
          tags JSON NOT NULL DEFAULT '[]',
          raw_text TEXT NOT NULL,
          char_count INT NOT NULL DEFAULT 0,
          page_count INT,
          language TEXT DEFAULT 'en',
          status TEXT NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','processing','ready','failed')),
          error TEXT,
          file_sha256 TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_doc_hash ON documents(user_id, file_sha256) WHERE file_sha256 IS NOT NULL"
    )
    op.execute("CREATE INDEX ix_docs_user_created ON documents(user_id, created_at DESC)")
    op.execute("CREATE INDEX ix_docs_user_status ON documents(user_id, status)")
    op.execute(
        """
        CREATE TABLE chunks (
          id TEXT PRIMARY KEY,
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          user_id TEXT NOT NULL,
          ord INT NOT NULL,
          text TEXT NOT NULL,
          start_char INT NOT NULL,
          end_char INT NOT NULL,
          page INT,
          token_count INT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(document_id, ord)
        )
        """
    )
    op.execute("CREATE INDEX ix_chunks_doc ON chunks(document_id, ord)")
    op.execute(
        """
        CREATE TABLE jobs (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          document_id TEXT,
          kind TEXT CHECK(kind IN ('ingest_text','ingest_file','transcribe','backup')) NOT NULL,
          status TEXT CHECK(status IN ('queued','processing','done','failed')) DEFAULT 'queued',
          progress REAL DEFAULT 0,
          error TEXT,
          attempts INT NOT NULL DEFAULT 0,
          max_attempts INT NOT NULL DEFAULT 3,
          worker_id TEXT,
          started_at DATETIME,
          heartbeat_at DATETIME,
          finished_at DATETIME,
          idempotency_key TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_jobs_idem ON jobs(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL"
    )
    op.execute("CREATE INDEX ix_jobs_claim ON jobs(status, heartbeat_at)")
    op.execute(
        "CREATE VIRTUAL TABLE chunks_fts USING fts5("
        "chunk_id UNINDEXED, document_id UNINDEXED, user_id UNINDEXED, text, tokenize='porter')"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS chunks_fts")
    op.execute("DROP TABLE IF EXISTS jobs")
    op.execute("DROP TABLE IF EXISTS chunks")
    op.execute("DROP TABLE IF EXISTS documents")
