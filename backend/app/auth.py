from dataclasses import dataclass
from functools import lru_cache
from typing import Optional

import firebase_admin
from fastapi import Header, HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials
from firebase_admin.exceptions import FirebaseError

from .config import settings


@dataclass(frozen=True)
class AuthContext:
    firebase_uid: str
    is_admin: bool = False


def _extract_bearer_token(authorization: Optional[str]) -> str:
    if authorization is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header.",
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header must use the Bearer scheme.",
        )
    return token.strip()


@lru_cache(maxsize=1)
def get_firebase_app():
    try:
        return firebase_admin.get_app()
    except ValueError:
        options: dict[str, str] = {}
        if settings.firebase_project_id is not None:
            options["projectId"] = settings.firebase_project_id

        if settings.firebase_credentials_path is not None:
            credential = credentials.Certificate(settings.firebase_credentials_path)
            return firebase_admin.initialize_app(credential=credential, options=options or None)

        return firebase_admin.initialize_app(options=options or None)


def get_auth_context(authorization: Optional[str] = Header(default=None, alias="Authorization")) -> AuthContext:
    token = _extract_bearer_token(authorization)

    try:
        firebase_app = get_firebase_app()
    except Exception as exc:  # pragma: no cover - configuration failures depend on runtime env
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Firebase authentication is not configured on the server.",
        ) from exc

    try:
        decoded_token = firebase_auth.verify_id_token(token, app=firebase_app, check_revoked=False)
    except (FirebaseError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
        ) from exc

    firebase_uid = decoded_token.get("uid") or decoded_token.get("user_id") or decoded_token.get("sub")
    if not isinstance(firebase_uid, str) or not firebase_uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
        )

    return AuthContext(
        firebase_uid=firebase_uid,
        is_admin=bool(decoded_token.get("admin")),
    )


def ensure_firebase_uid_access(firebase_uid: str, auth_context: AuthContext) -> None:
    if auth_context.is_admin:
        return
    if firebase_uid != auth_context.firebase_uid:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this user.",
        )
