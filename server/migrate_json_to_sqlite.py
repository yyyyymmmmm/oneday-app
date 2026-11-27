#!/usr/bin/env python3
"""Idempotent migration CLI: import all four legacy JSON/JSONL stores into oneday.db (SQLite WAL).

Usage:
    python3 server/migrate_json_to_sqlite.py --data-dir /opt/data --db-path /opt/data/oneday.db
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "patches"))

import oneday_db  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Migrate OneDay JSON/JSONL stores to SQLite WAL")
    parser.add_argument("--data-dir", type=Path, default=Path("/opt/data"), help="Root data directory")
    parser.add_argument("--db-path", type=Path, default=None, help="Target SQLite DB path (default: <data-dir>/oneday.db)")
    args = parser.parse_args()

    db_path = args.db_path or (args.data_dir / "oneday.db")
    summary = oneday_db.migrate_all_legacy_files(args.data_dir, db_path=db_path)
    ver = oneday_db.schema_version(db_path)
    print(json.dumps({"ok": True, "db_path": str(db_path), "schema_version": ver, "migrated": summary}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
