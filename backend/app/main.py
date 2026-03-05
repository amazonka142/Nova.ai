import base64
import binascii
import uuid
from datetime import datetime, timezone
from typing import List

from fastapi import Depends, FastAPI, HTTPException, Query, status
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import get_db
from .models import Chat, Message, MessageRole, MessageType, User
from .schemas import (
    ChatCreate,
    ChatRead,
    MessageCreate,
    MessageRead,
    UserRead,
    UserUpsert,
)

app = FastAPI(title="Nova.ai Backend", version="0.1.0")
MAX_IMAGE_BYTES = 5 * 1024 * 1024


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def parse_uuid(raw_value: str, field_name: str) -> uuid.UUID:
    try:
        return uuid.UUID(raw_value)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} must be a valid UUID",
        ) from exc


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict:
    db.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.post("/users", response_model=UserRead)
def upsert_user(payload: UserUpsert, db: Session = Depends(get_db)) -> UserRead:
    user = db.scalar(select(User).where(User.firebase_uid == payload.firebase_uid))

    if user is None:
        user = User(firebase_uid=payload.firebase_uid)
        db.add(user)

    if payload.email is not None:
        user.email = payload.email

    for field in (
        "is_pro",
        "is_max",
        "admin_note",
        "subscription_expires_at",
        "daily_request_count",
        "model_usage",
        "weekly_model_usage",
        "last_request_at",
        "last_weekly_reset_at",
    ):
        value = getattr(payload, field)
        if value is not None:
            setattr(user, field, value)

    user.updated_at = utcnow()

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User with this email already exists.",
        ) from exc

    db.refresh(user)
    return UserRead.model_validate(user)


@app.get("/users/{firebase_uid}", response_model=UserRead)
def get_user(firebase_uid: str, db: Session = Depends(get_db)) -> UserRead:
    user = db.scalar(select(User).where(User.firebase_uid == firebase_uid))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return UserRead.model_validate(user)


@app.post("/users/{firebase_uid}/chats", response_model=ChatRead, status_code=status.HTTP_201_CREATED)
def create_chat(firebase_uid: str, payload: ChatCreate, db: Session = Depends(get_db)) -> ChatRead:
    user = db.scalar(select(User).where(User.firebase_uid == firebase_uid))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    chat = Chat(
        user_id=user.id,
        external_id=payload.external_id,
        title=payload.title,
        model=payload.model,
        last_modified=payload.last_modified or utcnow(),
    )
    db.add(chat)

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Chat with this external_id already exists for the user.",
        ) from exc

    db.refresh(chat)
    return ChatRead.model_validate(chat)


@app.get("/users/{firebase_uid}/chats", response_model=List[ChatRead])
def list_chats(
    firebase_uid: str,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
) -> List[ChatRead]:
    user = db.scalar(select(User).where(User.firebase_uid == firebase_uid))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    chats = db.scalars(
        select(Chat)
        .where(Chat.user_id == user.id)
        .order_by(Chat.last_modified.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    return [ChatRead.model_validate(chat) for chat in chats]


@app.post("/chats/{chat_id}/messages", response_model=MessageRead, status_code=status.HTTP_201_CREATED)
def create_message(chat_id: str, payload: MessageCreate, db: Session = Depends(get_db)) -> MessageRead:
    chat_uuid = parse_uuid(chat_id, "chat_id")
    chat = db.get(Chat, chat_uuid)
    if chat is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found")

    image_data = None
    if payload.image_data_base64:
        try:
            image_data = base64.b64decode(payload.image_data_base64, validate=True)
        except binascii.Error as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="image_data_base64 is not valid base64",
            ) from exc
        if len(image_data) > MAX_IMAGE_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"image_data_base64 exceeds {MAX_IMAGE_BYTES} bytes after decoding",
            )

    message = Message(
        chat_id=chat.id,
        external_id=payload.external_id,
        role=MessageRole(payload.role),
        type=MessageType(payload.type),
        content=payload.content,
        image_data=image_data,
        created_at=payload.created_at or utcnow(),
    )
    db.add(message)

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Message with this external_id already exists for the chat.",
        ) from exc

    db.refresh(message)
    return MessageRead.model_validate(message)


@app.get("/chats/{chat_id}/messages", response_model=List[MessageRead])
def list_messages(
    chat_id: str,
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
) -> List[MessageRead]:
    chat_uuid = parse_uuid(chat_id, "chat_id")
    chat = db.get(Chat, chat_uuid)
    if chat is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found")

    messages = db.scalars(
        select(Message)
        .where(Message.chat_id == chat.id)
        .order_by(Message.created_at.asc())
        .limit(limit)
        .offset(offset)
    ).all()
    return [MessageRead.model_validate(message) for message in messages]
