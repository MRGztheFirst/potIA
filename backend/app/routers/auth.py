from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, status

from ..config import Settings
from ..database import EmailAlreadyRegisteredError
from ..deps import CurrentUser, SettingsDep, UsersDep
from ..schemas import LoginRequest, RegisterRequest, TokenResponse, UserOut
from ..security import create_access_token, dummy_hash, hash_password, verify_password

router = APIRouter(prefix="/api/v1/auth", tags=["Autenticação"])


def _token_response(user: dict[str, Any], settings: Settings) -> TokenResponse:
    token, expires_in = create_access_token(user["id"], settings)
    return TokenResponse(access_token=token, expires_in=expires_in, user=UserOut(**user))


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(body: RegisterRequest, settings: SettingsDep, users: UsersDep) -> TokenResponse:
    password_hash = hash_password(body.password, iterations=settings.password_iterations)
    try:
        user = users.create(body.name, body.email, password_hash)
    except EmailAlreadyRegisteredError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Este e-mail já está cadastrado.") from None
    return _token_response(user, settings)


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, settings: SettingsDep, users: UsersDep) -> TokenResponse:
    user = users.get_by_email(body.email)
    if user is None:
        verify_password(body.password, dummy_hash(settings.password_iterations))
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "E-mail ou senha incorretos.")
    if not verify_password(body.password, user["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "E-mail ou senha incorretos.")
    return _token_response(user, settings)


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser) -> UserOut:
    return UserOut(**user)
