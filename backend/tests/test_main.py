import uuid

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app, parse_uuid


class _DummyDB:
    def execute(self, *_args, **_kwargs):
        return 1

    def close(self):
        return None


def _override_get_db():
    db = _DummyDB()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _override_get_db
client = TestClient(app)


def test_health_endpoint_returns_ok():
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
