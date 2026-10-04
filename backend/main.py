from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings
from app.database import UserRepository
from app.errors import register_exception_handlers
from app.llm_engines import create_engine
from app.routers import auth_router, chat_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-7s | %(name)s | %(message)s")
logger = logging.getLogger("potia")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.users.init_schema()
        engine = create_engine(settings)
        await engine.startup()
        app.state.engine = engine
        logger.info("PotIA pronta | motor: %s", engine.name)
        try:
            yield
        finally:
            await engine.shutdown()

    app = FastAPI(
        title=settings.app_name,
        version=settings.version,
        description="API da PotIA, a assistente culinária com IA.",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.users = UserRepository(settings.database_path)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    register_exception_handlers(app)
    app.include_router(auth_router)
    app.include_router(chat_router)

    @app.get("/health", tags=["Infra"])
    async def health() -> dict:
        engine = getattr(app.state, "engine", None)
        return {"status": "ok", "version": settings.version, **(engine.describe() if engine else {})}

    @app.get("/", include_in_schema=False)
    async def root() -> dict:
        return {"name": settings.app_name, "docs": "/docs", "health": "/health"}

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=os.getenv("POTIA_HOST", "0.0.0.0"), port=int(os.getenv("POTIA_PORT", "8000")))
