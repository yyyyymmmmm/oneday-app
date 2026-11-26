#!/usr/bin/env python3
"""Batch-4 smoke selftest: identity_gateway + front_gateway with
stub stores (temp HERMES_HOME with a SOUL.md, temp avatar dir,
temp front state), a stub oneday traces sink on loopback and a
stub New API admin face. No production data, no real keys.
Run: python3 identity_front_gateway_selftest.py
"""
import base64
import json
import os
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(tempfile.mkdtemp(prefix="batch4-selftest-"))
HERMES_HOME = ROOT / "data"
HERMES_HOME.mkdir(parents=True)
(HERMES_HOME / "SOUL.md").write_text("# 小天\n\n我是小天，OneDay 的智能体。\n", encoding="utf-8")
(HERMES_HOME / ".env").write_text(
    "GITHUB_MCP_TOKEN=test-github-token\nMCP_BOX_API_KEY=box-stub-key-123456\n",
    encoding="utf-8")

traces = []


class TraceStub(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        traces.append(body)
        raw = json.dumps({"id": "trc_stub"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


trace_server = ThreadingHTTPServer(("127.0.0.1", 0), TraceStub)
threading.Thread(target=trace_server.serve_forever, daemon=True).start()
trace_port = trace_server.server_address[1]


class NewApiStub(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        raw = json.dumps({"success": True, "data": {"total": 1, "items": [
            {"id": 7, "name": "主渠道", "status": 1,
             "models": "claude-sonnet-4-6,gpt-5", "priority": 3,
             "weight": 2, "group": "default",
             "key": "sk-MUST-NOT-LEAK"}]}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


newapi_server = ThreadingHTTPServer(("127.0.0.1", 0), NewApiStub)
threading.Thread(target=newapi_server.serve_forever, daemon=True).start()
newapi_port = newapi_server.server_address[1]

os.environ["HERMES_HOME"] = str(HERMES_HOME)
os.environ["AVATAR_DIR"] = str(ROOT / "identity")
os.environ["FRONT_STATE_DIR"] = str(ROOT / "front")
os.environ["API_SERVER_KEY"] = "test-single-key"
os.environ["ONEDAY_BASE"] = f"http://127.0.0.1:{trace_port}/api/oneday-bridge"

sys.path.insert(0, str(Path(__file__).parent / "patches"))
import front_gateway as fg  # noqa: E402
import identity_gateway as ig  # noqa: E402

PASS = 0
FAIL = 0


def check(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name} {extra}")


def call(method, path, body=None):
    raw = json.dumps(body).encode() if body is not None else b""
    status, resp, hdrs = ig.dispatch(method, path, {}, raw)
    try:
        return status, json.loads(resp or b"{}"), hdrs, resp
    except Exception:
        return status, {}, hdrs, resp


PNG_B64 = base64.b64encode(
    base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
        "+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")).decode()

print("== identity_gateway ==")
st, body, _, _ = call("GET", "/health")
check("health 200 + traceSink oneday",
      st == 200 and body.get("module") == "identity"
      and body.get("traceSink") == "oneday", f"{st} {body}")
st, body, _, _ = call("GET", "/identity/name")
check("name read from SOUL", st == 200 and body.get("soulName") == "小天",
      f"{st} {body}")
st, body, _, _ = call("POST", "/identity/name", {"name": "x"})
check("POST /identity/name stays retired (404 fall-through)", st == 404,
      f"{st}")
st, body, _, _ = call("POST", "/identity/avatar",
                      {"kind": "preset", "presetId": "paw"})
preset_id = body.get("id")
check("avatar preset add 201 current",
      st == 201 and body.get("current") is True and preset_id, f"{st} {body}")
dynamic_presets = (
    "blob-blue", "cat-violet", "bear-amber", "bot-cyan",
    "sprout-green", "star-pink", "blob-coral", "bot-slate",
)
classic_presets = ("partner", "paw", "sparkles", "atom")
for preset in dynamic_presets:
    st, body, _, _ = call("POST", "/identity/avatar",
                          {"kind": "preset", "presetId": preset})
    check(f"dynamic avatar preset {preset} saved + current",
          st == 201 and body.get("presetId") == preset
          and body.get("current") is True, f"{st} {body}")
for preset in classic_presets:
    st, body, _, _ = call("POST", "/identity/avatar",
                          {"kind": "preset", "presetId": preset})
    check(f"classic avatar preset {preset} saved + current",
          st == 201 and body.get("presetId") == preset
          and body.get("current") is True, f"{st} {body}")
st, body, _, _ = call("POST", "/identity/avatar",
                      {"kind": "preset", "presetId": "not-a-real-avatar"})
check("unknown avatar preset rejected with 400",
      st == 400 and "不在目录内" in body.get("error", ""), f"{st} {body}")
st, body, _, _ = call("POST", "/identity/avatar",
                      {"imageBase64": PNG_B64})
img_id = body.get("id")
check("avatar image add 201", st == 201 and img_id, f"{st} {body}")
st, body, hdrs, raw = call("GET", f"/identity/avatar/image?id={img_id}")
check("avatar image bytes round-trip",
      st == 200 and raw == base64.b64decode(PNG_B64)
      and hdrs.get("Content-Type") == "image/png", f"{st}")
st, body, _, _ = call("GET", "/identity/avatar")
check("avatar index: current=image, 14 items",
      st == 200 and body.get("currentId") == img_id
      and len(body.get("items", [])) == 14, f"{st} {body}")
st, body, _, _ = call("POST", "/identity/avatar/select", {"id": preset_id})
check("avatar select back to preset",
      st == 200 and body.get("current") is True, f"{st} {body}")
check("traces reached the oneday sink",
      any(t.get("action") == "identity.set_avatar_preset" for t in traces)
      and any(t.get("action") == "identity.select_avatar" for t in traces),
      f"{[t.get('action') for t in traces]}")

st, body, _, _ = call("POST", "/mcp", {"jsonrpc": "2.0", "id": 1,
                                       "method": "initialize", "params": {}})
check("mcp initialize", st == 200
      and body["result"]["serverInfo"]["name"] == "oneday-identity", f"{st}")
st, body, _, _ = call("POST", "/mcp", {"jsonrpc": "2.0", "id": 2,
                                       "method": "tools/list", "params": {}})
check("mcp tools/list = 6 tools",
      st == 200 and len(body["result"]["tools"]) == 6, f"{st}")
st, body, _, _ = call("POST", "/mcp", {
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {"name": "identity_set_name", "arguments": {"name": "阿狗"}}})
res = json.loads(body["result"]["content"][0]["text"])
soul_now = (HERMES_HOME / "SOUL.md").read_text(encoding="utf-8")
check("mcp set_name rewrites only the title line",
      res.get("soulName") == "阿狗"
      and soul_now.splitlines()[0] == "# 阿狗"
      and "我是小天，OneDay 的智能体。" in soul_now, f"{res} / {soul_now!r}")
check("set_name trace via sink (mode oneday)",
      res.get("trace", {}).get("mode") == "oneday", f"{res.get('trace')}")
st, body, _, _ = call("POST", "/mcp", {
    "jsonrpc": "2.0", "id": 4, "method": "tools/call",
    "params": {"name": "identity_get_name", "arguments": {}}})
res = json.loads(body["result"]["content"][0]["text"])
check("mcp get_name reads back 阿狗", res.get("soulName") == "阿狗", f"{res}")

trace_server.shutdown()
st, body, _, _ = call("POST", "/mcp", {
    "jsonrpc": "2.0", "id": 5, "method": "tools/call",
    "params": {"name": "identity_set_name", "arguments": {"name": "小天"}}})
res = json.loads(body["result"]["content"][0]["text"])
spill = Path(os.environ["AVATAR_DIR"]) / "traces-spill.jsonl"
check("sink down -> trace spills locally, action still succeeds",
      res.get("soulName") == "小天" and res.get("trace", {}).get("mode") == "spill"
      and spill.exists(), f"{res.get('trace')}")

print("== front_gateway ==")
st, payload = fg.get_connections()
conns = {c["id"]: c for c in payload["connections"]}
check("connections read 200", st == 200, f"{st}")
check("github configured from Hermes .env presence",
      conns["github"]["configured"] is True, f"{conns.get('github')}")
check("box configured from Hermes .env presence",
      conns["box"]["configured"] is True, f"{conns.get('box')}")
check("public view carries no secret material",
      all("secret" not in c for c in payload["connections"])
      and "ghp_stubtoken" not in json.dumps(payload), "")
st, payload = fg.get_gateway_channels()
check("gateway-channels unconfigured -> honest 503", st == 503, f"{st}")
fg.NEWAPI_BASE = f"http://127.0.0.1:{newapi_port}"
fg.NEWAPI_ADMIN_TOKEN = "test-admin-token"
st, payload = fg.get_gateway_channels()
ch = (payload.get("channels") or [{}])[0]
check("gateway-channels proxies display fields only",
      st == 200 and ch.get("name") == "主渠道"
      and ch.get("status") == "enabled"
      and ch.get("models") == ["claude-sonnet-4-6", "gpt-5"]
      and "key" not in ch and "sk-MUST-NOT-LEAK" not in json.dumps(payload),
      f"{st} {payload}")

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
