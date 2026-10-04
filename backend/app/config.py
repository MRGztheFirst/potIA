from __future__ import annotations

import logging
import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

BACKEND_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = BACKEND_DIR.parent

logger = logging.getLogger("potia.config")

DEFAULT_SYSTEM_PROMPT = (
    "Você é a PotIA, uma assistente culinária brasileira simpática, paciente e precisa. "
    "Responda sempre em português do Brasil. Ao passar uma receita, informe o tempo de preparo "
    "e o rendimento quando souber, liste os ingredientes com as medidas e explique o modo de "
    "preparo em passos numerados. Se não tiver certeza de algo, diga isso com honestidade e "
    "sugira alternativas seguras."
)

VALID_ENGINES = ("mock", "transformers", "vllm")


def _env(name: str, default: str | None = None) -> str | None:
    value = os.getenv(f"POTIA_{name}")
    return value if value not in (None, "") else default


def _env_int(name: str, default: int) -> int:
    return int(_env(name, str(default)))


def _env_float(name: str, default: float) -> float:
    return float(_env(name, str(default)))


def _env_bool(name: str, default: bool) -> bool:
    return str(_env(name, str(default))).strip().lower() in {"1", "true", "yes", "sim", "on"}


def _resolve_local(value: str | None) -> str | None:
    if value and value.startswith(("./", "../", ".\\", "..\\")):
        return str((BACKEND_DIR / value).resolve())
    return value


@dataclass(frozen=True)
class Settings:
    app_name: str = "PotIA API"
    version: str = "1.0.0"

    jwt_secret: str = field(default_factory=lambda: secrets.token_urlsafe(64))
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7
    password_iterations: int = 600_000
    database_path: Path = BACKEND_DIR / "data" / "potia.db"

    cors_origins: tuple[str, ...] = ("*",)

    llm_engine: str = "mock"
    model_path: str = str(PROJECT_DIR / "ml" / "artifacts" / "potia-qwen2.5-7b" / "merged")
    adapter_path: str | None = None
    load_in_4bit: bool = False
    vllm_base_url: str = "http://localhost:8001"
    vllm_model: str = "potia"
    vllm_api_key: str | None = None
    mock_token_delay: float = 0.03

    max_new_tokens: int = 1024
    temperature: float = 0.7
    top_p: float = 0.9
    repetition_penalty: float = 1.05
    generation_timeout: float = 120.0
    max_history_messages: int = 20
    max_history_chars: int = 12_000
    system_prompt: str = DEFAULT_SYSTEM_PROMPT

    def __post_init__(self) -> None:
        if self.llm_engine not in VALID_ENGINES:
            raise ValueError(f"POTIA_LLM_ENGINE inválido: {self.llm_engine!r}. Use um de {VALID_ENGINES}.")

    @classmethod
    def from_env(cls) -> "Settings":
        if load_dotenv is not None:
            load_dotenv(BACKEND_DIR / ".env")

        jwt_secret = _env("JWT_SECRET")
        if not jwt_secret:
            jwt_secret = secrets.token_urlsafe(64)
            logger.warning(
                "POTIA_JWT_SECRET não definido: usando uma chave aleatória. "
                "Os logins serão invalidados a cada reinício da API."
            )

        defaults = cls(jwt_secret=jwt_secret)
        origins = _env("CORS_ORIGINS", "*")
        return cls(
            jwt_secret=jwt_secret,
            access_token_expire_minutes=_env_int("ACCESS_TOKEN_EXPIRE_MINUTES", defaults.access_token_expire_minutes),
            password_iterations=_env_int("PASSWORD_ITERATIONS", defaults.password_iterations),
            database_path=BACKEND_DIR / _env("DATABASE_PATH", str(defaults.database_path)),
            cors_origins=tuple(o.strip() for o in origins.split(",") if o.strip()),
            llm_engine=_env("LLM_ENGINE", defaults.llm_engine).lower(),
            model_path=_resolve_local(_env("MODEL_PATH", defaults.model_path)),
            adapter_path=_resolve_local(_env("ADAPTER_PATH")),
            load_in_4bit=_env_bool("LOAD_IN_4BIT", defaults.load_in_4bit),
            vllm_base_url=_env("VLLM_BASE_URL", defaults.vllm_base_url).rstrip("/"),
            vllm_model=_env("VLLM_MODEL", defaults.vllm_model),
            vllm_api_key=_env("VLLM_API_KEY"),
            mock_token_delay=_env_float("MOCK_TOKEN_DELAY", defaults.mock_token_delay),
            max_new_tokens=_env_int("MAX_NEW_TOKENS", defaults.max_new_tokens),
            temperature=_env_float("TEMPERATURE", defaults.temperature),
            top_p=_env_float("TOP_P", defaults.top_p),
            repetition_penalty=_env_float("REPETITION_PENALTY", defaults.repetition_penalty),
            generation_timeout=_env_float("GENERATION_TIMEOUT", defaults.generation_timeout),
            max_history_messages=_env_int("MAX_HISTORY_MESSAGES", defaults.max_history_messages),
            max_history_chars=_env_int("MAX_HISTORY_CHARS", defaults.max_history_chars),
            system_prompt=_env("SYSTEM_PROMPT", defaults.system_prompt),
        )
