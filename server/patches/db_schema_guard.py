"""Read-only SQLite schema fingerprint guard for companion state.db readers (#16).

Companion services that read Hermes ``state.db`` directly (read-only) call
``verify_state_db_schema(db_path)`` before querying. If an upstream Hermes
upgrade renames or drops required tables/columns, this guard returns a clear
structured mismatch report instead of letting raw sqlite3 OperationalErrors
cascade through handlers.
"""

from __future__ import annotations

import hashlib
import sqlite3
from pathlib import Path
from typing import Any

REQUIRED_SCHEMA: dict[str, tuple[str, ...]] = {
    "sessions": ("id", "source", "title", "started_at"),
    "messages": ("id", "session_id", "role", "content", "timestamp"),
}


def verify_state_db_schema(db_path: str | Path) -> dict[str, Any]:
    """Verify required tables/columns exist and return a deterministic fingerprint."""
    path = Path(db_path)
    if not path.is_file():
        return {"ok": False, "reason": "db_missing", "missing": [], "fingerprint": None}

    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        cur = conn.cursor()
        missing: list[str] = []
        sig_parts: list[str] = []
        for table in sorted(REQUIRED_SCHEMA):
            cols = [row[1] for row in cur.execute(f"PRAGMA table_info({table})").fetchall()]
            if not cols:
                missing.append(f"table:{table}")
                continue
            col_set = set(cols)
            for req in REQUIRED_SCHEMA[table]:
                if req not in col_set:
                    missing.append(f"{table}.{req}")
            sig_parts.append(f"{table}:{','.join(sorted(cols))}")
        fingerprint = hashlib.sha256("|".join(sig_parts).encode("utf-8")).hexdigest()[:16]
        return {
            "ok": not missing,
            "reason": None if not missing else "schema_mismatch",
            "missing": missing,
            "fingerprint": fingerprint,
        }
    finally:
        conn.close()
