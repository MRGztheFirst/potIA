from __future__ import annotations

import json
import logging
from typing import Any, AsyncIterator

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from ..config import Settings
from ..deps import CurrentUser, EngineDep, SettingsDep
from ..llm_engines import EngineError, GenerationParams, Messages
from ..schemas import ChatMessage, ChatRequest, ChatResponse

router = APIRouter(prefix="/api/v1", tags=["Chat"])
logger = logging.getLogger("potia.chat")


def build_conversation(request: ChatRequest, settings: Settings) -> Messages:
    turns = [m for m in request.messages if m.role != "system"][-settings.max_history_messages :]

    kept: list[ChatMessage] = []
    total_chars = 0
    for message in reversed(turns):
        total_chars += len(message.content)
        if kept and total_chars > settings.max_history_chars:
            break
        kept.append(message)
    kept.reverse()

    merged: Messages = []
    for message in kept:
        if merged and merged[-1]["role"] == message.role:
            merged[-1]["content"] += "\n\n" + message.content
        else:
            merged.append({"role": message.role, "content": message.content})
    while merged and merged[0]["role"] != "user":
        merged.pop(0)

    return [{"role": "system", "content": settings.system_prompt}, *merged]


def build_params(request: ChatRequest, settings: Settings) -> GenerationParams:
    return GenerationParams(
        max_new_tokens=request.max_tokens or settings.max_new_tokens,
        temperature=settings.temperature if request.temperature is None else request.temperature,
        top_p=settings.top_p,
        repetition_penalty=settings.repetition_penalty,
    )


def sse_event(payload: dict[str, Any]) -> str:
    return f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"


@router.post(
    "/chat",
    response_model=ChatResponse,
    responses={200: {"content": {"text/event-stream": {}}, "description": "Stream SSE quando stream=true."}},
)
async def chat(body: ChatRequest, user: CurrentUser, settings: SettingsDep, engine: EngineDep):
    messages = build_conversation(body, settings)
    params = build_params(body, settings)
    logger.info("Chat de user=%s (%d mensagens, engine=%s)", user["id"], len(messages) - 1, engine.name)

    if not body.stream:
        try:
            answer = await engine.generate(messages, params)
        except EngineError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        return ChatResponse(message=ChatMessage(role="assistant", content=answer or "..."), engine=engine.name)

    async def event_stream() -> AsyncIterator[str]:
        try:
            async for chunk in engine.stream(messages, params):
                yield sse_event({"type": "token", "content": chunk})
            yield sse_event({"type": "done"})
        except EngineError as exc:
            yield sse_event({"type": "error", "detail": str(exc)})
        except Exception:
            logger.exception("Erro inesperado durante o streaming")
            yield sse_event({"type": "error", "detail": "Erro interno ao gerar a resposta."})

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
