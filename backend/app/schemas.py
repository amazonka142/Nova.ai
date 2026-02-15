from datetime import datetime
from typing import Dict, Literal, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class UserUpsert(BaseModel):
    firebase_uid: str = Field(..., min_length=1, max_length=128)
    email: Optional[str] = Field(default=None, max_length=255)

    is_pro: Optional[bool] = None
    is_max: Optional[bool] = None
    admin_note: Optional[str] = None
    subscription_expires_at: Optional[datetime] = None

    daily_request_count: Optional[int] = Field(default=None, ge=0)
    model_usage: Optional[Dict[str, int]] = None
    weekly_model_usage: Optional[Dict[str, int]] = None
    last_request_at: Optional[datetime] = None
    last_weekly_reset_at: Optional[datetime] = None


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    firebase_uid: str
    email: Optional[str]
    is_pro: bool
    is_max: bool
    admin_note: Optional[str]
    subscription_expires_at: Optional[datetime]
    daily_request_count: int
    model_usage: Dict[str, int]
    weekly_model_usage: Dict[str, int]
    last_request_at: Optional[datetime]
    last_weekly_reset_at: Optional[datetime]
    created_at: datetime
    updated_at: datetime


class ChatCreate(BaseModel):
    external_id: str = Field(..., min_length=1, max_length=64)
    title: str = Field(..., min_length=1, max_length=255)
    model: str = Field(..., min_length=1, max_length=64)
    last_modified: Optional[datetime] = None


class ChatRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    external_id: str
    title: str
    model: str
    last_modified: datetime
    created_at: datetime
    updated_at: datetime


class MessageCreate(BaseModel):
    external_id: str = Field(..., min_length=1, max_length=64)
    role: Literal["user", "assistant", "system"]
    type: Literal["text", "image"] = "text"
    content: str = Field(..., min_length=1)
    image_data_base64: Optional[str] = None
    created_at: Optional[datetime] = None


class MessageRead(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)

    id: UUID
    chat_id: UUID
    external_id: str
    role: Literal["user", "assistant", "system"]
    type: Literal["text", "image"]
    content: str
    created_at: datetime
