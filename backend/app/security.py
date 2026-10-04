from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any

import jwt

from .config import Settings

_ALGORITHM = "pbkdf2_sha256"


def hash_password(password: str, *, iterations: int) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return "$".join(
        [_ALGORITHM, str(iterations), base64.b64encode(salt).decode(), base64.b64encode(digest).decode()]
    )


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        algorithm, iterations, salt_b64, digest_b64 = stored_hash.split("$")
        if algorithm != _ALGORITHM:
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(digest_b64)
        candidate = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iterations))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(candidate, expected)


@lru_cache(maxsize=4)
def dummy_hash(iterations: int) -> str:
    return hash_password(secrets.token_urlsafe(16), iterations=iterations)


def create_access_token(user_id: int, settings: Settings) -> tuple[str, int]:
    now = datetime.now(timezone.utc)
    expires_in = settings.access_token_expire_minutes * 60
    payload = {"sub": str(user_id), "iat": now, "exp": now + timedelta(seconds=expires_in), "type": "access"}
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_in


def decode_access_token(token: str, settings: Settings) -> dict[str, Any]:
    payload = jwt.decode(
        token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        options={"require": ["exp", "sub"]},
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("tipo de token inválido")
    return payload
