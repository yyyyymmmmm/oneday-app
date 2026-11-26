#!/usr/bin/env python3
"""Self-test for the delivery sentinel (structured-delivery
benchmark, plan A): assistant messages in a fake state.db get
their mentioned files auto-registered and linked; the
/deliveries/by-message index serves them back.

Boots the module copy staged next to this file (run via
run_bridge_selftests.sh) or the repo module directly. Asserts:
MEDIA: and bare-path pickup, code fence / inline code exemption,
missing-file and source-extension rejection, role filter, one
registration shared by two messages (fingerprint dedup), live
tailing of a message inserted after boot, watermark persistence
across a restart (no duplicate links), index endpoint shapes,
auth, and sentinel status on /health.
"""
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
CANDIDATES = [os.path.join(HERE, "oneday_bridge.py"),
              os.path.join(HERE, "..", "modules", "oneday_bridge.py")]
BRIDGE = next(p for p in CANDIDATES if os.path.exists(p))
KEY = "sentinel-selftest-key"
PORT = 18762
BASE = f"http://127.0.0.1:{PORT}"
SID = "sentinel-test-session"

FAILURES = []


def check(name, cond, extra=""):
    if cond:
        print(f"  ok: {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL: {name} {extra}")


def call(method, path, key=KEY, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def wait_index(mid, want=1, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        s, body = call(
            "GET",
            f"/deliveries/by-message?session_id={SID}&message_id={mid}")
        if s == 200 and len(body.get("deliveries", [])) >= want:
            return body
        time.sleep(0.4)
    return body


def ledger_lines(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def main():
    from PIL import Image

    root = tempfile.mkdtemp(prefix="sentinel-root-")
    data_tmp = tempfile.mkdtemp(prefix="sentinel-data-")
    home_tmp = tempfile.mkdtemp(prefix="sentinel-home-")

    shot = os.path.join(root, "shot.png")
    Image.new("RGB", (640, 400), (40, 120, 200)).save(shot)
    doc = os.path.join(root, "报告.md")
    with open(doc, "w", encoding="utf-8") as f:
        f.write("# 测试报告\n\n这是哨兵自测用的文档正文。\n第二行。\n")
    code = os.path.join(root, "tool.py")
    with open(code, "w", encoding="utf-8") as f:
        f.write("print('not a deliverable')\n")
    late = os.path.join(root, "late.jpg")
    Image.new("RGB", (320, 200), (200, 90, 30)).save(late)

    db_path = os.path.join(home_tmp, "state.db")
    db = sqlite3.connect(db_path)
    db.execute(
        "CREATE TABLE messages (id INTEGER PRIMARY KEY,"
        " session_id TEXT, role TEXT, content TEXT,"
        " timestamp REAL, active INTEGER)")
    old = time.time() - 600
    msgs = [
        (1, "assistant", f"拍好了。\nMEDIA:{shot}"),
        (2, "assistant", f"报告在这：\n{doc}\n看完告诉我。"),
        (3, "assistant", f"示例：\n```\n{shot}\n```\n上面是代码示例"),
        (4, "assistant", f"这个文件还没写：{root}/missing.png"),
        (5, "assistant", f"脚本路径 {code} 已生成"),
        (6, "user", f"这是我发的 {doc}"),
        (7, "assistant", f"行内提及 `{doc}` 不算交付"),
        (8, "assistant", f"同一份报告再发一次：{doc}"),
    ]
    for mid, role, content in msgs:
        db.execute(
            "INSERT INTO messages VALUES (?,?,?,?,?,1)",
            (mid, SID, role, content, old))
    db.commit()
    db.close()

    ledger = os.path.join(data_tmp, "deliveries.jsonl")
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(data_tmp, "data.json"),
               ONEDAY_PORT=str(PORT), DELIVERY_ROOT=root,
               DELIVERY_SENTINEL_DB=db_path,
               DELIVERY_SENTINEL_INTERVAL="1",
               DELIVERY_SENTINEL_START_ID="0")
    env.pop("HERMES_API_KEY", None)

    def boot():
        proc = subprocess.Popen(
            [sys.executable, BRIDGE], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(60):
            try:
                s, _ = call("GET", "/health", key=None)
                if s == 200:
                    return proc
            except Exception:
                pass
            time.sleep(0.2)
        raise RuntimeError("bridge did not come up")

    def stop(proc):
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    proc = boot()
    try:
        s, _ = call("GET", "/deliveries/by-message?session_id=" + SID,
                    key=None)
        check("index no key -> 401", s == 401, f"{s}")

        body = wait_index(1)
        d1 = body.get("deliveries", [])
        check("MEDIA: message auto-registered", len(d1) == 1,
              str(body))
        if d1:
            check("media meta from real file",
                  d1[0].get("name") == "shot.png"
                  and d1[0].get("size") == os.path.getsize(shot)
                  and d1[0].get("kind") == "image",
                  str(d1[0]))
            with open(shot, "rb") as f:
                want = hashlib.sha256(f.read()).hexdigest()
            check("media sha matches real file",
                  d1[0].get("sha256") == want)
            shot_id = d1[0].get("id")

        body = wait_index(2)
        d2 = body.get("deliveries", [])
        check("bare path auto-registered", len(d2) == 1, str(body))
        doc_id = d2[0].get("id") if d2 else None
        check("chinese-name doc meta",
              bool(d2) and d2[0].get("name") == "报告.md"
              and d2[0].get("kind") == "document", str(d2))

        for mid, name in ((3, "code fence exempt"),
                          (4, "missing file skipped"),
                          (5, "source ext excluded"),
                          (6, "user role not scanned"),
                          (7, "inline code exempt")):
            s, b = call(
                "GET",
                f"/deliveries/by-message?session_id={SID}"
                f"&message_id={mid}")
            check(name, s == 200 and b.get("deliveries") == [],
                  f"{s} {b}")

        body = wait_index(8)
        d8 = body.get("deliveries", [])
        check("second mention linked too", len(d8) == 1, str(body))
        check("same registration reused (dedup)",
              bool(d8) and d8[0].get("id") == doc_id, str(d8))

        recs = ledger_lines(ledger)
        regs = [r for r in recs if r.get("id")]
        links = [r for r in recs if r.get("link") is True]
        check("one registration per real file", len(regs) == 2,
              f"regs={len(regs)}")
        check("link lines are auto kind",
              len(links) == 3
              and all(l.get("kind") == "auto" for l in links),
              f"links={len(links)}")

        s, b = call("GET", f"/deliveries/by-message?session_id={SID}")
        mids = [m.get("messageId") for m in b.get("messages", [])]
        check("session index groups by message",
              s == 200 and mids == [1, 2, 8], f"{s} {mids}")
        s, b = call("GET", "/deliveries/by-message")
        check("missing session_id -> 400", s == 400, f"{s}")
        s, b = call(
            "GET",
            "/deliveries/by-message?session_id=nope&message_id=1")
        check("unknown session -> empty 200",
              s == 200 and b.get("deliveries") == [], f"{s} {b}")
        s, b = call(
            "GET",
            "/deliveries/by-message?session_id=x&message_id=abc")
        check("bad message_id -> 400", s == 400, f"{s}")

        s, health = call("GET", "/health", key=None)
        sent = health.get("deliverySentinel", {})
        check("health carries sentinel status",
              s == 200 and sent.get("lastMessageId") == 8
              and sent.get("autoLinks") == 3
              and sent.get("lastError") is None, str(sent))

        s, marker_delivery = call("POST", "/deliveries", body={"path": doc})
        marker = marker_delivery.get("marker")
        db = sqlite3.connect(db_path)
        db.execute("INSERT INTO messages VALUES (?,?,?,?,?,1)",
                   (10, SID, "assistant", f"只有标记 {marker}", time.time() - 60))
        db.execute("INSERT INTO messages VALUES (?,?,?,?,?,1)",
                   (11, SID, "assistant", f"哨兵标记 {marker}", time.time() - 30))
        db.commit()
        db.close()
        body = wait_index(11)
        marker_links = body.get("deliveries", [])
        check("marker-only sentinel message linked",
              len(marker_links) == 1 and marker_links[0].get("id")
              == marker_delivery.get("id"), str(body))
        # Backfill is explicitly callable from the loaded segment, scans all
        # active assistant rows read-only, and skips already-linked tuples.
        # Backfill the deliberately older marker row with the production
        # helper in a namespace seeded from the same segment globals.
        backfill_rows = [(10, SID, f"只有标记 {marker}")]
        # Remove the historical link created by tailing, simulating an older
        # install whose watermark already passed this row before markers were
        # understood.
        kept = [r for r in ledger_lines(ledger)
                if not (r.get("link") is True
                        and r.get("messageId") == 10
                        and r.get("deliveryId") == marker_delivery["id"])]
        with open(ledger, "w", encoding="utf-8") as f:
            for rec in kept:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        def append_backfill(rec):
            with open(ledger, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec) + "\n")

        segment_ns = {
            "_SENTINEL_DB_PATH": __import__("pathlib").Path(db_path),
            "_DELIVERY_LOCK": __import__("threading").Lock(),
            "_delivery_links_load": lambda: [r for r in ledger_lines(ledger)
                                                if r.get("link") is True],
            "_delivery_find": lambda rid: marker_delivery if rid == marker_delivery.get("id") else None,
            "_sentinel_extract": lambda text: [("delivery", m.group(1))
                for m in __import__("re").finditer(r"\[\[deliver:(dlv_[0-9a-f]{20})\]\]", text)],
            "_delivery_append": append_backfill,
            "_DELIVERY_LEDGER_PATH": __import__("pathlib").Path(ledger),
            "_DELIVERY_ASSET_DIR": __import__("pathlib").Path(data_tmp),
            "DELIVERY_ROOT": __import__("pathlib").Path(root),
            "DATA_PATH": __import__("pathlib").Path(os.path.join(data_tmp, "data.json")),
            "_delivery_public": lambda rec, status: dict(rec),
            "_delivery_status": lambda rec: "ok",
            "json": json, "sqlite3": sqlite3, "datetime": __import__("datetime").datetime,
            "timezone": __import__("datetime").timezone,
        }
        # Use the source function body from the package segment for an actual
        # execution rather than mirroring its idempotency logic in the test.
        import ast
        segment_path = os.path.join(HERE, "..", "modules", "oneday_seg_delivery.py")
        tree = ast.parse(open(segment_path, encoding="utf-8").read())
        func = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                    and n.name == "_delivery_backfill_markers")
        exec(compile(ast.Module(body=[func], type_ignores=[]), segment_path, "exec"), segment_ns)
        first_added = segment_ns["_delivery_backfill_markers"]()
        existing = {(l.get("sessionId"), l.get("messageId"),
                     l.get("deliveryId")) for l in ledger_lines(ledger)
                    if l.get("link") is True}
        second_added = segment_ns["_delivery_backfill_markers"]()
        check("historical marker backfill idempotent",
              first_added == 1 and second_added == 0
              and (SID, 10, marker_delivery["id"]) in existing,
              f"first={first_added} second={second_added}")
        s, old_message = call(
            "GET", f"/deliveries/by-message?session_id={SID}&message_id=10")
        check("backfilled message index matches attachment metadata",
              s == 200 and len(old_message.get("deliveries", [])) == 1
              and old_message["deliveries"][0].get("id")
              == marker_delivery.get("id"), str(old_message))

        # Live tail: a message inserted after boot gets picked up.
        db = sqlite3.connect(db_path)
        db.execute(
            "INSERT INTO messages VALUES (?,?,?,?,?,1)",
            (12, SID, "assistant", f"新图：{late}", time.time() - 30))
        db.commit()
        db.close()
        body = wait_index(12)
        d9 = body.get("deliveries", [])
        check("live tail picks up new message",
              len(d9) == 1 and d9[0].get("name") == "late.jpg",
              str(body))
        links_before = len(
            [r for r in ledger_lines(ledger) if r.get("link") is True])
    finally:
        stop(proc)

    # Restart: the persisted watermark must prevent reprocessing.
    proc = boot()
    try:
        time.sleep(3)
        links_after = len(
            [r for r in ledger_lines(ledger) if r.get("link") is True])
        check("restart adds no duplicate links",
              links_after == links_before,
              f"{links_before} -> {links_after}")
        state = os.path.join(data_tmp, "delivery-sentinel.json")
        with open(state, encoding="utf-8") as f:
            wm = json.load(f)
        check("watermark persisted at last message",
              wm.get("lastMessageId") == 12, str(wm))
    finally:
        stop(proc)

    print(f"\n{'ALL PASS' if not FAILURES else 'FAILURES: ' + str(FAILURES)}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
