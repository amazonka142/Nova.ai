import os
from dataclasses import dataclass

DEFAULT_DATABASE_URL = "postgresql+psycopg2://postgres:postgres@localhost:5432/nova_ai"


def _read_bool_env(var_name: str, default: bool = False) -> bool:
    raw = os.getenv(var_name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    database_url: str
    sqlalchemy_echo: bool


settings = Settings(
    database_url=os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL),
    sqlalchemy_echo=_read_bool_env("SQLALCHEMY_ECHO", default=False),
)
