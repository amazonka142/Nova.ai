import os
from dataclasses import dataclass
from typing import Optional

DEFAULT_DATABASE_URL = "postgresql+psycopg2://postgres:postgres@localhost:5432/nova_ai"


def _read_bool_env(var_name: str, default: bool = False) -> bool:
    raw = os.getenv(var_name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _read_optional_env(var_name: str) -> Optional[str]:
    raw = os.getenv(var_name)
    if raw is None:
        return None
    trimmed = raw.strip()
    return trimmed or None


@dataclass(frozen=True)
class Settings:
    database_url: str
    sqlalchemy_echo: bool
    firebase_project_id: Optional[str]
    firebase_credentials_path: Optional[str]


settings = Settings(
    database_url=os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL),
    sqlalchemy_echo=_read_bool_env("SQLALCHEMY_ECHO", default=False),
    firebase_project_id=_read_optional_env("FIREBASE_PROJECT_ID"),
    firebase_credentials_path=_read_optional_env("FIREBASE_CREDENTIALS_PATH"),
)
