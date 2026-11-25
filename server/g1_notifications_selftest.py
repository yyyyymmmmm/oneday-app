#!/usr/bin/env python3
"""G1 task-side failure coverage self-test (package 2.4.0).

Covers the two read-time failure sources added to
overview_gateway.py (DESIGN 385.1 G1 remainder):

 1. cron: one entry per OPEN incident (detected/alerted);
    resolved/closed incidents stay silent
 2. cron: incidents last seen before the cron_since baseline
    never backfill
 3. cron: two incidents for the same job stay two entries
    (upstream (job_id, error_sig) aggregation is the dedup;
    this source never re-aggregates executions)
 4. cron: error text is projected as ONE sanitized line --
    no newlines, no filesystem paths, length capped
 5. cron: empty error falls back to the failure_type word
 6. kanban: a task whose LATEST terminal run failed surfaces
    exactly one entry (board + task title + one-line reason)
 7. kanban: a crash healed by a later successful run does
    NOT surface; intermediate retries mint nothing
 8. kanban: failures ended before the kanban_since baseline
    never backfill
 9. both sources are born unread and count into the
    /overview unreadNotifications total
10. mark_read persists for a cron entry (read_ids) and the
    entry reads back read on the next fetch
11. fresh state boot writes cron_since / kanban_since
    baselines into state.json

Run: python3 g1_notifications_selftest.py
     (loads patches/overview_gateway.py from this directory,
     all fixtures are stub DBs in a temp dir)
"""
import importlib.util
import json
import os
import sqlite3
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="g1-selftest-")

BASELINE_ISO = "2026-11-25T00:00:00Z"
BASELINE_EPOCH = 1795564800  # 2026-11-25T00:00:00Z
FRESH_ISO = "2026-11-25T01:00:00+00:00"
STALE_ISO = "2026-11-24T23:00:00+00:00"

os.environ["STATE_DIR"] = os.path.join(TMP, "state")
os.environ["CRON_EXECUTIONS_DB"] = os.path.join(TMP, "executions.db")
os.environ["CRON_JOBS_FILE"] = os.path.join(TMP, "jobs.json")
os.environ["KANBAN_BOARDS_DIR"] = os.path.join(TMP, "boards")

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def build_cron_db():
    conn = sqlite3.connect(os.environ["CRON_EXECUTIONS_DB"])
    conn.execute(
        "CREATE TABLE cron_incidents ("
        " id TEXT PRIMARY KEY, job_id TEXT NOT NULL,"
        " error_sig TEXT NOT NULL, state TEXT NOT NULL,"
        " failure_type TEXT NOT NULL DEFAULT 'unknown',"
        " first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL,"
        " acked_at TEXT, alerted_at TEXT, closed_at TEXT,"
        " error TEXT NOT NULL, output_file TEXT)")
    rows = [
        ("inc-fresh", "jobA", "sig1", "detected", "rate_limit",
         FRESH_ISO, FRESH_ISO,
         "RuntimeError: HTTP 403: quota exceeded\n"
         "stderr: Traceback in /opt/data/cron/secret.py line 9\n"
         "more stderr body that must never surface"),
        ("inc-stale", "jobA", "sig2", "detected", "script",
         STALE_ISO, STALE_ISO, "Script exited with code 1"),
        ("inc-resolved", "jobB", "sig3", "resolved", "auth",
         FRESH_ISO, FRESH_ISO, "HTTP 401 unauthorized"),
        ("inc-closed", "jobB", "sig4", "closed", "auth",
         FRESH_ISO, FRESH_ISO, "HTTP 401 unauthorized"),
        ("inc-alerted", "jobB", "sig5", "alerted", "script",
         FRESH_ISO, FRESH_ISO, ""),
    ]
    conn.executemany(
        "INSERT INTO cron_incidents"
        " (id, job_id, error_sig, state, failure_type,"
        "  first_seen_at, last_seen_at, error)"
        " VALUES (?,?,?,?,?,?,?,?)", rows)
    conn.commit()
    conn.close()
    with open(os.environ["CRON_JOBS_FILE"], "w", encoding="utf-8") as f:
        json.dump({"jobs": [
            {"id": "jobA", "name": "测试日结"},
            {"id": "jobB", "name": "测试周报"},
        ]}, f)


def build_kanban_db():
    board = os.path.join(os.environ["KANBAN_BOARDS_DIR"], "testboard")
    os.makedirs(board)
    conn = sqlite3.connect(os.path.join(board, "kanban.db"))
    conn.execute("CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT)")
    conn.execute(
        "CREATE TABLE task_runs ("
        " id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT,"
        " status TEXT, outcome TEXT, error TEXT, ended_at INTEGER)")
    conn.executemany("INSERT INTO tasks VALUES (?,?)", [
        ("t1", "会崩的任务"), ("t2", "先崩后好的任务"), ("t3", "老失败任务")])
    conn.executemany(
        "INSERT INTO task_runs (task_id, status, outcome, error, ended_at)"
        " VALUES (?,?,?,?,?)", [
            ("t1", "crashed", "crashed", "worker died early",
             BASELINE_EPOCH - 3600),
            ("t1", "crashed", "crashed",
             "worker exploded\nstack /srv/worker/deep/path.py blew up",
             BASELINE_EPOCH + 3600),
            ("t2", "crashed", "crashed", "boom", BASELINE_EPOCH + 3600),
            ("t2", "done", "completed", None, BASELINE_EPOCH + 7200),
            ("t3", "failed", "gave_up", "gave up after retries",
             BASELINE_EPOCH - 3600),
        ])
    conn.commit()
    conn.close()


def load_module():
    spec = importlib.util.spec_from_file_location(
        "overview_gateway_g1",
        os.path.join(HERE, "patches", "overview_gateway.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    build_cron_db()
    build_kanban_db()
    # Pre-seed state with fixed baselines so fixture times are
    # deterministic (a fresh boot would baseline at "now").
    state_dir = os.environ["STATE_DIR"]
    os.makedirs(state_dir)
    with open(os.path.join(state_dir, "state.json"), "w",
              encoding="utf-8") as f:
        json.dump({"read_ids": [], "monitor_since": BASELINE_ISO,
                   "runs_since": BASELINE_ISO,
                   "cron_since": BASELINE_ISO,
                   "kanban_since": BASELINE_ISO}, f)
    mod = load_module()
    mod.start()
    # Hermetic: the HTTP-backed sources are not under test here.
    mod._fetch_decisions = lambda: []
    mod._fetch_monitor = lambda: []
    mod._fetch_pending = lambda: []
    mod._fetch_runs = lambda: []

    cron_items = mod._fetch_cron_failures()
    cron_ids = sorted(n["id"] for n in cron_items)
    check("cron open incidents only, one entry each",
          cron_ids == ["cron-inc-alerted", "cron-inc-fresh"],
          f"got {cron_ids}")
    fresh = next(n for n in cron_items if n["id"] == "cron-inc-fresh")
    check("cron kind/title/refId",
          fresh["kind"] == "cron_failed"
          and fresh["title"] == "定时任务失败"
          and fresh["refId"] == "jobA")
    check("cron body has job name + first error line",
          fresh["body"].startswith("测试日结：RuntimeError: HTTP 403"),
          fresh["body"])
    check("cron body sanitized (no newline/path/stderr body)",
          "\n" not in fresh["body"] and "/opt/data" not in fresh["body"]
          and "more stderr" not in fresh["body"]
          and len(fresh["body"]) <= len("测试日结：") + 120,
          fresh["body"])
    alerted = next(n for n in cron_items if n["id"] == "cron-inc-alerted")
    check("cron empty error falls back to failure_type",
          alerted["body"] == "测试周报：script", alerted["body"])
    check("cron createdAt normalized to Z",
          fresh["createdAt"] == "2026-11-25T01:00:00Z",
          fresh["createdAt"])

    kb_items = mod._fetch_kanban_failures()
    check("kanban latest-run caliber: exactly the still-failing task",
          [n["id"] for n in kb_items] == ["kanban-testboard-t1"],
          f"got {[n['id'] for n in kb_items]}")
    if kb_items:
        kb = kb_items[0]
        check("kanban kind/body shape",
              kb["kind"] == "kanban_failed"
              and kb["body"].startswith("testboard · 会崩的任务：worker exploded")
              and "/srv/worker" not in kb["body"]
              and kb["refId"] == "t1", kb["body"])

    items = mod._current_notifications()
    check("merged stream carries both new kinds",
          sorted(n["kind"] for n in items)
          == ["cron_failed", "cron_failed", "kanban_failed"],
          f"got {sorted(n['kind'] for n in items)}")
    check("new failure items born unread",
          all(not n["read"] for n in items))
    status, payload = mod.get_overview()
    check("overview unread counts failures",
          status == 200 and payload["unreadNotifications"] == 3,
          f"got {status} {payload.get('unreadNotifications')}")

    status, _ = mod.mark_read("cron-inc-fresh")
    again = {n["id"]: n for n in mod._fetch_cron_failures()}
    check("mark_read persists for cron entry",
          status == 200 and again["cron-inc-fresh"]["read"] is True
          and again["cron-inc-alerted"]["read"] is False)

    # Fresh-boot baseline: a brand-new state dir must gain both
    # new baseline keys (no backfill of pre-existing stock).
    fresh_dir = os.path.join(TMP, "state-fresh")
    mod.STATE_DIR = type(mod.STATE_DIR)(fresh_dir)
    mod.STATE_PATH = mod.STATE_DIR / "state.json"
    mod._started = False
    mod._state = {"read_ids": [], "monitor_since": None,
                  "runs_since": None, "cron_since": None,
                  "kanban_since": None}
    mod._read_set = set()
    mod.start()
    saved = json.loads(mod.STATE_PATH.read_text(encoding="utf-8"))
    check("fresh boot writes cron_since/kanban_since baselines",
          bool(saved.get("cron_since")) and bool(saved.get("kanban_since")))

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
