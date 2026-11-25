#!/usr/bin/env python3
"""§475 ledger settlement self-test (parts 1 + 2).

Part A covers ledger.settle_orphan_jobs against a fake clock:
  1. orphan with a matching round record (ok) -> completed
  2. orphan with a matching record (empty) -> completed
  3. orphan with a matching record (skipped) -> failed 原因未明
  4. orphan with NO record -> failed 执行被打断 (interrupted)
  5. a LATER round's record must NOT settle an earlier orphan
  6. non-job items are never touched; terminal items neither
  7. a second pass settles nothing (idempotent)
Part B covers delivery-point settlement (§475 part 2) by
exec'ing the REAL oneday_seg_ledger.py job hooks in a stub
namespace wired to a real LedgerStore:
  8. delivered settle flips the job completed AT the
     delivery point, produced count booked, note written
  9. a tail failure at round end does NOT roll the
     delivered status back
 10. an empty round (produced=0) settles at the same point
 11. "full" on the plain finish path books completed
     (shared DELIVERY_CONSISTENT_STATUSES table)
 12. delivered-settle with no job booked is a silent no-op
 13. interplay: a delivered-settled (terminal) item is
     invisible to the orphan pass even with a failed record
 14. an orphan whose record says "full" settles completed
     via the same shared table
 15. a stale-marked job still settles at delivery
Run: python3 ledgerfix_selftest.py [path-to-ledger.py]
     (the segment file is read from the same directory)
"""
import importlib.util
import os
import sys
import tempfile
from datetime import timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
TZ = timezone(timedelta(hours=8))

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def load_mod(path):
    spec = importlib.util.spec_from_file_location("ledger_mod", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "ledger.py")
    mod = load_mod(path)
    clock = {"t": 5000.0}
    tmp = tempfile.mkdtemp()
    store = mod.LedgerStore(
        os.path.join(tmp, "ledger-events.jsonl"),
        now_fn=lambda: clock["t"], tz=TZ)

    def job(jid, started, status="running"):
        store.create_or_merge({
            "id": jid, "kind": "job", "source": "bridge",
            "title": "动态调研", "titleSource": "job_name",
            "status": status, "startedAt": started,
            "origin": "bridge_self", "by": "bridge"})

    job("job:morning:1000", 1000.0)          # rec ok -> completed
    job("job:morning:2000", 2000.0)          # rec empty -> completed
    job("job:ideas:3000", 3000.0)            # rec skipped -> failed
    job("job:morning:4000", 4000.0)          # no rec -> interrupted
    job("job:morning:4500", 4500.0)          # later rec only -> interrupted
    job("job:briefing:1500", 1500.0, status="completed")  # terminal
    store.create_or_merge({                   # non-job active item
        "id": "run:xyz", "kind": "run", "source": "app",
        "title": "会话", "titleSource": "user_excerpt",
        "status": "running", "startedAt": 1000.0,
        "origin": "reported", "by": "app"})

    histories = {
        "morning": [
            {"at": 1000.0, "status": "ok", "error": None},
            {"at": 2000.0, "status": "empty",
             "error": "候选全部被编辑环退稿"},
            {"at": 4600.0, "status": "ok", "error": None},
        ],
        "ideas": [
            {"at": 3000.0, "status": "skipped",
             "error": "简报为空，本轮跳过"},
        ],
        "briefing": [],
    }

    n = mod.settle_orphan_jobs(store, histories, now=clock["t"])
    check("settles five orphans", n == 5, f"got {n}")
    check("ok rec -> completed",
          store.get("job:morning:1000")["status"] == "completed")
    check("empty rec -> completed",
          store.get("job:morning:2000")["status"] == "completed")
    it = store.get("job:ideas:3000")
    check("skipped rec -> failed",
          it["status"] == "failed"
          and it["failReason"]["category"] == "原因未明",
          str(it.get("failReason")))
    it = store.get("job:morning:4000")
    check("no rec -> failed interrupted",
          it["status"] == "failed"
          and it["failReason"]["category"] == "执行被打断",
          str(it.get("failReason")))
    it = store.get("job:morning:4500")
    check("later rec does not settle earlier orphan as completed",
          it["status"] == "failed"
          and it["failReason"]["category"] == "执行被打断",
          str(it.get("status")))
    check("terminal item untouched",
          store.get("job:briefing:1500")["status"] == "completed")
    check("non-job item untouched",
          store.get("run:xyz")["status"] == "running")
    n2 = mod.settle_orphan_jobs(store, histories, now=clock["t"])
    check("second pass idempotent", n2 == 0, f"got {n2}")

    part_b(mod, path)

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


def part_b(mod, ledger_path):
    """Delivery-point settlement through the segment's real
    job hooks (exec'd, not imported -- the segment is not a
    standalone module). The store is a real LedgerStore on a
    temp event log; the clock is fake via the _now seam."""
    import json
    import threading
    import time
    import urllib
    from datetime import datetime
    from pathlib import Path

    seg_path = os.path.join(
        os.path.dirname(os.path.abspath(ledger_path)),
        "oneday_seg_ledger.py")
    clock = {"t": 10000.0}
    tmp = tempfile.mkdtemp()
    os.environ["LEDGER_PATH"] = os.path.join(
        tmp, "ledger-events.jsonl")
    ns = {
        "os": os, "sys": sys, "json": json, "time": time,
        "threading": threading, "datetime": datetime,
        "timedelta": timedelta, "Path": Path, "urllib": urllib,
        "DATA_PATH": Path(tmp), "GEN_SESSION_ID": "selftest",
        "_ledger_mod": mod,
        "_now": lambda: clock["t"],
        "_sched_tz": lambda: TZ,
    }
    with open(seg_path, encoding="utf-8") as fh:
        exec(compile(fh.read(), seg_path, "exec"), ns)
    start = ns["_ledger_job_start"]
    delivered = ns["_ledger_job_delivered"]
    finish = ns["_ledger_job_finish"]
    store = ns["_ledger"]()

    # 8. delivery settles the job at the delivery point
    start("morning")
    jid = "job:morning:10000"
    check("B: job running before delivery",
          store.get(jid)["status"] == "running")
    delivered("morning", 3)
    it = store.get(jid)
    check("B: delivered -> completed immediately",
          it["status"] == "completed", str(it["status"]))
    check("B: produced count booked",
          (it.get("counts") or {}).get("produced") == 3,
          str(it.get("counts")))
    check("B: endedAt stamped at delivery time",
          it.get("endedAt") == 10000.0, str(it.get("endedAt")))
    check("B: delivery note in history",
          any(h.get("note") == "交付齐，先行结算完成"
              for h in it.get("history") or []))

    # 9. a tail failure must not roll the delivered status back
    finish("morning", {"status": "failed",
                       "error": "RuntimeError: tail boom"})
    check("B: tail failure does not roll back",
          store.get(jid)["status"] == "completed")

    # 10. an empty round settles at the same point
    clock["t"] = 20000.0
    start("ideas")
    delivered("ideas", 0)
    it = store.get("job:ideas:20000")
    check("B: empty round settles at delivery point",
          it["status"] == "completed"
          and (it.get("counts") or {}).get("produced") == 0,
          str(it.get("status")))
    finish("ideas", {"status": "empty",
                     "error": "候选全部被编辑环退稿"})
    check("B: empty finish after delivery keeps completed",
          store.get("job:ideas:20000")["status"] == "completed")

    # 11. "full" books completed on the plain finish path
    clock["t"] = 30000.0
    start("ideas")
    finish("ideas", {"status": "full", "error": None})
    check("B: full -> completed (not failed)",
          store.get("job:ideas:30000")["status"] == "completed",
          str(store.get("job:ideas:30000")["status"]))

    # 12. delivered-settle with no job booked: silent no-op
    delivered("briefing", 5)
    check("B: delivered with no job is a no-op",
          not any(i["id"].startswith("job:briefing:")
                  for i in store.list_items()))

    # 13. interplay: delivered-settled items are terminal, so
    # the boot orphan pass cannot touch them -- even with a
    # failed record in the window
    n = mod.settle_orphan_jobs(
        store, {"morning": [{"at": 10000.0, "status": "failed",
                             "error": "x"}]},
        now=40000.0)
    check("B: orphan pass leaves delivered items alone",
          n == 0 and store.get(jid)["status"] == "completed",
          f"n={n} status={store.get(jid)['status']}")

    # 14. an orphan whose record says "full" settles completed
    # via the same shared table
    store.create_or_merge({
        "id": "job:ideas:5000", "kind": "job", "source": "bridge",
        "title": "点子生成", "titleSource": "job_name",
        "status": "running", "startedAt": 5000.0,
        "origin": "bridge_self", "by": "bridge"})
    n = mod.settle_orphan_jobs(
        store, {"ideas": [{"at": 5000.0, "status": "full",
                           "error": None}]},
        now=40000.0)
    check("B: orphan with full record -> completed",
          n == 1
          and store.get("job:ideas:5000")["status"]
          == "completed",
          f"n={n} "
          f"status={store.get('job:ideas:5000')['status']}")

    # 15. a stale-marked job still settles at delivery
    clock["t"] = 45000.0
    start("briefing")
    store.set_status("job:briefing:45000", "stale",
                     by="collector")
    delivered("briefing", 2)
    it = store.get("job:briefing:45000")
    check("B: stale-marked job settles at delivery",
          it["status"] == "completed"
          and (it.get("counts") or {}).get("produced") == 2,
          str(it["status"]))


if __name__ == "__main__":
    sys.exit(main())
