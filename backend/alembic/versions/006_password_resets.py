"""006_password_resets — forgot-password codes

Revision ID: 006_password_resets
Revises: 005_backups
Create Date: 2026-09-10
"""

from typing import Sequence, Union

from alembic import op

revision: str = "006_password_resets"
down_revision: Union[str, None] = "005_backups"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE password_resets (
          id TEXT PRIMARY KEY,
          email TEXT NOT NULL,
          code_sha256 TEXT NOT NULL,
          expires_at DATETIME NOT NULL,
          used BOOL NOT NULL DEFAULT 0,
          created_at DATETIME NOT NULL
        )
        """
    )
    op.execute("CREATE INDEX ix_password_resets_email ON password_resets(email)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS password_resets")
