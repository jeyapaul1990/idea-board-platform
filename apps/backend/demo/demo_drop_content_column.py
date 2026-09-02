"""DEMO ONLY — destructive migration for AI Release Risk Analyst video.

DO NOT apply on main. Copy to alembic/versions/ on branch demo/risky-migration.

Revision ID: demo_drop_content
Revises: 001
Create Date: 2026-09-01
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "demo_drop_content"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_column("ideas", "content")


def downgrade() -> None:
    op.add_column("ideas", sa.Column("content", sa.Text(), nullable=False))
