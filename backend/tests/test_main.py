import base64
import uuid
from datetime import datetime, timezone
from typing import Optional

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.auth import AuthContext, get_auth_context
from app.db import get_db
from app.main import app, parse_uuid
from app.models import Chat, Message, MessageRole, MessageType, User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _build_user(firebase_uid: str = "user-1", email: Optional[str] = "user@example.com") -> User:
    now = _utcnow()
    user = User(firebase_uid=firebase_uid)
    user.id = uuid.uuid4()
    user.email = email
    user.is_pro = False
    user.is_max = False
    user.admin_note = None
    user.subscription_expires_at = None
    user.daily_request_count = 0
    user.model_usage = {}
    user.weekly_model_usage = {}
    user.last_request_at = None
    user.last_weekly_reset_at = None
    user.created_at = now
    user.updated_at = now
    return user


def _build_chat(user_id: uuid.UUID, external_id: str = "chat-ext-1") -> Chat:
    now = _utcnow()
    chat = Chat(
        user_id=user_id,
        external_id=external_id,
        title="Test chat",
        model="gemini-fast",
        last_modified=now,
    )
    chat.id = uuid.uuid4()
    chat.created_at = now
    chat.updated_at = now
    return chat


def _build_message(
    chat_id: uuid.UUID,
    external_id: str = "msg-ext-1",
    type_: MessageType = MessageType.text,
    image_data: Optional[bytes] = None,
) -> Message:
    now = _utcnow()
    message = Message(
        chat_id=chat_id,
        external_id=external_id,
        role=MessageRole.user,
        type=type_,
        content="hello",
        image_data=image_data,
        created_at=now,
    )
    message.id = uuid.uuid4()
    return message


class _FakeScalarsResult:
    def __init__(self, items):
        self._items = items

    def all(self):
        return self._items


class _FakeDB:
    def __init__(self):
        self.scalar_values = []
        self.scalars_values = []
        self.get_values = {}
        self.commit_exception = None
        self.did_rollback = False

    def execute(self, *_args, **_kwargs):
        return 1

    def scalar(self, *_args, **_kwargs):
        if self.scalar_values:
            return self.scalar_values.pop(0)
        return None

    def scalars(self, *_args, **_kwargs):
        items = self.scalars_values.pop(0) if self.scalars_values else []
        return _FakeScalarsResult(items)

    def get(self, _model, key):
        return self.get_values.get(key)

    def add(self, _obj):
        return None

    def commit(self):
        if self.commit_exception is not None:
            raise self.commit_exception

    def rollback(self):
        self.did_rollback = True

    def refresh(self, obj):
        now = _utcnow()
        if isinstance(obj, User):
            obj.id = obj.id or uuid.uuid4()
            obj.is_pro = bool(getattr(obj, "is_pro", False))
            obj.is_max = bool(getattr(obj, "is_max", False))
            obj.model_usage = getattr(obj, "model_usage", None) or {}
            obj.weekly_model_usage = getattr(obj, "weekly_model_usage", None) or {}
            obj.daily_request_count = getattr(obj, "daily_request_count", 0) or 0
            obj.created_at = getattr(obj, "created_at", None) or now
            obj.updated_at = now
            return

        if isinstance(obj, Chat):
            obj.id = obj.id or uuid.uuid4()
            obj.title = obj.title or "New Chat"
            obj.model = obj.model or "gemini-fast"
            obj.last_modified = obj.last_modified or now
            obj.created_at = getattr(obj, "created_at", None) or now
            obj.updated_at = now
            return

        if isinstance(obj, Message):
            obj.id = obj.id or uuid.uuid4()
            obj.role = obj.role or MessageRole.user
            obj.type = obj.type or MessageType.text
            obj.content = obj.content or ""
            obj.created_at = obj.created_at or now

    def close(self):
        return None


@pytest.fixture
def fake_db():
    return _FakeDB()


@pytest.fixture
def auth_state():
    return {"firebase_uid": "firebase-1", "is_admin": False}


@pytest.fixture
def client(fake_db, auth_state):
    def _override_get_db():
        try:
            yield fake_db
        finally:
            fake_db.close()

    def _override_get_auth_context():
        return AuthContext(
            firebase_uid=auth_state["firebase_uid"],
            is_admin=auth_state["is_admin"],
        )

    app.dependency_overrides[get_db] = _override_get_db
    app.dependency_overrides[get_auth_context] = _override_get_auth_context
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_health_endpoint_returns_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_parse_uuid_valid_value():
    raw = str(uuid.uuid4())
    parsed = parse_uuid(raw, "chat_id")
    assert parsed == uuid.UUID(raw)


def test_parse_uuid_invalid_value_returns_http_400():
    with pytest.raises(HTTPException) as exc_info:
        parse_uuid("not-a-uuid", "chat_id")
    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "chat_id must be a valid UUID"


def test_upsert_user_creates_new_user(client, auth_state):
    auth_state["firebase_uid"] = "firebase-1"
    response = client.post("/users", json={"firebase_uid": "firebase-1", "email": "new@example.com"})
    assert response.status_code == 200
    body = response.json()
    assert body["firebase_uid"] == "firebase-1"
    assert body["email"] == "new@example.com"
    assert body["is_pro"] is False
    assert body["is_max"] is False


def test_upsert_user_updates_existing_user(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-1"
    existing = _build_user(firebase_uid="firebase-1", email="old@example.com")
    fake_db.scalar_values = [existing]
    response = client.post(
        "/users",
        json={"firebase_uid": "firebase-1", "email": "new@example.com"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "new@example.com"
    assert body["is_pro"] is False


def test_upsert_user_rejects_admin_only_fields_for_non_admin(client, auth_state):
    auth_state["firebase_uid"] = "firebase-1"
    response = client.post(
        "/users",
        json={"firebase_uid": "firebase-1", "is_pro": True},
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "Only admins can update subscription or usage fields."


def test_upsert_user_allows_admin_only_fields_for_admin(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "admin-user"
    auth_state["is_admin"] = True
    existing = _build_user(firebase_uid="firebase-1", email="old@example.com")
    fake_db.scalar_values = [existing]
    response = client.post(
        "/users",
        json={"firebase_uid": "firebase-1", "is_pro": True},
    )
    assert response.status_code == 200
    assert response.json()["is_pro"] is True


def test_upsert_user_returns_409_on_integrity_error(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-2"
    fake_db.commit_exception = IntegrityError("INSERT", {}, Exception("duplicate"))
    response = client.post("/users", json={"firebase_uid": "firebase-2", "email": "dup@example.com"})
    assert response.status_code == 409
    assert response.json()["detail"] == "User with this email already exists."
    assert fake_db.did_rollback is True


def test_get_user_returns_404_when_missing(client, auth_state):
    auth_state["firebase_uid"] = "unknown"
    response = client.get("/users/unknown")
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


def test_get_user_returns_403_for_other_user(client, auth_state):
    auth_state["firebase_uid"] = "firebase-1"
    response = client.get("/users/firebase-2")
    assert response.status_code == 403
    assert response.json()["detail"] == "You do not have access to this user."


def test_get_user_returns_user(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-3"
    fake_db.scalar_values = [_build_user(firebase_uid="firebase-3", email="user3@example.com")]
    response = client.get("/users/firebase-3")
    assert response.status_code == 200
    assert response.json()["firebase_uid"] == "firebase-3"


def test_create_chat_returns_403_for_other_user(client, auth_state):
    auth_state["firebase_uid"] = "firebase-1"
    payload = {"external_id": "chat-ext-1", "title": "Chat 1", "model": "gemini-fast"}
    response = client.post("/users/firebase-2/chats", json=payload)
    assert response.status_code == 403
    assert response.json()["detail"] == "You do not have access to this user."


def test_create_chat_returns_404_when_user_missing(client, auth_state):
    auth_state["firebase_uid"] = "missing"
    payload = {"external_id": "chat-ext-1", "title": "Chat 1", "model": "gemini-fast"}
    response = client.post("/users/missing/chats", json=payload)
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


def test_create_chat_returns_201(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-4"
    user = _build_user(firebase_uid="firebase-4")
    fake_db.scalar_values = [user]
    payload = {"external_id": "chat-ext-2", "title": "Chat 2", "model": "gemini-fast"}
    response = client.post("/users/firebase-4/chats", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["external_id"] == "chat-ext-2"
    assert body["title"] == "Chat 2"


def test_create_chat_returns_409_on_integrity_error(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-5"
    user = _build_user(firebase_uid="firebase-5")
    fake_db.scalar_values = [user]
    fake_db.commit_exception = IntegrityError("INSERT", {}, Exception("duplicate chat"))
    payload = {"external_id": "chat-ext-dup", "title": "Dup", "model": "gemini-fast"}
    response = client.post("/users/firebase-5/chats", json=payload)
    assert response.status_code == 409
    assert response.json()["detail"] == "Chat with this external_id already exists for the user."
    assert fake_db.did_rollback is True


def test_list_chats_returns_404_when_user_missing(client, auth_state):
    auth_state["firebase_uid"] = "unknown"
    response = client.get("/users/unknown/chats")
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


def test_list_chats_returns_chats(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-6"
    user = _build_user(firebase_uid="firebase-6")
    chat_one = _build_chat(user.id, external_id="chat-ext-a")
    chat_two = _build_chat(user.id, external_id="chat-ext-b")
    fake_db.scalar_values = [user]
    fake_db.scalars_values = [[chat_one, chat_two]]
    response = client.get("/users/firebase-6/chats")
    assert response.status_code == 200
    body = response.json()
    assert len(body) == 2
    assert {body[0]["external_id"], body[1]["external_id"]} == {"chat-ext-a", "chat-ext-b"}


def test_create_message_returns_400_for_invalid_chat_uuid(client):
    payload = {"external_id": "msg-1", "role": "user", "type": "text", "content": "hello"}
    response = client.post("/chats/not-a-uuid/messages", json=payload)
    assert response.status_code == 400
    assert response.json()["detail"] == "chat_id must be a valid UUID"


def test_create_message_returns_404_when_chat_missing(client):
    payload = {"external_id": "msg-2", "role": "user", "type": "text", "content": "hello"}
    response = client.post(f"/chats/{uuid.uuid4()}/messages", json=payload)
    assert response.status_code == 404
    assert response.json()["detail"] == "Chat not found"


def test_create_message_returns_404_for_chat_owned_by_other_user(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-1"
    owner = _build_user(firebase_uid="firebase-2")
    chat = _build_chat(user_id=owner.id, external_id="chat-owned-by-someone-else")
    fake_db.get_values[chat.id] = chat
    fake_db.scalar_values = [_build_user(firebase_uid="firebase-1")]
    payload = {"external_id": "msg-2b", "role": "user", "type": "text", "content": "hello"}
    response = client.post(f"/chats/{chat.id}/messages", json=payload)
    assert response.status_code == 404
    assert response.json()["detail"] == "Chat not found"


def test_create_message_returns_400_for_invalid_base64(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-7"
    request_user = _build_user(firebase_uid="firebase-7")
    chat = _build_chat(user_id=request_user.id, external_id="chat-base64")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    payload = {
        "external_id": "msg-3",
        "role": "user",
        "type": "image",
        "content": "image",
        "image_data_base64": "not-base64",
    }
    response = client.post(f"/chats/{chat.id}/messages", json=payload)
    assert response.status_code == 400
    assert response.json()["detail"] == "image_data_base64 is not valid base64"


def test_create_message_returns_413_for_too_large_image(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-8"
    request_user = _build_user(firebase_uid="firebase-8")
    chat = _build_chat(user_id=request_user.id, external_id="chat-large-image")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    too_large_bytes = b"a" * ((5 * 1024 * 1024) + 1)
    payload = {
        "external_id": "msg-large",
        "role": "user",
        "type": "image",
        "content": "image",
        "image_data_base64": base64.b64encode(too_large_bytes).decode("utf-8"),
    }
    response = client.post(f"/chats/{chat.id}/messages", json=payload)
    assert response.status_code == 413
    assert "exceeds" in response.json()["detail"]


def test_create_message_returns_201(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-9"
    request_user = _build_user(firebase_uid="firebase-9")
    chat = _build_chat(user_id=request_user.id, external_id="chat-ok")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    payload = {"external_id": "msg-4", "role": "assistant", "type": "text", "content": "done"}
    response = client.post(f"/chats/{chat.id}/messages", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["chat_id"] == str(chat.id)
    assert body["role"] == "assistant"
    assert body["type"] == "text"
    assert body["content"] == "done"
    assert body["image_data_base64"] is None


def test_create_message_returns_image_payload(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-10"
    request_user = _build_user(firebase_uid="firebase-10")
    chat = _build_chat(user_id=request_user.id, external_id="chat-image")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    image_bytes = b"tiny-image"
    payload = {
        "external_id": "msg-image",
        "role": "assistant",
        "type": "image",
        "content": "image",
        "image_data_base64": base64.b64encode(image_bytes).decode("utf-8"),
    }
    response = client.post(f"/chats/{chat.id}/messages", json=payload)
    assert response.status_code == 201
    assert response.json()["image_data_base64"] == base64.b64encode(image_bytes).decode("ascii")


def test_create_message_returns_409_on_integrity_error(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-11"
    request_user = _build_user(firebase_uid="firebase-11")
    chat = _build_chat(user_id=request_user.id, external_id="chat-dup-msg")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    fake_db.commit_exception = IntegrityError("INSERT", {}, Exception("duplicate message"))
    payload = {"external_id": "msg-dup", "role": "user", "type": "text", "content": "hello"}
    response = client.post(f"/chats/{chat.id}/messages", json=payload)
    assert response.status_code == 409
    assert response.json()["detail"] == "Message with this external_id already exists for the chat."
    assert fake_db.did_rollback is True


def test_list_messages_returns_404_when_chat_missing(client):
    response = client.get(f"/chats/{uuid.uuid4()}/messages")
    assert response.status_code == 404
    assert response.json()["detail"] == "Chat not found"


def test_list_messages_returns_messages(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-12"
    request_user = _build_user(firebase_uid="firebase-12")
    chat = _build_chat(user_id=request_user.id, external_id="chat-list-msg")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    msg_one = _build_message(chat.id, external_id="msg-one")
    msg_two = _build_message(chat.id, external_id="msg-two")
    fake_db.scalars_values = [[msg_one, msg_two]]

    response = client.get(f"/chats/{chat.id}/messages?limit=2&offset=0")
    assert response.status_code == 200
    body = response.json()
    assert len(body) == 2
    assert {body[0]["external_id"], body[1]["external_id"]} == {"msg-one", "msg-two"}


def test_list_messages_returns_image_payload(client, fake_db, auth_state):
    auth_state["firebase_uid"] = "firebase-13"
    request_user = _build_user(firebase_uid="firebase-13")
    chat = _build_chat(user_id=request_user.id, external_id="chat-list-image")
    fake_db.scalar_values = [request_user]
    fake_db.get_values[chat.id] = chat
    image_bytes = b"restored-image"
    image_message = _build_message(
        chat.id,
        external_id="msg-image",
        type_=MessageType.image,
        image_data=image_bytes,
    )
    fake_db.scalars_values = [[image_message]]

    response = client.get(f"/chats/{chat.id}/messages")
    assert response.status_code == 200
    body = response.json()
    assert body[0]["image_data_base64"] == base64.b64encode(image_bytes).decode("ascii")


def test_message_factory_has_expected_defaults():
    chat_id = uuid.uuid4()
    message = _build_message(chat_id)
    assert message.chat_id == chat_id
    assert message.role == MessageRole.user
    assert message.type == MessageType.text
