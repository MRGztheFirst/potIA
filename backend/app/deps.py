from __future__ import annotations

from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings
from .database import UserRepository
from .llm_engines import LLMEngine
from .security import decode_access_token

_bearer_scheme = HTTPBearer(auto_error=False)


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_users(request: Request) -> UserRepository:
    return request.app.state.users


def get_engine(request: Request) -> LLMEngine:
    return request.app.state.engine


SettingsDep = Annotated[Settings, Depends(get_settings)]
UsersDep = Annotated[UserRepository, Depends(get_users)]
EngineDep = Annotated[LLMEngine, Depends(get_engine)]


def get_current_user(
    settings: SettingsDep,
    users: UsersDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
) -> dict[str, Any]:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Sessão inválida ou expirada. Faça login novamente.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized
    try:
        payload = decode_access_token(credentials.credentials, settings)
        user_id = int(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise unauthorized from None

    user = users.get_by_id(user_id)
    if user is None:
        raise unauthorized
    return user


CurrentUser = Annotated[dict[str, Any], Depends(get_current_user)]
