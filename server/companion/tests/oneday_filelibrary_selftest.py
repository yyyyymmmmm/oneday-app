#!/usr/bin/env python3
"""Self-test for the A-06 file-library read surface:
GET /file-library against a scratch bridge + scratch data root.

Boots the module copy staged next to this file (run via
run_bridge_selftests.sh) or the repo module directly. Asserts:
auth, the aggregated set (curated roots walked server-side,
depth cap 3 below each root), admission parity with the
retired client rules (the 2026-11-10 pollutant samples the
client tests pinned, morphology variants, hidden files, the
root-loose extension whitelist + protected-names gate),
mtime-descending order, source labels, /api/files entry
shape, and offset/limit paging that never truncates silently
(total always reports the full admitted count).
"""
import json
import os
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
KEY = "filelibrary-selftest-key"
PORT = 18771
BASE = f"http://127.0.0.1:{PORT}"

FAILURES = []


def check(name, cond, extra=""):
    if cond:
        print(f"  ok: {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL: {name} {extra}")


def call(method, path, key=KEY):
    req = urllib.request.Request(BASE + path, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def put(root, rel, mtime):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("x")
    os.utime(path, (mtime, mtime))
    return path


def main():
    root = tempfile.mkdtemp(prefix="filelibrary-root-")
    data_tmp = tempfile.mkdtemp(prefix="filelibrary-data-")

    # admitted, one per interesting position
    put(root, "uploads/report.pdf", 1000)
    put(root, "uploads/sub/deep.md", 3000)
    put(root, "uploads/sub/sub2/deeper.txt", 2000)
    # dir depth 3 below the root: its files are still in
    # (the client's BFS absorbed the depth-3 listing)
    put(root, "uploads/sub/sub2/sub3/too-deep.txt", 1500)
    # dir depth 4: never listed, never admitted
    put(root, "uploads/sub/sub2/sub3/sub4/never.txt", 9000)
    # output roots skip the extension whitelist
    put(root, "uploads/中间稿.xyz", 500)
    put(root, "attachments/photo.png", 5000)
    put(root, "cache/documents/gen.docx", 4000)
    put(root, "cron/output/cron-result.json", 2500)
    put(root, "报告.pdf", 6000)  # root-loose, whitelisted ext

    # rejected inside an output root: pollutants + morphology
    for name in ("kanban.db-wal", "state.db", "foo.sqlite",
                 "sessions.json", "x.lock", ".hidden.png"):
        put(root, f"uploads/{name}", 9500)

    # rejected at the workspace root: pipeline/internal files,
    # protected persona/config names, no/unknown extension
    for name in ("data.json", "state.db", "gateway_state.json",
                 "models_dev_cache.etag", "SOUL.md", "config.yaml",
                 "notes", "script.py", ".env", "auth.json"):
        put(root, name, 9500)

    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(data_tmp, "data.json"),
               ONEDAY_PORT=str(PORT), FILE_LIBRARY_ROOT=root)
    env.pop("HERMES_API_KEY", None)
    env.pop("DELIVERY_ROOT", None)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        up = False
        for _ in range(60):
            try:
                s, _ = call("GET", "/health", key=None)
                if s == 200:
                    up = True
                    break
            except Exception:
                pass
            time.sleep(0.2)
        check("bridge up", up)

        s, _ = call("GET", "/file-library", key=None)
        check("no key -> 401", s == 401, f"{s}")

        s, body = call("GET", "/file-library")
        check("GET -> 200", s == 200, f"{s}")
        items = body.get("items", [])
        names = [i["name"] for i in items]
        check("total is the full admitted count",
              body.get("total") == 9, f"{body.get('total')}")
        check("never truncated", body.get("truncated") is False)
        check("default page is the whole set",
              len(items) == 9 and body.get("limit") is None
              and body.get("offset") == 0)
        check("mtime-descending order", names == [
            "报告.pdf", "photo.png", "gen.docx", "deep.md",
            "cron-result.json", "deeper.txt", "too-deep.txt",
            "report.pdf", "中间稿.xyz"], f"{names}")

        by_name = {i["name"]: i for i in items}
        check("source labels ride along",
              by_name["report.pdf"]["source"] == "App 上传"
              and by_name["photo.png"]["source"] == "聊天发送"
              and by_name["gen.docx"]["source"] == "生成文档"
              and by_name["cron-result.json"]["source"]
              == "定时任务产出"
              and by_name["报告.pdf"]["source"] == "工作区根目录")
        photo = by_name["photo.png"]
        check("entry shape mirrors /api/files",
              photo["is_directory"] is False
              and photo["path"] == os.path.join(
                  root, "attachments", "photo.png")
              and photo["size"] == 1
              and photo["mtime"] == 5000
              and photo["mime_type"] == "image/png",
              f"{photo}")
        check("pdf mime derived",
              by_name["report.pdf"]["mime_type"]
              == "application/pdf")

        rejected = ("kanban.db-wal", "state.db", "foo.sqlite",
                    "sessions.json", "x.lock", ".hidden.png",
                    "data.json", "gateway_state.json",
                    "models_dev_cache.etag", "SOUL.md",
                    "config.yaml", "notes", "script.py", ".env",
                    "auth.json", "never.txt")
        leaked = [n for n in rejected if n in by_name]
        check("pollutants/internal/protected never admitted",
              not leaked, f"{leaked}")

        s, page = call("GET", "/file-library?offset=1&limit=2")
        check("paging slices the same ordered set",
              s == 200
              and [i["name"] for i in page["items"]]
              == ["photo.png", "gen.docx"]
              and page["total"] == 9
              and page["truncated"] is False, f"{s} {page}")
        s, page = call("GET", "/file-library?offset=100")
        check("offset past the end is an empty page, not an error",
              s == 200 and page["items"] == [] and page["total"] == 9)
        s, _ = call("GET", "/file-library?offset=-1")
        check("negative offset -> 400", s == 400, f"{s}")
        s, _ = call("GET", "/file-library?limit=abc")
        check("non-integer limit -> 400", s == 400, f"{s}")
        s, _ = call("POST", "/file-library")
        check("POST -> 405", s == 405, f"{s}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    print(f"filelibrary selftest: {len(FAILURES)} failed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
