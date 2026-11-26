#!/usr/bin/env python3
"""Wiring self-test for the db_schema_guard call sites (2026-11-26, 裁 A).

Proves the two in-package readers actually CALL
``db_schema_guard.verify_state_db_schema`` on their open-db path --
the guard module alone was already covered by
push_sender_and_schema_guard_selftest.py; this test covers the
wiring transplanted from a2fecf5c into:

  1. patches/write_gate_gateway.py  _AnchorResolver._load
  2. patches/oneday_seg_delivery.py _sentinel_pass (segment file,
     exec'ed into a stub namespace like the bridge selftests do)

A counting fake guard is injected into sys.modules so the call
count is observable; the real guard is then exercised end-to-end
against good / drifted state.db fixtures.
"""

import importlib.util
import json
import os
import re
import sqlite3
import sys
import tempfile
import threading
import time
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PATCHES = ROOT / "patches"
sys.path.insert(0, str(PATCHES))

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def make_state_db(path: Path, drifted: bool = False) -> None:
    conn = sqlite3.connect(path)
    title_col = "" if drifted else ", title TEXT"
    conn.execute(
        "CREATE TABLE sessions (id TEXT, source TEXT" + title_col +
        ", started_at REAL, ended_at REAL, last_activity_at REAL"
        ", archived INTEGER, hidden INTEGER)")
    conn.execute(
        "INSERT INTO sessions VALUES ('s1', 'api_server', " +
        ("" if drifted else "'t', ") +
        "1.0, NULL, 1.0, 0, 0)")
    conn.execute(
        "CREATE TABLE messages (id INTEGER, session_id TEXT, role TEXT"
        ", content TEXT, timestamp REAL, active INTEGER)")
    conn.commit()
    conn.close()


class FakeGuard:
    def __init__(self, result):
        self.result = result
        self.calls = []

    def module(self):
        mod = types.ModuleType("db_schema_guard")
        def verify(db_path):
            self.calls.append(db_path)
            return self.result
        mod.verify_state_db_schema = verify
        return mod


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> None:
    real_guard_mod = sys.modules.get("db_schema_guard")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        home = tmp / "home"
        home.mkdir()
        make_state_db(home / "state.db")

        # ---- 1. write_gate_gateway._AnchorResolver._load ----
        wg = load_module("write_gate_gateway", PATCHES / "write_gate_gateway.py")
        wg._home = lambda: home

        fake = FakeGuard({"ok": True, "reason": None, "missing": []})
        sys.modules["db_schema_guard"] = fake.module()
        resolver = wg._AnchorResolver()
        check("wg: _load True with ok guard", resolver._load() is True)
        check("wg: guard called once on open path", len(fake.calls) == 1,
              f"calls={fake.calls}")
        check("wg: guard got the state.db path",
              fake.calls and Path(fake.calls[0]) == home / "state.db")
        check("wg: sessions loaded past guard", len(resolver._sessions) == 1)
        resolver.close()

        fake_bad = FakeGuard({"ok": False, "reason": "schema_mismatch",
                              "missing": ["sessions.title"]})
        sys.modules["db_schema_guard"] = fake_bad.module()
        resolver2 = wg._AnchorResolver()
        check("wg: _load False when guard rejects", resolver2._load() is False)
        check("wg: guard called once (reject path)", len(fake_bad.calls) == 1)
        check("wg: no connection opened past failed guard",
              resolver2._conn is None)

        # real guard end-to-end: good db passes, drifted db is stopped
        sys.modules.pop("db_schema_guard", None)
        resolver3 = wg._AnchorResolver()
        check("wg: real guard lets good db through", resolver3._load() is True)
        resolver3.close()
        drift_home = tmp / "drift_home"
        drift_home.mkdir()
        make_state_db(drift_home / "state.db", drifted=True)
        wg._home = lambda: drift_home
        resolver4 = wg._AnchorResolver()
        check("wg: real guard stops drifted db", resolver4._load() is False)
        wg._home = lambda: home

        # ---- 2. oneday_seg_delivery._sentinel_pass (exec segment) ----
        seg_db = tmp / "seg_state.db"
        make_state_db(seg_db)
        seg_state = tmp / "sentinel-state.json"
        os.environ["DELIVERY_SENTINEL_DB"] = str(seg_db)
        os.environ["DELIVERY_SENTINEL_STATE"] = str(seg_state)
        ns = {
            "__name__": "oneday_seg_delivery_wiring_test",
            "__file__": str(PATCHES / "oneday_seg_delivery.py"),
            "os": os, "re": re, "json": json, "time": time,
            "threading": threading, "Path": Path,
            "DATA_PATH": tmp / "data.json",
            "_degraded_reason": "",
            "_now": lambda: "2026-11-26T00:00:00Z",
        }
        src = (PATCHES / "oneday_seg_delivery.py").read_text(encoding="utf-8")
        exec(compile(src, "oneday_seg_delivery.py", "exec"), ns)
        sentinel_pass = ns["_sentinel_pass"]
        status = ns["_sentinel_status"]

        fake2 = FakeGuard({"ok": True, "reason": None, "missing": []})
        sys.modules["db_schema_guard"] = fake2.module()
        sentinel_pass()
        check("seg: guard called once on open path", len(fake2.calls) == 1,
              f"calls={fake2.calls}")
        check("seg: guard got the sentinel db path",
              fake2.calls and Path(fake2.calls[0]) == seg_db)
        check("seg: no schema_guard error after ok guard",
              not (status.get("lastError") or "").startswith("schema_guard:"))

        wm_calls = []
        real_wm = ns["_sentinel_load_watermark"]
        def counting_wm():
            wm_calls.append(1)
            return real_wm()
        ns["_sentinel_load_watermark"] = counting_wm
        fake2_bad = FakeGuard({"ok": False, "reason": "schema_mismatch",
                               "missing": ["sessions.title"]})
        sys.modules["db_schema_guard"] = fake2_bad.module()
        status["lastError"] = None
        sentinel_pass()
        check("seg: guard called once (reject path)", len(fake2_bad.calls) == 1)
        check("seg: schema_guard error recorded",
              (status.get("lastError") or "").startswith(
                  "schema_guard:schema_mismatch:"))
        check("seg: watermark never loaded past failed guard",
              len(wm_calls) == 0, f"wm_calls={wm_calls}")
        ns["_sentinel_load_watermark"] = real_wm

        # real guard end-to-end on the segment path
        sys.modules.pop("db_schema_guard", None)
        status["lastError"] = None
        sentinel_pass()
        check("seg: real guard lets good db through",
              not (status.get("lastError") or "").startswith("schema_guard:"))

    if real_guard_mod is not None:
        sys.modules["db_schema_guard"] = real_guard_mod
    print(f"db_schema_guard_wiring_selftest: {passed} passed, {failed} failed")
    if failed:
        sys.exit(1)
    print("db_schema_guard_wiring_selftest: ALL PASSED")


if __name__ == "__main__":
    main()
