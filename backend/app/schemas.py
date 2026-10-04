from __future__ import annotations

import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


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
    content: str = Field(min_length=1, max_length=8000)


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
