#!/usr/bin/env python3
"""Traces + goals-MCP self-test for oneday_bridge.py (P0/P3,
AI internal powers foundation, 2026-11-13).

Against a subprocess bridge on temp data:
- /traces and /mcp are behind the bridge key (401 without it).
- MCP handshake: initialize / ping / notification / tools/list.
- goals facade end-to-end: create (source=chat) -> add_entry
  (source=agent) -> list (+status filter) -> update to completed.
- Failure paths answer isError AND leave a failed trace whose
  error text is the verbatim bridge refusal (的目标不存在 etc.).
- Every facade call leaves exactly one trace with the five echo
  elements (action / pointable target / at / result or error).
- POST /traces door validation: ok needs result, failed needs
  verbatim error, status/target shape enforced.
- Traces survive a bridge restart (data.json round-trip).
- The pre-existing goals REST surface is untouched.
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
BRIDGE = os.path.join(HERE, "oneday_bridge.py")
KEY = "traces-mcp-selftest-key"
PORT = 18751
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
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
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
    return call("POST", "/mcp", body)


def tool(name, args=None):
    st, resp = rpc("tools/call",
                   {"name": name, "arguments": args or {}})
    assert st == 200, (st, resp)
    result = resp["result"]
    payload = json.loads(result["content"][0]["text"])
    return result["isError"], payload


def start(tmp):
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(tmp, "data.json"),
               ONEDAY_PORT=str(PORT))
    env.pop("HERMES_API_KEY", None)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        try:
            st, _ = call("GET", "/health", key=None)
            if st == 200:
                return proc
        except Exception:
            pass
        time.sleep(0.25)
    raise RuntimeError("bridge did not come up")


def main():
    tmp = tempfile.mkdtemp(prefix="traces-mcp-")
    proc = start(tmp)
    try:
        st, _ = call("GET", "/traces", key=None)
        check("traces requires key", st == 401, f"got {st}")
        st, _ = call("POST", "/mcp",
                     {"jsonrpc": "2.0", "id": 1, "method": "ping"},
                     key=None)
        check("mcp requires key", st == 401, f"got {st}")

        st, resp = rpc("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "selftest", "version": "0"}})
        check("initialize names the facade",
              resp["result"]["serverInfo"]["name"] == "oneday-goals",
              str(resp))
        st, resp = rpc("ping")
        check("ping answers", resp["result"] == {}, str(resp))
        st, _ = rpc("notifications/initialized", notify=True)
        check("notification accepted", st == 202, f"got {st}")
        st, resp = rpc("tools/list")
        names = {t["name"] for t in resp["result"]["tools"]}
        check("tools/list is the four goal tools",
              names == {"goals_list", "goals_create",
                        "goals_add_entry", "goals_update"},
              str(names))
        st, resp = rpc("bogus/method")
        check("unknown method is a JSON-RPC error",
              resp["error"]["code"] == -32601, str(resp))

        is_err, goal = tool("goals_create",
                            {"title": "自检目标·留痕门面",
                             "note": "traces-mcp selftest"})
        check("goals_create ok", not is_err, str(goal))
        check("facade goal carries source=chat",
              goal.get("source") == "chat", str(goal))
        gid = goal["id"]

        is_err, entry = tool("goals_add_entry",
                             {"goalId": gid, "body": "自检进展一"})
        check("goals_add_entry ok", not is_err, str(entry))
        check("facade entry carries source=agent",
              entry.get("source") == "agent", str(entry))

        is_err, listing = tool("goals_list")
        check("goals_list sees the goal",
              any(g["id"] == gid for g in listing["items"]),
              str(listing))
        is_err, listing = tool("goals_list",
                               {"status": "completed"})
        check("goals_list status filter excludes active goal",
              all(g["id"] != gid for g in listing["items"]),
              str(listing))

        is_err, updated = tool("goals_update",
                               {"goalId": gid, "status": "completed"})
        check("goals_update completes the goal",
              not is_err and updated.get("status") == "completed",
              str(updated))

        is_err, payload = tool("goals_add_entry",
                               {"goalId": "g_nope", "body": "x"})
        check("entry into missing goal is an MCP error",
              is_err and payload.get("error") == "目标不存在",
              str(payload))
        is_err, payload = tool("goals_create", {"title": "  "})
        check("empty title refused", is_err, str(payload))
        is_err, payload = tool("goals_bogus", {})
        check("unknown tool is an MCP error", is_err, str(payload))

        st, resp = call("GET", "/traces?limit=500")
        items = resp["items"]
        creates = [t for t in items if t["action"] == "goals.create"
                   and t["status"] == "ok"
                   and t["target"].get("id") == gid]
        check("create left one ok trace on the goal",
              len(creates) == 1, str(items))
        if creates:
            tr = creates[0]
            check("trace has all five echo elements",
                  tr["id"].startswith("trc_")
                  and tr["actor"] == "agent"
                  and tr["target"]["kind"] == "goal"
                  and tr["target"]["ref"] == f"oneday://goals/{gid}"
                  and isinstance(tr["at"], float)
                  and "已创建目标" in (tr["result"] or "")
                  and tr["error"] is None, str(tr))
            st, one = call("GET", f"/traces/{tr['id']}")
            check("single trace reads back",
                  st == 200 and one["id"] == tr["id"], str(one))
        failures = [t for t in items if t["status"] == "failed"]
        verbatim = [t for t in failures
                    if t["action"] == "goals.add_entry"
                    and t["error"] == "目标不存在"]
        check("failure trace keeps the error verbatim",
              len(verbatim) == 1, str(failures))
        check("every facade call left a trace",
              len([t for t in items
                   if t["action"].startswith("goals.")]) == 8,
              str(len(items)))
        st, resp = call("GET", "/traces?status=failed")
        check("status filter returns only failures",
              all(t["status"] == "failed" for t in resp["items"])
              and len(resp["items"]) == 3, str(resp))
        st, resp = call("GET", "/traces?targetId=" + gid)
        check("targetId filter finds the goal's traces",
              len(resp["items"]) >= 3
              and all(t["target"].get("id") == gid
                      for t in resp["items"]), str(resp))
        st, _ = call("GET", "/traces/trc_nope")
        check("missing trace is 404", st == 404, f"got {st}")

        st, rec = call("POST", "/traces", {
            "action": "identity.rename", "actor": "agent",
            "target": {"kind": "identity", "id": "soul",
                       "label": "智能体名",
                       "ref": "oneday://hub/identity"},
            "status": "ok", "result": "已把名字改为「小天」"})
        check("generic trace write (P1-shaped) lands",
              st == 201 and rec["id"].startswith("trc_"), str(rec))
        st, _ = call("POST", "/traces", {
            "action": "x.y", "target": {"kind": "goal"},
            "status": "failed"})
        check("failed trace without error text refused", st == 400,
              f"got {st}")
        st, _ = call("POST", "/traces", {
            "action": "x.y", "target": {"kind": "goal"},
            "status": "ok"})
        check("ok trace without result refused", st == 400,
              f"got {st}")
        st, _ = call("POST", "/traces", {
            "action": "x.y", "target": {"kind": "goal"},
            "status": "maybe", "result": "r", "error": "e"})
        check("bad status refused", st == 400, f"got {st}")
        st, _ = call("POST", "/traces", {
            "action": "x.y", "status": "ok", "result": "r"})
        check("target-less trace refused", st == 400, f"got {st}")

        st, g2 = call("POST", "/goals",
                      {"title": "自检目标·REST 回归",
                       "source": "manual"})
        check("goals REST create untouched",
              st == 201 and g2.get("source") == "manual", str(g2))
        st, _ = call("DELETE", f"/goals/{g2['id']}")
        check("goals REST delete untouched", st == 200, f"got {st}")

        st, before = call("GET", "/traces?limit=500")
        count_before = len(before["items"])
    finally:
        proc.terminate()
        proc.wait(timeout=10)

    proc = start(tmp)
    try:
        st, after = call("GET", "/traces?limit=500")
        check("traces survive a bridge restart",
              len(after["items"]) == count_before,
              f"{count_before} -> {len(after['items'])}")
        is_err, listing = tool("goals_list")
        check("goal survives alongside its traces",
              any(g["id"] == gid for g in listing["items"]),
              str(listing))
    finally:
        proc.terminate()
        proc.wait(timeout=10)

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
