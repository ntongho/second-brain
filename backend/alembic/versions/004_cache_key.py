"""004_cache_key — embedding_cache compound PK (sha256, model)

Revision ID: 004_cache
Revises: 003_jobs
Create Date: 2026-09-07
"""

from typing import Sequence, Union

from alembic import op

revision: str = "004_cache"
down_revision: Union[str, None] = "003_jobs"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE embedding_cache (
          text_sha256 TEXT NOT NULL,
          model TEXT NOT NULL,
          vector BLOB NOT NULL,
          dim INT NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (text_sha256, model)
        )
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS embedding_cache")
