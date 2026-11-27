#!/usr/bin/env python3
"""Self-test for Batch 4 server refactoring (#44, #45, #46):
- oneday_db.py SQLite WAL unified storage + 4-store wiring + auto-migration CLI
- push_sender.py async aioapns / httpx fallback + PushDispatchScheduler coalescing
- Modularized helpers: device_gateway_catalog, oneday_feed_helpers, api_server_helpers
"""

from __future__ import annotations

import asyncio
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "patches"))

import api_server_helpers  # noqa: E402
import auth_tokens  # noqa: E402
import credential_vault  # noqa: E402
import device_gateway_catalog  # noqa: E402
import front_gateway  # noqa: E402
import oneday_db  # noqa: E402
import oneday_feed_helpers  # noqa: E402
import push_sender  # noqa: E402
import write_gate_gateway  # noqa: E402


def test_sqlite_wal_and_four_stores() -> None:
    with tempfile.TemporaryDirectory() as tmp_str:
        tmp = Path(tmp_str)
        db_path = tmp / "oneday.db"
        os.environ["ONEDAY_DB_PATH"] = str(db_path)
        try:
            # 1. Seed legacy JSON/JSONL files for all 4 stores
            conn_file = tmp / "front" / "connections.json"
            conn_file.parent.mkdir(parents=True, exist_ok=True)
            conn_file.write_text(json.dumps([
                {"id": "github", "kind": "service", "provider": "github", "name": "GitHub", "configured": True}
            ]), encoding="utf-8")

            vault_file = tmp / "vault" / "entries.json"
            vault_file.parent.mkdir(parents=True, exist_ok=True)
            vault_file.write_text(json.dumps({
                "entries": {
                    "vlt_legacy1": {
                        "name": "Demo", "service": "Demo", "domains": ["example.com"],
                        "username": "alice", "field_names": ["password"], "updated_at": 1,
                        "version": 1, "sealed": {"v": 2, "ciphertext": "abc"}, "revoked": False,
                    }
                }
            }), encoding="utf-8")

            auth_file = tmp / "auth" / "sessions.json"
            auth_file.parent.mkdir(parents=True, exist_ok=True)
            auth_file.write_text(json.dumps({
                "version": 1,
                "sessions": {
                    "sess_legacy1": {"session_id": "sess_legacy1", "device_name": "Legacy", "last_used_at": 10.0}
                }
            }), encoding="utf-8")

            wg_file = tmp / "write-gate" / "decisions.jsonl"
            wg_file.parent.mkdir(parents=True, exist_ok=True)
            wg_file.write_text(
                json.dumps({"id": "dec_legacy1", "subsystem": "memory", "decision": "approved", "decided_at": "2026-11-26T00:00:00Z"}) + "\n",
                encoding="utf-8",
            )

            # 2. Run explicit migration CLI function (idempotent)
            summary1 = oneday_db.migrate_all_legacy_files(tmp, db_path)
            assert summary1 == {"connections": 1, "vault_entries": 1, "auth_sessions": 1, "write_gate_decisions": 1}, summary1
            summary2 = oneday_db.migrate_all_legacy_files(tmp, db_path)
            assert summary2 == summary1, (summary1, summary2)

            # 3. Verify WAL mode + schema_migrations version
            conn = sqlite3.connect(str(db_path))
            try:
                mode = conn.execute("PRAGMA journal_mode;").fetchone()[0]
                assert str(mode).lower() == "wal", mode
                assert oneday_db.schema_version(db_path) == 1
            finally:
                conn.close()

            # 4. Verify wired front_gateway round-trip
            front_gateway.STATE_DIR = tmp / "front"
            front_gateway.CONN_PATH = conn_file
            recs = front_gateway.conn_load()
            assert len(recs) == 1 and recs[0]["id"] == "github"
            recs.append({"id": "vps_ssh-1", "kind": "cloud_computer", "provider": "vps_ssh", "name": "Prod", "configured": False})
            front_gateway.conn_save(recs)
            assert len(front_gateway.conn_load()) == 2

            # 5. Verify wired credential_vault _load/_save round-trip
            credential_vault.STORE_PATH = vault_file
            loaded_vault = credential_vault._load("default")
            assert "vlt_legacy1" in loaded_vault["entries"]
            loaded_vault["entries"]["vlt_new2"] = {"name": "New", "service": "New", "domains": [], "revoked": False}
            credential_vault._save(loaded_vault, "default")
            assert "vlt_new2" in credential_vault._load("default")["entries"]

            # 6. Verify wired auth_tokens round-trip (preserving odt1. format)
            auth_tokens.STORE_PATH = auth_file
            pair = auth_tokens.exchange_key_for_tokens(api_key="test-key-1234567890", device_name="iPhone 17")
            assert pair["access_token"].startswith("odt1.")
            ok, sid, err = auth_tokens.verify_access_token(pair["access_token"], api_key="test-key-1234567890")
            assert ok and sid == pair["session_id"] and err is None

            # 7. Verify wired write_gate_gateway round-trip + write-through mirror
            old_home = write_gate_gateway._home
            write_gate_gateway._home = lambda: tmp
            try:
                write_gate_gateway._append_decision(
                    {"id": "wg_2", "action": "add", "summary": "add mem", "origin": "foreground", "created_at": 100.0},
                    "memory",
                    "approved",
                )
                rows = write_gate_gateway._read_decisions(10)
                ids = [r.get("id") for r in rows]
                assert "wg_2" in ids and "dec_legacy1" in ids, ids
                # Write-through mirror check
                mirror_text = wg_file.read_text(encoding="utf-8")
                assert "wg_2" in mirror_text
            finally:
                write_gate_gateway._home = old_home
        finally:
            os.environ.pop("ONEDAY_DB_PATH", None)


def test_push_sender_async_and_scheduler() -> None:
    # Ensure unconfigured credentials fail gracefully in both sync & async paths
    for env_k in ("APNS_KEY_PATH", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC"):
        os.environ.pop(env_k, None)

    sync_res = push_sender.send_notification(
        title="Approval", body="Check", kind="approval", request_id="req_1"
    )
    assert sync_res["skipped_reason"] == "apns_not_configured"
    assert sync_res["payload"]["request_id"] == "req_1"

    async def _run() -> None:
        async_res = await push_sender.send_notification_async(
            title="Run done", body="Finished", kind="run", session_id="sess_1"
        )
        assert async_res["skipped_reason"] == "apns_not_configured"
        assert async_res["payload"]["session_id"] == "sess_1"

        sched = push_sender.PushDispatchScheduler(coalesce_window_sec=0.05)
        assert sched.enqueue("run:sess_1", title="T1", body="B1", kind="run", session_id="sess_1")
        assert sched.enqueue("run:sess_1", title="T2", body="B2", kind="run", session_id="sess_1")
        out = await sched.flush_once()
        # Coalesced into a single notification with latest payload
        assert len(out) == 1 and out[0]["payload"]["aps"]["alert"]["title"] == "T2"

    asyncio.run(_run())


def test_extracted_modules() -> None:
    assert len(device_gateway_catalog.TOOLS) == 53
    assert "calendar_list_events" in device_gateway_catalog.TOOL_BY_NAME
    assert "auth_biometric" in device_gateway_catalog.NEVER_REPLAY_TOOLS
    assert oneday_feed_helpers._norm_url("https://Example.COM/a/b/?utm_source=x&id=1#frag") == "https://example.com/a/b?id=1"
    assert oneday_feed_helpers._clamp_feed_title("短标题") == "短标题"
    assert api_server_helpers._coerce_request_bool("false", default=True) is False
    assert api_server_helpers._canonical_vault_field_order(["password", "username"]) == ["username", "password"]


def main() -> None:
    test_sqlite_wal_and_four_stores()
    test_push_sender_async_and_scheduler()
    test_extracted_modules()
    print("oneday_db_selftest: ALL PASSED")


if __name__ == "__main__":
    main()
