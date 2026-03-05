"""add chat/message performance indexes

Revision ID: 20260305_0002
Revises: 20260209_0001
Create Date: 2026-03-05 00:00:00.000000

"""

from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "20260305_0002"
down_revision: Union[str, None] = "20260209_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "ix_chats_user_last_modified",
        "chats",
        ["user_id", "last_modified"],
        unique=False,
    )
    op.create_index(
        "ix_messages_chat_created_at",
        "messages",
        ["chat_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_messages_chat_created_at", table_name="messages")
    op.drop_index("ix_chats_user_last_modified", table_name="chats")
