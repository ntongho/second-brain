"""005_backups — snapshot catalog for daily SQLite+Chroma backups

Revision ID: 005_backups
Revises: 004_cache
Create Date: 2026-09-10
"""

from typing import Sequence, Union

from alembic import op

revision: str = "005_backups"
down_revision: Union[str, None] = "004_cache"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE backups (
          id TEXT PRIMARY KEY,
          path TEXT NOT NULL,
          size_bytes INT NOT NULL DEFAULT 0,
          sqlite_ok INT NOT NULL DEFAULT 0,
          chroma_ok INT NOT NULL DEFAULT 0,
          error TEXT,
          created_at DATETIME NOT NULL
        )
        """
    )
    op.execute("CREATE INDEX ix_backups_created ON backups(created_at DESC)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS backups")
