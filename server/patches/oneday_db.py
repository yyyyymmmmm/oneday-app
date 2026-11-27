"""Unified SQLite WAL storage layer for OneDay gateway state (#45).

Consolidates the four scattered JSON/JSONL operational stores into a
single SQLite WAL database with versioned schema migrations and
transparent backward-compatible auto-migration on first access:

1. ``connections``          (was ``front/connections.json``)
2. ``vault_entries``        (was ``vault/entries*.json`` — ciphertext/envelope v2 preserved verbatim)
3. ``auth_sessions``        (was ``auth/sessions.json`` — ``odt1.`` tokens unchanged)
4. ``write_gate_decisions`` (was ``write-gate/decisions.jsonl``)

Path resolution:
- When ``ONEDAY_DB_PATH`` is explicitly set, all four stores share that
  single database file (production default: ``/opt/data/oneday.db``).
- Otherwise, when a caller passes a ``legacy_path`` (for example in
  isolated unit tests that redirect ``STORE_PATH`` or ``CONN_PATH`` into
  a temporary directory), the database is placed beside ``legacy_path``
  (``legacy_path.parent / "oneday.db"``) so tests never pollute each
  other or the host filesystem.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger("gateway.platforms.oneday_db")

SCHEMA_VERSION = 1

_lock = threading.RLock()
_initialized_dbs: set[str] = set()

_DDL_V1 = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS connections (
    id TEXT PRIMARY KEY,
    sort_order INTEGER NOT NULL DEFAULT 0,
    payload_json TEXT NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS vault_entries (
    scope TEXT NOT NULL,
    entry_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    updated_at REAL NOT NULL,
    PRIMARY KEY (scope, entry_id)
);

CREATE TABLE IF NOT EXISTS auth_sessions (
    session_id TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    last_used_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS write_gate_decisions (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    dedup_key TEXT UNIQUE,
    decided_at TEXT,
    payload_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_wg_decisions_seq
    ON write_gate_decisions (seq DESC);
"""


def resolve_db_path(legacy_path: Path | None = None) -> Path:
    """Resolve the SQLite WAL database path."""
    explicit = os.environ.get("ONEDAY_DB_PATH", "").strip()
    if explicit:
        return Path(explicit)
    if legacy_path is not None:
        return legacy_path.parent / "oneday.db"
    return Path(os.environ.get("HERMES_HOME", "/opt/data")) / "oneday.db"


def _connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=5.0, isolation_level=None)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA busy_timeout=5000;")
    conn.execute("PRAGMA foreign_keys=ON;")
    key = str(db_path.resolve())
    if key not in _initialized_dbs:
        with _lock:
            if key not in _initialized_dbs:
                conn.executescript(_DDL_V1)
                row = conn.execute(
                    "SELECT MAX(version) FROM schema_migrations"
                ).fetchone()
                cur = int(row[0]) if row and row[0] is not None else 0
                if cur < SCHEMA_VERSION:
                    conn.execute(
                        "INSERT OR REPLACE INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                        (SCHEMA_VERSION, time.time()),
                    )
                try:
                    os.chmod(db_path, 0o600)
                except Exception:
                    pass
                _initialized_dbs.add(key)
    return conn


def schema_version(db_path: Path) -> int:
    conn = _connect(db_path)
    try:
        row = conn.execute("SELECT MAX(version) FROM schema_migrations").fetchone()
        return int(row[0]) if row and row[0] is not None else 0
    finally:
        conn.close()


# ------------------------------------------------------------------ 1. connections

def load_connections(legacy_path: Path) -> list[dict[str, Any]] | None:
    """Load connections from SQLite WAL, auto-migrating legacy JSON if needed."""
    db_path = resolve_db_path(legacy_path)
    with _lock:
        conn = _connect(db_path)
        try:
            rows = conn.execute(
                "SELECT payload_json FROM connections ORDER BY sort_order ASC, id ASC"
            ).fetchall()
            if rows:
                out = []
                for (raw,) in rows:
                    try:
                        obj = json.loads(raw)
                        if isinstance(obj, dict):
                            out.append(obj)
                    except Exception:
                        continue
                return out
            # Backward-compatible auto-migration from legacy connections.json
            if legacy_path.exists():
                try:
                    legacy = json.loads(legacy_path.read_text(encoding="utf-8"))
                    if isinstance(legacy, list) and legacy:
                        _save_connections_conn(conn, legacy)
                        return legacy
                except Exception:
                    logger.warning("oneday_db: legacy connections migration skipped")
            return None
        finally:
            conn.close()


def _save_connections_conn(conn: sqlite3.Connection, recs: list[dict[str, Any]]) -> None:
    now = time.time()
    conn.execute("BEGIN IMMEDIATE")
    try:
        conn.execute("DELETE FROM connections")
        for idx, rec in enumerate(recs):
            cid = str(rec.get("id") or f"conn_{idx}")
            conn.execute(
                "INSERT OR REPLACE INTO connections (id, sort_order, payload_json, updated_at) VALUES (?, ?, ?, ?)",
                (cid, idx, json.dumps(rec, ensure_ascii=False, separators=(",", ":")), now),
            )
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


def save_connections(recs: list[dict[str, Any]], legacy_path: Path) -> None:
    db_path = resolve_db_path(legacy_path)
    with _lock:
        conn = _connect(db_path)
        try:
            _save_connections_conn(conn, recs)
        finally:
            conn.close()


# ------------------------------------------------------------------ 2. vault_entries

def load_vault_entries(scope: str, legacy_path: Path) -> dict[str, Any]:
    """Load encrypted vault entries for ``scope`` from SQLite WAL with auto-migration."""
    db_path = resolve_db_path(legacy_path)
    scope = scope or "default"
    with _lock:
        conn = _connect(db_path)
        try:
            rows = conn.execute(
                "SELECT entry_id, payload_json FROM vault_entries WHERE scope = ?",
                (scope,),
            ).fetchall()
            if rows:
                entries: dict[str, Any] = {}
                for entry_id, raw in rows:
                    try:
                        obj = json.loads(raw)
                        if isinstance(obj, dict):
                            entries[entry_id] = obj
                    except Exception:
                        continue
                return {"entries": entries}
            # Backward-compatible auto-migration from legacy entries.json
            if legacy_path.exists():
                try:
                    raw = json.loads(legacy_path.read_text(encoding="utf-8"))
                    if isinstance(raw, dict) and isinstance(raw.get("entries"), dict) and raw["entries"]:
                        _save_vault_entries_conn(conn, scope, raw["entries"])
                        return {"entries": dict(raw["entries"])}
                except Exception:
                    logger.warning("oneday_db: legacy vault_entries migration skipped")
            return {"entries": {}}
        finally:
            conn.close()


def _save_vault_entries_conn(
    conn: sqlite3.Connection, scope: str, entries: dict[str, Any]
) -> None:
    now = time.time()
    conn.execute("BEGIN IMMEDIATE")
    try:
        conn.execute("DELETE FROM vault_entries WHERE scope = ?", (scope,))
        for entry_id, row in entries.items():
            conn.execute(
                "INSERT OR REPLACE INTO vault_entries (scope, entry_id, payload_json, updated_at) VALUES (?, ?, ?, ?)",
                (scope, str(entry_id), json.dumps(row, ensure_ascii=False, separators=(",", ":")), now),
            )
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


def save_vault_entries(data: dict[str, Any], scope: str, legacy_path: Path) -> None:
    db_path = resolve_db_path(legacy_path)
    scope = scope or "default"
    entries = data.get("entries") if isinstance(data, dict) else {}
    if not isinstance(entries, dict):
        entries = {}
    with _lock:
        conn = _connect(db_path)
        try:
            _save_vault_entries_conn(conn, scope, entries)
        finally:
            conn.close()


# ------------------------------------------------------------------ 3. auth_sessions

def load_auth_sessions(legacy_path: Path) -> dict[str, dict[str, Any]]:
    """Load auth sessions from SQLite WAL, auto-migrating legacy sessions.json."""
    db_path = resolve_db_path(legacy_path)
    with _lock:
        conn = _connect(db_path)
        try:
            rows = conn.execute(
                "SELECT session_id, payload_json FROM auth_sessions"
            ).fetchall()
            if rows:
                out: dict[str, dict[str, Any]] = {}
                for sid, raw in rows:
                    try:
                        obj = json.loads(raw)
                        if isinstance(obj, dict):
                            out[sid] = obj
                    except Exception:
                        continue
                return out
            if legacy_path.exists():
                try:
                    raw = json.loads(legacy_path.read_text(encoding="utf-8"))
                    if isinstance(raw, dict) and isinstance(raw.get("sessions"), dict) and raw["sessions"]:
                        sessions = {
                            k: v for k, v in raw["sessions"].items()
                            if isinstance(k, str) and isinstance(v, dict)
                        }
                        if sessions:
                            _save_auth_sessions_conn(conn, sessions)
                            return sessions
                except Exception:
                    logger.warning("oneday_db: legacy auth_sessions migration skipped")
            return {}
        finally:
            conn.close()


def _save_auth_sessions_conn(
    conn: sqlite3.Connection, sessions: dict[str, dict[str, Any]]
) -> None:
    conn.execute("BEGIN IMMEDIATE")
    try:
        conn.execute("DELETE FROM auth_sessions")
        for sid, rec in sessions.items():
            last_used = float(rec.get("last_used_at") or rec.get("created_at") or 0.0)
            conn.execute(
                "INSERT OR REPLACE INTO auth_sessions (session_id, payload_json, last_used_at) VALUES (?, ?, ?)",
                (sid, json.dumps(rec, ensure_ascii=False, separators=(",", ":")), last_used),
            )
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


def save_auth_sessions(sessions: dict[str, dict[str, Any]], legacy_path: Path) -> None:
    db_path = resolve_db_path(legacy_path)
    with _lock:
        conn = _connect(db_path)
        try:
            _save_auth_sessions_conn(conn, sessions)
        finally:
            conn.close()


# ------------------------------------------------------------------ 4. write_gate_decisions

def _decision_dedup_key(entry: dict[str, Any]) -> str:
    canonical = json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]


def _migrate_legacy_decisions_conn(conn: sqlite3.Connection, legacy_path: Path) -> int:
    if not legacy_path.exists():
        return 0
    count_row = conn.execute("SELECT COUNT(*) FROM write_gate_decisions").fetchone()
    if count_row and int(count_row[0]) > 0:
        return 0
    inserted = 0
    conn.execute("BEGIN IMMEDIATE")
    try:
        for line in legacy_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            if not isinstance(entry, dict):
                continue
            dk = _decision_dedup_key(entry)
            cur = conn.execute(
                "INSERT OR IGNORE INTO write_gate_decisions (dedup_key, decided_at, payload_json) VALUES (?, ?, ?)",
                (dk, str(entry.get("decided_at") or ""), json.dumps(entry, ensure_ascii=False, separators=(",", ":"))),
            )
            if cur.rowcount:
                inserted += 1
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    return inserted


def append_write_gate_decision(entry: dict[str, Any], legacy_path: Path) -> None:
    db_path = resolve_db_path(legacy_path)
    with _lock:
        conn = _connect(db_path)
        try:
            _migrate_legacy_decisions_conn(conn, legacy_path)
            dk = _decision_dedup_key(entry)
            conn.execute(
                "INSERT OR IGNORE INTO write_gate_decisions (dedup_key, decided_at, payload_json) VALUES (?, ?, ?)",
                (dk, str(entry.get("decided_at") or ""), json.dumps(entry, ensure_ascii=False, separators=(",", ":"))),
            )
        finally:
            conn.close()


def read_write_gate_decisions(limit: int, legacy_path: Path) -> list[dict[str, Any]]:
    db_path = resolve_db_path(legacy_path)
    with _lock:
        conn = _connect(db_path)
        try:
            _migrate_legacy_decisions_conn(conn, legacy_path)
            rows = conn.execute(
                "SELECT payload_json FROM write_gate_decisions ORDER BY seq DESC LIMIT ?",
                (max(1, int(limit)),),
            ).fetchall()
            out: list[dict[str, Any]] = []
            for (raw,) in rows:
                try:
                    obj = json.loads(raw)
                    if isinstance(obj, dict):
                        out.append(obj)
                except Exception:
                    continue
            return out
        finally:
            conn.close()


def migrate_all_legacy_files(data_dir: Path, db_path: Path | None = None) -> dict[str, int]:
    """Explicit idempotent migration of all four JSON/JSONL stores into SQLite WAL."""
    target_db = db_path or (data_dir / "oneday.db")
    old_env = os.environ.get("ONEDAY_DB_PATH")
    os.environ["ONEDAY_DB_PATH"] = str(target_db)
    summary = {"connections": 0, "vault_entries": 0, "auth_sessions": 0, "write_gate_decisions": 0}
    try:
        conn_file = data_dir / "front" / "connections.json"
        if conn_file.exists():
            recs = load_connections(conn_file) or []
            summary["connections"] = len(recs)

        vault_dir = data_dir / "vault"
        if vault_dir.exists():
            entries_file = vault_dir / "entries.json"
            if entries_file.exists():
                data = load_vault_entries("default", entries_file)
                summary["vault_entries"] += len(data.get("entries", {}))

        auth_file = data_dir / "auth" / "sessions.json"
        if auth_file.exists():
            sessions = load_auth_sessions(auth_file)
            summary["auth_sessions"] = len(sessions)

        wg_file = data_dir / "write-gate" / "decisions.jsonl"
        if wg_file.exists():
            decisions = read_write_gate_decisions(10000, wg_file)
            summary["write_gate_decisions"] = len(decisions)
    finally:
        if old_env is None:
            os.environ.pop("ONEDAY_DB_PATH", None)
        else:
            os.environ["ONEDAY_DB_PATH"] = old_env
    return summary
