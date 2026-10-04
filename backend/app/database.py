from __future__ import annotations

import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class EmailAlreadyRegisteredError(Exception):
    pass


class UserRepository:
    def __init__(self, db_path: Path) -> None:
        self.db_path = Path(db_path)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def init_schema(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with closing(self._connect()) as conn, conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    name          TEXT NOT NULL,
                    email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    password_hash TEXT NOT NULL,
                    created_at    TEXT NOT NULL
                )
                """
            )

    def create(self, name: str, email: str, password_hash: str) -> dict[str, Any]:
        created_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        try:
            with closing(self._connect()) as conn, conn:
                cursor = conn.execute(
                    "INSERT INTO users (name, email, password_hash, created_at) VALUES (?, ?, ?, ?)",
                    (name, email, password_hash, created_at),
                )
                user_id = cursor.lastrowid
        except sqlite3.IntegrityError as exc:
            raise EmailAlreadyRegisteredError(email) from exc
        return {"id": user_id, "name": name, "email": email, "created_at": created_at}

    def get_by_email(self, email: str) -> dict[str, Any] | None:
        return self._fetch_one("SELECT * FROM users WHERE email = ?", (email,))

    def get_by_id(self, user_id: int) -> dict[str, Any] | None:
        return self._fetch_one("SELECT * FROM users WHERE id = ?", (user_id,))

    def _fetch_one(self, query: str, params: tuple[Any, ...]) -> dict[str, Any] | None:
        with closing(self._connect()) as conn:
            row = conn.execute(query, params).fetchone()
        return dict(row) if row else None
