from __future__ import annotations

import asyncio
import base64
import contextlib
import json
import logging
import queue
import re
import threading
import unicodedata
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, AsyncIterator

import httpx
from starlette.concurrency import iterate_in_threadpool

from .config import Settings
from .schemas import image_mime

logger = logging.getLogger("potia.llm")

Messages = list[dict[str, Any]]


class EngineError(RuntimeError):
    pass


@dataclass(frozen=True)
class GenerationParams:
    max_new_tokens: int
    temperature: float
    top_p: float
    repetition_penalty: float


class LLMEngine(ABC):
    name = "base"
    supports_images = False

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.ready = False

    async def startup(self) -> None:
        self.ready = True

    async def shutdown(self) -> None:
        self.ready = False

    @abstractmethod
    def stream(self, messages: Messages, params: GenerationParams) -> AsyncIterator[str]:
        ...

    async def generate(self, messages: Messages, params: GenerationParams) -> str:
        parts = [chunk async for chunk in self.stream(messages, params)]
        return "".join(parts).strip()

    def describe(self) -> dict[str, Any]:
        return {"engine": self.name, "ready": self.ready}


_MOCK_RECIPES = {
    "brigadeiro": (
        "Claro! Aqui está a receita de brigadeiro de panela.\n\n"
        "⏱️ Tempo de preparo: 20 min\n🍽️ Rendimento: 25 unidades\n\n"
        "Ingredientes:\n• 1 lata de leite condensado\n• 1 colher de sopa de manteiga sem sal\n"
        "• 4 colheres de sopa de chocolate em pó\n• Chocolate granulado para enrolar\n\n"
        "Modo de preparo:\n1. Em uma panela, junte o leite condensado, a manteiga e o chocolate em pó.\n"
        "2. Cozinhe em fogo baixo, mexendo sem parar, até a massa desgrudar do fundo da panela.\n"
        "3. Transfira para um prato untado e deixe esfriar.\n"
        "4. Com as mãos untadas, enrole bolinhas e passe no granulado.\n\nBom apetite!"
    ),
    "bolo de cenoura": (
        "Ótima escolha! Veja como fazer bolo de cenoura.\n\n"
        "⏱️ Tempo de preparo: 1 h\n🍽️ Rendimento: 12 fatias\n\n"
        "Ingredientes:\n• 3 cenouras médias picadas\n• 4 ovos\n• 1/2 xícara de chá de óleo\n"
        "• 2 xícaras de chá de açúcar\n• 2 1/2 xícaras de chá de farinha de trigo\n"
        "• 1 colher de sopa de fermento em pó\n\n"
        "Modo de preparo:\n1. Pré-aqueça o forno a 180 °C e unte uma forma.\n"
        "2. Bata no liquidificador as cenouras, os ovos e o óleo.\n"
        "3. Em uma tigela, misture o creme com o açúcar e a farinha; por último, o fermento.\n"
        "4. Asse por cerca de 40 minutos, até o palito sair limpo.\n\nEspero que fique delicioso!"
    ),
    "arroz": (
        "Vamos lá! Arroz branco soltinho:\n\n⏱️ Tempo de preparo: 30 min\n🍽️ Rendimento: 4 porções\n\n"
        "Ingredientes:\n• 2 xícaras de chá de arroz\n• 4 xícaras de chá de água fervente\n"
        "• 2 colheres de sopa de óleo\n• 2 dentes de alho amassados\n• Sal a gosto\n\n"
        "Modo de preparo:\n1. Refogue o alho no óleo até dourar.\n2. Junte o arroz e refogue por 2 minutos.\n"
        "3. Acrescente a água fervente e o sal, tampe parcialmente e cozinhe em fogo baixo até secar.\n"
        "4. Desligue e deixe descansar tampado por 5 minutos.\n\nBom apetite!"
    ),
}


def _strip_accents(text: str) -> str:
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()


class MockEngine(LLMEngine):
    name = "mock"
    supports_images = True

    async def stream(self, messages: Messages, params: GenerationParams) -> AsyncIterator[str]:
        last = messages[-1]
        answer = self._describe_photos(len(last["images"])) if last.get("images") else self._compose(last["content"])
        for piece in re.findall(r"\S+\s*", answer):
            await asyncio.sleep(self.settings.mock_token_delay)
            yield piece

    @staticmethod
    def _describe_photos(count: int) -> str:
        noun = "sua foto" if count == 1 else f"suas {count} fotos"
        return (
            f"Recebi {noun}! 📸 No modo de demonstração eu ainda não enxergo imagens, "
            "mas com POTIA_LLM_ENGINE=ollama e um modelo com visão (qwen3.5:9b) eu identifico "
            "os ingredientes e sugiro receitas."
        )

    @staticmethod
    def _compose(question: str) -> str:
        normalized = _strip_accents(question)
        for keyword, recipe in _MOCK_RECIPES.items():
            if _strip_accents(keyword) in normalized:
                return recipe
        short = question if len(question) <= 160 else question[:157] + "..."
        return (
            "Olá! Estou rodando em modo de demonstração (POTIA_LLM_ENGINE=mock), "
            "então ainda não consigo criar receitas novas. 😊\n\n"
            f"Você perguntou: \"{short}\"\n\n"
            "Para respostas de verdade, use POTIA_LLM_ENGINE=ollama ou treine o modelo na Fase 3 "
            "e use POTIA_LLM_ENGINE=transformers ou vllm. Enquanto isso, pergunte sobre "
            "brigadeiro, bolo de cenoura ou arroz!"
        )


def _dtype_kwarg(value: Any) -> dict[str, Any]:
    import transformers
    from packaging.version import Version

    key = "dtype" if Version(transformers.__version__) >= Version("4.56.0") else "torch_dtype"
    return {key: value}


def _make_cancel_criteria(event: threading.Event) -> Any:
    import torch
    from transformers import StoppingCriteria

    class CancelCriteria(StoppingCriteria):
        def __call__(self, input_ids: Any, scores: Any, **kwargs: Any) -> Any:
            return torch.full((input_ids.shape[0],), event.is_set(), dtype=torch.bool, device=input_ids.device)

    return CancelCriteria()


class TransformersEngine(LLMEngine):
    name = "transformers"

    def __init__(self, settings: Settings) -> None:
        super().__init__(settings)
        self.model: Any = None
        self.tokenizer: Any = None
        self._queue_lock = asyncio.Lock()
        self._gpu_lock = threading.Lock()

    async def startup(self) -> None:
        logger.info("Carregando modelo de %s (isso pode levar alguns minutos)...", self.settings.model_path)
        await asyncio.to_thread(self._load)
        self.ready = True
        logger.info("Modelo pronto em %s.", self.model.device)

    def _load(self) -> None:
        try:
            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer
        except ImportError as exc:
            raise RuntimeError("Instale backend/requirements-gpu.txt para usar POTIA_LLM_ENGINE=transformers.") from exc

        s = self.settings
        kwargs: dict[str, Any] = {"device_map": "auto", "low_cpu_mem_usage": True, **_dtype_kwarg("auto")}
        if s.load_in_4bit:
            from transformers import BitsAndBytesConfig

            ampere = torch.cuda.is_available() and torch.cuda.get_device_capability()[0] >= 8
            kwargs["quantization_config"] = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_use_double_quant=True,
                bnb_4bit_compute_dtype=torch.bfloat16 if ampere else torch.float16,
            )
        model = AutoModelForCausalLM.from_pretrained(s.model_path, **kwargs)
        if s.adapter_path:
            from peft import PeftModel

            model = PeftModel.from_pretrained(model, s.adapter_path)
        model.eval()

        tokenizer = AutoTokenizer.from_pretrained(s.adapter_path or s.model_path)
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
        self.model, self.tokenizer = model, tokenizer

    def _run_generate(self, kwargs: dict[str, Any], streamer: Any, errors: list[BaseException]) -> None:
        try:
            with self._gpu_lock:
                self.model.generate(**kwargs)
        except BaseException as exc:
            logger.exception("Erro durante model.generate")
            errors.append(exc)
            streamer.end()

    async def stream(self, messages: Messages, params: GenerationParams) -> AsyncIterator[str]:
        if not self.ready:
            raise EngineError("O modelo ainda está carregando. Tente novamente em instantes.")
        from transformers import StoppingCriteriaList, TextIteratorStreamer

        async with self._queue_lock:
            prompt = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            inputs = self.tokenizer(prompt, return_tensors="pt", add_special_tokens=False).to(self.model.device)
            streamer = TextIteratorStreamer(
                self.tokenizer, skip_prompt=True, skip_special_tokens=True, timeout=self.settings.generation_timeout
            )
            cancel = threading.Event()
            errors: list[BaseException] = []
            kwargs: dict[str, Any] = {
                **inputs,
                "streamer": streamer,
                "max_new_tokens": params.max_new_tokens,
                "repetition_penalty": params.repetition_penalty,
                "pad_token_id": self.tokenizer.pad_token_id,
                "stopping_criteria": StoppingCriteriaList([_make_cancel_criteria(cancel)]),
            }
            if params.temperature > 0:
                kwargs.update(do_sample=True, temperature=params.temperature, top_p=params.top_p)
            else:
                kwargs["do_sample"] = False

            thread = threading.Thread(target=self._run_generate, args=(kwargs, streamer, errors), daemon=True)
            thread.start()
            try:
                async for text in iterate_in_threadpool(streamer):
                    if text:
                        yield text
            except queue.Empty as exc:
                raise EngineError("O modelo demorou demais para responder.") from exc
            finally:
                cancel.set()

        if errors:
            raise EngineError("Falha ao gerar a resposta no modelo.") from errors[0]

    def describe(self) -> dict[str, Any]:
        info = super().describe()
        if self.model is not None:
            info["device"] = str(self.model.device)
        info["model_path"] = self.settings.model_path
        return info


class HTTPEngine(LLMEngine):
    label = "servidor do modelo"

    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None) -> None:
        super().__init__(settings)
        self._transport = transport
        self._client: httpx.AsyncClient | None = None

    def _open_client(self, base_url: str, headers: dict[str, str] | None = None) -> None:
        self._client = httpx.AsyncClient(
            base_url=base_url,
            headers=headers or {},
            transport=self._transport,
            timeout=httpx.Timeout(connect=10.0, read=self.settings.generation_timeout, write=30.0, pool=10.0),
        )

    async def shutdown(self) -> None:
        if self._client is not None:
            await self._client.aclose()
        self.ready = False

    def _status_error(self, status_code: int, body: str) -> EngineError:
        return EngineError(f"O {self.label} respondeu com erro {status_code}.")

    async def _stream_lines(self, path: str, payload: dict[str, Any]) -> AsyncIterator[str]:
        assert self._client is not None, "startup() não foi chamado"
        try:
            async with self._client.stream("POST", path, json=payload) as response:
                if response.status_code != 200:
                    body = (await response.aread()).decode("utf-8", "replace")[:300]
                    logger.error("%s respondeu %s: %s", self.name, response.status_code, body)
                    raise self._status_error(response.status_code, body)
                self.ready = True
                async for line in response.aiter_lines():
                    yield line
        except httpx.ConnectError as exc:
            self.ready = False
            raise EngineError(f"Não foi possível conectar ao {self.label}.") from exc
        except httpx.TimeoutException as exc:
            raise EngineError(f"O {self.label} demorou demais para responder.") from exc
        except httpx.HTTPError as exc:
            raise EngineError(f"Erro de comunicação com o {self.label}.") from exc


def _openai_message(message: dict[str, Any]) -> dict[str, Any]:
    images = message.get("images")
    if not images:
        return {"role": message["role"], "content": message["content"]}
    parts: list[dict[str, Any]] = [{"type": "text", "text": message["content"]}]
    for encoded in images:
        mime = image_mime(base64.b64decode(encoded[:32])) or "image/jpeg"
        parts.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{encoded}"}})
    return {"role": message["role"], "content": parts}


class VLLMEngine(HTTPEngine):
    name = "vllm"
    label = "servidor do modelo (vLLM)"
    supports_images = True

    async def startup(self) -> None:
        s = self.settings
        self._open_client(s.vllm_base_url, {"Authorization": f"Bearer {s.vllm_api_key}"} if s.vllm_api_key else None)
        try:
            response = await self._client.get("/v1/models")
            response.raise_for_status()
            served = [m.get("id") for m in response.json().get("data", [])]
            if s.vllm_model not in served:
                logger.warning("Modelo %r não encontrado no vLLM. Disponíveis: %s", s.vllm_model, served)
            self.ready = True
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("vLLM indisponível em %s (%s).", s.vllm_base_url, exc)

    async def stream(self, messages: Messages, params: GenerationParams) -> AsyncIterator[str]:
        payload = {
            "model": self.settings.vllm_model,
            "messages": [_openai_message(m) for m in messages],
            "stream": True,
            "max_tokens": params.max_new_tokens,
            "temperature": params.temperature,
            "top_p": params.top_p,
            "repetition_penalty": params.repetition_penalty,
        }
        async with contextlib.aclosing(self._stream_lines("/v1/chat/completions", payload)) as lines:
            async for line in lines:
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                except json.JSONDecodeError:
                    continue
                choices = chunk.get("choices") or []
                delta = (choices[0].get("delta") or {}).get("content") if choices else None
                if delta:
                    yield delta


def _ollama_name(model: str) -> str:
    return model if ":" in model else f"{model}:latest"


class OllamaEngine(HTTPEngine):
    name = "ollama"
    label = "Ollama"

    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None) -> None:
        super().__init__(settings, transport)
        self._capabilities: set[str] | None = None

    @property
    def supports_images(self) -> bool:
        return self._capabilities is None or "vision" in self._capabilities

    async def startup(self) -> None:
        s = self.settings
        self._open_client(s.ollama_base_url)
        try:
            response = await self._client.get("/api/tags")
            response.raise_for_status()
            installed = {m.get("name") for m in response.json().get("models", [])}
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Ollama indisponível em %s (%s). Abra o Ollama e reinicie a API.", s.ollama_base_url, exc)
            return
        if _ollama_name(s.ollama_model) not in installed:
            logger.warning(
                "Modelo %r não está instalado no Ollama. Rode: ollama pull %s. Instalados: %s",
                s.ollama_model, s.ollama_model, sorted(installed),
            )
            return
        self.ready = True
        await self._load_capabilities()
        logger.info("Modelo %s | recursos: %s", s.ollama_model, sorted(self._capabilities or ()))

    async def _load_capabilities(self) -> None:
        try:
            response = await self._client.post("/api/show", json={"model": self.settings.ollama_model})
            response.raise_for_status()
            self._capabilities = set(response.json().get("capabilities") or ())
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Não foi possível ler os recursos do modelo no Ollama (%s).", exc)

    def describe(self) -> dict[str, Any]:
        info = super().describe()
        info["model"] = self.settings.ollama_model
        info["vision"] = self.supports_images
        return info

    def _status_error(self, status_code: int, body: str) -> EngineError:
        if status_code == 404:
            return EngineError("O modelo da PotIA não está instalado no Ollama.")
        return super()._status_error(status_code, body)

    async def stream(self, messages: Messages, params: GenerationParams) -> AsyncIterator[str]:
        s = self.settings
        if self._capabilities is None and self._client is not None:
            await self._load_capabilities()
        payload: dict[str, Any] = {
            "model": s.ollama_model,
            "messages": messages,
            "stream": True,
            "keep_alive": s.ollama_keep_alive,
            "options": {
                "num_ctx": s.ollama_num_ctx,
                "num_predict": params.max_new_tokens,
                "temperature": params.temperature,
                "top_p": params.top_p,
                "repeat_penalty": params.repetition_penalty,
            },
        }
        if self._capabilities and "thinking" in self._capabilities:
            payload["think"] = False
        async with contextlib.aclosing(self._stream_lines("/api/chat", payload)) as lines:
            async for line in lines:
                if not line.strip():
                    continue
                try:
                    chunk = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if chunk.get("error"):
                    logger.error("Ollama: %s", chunk["error"])
                    raise EngineError("O Ollama interrompeu a resposta.")
                content = (chunk.get("message") or {}).get("content")
                if content:
                    yield content
                if chunk.get("done"):
                    break


def create_engine(settings: Settings) -> LLMEngine:
    engines: dict[str, type[LLMEngine]] = {
        "mock": MockEngine,
        "transformers": TransformersEngine,
        "vllm": VLLMEngine,
        "ollama": OllamaEngine,
    }
    return engines[settings.llm_engine](settings)
