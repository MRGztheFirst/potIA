from __future__ import annotations

import asyncio
import json
from collections.abc import Callable

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


def answer(*pieces: str) -> Callable[[httpx.Request], httpx.Response]:
    chunks = [{"message": {"role": "assistant", "content": p}, "done": False} for p in pieces]
    return lambda request: httpx.Response(200, content=ndjson(*chunks, {"message": {"content": ""}, "done": True}))


class FakeOllama:
    def __init__(
        self,
        models: tuple[str, ...] = ("qwen3.5:9b",),
        capabilities: tuple[str, ...] = ("completion", "vision", "thinking"),
        chat: Callable[[httpx.Request], httpx.Response] | None = None,
    ) -> None:
        self.models = models
        self.capabilities = capabilities
        self.chat = chat or answer("Oi")
        self.sent: list[dict] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/tags":
            return httpx.Response(200, json={"models": [{"name": n, "model": n} for n in self.models]})
        if request.url.path == "/api/show":
            return httpx.Response(200, json={"capabilities": list(self.capabilities)})
        self.sent.append(json.loads(request.content))
        return self.chat(request)


def run_engine(fake, messages=MESSAGES, **overrides) -> tuple[OllamaEngine, str]:
    async def run() -> tuple[OllamaEngine, str]:
        engine = OllamaEngine(make_settings(**overrides), transport=httpx.MockTransport(fake))
        await engine.startup()
        try:
            text = "".join([chunk async for chunk in engine.stream(messages, PARAMS)])
        finally:
            await engine.shutdown()
        return engine, text

    return asyncio.run(run())


def test_streams_chat_with_options() -> None:
    fake = FakeOllama(chat=lambda r: httpx.Response(200, content=ndjson(
        {"message": {"content": "Macarronada "}, "done": False},
        {"message": {"content": "simples!"}, "done": False},
        {"message": {"content": ""}, "done": True},
        {"message": {"content": "ignorado"}, "done": False},
    )))
    _, text = run_engine(fake)
    assert text == "Macarronada simples!"
    payload = fake.sent[0]
    assert payload["model"] == "qwen3.5:9b"
    assert payload["messages"] == MESSAGES
    assert payload["stream"] is True
    assert payload["think"] is False
    assert payload["options"] == {
        "num_ctx": 8192,
        "num_predict": 256,
        "temperature": 0.7,
        "top_p": 0.9,
        "repeat_penalty": 1.05,
    }


def test_think_flag_only_for_thinking_models() -> None:
    fake = FakeOllama(models=("qwen2.5:7b",), capabilities=("completion",))
    engine, _ = run_engine(fake, ollama_model="qwen2.5:7b")
    assert "think" not in fake.sent[0]
    assert engine.supports_images is False


def test_images_are_forwarded() -> None:
    fake = FakeOllama(chat=answer("Vejo tomates!"))
    messages = [*MESSAGES[:1], {"role": "user", "content": "O que é isso?", "images": ["aGVsbG8="]}]
    engine, text = run_engine(fake, messages=messages)
    assert engine.supports_images is True
    assert text == "Vejo tomates!"
    assert fake.sent[0]["messages"][-1]["images"] == ["aGVsbG8="]


def test_model_without_tag_matches_latest() -> None:
    fake = FakeOllama(models=("llama3.2:latest",))

    async def run() -> bool:
        engine = OllamaEngine(make_settings(ollama_model="llama3.2"), transport=httpx.MockTransport(fake))
        await engine.startup()
        ready = engine.ready
        await engine.shutdown()
        return ready

    assert asyncio.run(run())


def test_missing_model_is_reported() -> None:
    fake = FakeOllama(
        models=("outro:1b",),
        chat=lambda r: httpx.Response(404, json={"error": 'model "qwen3.5:9b" not found, try pulling it first'}),
    )
    with pytest.raises(EngineError, match="não está instalado"):
        run_engine(fake)


def test_error_in_middle_of_stream() -> None:
    fake = FakeOllama(chat=lambda r: httpx.Response(
        200, content=ndjson({"message": {"content": "Oi"}, "done": False}, {"error": "out of memory"})
    ))
    with pytest.raises(EngineError, match="interrompeu"):
        run_engine(fake)


def test_offline_ollama() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    with pytest.raises(EngineError, match="conectar ao Ollama"):
        run_engine(handler)
