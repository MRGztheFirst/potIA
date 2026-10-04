from __future__ import annotations

import base64
import binascii
import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

MAX_IMAGES_PER_MESSAGE = 4
MAX_IMAGE_BYTES = 6 * 1024 * 1024
_IMAGE_SIGNATURES = ((b"\xff\xd8\xff", "image/jpeg"), (b"\x89PNG", "image/png"))


def image_mime(data: bytes) -> str | None:
    for signature, mime in _IMAGE_SIGNATURES:
        if data.startswith(signature):
            return mime
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def _clean_image(value: str) -> str:
    encoded = value.split(",", 1)[1] if value.startswith("data:") else value
    encoded = "".join(encoded.split())
    if len(encoded) * 3 // 4 > MAX_IMAGE_BYTES:
        raise ValueError("Cada foto pode ter no máximo 6 MB.")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("Foto inválida: envie a imagem em base64.") from None
    if image_mime(raw) is None:
        raise ValueError("Envie fotos em JPG, PNG ou WebP.")
    return encoded


def _normalize_email(value: str) -> str:
    value = value.strip().lower()
    if not _EMAIL_RE.match(value):
        raise ValueError("Informe um e-mail válido.")
    return value


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80, examples=["Ana Souza"])
    email: str = Field(max_length=254, examples=["ana@exemplo.com"])
    password: str = Field(min_length=8, max_length=128, examples=["receita123"])

    @field_validator("name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        value = " ".join(value.split())
        if len(value) < 2:
            raise ValueError("Informe seu nome.")
        return value

    @field_validator("email")
    @classmethod
    def _email(cls, value: str) -> str:
        return _normalize_email(value)

    @field_validator("password")
    @classmethod
    def _password_strength(cls, value: str) -> str:
        if not re.search(r"[A-Za-zÀ-ÿ]", value) or not re.search(r"\d", value):
            raise ValueError("A senha precisa ter pelo menos uma letra e um número.")
        return value


class LoginRequest(BaseModel):
    email: str = Field(max_length=254, examples=["ana@exemplo.com"])
    password: str = Field(min_length=1, max_length=128, examples=["receita123"])

    @field_validator("email")
    @classmethod
    def _email(cls, value: str) -> str:
        return _normalize_email(value)


class UserOut(BaseModel):
    id: int
    name: str
    email: str
    created_at: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int = Field(description="Validade do token em segundos.")
    user: UserOut


class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str = Field(default="", max_length=24_000)
    images: list[str] = Field(
        default_factory=list,
        max_length=MAX_IMAGES_PER_MESSAGE,
        description="Fotos em base64 (JPG, PNG ou WebP), só em mensagens do usuário.",
    )

    @field_validator("images")
    @classmethod
    def _validate_images(cls, value: list[str]) -> list[str]:
        return [_clean_image(item) for item in value]

    @model_validator(mode="after")
    def _not_empty(self) -> "ChatMessage":
        if self.images and self.role != "user":
            raise ValueError("Só mensagens do usuário podem ter fotos.")
        if not self.content.strip() and not self.images:
            raise ValueError("A mensagem não pode ficar vazia.")
        return self


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(min_length=1, max_length=100, description="Histórico, do mais antigo ao mais novo.")
    stream: bool = Field(default=True, description="true = resposta via Server-Sent Events.")
    temperature: float | None = Field(default=None, ge=0.0, le=2.0)
    max_tokens: int | None = Field(default=None, ge=1, le=4096)

    @model_validator(mode="after")
    def _last_message_from_user(self) -> "ChatRequest":
        if self.messages[-1].role != "user":
            raise ValueError("A última mensagem do histórico deve ser do usuário.")
        return self


class ChatResponse(BaseModel):
    message: ChatMessage
    engine: str
