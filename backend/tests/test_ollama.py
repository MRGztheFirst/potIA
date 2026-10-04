from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from app.config import Settings
from app.llm_engines import EngineError, GenerationParams, OllamaEngine

PARAMS = GenerationParams(max_new_tokens=256, temperature=0.7, top_p=0.9, repetition_penalty=1.05)
MESSAGES = [{"role": "system", "content": "Você é a PotIA."}, {"role": "user", "content": "Como fazer macarronada?"}]


def make_settings(**overrides) -> Settings:
    return Settings(jwt_secret="x" * 64, llm_engine="ollama", **overrides)


def ndjson(*chunks: dict) -> bytes:
    return "".join(json.dumps(c) + "\n" for c in chunks).encode()


def tags(*names: str) -> httpx.Response:
    return httpx.Response(200, json={"models": [{"name": n, "model": n} for n in names]})


async def collect(engine: OllamaEngine) -> str:
    try:
        return "".join([chunk async for chunk in engine.stream(MESSAGES, PARAMS)])
    finally:
        await engine.shutdown()


def test_streams_chat_with_options() -> None:
    sent: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/tags":
            return tags("qwen2.5:7b")
        sent.append(json.loads(request.content))
        body = ndjson(
            {"message": {"role": "assistant", "content": "Macarronada "}, "done": False},
            {"message": {"role": "assistant", "content": "simples!"}, "done": False},
            {"message": {"role": "assistant", "content": ""}, "done": True},
            {"message": {"role": "assistant", "content": "ignorado"}, "done": False},
        )
        return httpx.Response(200, content=body)

    async def run() -> tuple[bool, str]:
        engine = OllamaEngine(make_settings(), transport=httpx.MockTransport(handler))
        await engine.startup()
        return engine.ready, await collect(engine)

    ready, answer = asyncio.run(run())
    assert ready
    assert answer == "Macarronada simples!"
    payload = sent[0]
    assert payload["model"] == "qwen2.5:7b"
    assert payload["messages"] == MESSAGES
    assert payload["stream"] is True
    assert payload["options"] == {
        "num_ctx": 8192,
        "num_predict": 256,
        "temperature": 0.7,
        "top_p": 0.9,
        "repeat_penalty": 1.05,
    }


def test_model_without_tag_matches_latest() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return tags("llama3.2:latest")

    async def run() -> bool:
        engine = OllamaEngine(make_settings(ollama_model="llama3.2"), transport=httpx.MockTransport(handler))
        await engine.startup()
        ready = engine.ready
        await engine.shutdown()
        return ready

    assert asyncio.run(run())


def test_missing_model_is_reported() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/tags":
            return tags("outro:1b")
        return httpx.Response(404, json={"error": 'model "qwen2.5:7b" not found, try pulling it first'})

    async def run() -> bool:
        engine = OllamaEngine(make_settings(), transport=httpx.MockTransport(handler))
        await engine.startup()
        ready = engine.ready
        with pytest.raises(EngineError, match="não está instalado"):
            await collect(engine)
        return ready

    assert asyncio.run(run()) is False


def test_error_in_middle_of_stream() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/tags":
            return tags("qwen2.5:7b")
        return httpx.Response(200, content=ndjson({"message": {"content": "Oi"}, "done": False}, {"error": "out of memory"}))

    async def run() -> None:
        engine = OllamaEngine(make_settings(), transport=httpx.MockTransport(handler))
        await engine.startup()
        with pytest.raises(EngineError, match="interrompeu"):
            await collect(engine)

    asyncio.run(run())


def test_offline_ollama() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    async def run() -> bool:
        engine = OllamaEngine(make_settings(), transport=httpx.MockTransport(handler))
        await engine.startup()
        ready = engine.ready
        with pytest.raises(EngineError, match="conectar ao Ollama"):
            await collect(engine)
        return ready

    assert asyncio.run(run()) is False
