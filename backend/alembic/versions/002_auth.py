"""002_auth — users + refresh_tokens (F0)

Revision ID: 002_auth
Revises:
Create Date: 2026-09-04
"""

from typing import Sequence, Union

from alembic import op

revision: str = "002_auth"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("PRAGMA foreign_keys=ON")
    op.execute(
        """
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          email TEXT UNIQUE NOT NULL CHECK(email LIKE '%@%.%'),
          email_hash TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          display_name TEXT DEFAULT '',
          failed_attempts INT NOT NULL DEFAULT 0,
          locked_until DATETIME,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    op.execute("CREATE INDEX ix_users_email ON users(email)")
    op.execute(
        """
        CREATE TABLE refresh_tokens (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          token_sha256 TEXT UNIQUE NOT NULL,
          expires_at DATETIME NOT NULL,
          revoked BOOL NOT NULL DEFAULT 0,
          revoked_reason TEXT,
          replaced_by TEXT REFERENCES refresh_tokens(id),
          last_used_at DATETIME,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    op.execute("CREATE INDEX ix_rt_user ON refresh_tokens(user_id, revoked, expires_at)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS refresh_tokens")
    op.execute("DROP TABLE IF EXISTS users")
