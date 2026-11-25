#!/usr/bin/env python3
"""Self-test for push_sender.py (#4) and db_schema_guard.py (#16)."""

import sqlite3
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "patches"))
sys.path.insert(0, str(ROOT / "companion" / "modules"))

import push_sender  # noqa: E402
import db_schema_guard  # noqa: E402


def main() -> None:
    # 1. push_sender payload matches PushNotificationRouteResolver + graceful unconfigured check
    p_app = push_sender.build_payload(
        title="待批提醒", body="需要你确认命令", kind="approval", request_id="req-99"
    )
    assert p_app["kind"] == "approval" and p_app["request_id"] == "req-99"
    assert p_app["aps"]["alert"]["title"] == "待批提醒"

    p_run = push_sender.build_payload(
        title="任务完成", body="报告已生成", kind="run", session_id="oneday-main-1"
    )
    assert p_run["kind"] == "run" and p_run["session_id"] == "oneday-main-1"

    res = push_sender.send_notification(
        title="测试", body="测试", kind="run", session_id="s1"
    )
    assert res["sent"] == 0 and res["skipped_reason"] == "apns_not_configured"

    # 2. db_schema_guard detects missing DB, valid schema, and column drift
    with tempfile.TemporaryDirectory() as tmp:
        missing_res = db_schema_guard.verify_state_db_schema(Path(tmp) / "nope.db")
        assert not missing_res["ok"] and missing_res["reason"] == "db_missing"

        good_db = Path(tmp) / "good.db"
        conn = sqlite3.connect(good_db)
        conn.execute("CREATE TABLE sessions (id TEXT, source TEXT, title TEXT, started_at REAL)")
        conn.execute("CREATE TABLE messages (id INTEGER, session_id TEXT, role TEXT, content TEXT, timestamp REAL)")
        conn.commit()
        conn.close()
        good_res = db_schema_guard.verify_state_db_schema(good_db)
        assert good_res["ok"] and len(good_res["fingerprint"]) == 16

        bad_db = Path(tmp) / "bad.db"
        conn = sqlite3.connect(bad_db)
        conn.execute("CREATE TABLE sessions (id TEXT, source TEXT)")
        conn.commit()
        conn.close()
        bad_res = db_schema_guard.verify_state_db_schema(bad_db)
        assert not bad_res["ok"]
        assert "sessions.title" in bad_res["missing"]
        assert "table:messages" in bad_res["missing"]

    print("push_sender_and_schema_guard_selftest: ALL PASSED")


if __name__ == "__main__":
    main()
