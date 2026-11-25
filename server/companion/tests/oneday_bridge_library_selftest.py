#!/usr/bin/env python3
"""Self-test for the library MCP facade (1.0.73):
POST /library-mcp against a subprocess bridge + scratch
file-library root.

Boots the module copy staged next to this file (run via
run_bridge_selftests.sh) or the repo module directly. Asserts:
- the facade sits behind the bridge key (401 without it) and
  speaks the same JSON-RPC shape as the goals/sessions
  facades (initialize / ping / notification / tools/list /
  tools/call, -32601 for unknown methods, 405 for non-POST);
- tools/list carries exactly one read-only tool, library_list;
- library_list reconciles with the REST face item for item:
  same admitted total, same order, same entry shape as
  GET /file-library (both are _file_library_view -- one
  source of truth, no second walk);
- since filters on mtime and reports sinceCount while total
  stays the whole admitted count; limit/offset page without
  ever truncating silently;
- bad arguments answer isError (never a 500, never a hang);
- every tools/call books exactly one P0 trace (ok with a
  result summary, failed with the verbatim error).
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
KEY = "library-mcp-selftest-key"
PORT = 18781
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(method, path, body=None, key=KEY):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data,
                                 method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


_rpc_id = [0]


def rpc(method, params=None, notify=False):
    _rpc_id[0] += 1
    body = {"jsonrpc": "2.0", "method": method}
    if not notify:
        body["id"] = _rpc_id[0]
    if params is not None:
        body["params"] = params
    return call("POST", "/library-mcp", body)


def tool(name, args=None):
    st, resp = rpc("tools/call",
                   {"name": name, "arguments": args or {}})
    if st != 200:
        return None, True, st
    result = resp.get("result") or {}
    content = result.get("content") or []
    text = content[0].get("text") if content else None
    try:
        parsed = json.loads(text) if text else None
    except Exception:
        parsed = None
    return parsed, bool(result.get("isError")), st


def put(root, rel, age_seconds):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("x")
    when = time.time() - age_seconds
    os.utime(path, (when, when))
    return when


def main():
    day = 86400.0
    root = tempfile.mkdtemp(prefix="library-mcp-root-")
    data_tmp = tempfile.mkdtemp(prefix="library-mcp-data-")
    # Admitted fixture set (ages pinned so mtime-desc order is
    # deterministic): a(1d) b(2d) e(2d+1h) c(3d) d(10d) = 5.
    put(root, "uploads/a.pdf", 1 * day)
    put(root, "attachments/b.png", 2 * day)
    put(root, "e.pdf", 2 * day + 3600)          # root-loose
    put(root, "cache/documents/c.md", 3 * day)
    put(root, "cron/output/d.txt", 10 * day)
    put(root, "uploads/state.db", 1 * day)      # pollutant: out

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
            time.sleep(0.5)
        check("bridge boots", up)
        if not up:
            return 1

        # --- auth + method gates -------------------------------
        st, _ = call("POST", "/library-mcp",
                     {"jsonrpc": "2.0", "id": 1, "method": "ping"},
                     key=None)
        check("no key -> 401", st == 401, f"got {st}")
        st, _ = call("GET", "/library-mcp")
        check("GET -> 405", st == 405, f"got {st}")

        # --- JSON-RPC handshake --------------------------------
        st, resp = rpc("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "selftest", "version": "0"}})
        info = (resp.get("result") or {}).get("serverInfo") or {}
        check("initialize names oneday-library",
              st == 200 and info.get("name") == "oneday-library",
              f"got {st} {info}")
        st, resp = rpc("ping")
        check("ping answers", st == 200
              and resp.get("result") == {})
        st, _ = rpc("notifications/initialized", notify=True)
        check("notification -> 202", st == 202, f"got {st}")
        st, resp = rpc("no/such-method")
        check("unknown method -> -32601", st == 200
              and (resp.get("error") or {}).get("code") == -32601,
              f"got {st} {resp}")

        # --- tools/list contract -------------------------------
        st, resp = rpc("tools/list")
        tools = (resp.get("result") or {}).get("tools") or []
        check("tools/list is exactly [library_list]",
              [t.get("name") for t in tools] == ["library_list"],
              f"got {[t.get('name') for t in tools]}")
        schema = (tools[0].get("inputSchema") or {}) \
            .get("properties") or {}
        check("schema carries since/limit/offset",
              set(schema) == {"since", "limit", "offset"},
              f"got {sorted(schema)}")

        # --- full list reconciles with the REST face -----------
        view, is_err, st = tool("library_list")
        check("library_list ok", st == 200 and not is_err
              and isinstance(view, dict), f"got {st} {view}")
        check("total is the admitted count 5",
              view.get("total") == 5, f"got {view.get('total')}")
        items = view.get("items") or []
        check("all 5 items returned without paging",
              len(items) == 5, f"got {len(items)}")
        check("mtime-desc order a,b,e,c,d",
              [i.get("name") for i in items]
              == ["a.pdf", "b.png", "e.pdf", "c.md", "d.txt"],
              f"got {[i.get('name') for i in items]}")
        check("entry shape matches /api/files entries",
              all({"name", "path", "is_directory", "size",
                   "mtime", "mime_type", "source"}
                  <= set(i) for i in items))
        check("truncated is False", view.get("truncated") is False)

        st, rest = call("GET", "/file-library")
        check("REST /file-library total agrees",
              st == 200 and rest.get("total") == view.get("total"),
              f"got {st} {rest.get('total')}")
        check("REST items identical to facade items",
              rest.get("items") == items)

        # --- since ---------------------------------------------
        since = time.time() - 2.5 * day
        view2, is_err, _ = tool("library_list", {"since": since})
        check("since 2.5d -> sinceCount 3, total still 5",
              not is_err and view2.get("sinceCount") == 3
              and view2.get("total") == 5,
              f"got {view2.get('sinceCount')} {view2.get('total')}")
        check("since page holds exactly the fresh items",
              [i.get("name") for i in view2.get("items") or []]
              == ["a.pdf", "b.png", "e.pdf"])
        check("every since item is at/after since",
              all((i.get("mtime") or 0) >= since
                  for i in view2.get("items") or []))
        view3, _, _ = tool("library_list",
                           {"since": time.time() - 7 * day})
        check("since 7d -> sinceCount 4",
              view3.get("sinceCount") == 4,
              f"got {view3.get('sinceCount')}")

        # --- paging --------------------------------------------
        page, _, _ = tool("library_list", {"limit": 2})
        check("limit 2 -> 2 items, total 5",
              len(page.get("items") or []) == 2
              and page.get("total") == 5)
        page, _, _ = tool("library_list",
                          {"offset": 4, "limit": 2})
        check("offset 4 limit 2 -> last item only",
              [i.get("name") for i in page.get("items") or []]
              == ["d.txt"])
        page, _, _ = tool("library_list", {"offset": 99})
        check("offset past end -> 0 items, total 5",
              (page.get("items") or []) == []
              and page.get("total") == 5)
        page, _, _ = tool("library_list", {
            "since": time.time() - 7 * day, "limit": 2})
        check("since + limit pages the filtered set",
              len(page.get("items") or []) == 2
              and page.get("sinceCount") == 4)

        # --- failure paths -------------------------------------
        _, is_err, _ = tool("library_nope")
        check("unknown tool -> isError", is_err)
        bad, is_err, _ = tool("library_list", {"since": "abc"})
        check("since garbage -> isError with message",
              is_err and bool((bad or {}).get("error")))
        _, is_err, _ = tool("library_list", {"offset": -1})
        check("negative offset -> isError", is_err)
        _, is_err, _ = tool("library_list", {"limit": "x"})
        check("limit garbage -> isError", is_err)

        # --- traces: one per call, five echo elements ----------
        st, traces = call("GET", "/traces?limit=200")
        recs = traces.get("items") or []
        lib = [r for r in recs
               if str(r.get("action", "")).startswith("library.")]
        oks = [r for r in lib if r.get("status") == "ok"]
        fails = [r for r in lib if r.get("status") == "failed"]
        check("ok calls booked ok traces with results",
              len(oks) >= 6 and all(r.get("result") for r in oks),
              f"ok={len(oks)}")
        check("failed calls booked failed traces with errors",
              len(fails) >= 4
              and all(r.get("error") for r in fails),
              f"failed={len(fails)}")
        check("trace target is pointable at the library",
              all((r.get("target") or {}).get("kind") == "library"
                  for r in lib))
        return 0 if failed == 0 else 1
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    rc = main()
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(rc if rc else (0 if failed == 0 else 1))
