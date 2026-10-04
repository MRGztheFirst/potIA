from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger("potia.errors")

_FIELD_LABELS = {
    "name": "nome",
    "email": "e-mail",
    "password": "senha",
    "messages": "mensagens",
    "content": "conteúdo da mensagem",
    "role": "papel da mensagem",
    "temperature": "temperatura",
    "max_tokens": "máximo de tokens",
}


def translate_validation_error(error: dict[str, Any]) -> str:
    location = [part for part in error.get("loc", ()) if isinstance(part, str) and part != "body"]
    field = location[-1] if location else ""
    label = _FIELD_LABELS.get(field, field or "requisição")
    kind = error.get("type", "")
    ctx = error.get("ctx") or {}

    if kind == "missing":
        return f"O campo '{label}' é obrigatório."
    if kind == "string_too_short":
        return f"O campo '{label}' deve ter pelo menos {ctx.get('min_length')} caracteres."
    if kind == "string_too_long":
        return f"O campo '{label}' deve ter no máximo {ctx.get('max_length')} caracteres."
    if kind == "too_short":
        return f"'{label}' deve ter pelo menos {ctx.get('min_length')} item(ns)."
    if kind == "too_long":
        return f"'{label}' deve ter no máximo {ctx.get('max_length')} itens."
    if kind == "literal_error":
        return f"Valor inválido para '{label}'. Opções aceitas: {ctx.get('expected')}."
    if kind == "json_invalid":
        return "O corpo da requisição não é um JSON válido."
    if kind in {"value_error", "assertion_error"}:
        return str(error.get("msg", "")).removeprefix("Value error, ").removeprefix("Assertion failed, ")
    if kind.startswith(("greater_than", "less_than")):
        return f"Valor fora do intervalo permitido para '{label}'."
    return f"Valor inválido para '{label}'."


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def _validation_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
        messages = [translate_validation_error(e) for e in exc.errors()]
        return JSONResponse(
            status_code=422,
            content={"detail": messages[0] if messages else "Dados inválidos.", "errors": messages},
        )

    @app.exception_handler(Exception)
    async def _unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Erro não tratado em %s %s", request.method, request.url.path)
        return JSONResponse(status_code=500, content={"detail": "Erro interno no servidor. Tente novamente."})
