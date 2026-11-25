#!/usr/bin/env python3
"""Feedfix (2026-11-24) replay self-test for the A+B sourcing
repair in oneday_seg_feed.py.

Replays the 2026-11-24 08:30 round's actual bad material
against the new code gates:
  R1  A1: a social material run with a VERIFIED zero
      tool-call count loses its whole submission (the
      fabricated "Nov 25" zhihu ranking, placeholder URL).
  R2  A1+A2: with a verified positive count, the future-
      dated candidate and the dead-link candidate drop,
      the good one survives, drops are named in the gate.
  R3  A1: an unverifiable count is NOT a zero -- material
      survives and the gate notes the road ran unaudited.
  R4  A2: the URL probe itself, against a local HTTP
      server (200 / 404 / HEAD-refused-then-GET / refused).
  R5  A2: the Chinese long-form future date also drops.
  R6  A3: model-release directions classify apart from
      open-source-project directions; the releases road
      keeps only in-window (7d) releases; the repo road
      still serves project directions.
  R7  B3: the avoid list carries research posts only.
  R8  B1: the used-angle window is 30 days by default
      (hourly keeps days=3); prompt versions bumped, the
      editor seat untouched.
B2 (dual twin-link) is covered end-to-end by the p3
selftest's D3b check; D3 keeps the E6 backstop covered.
"""
import importlib.util
import json
import os
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "oneday_bridge.py")

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


tmp = tempfile.mkdtemp(prefix="feedfix-")
os.environ["ONEDAY_BRIDGE_KEY"] = "feedfix-selftest-key"
os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
os.environ["HERMES_API_KEY"] = "fake-key"

spec = importlib.util.spec_from_file_location("ob_ff", BRIDGE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod._load()

NOW = time.time()
DAY = 24 * 3600
TZ = mod._sched_tz()


def iso(days_offset):
    d = datetime.fromtimestamp(NOW + days_offset * DAY, tz=TZ)
    return d.strftime("%Y-%m-%d")


def cn_date(days_offset):
    d = datetime.fromtimestamp(NOW + days_offset * DAY, tz=TZ)
    return f"{d.year}年{d.month}月{d.day}日"


def long_content(tag):
    return (f"{tag}的正文内容。" * 120)


# ---------- R1: A1 verified zero discards everything ------
SOCIAL_BAD = json.dumps({"candidates": [{
    "title": "知乎热榜（明日版）",
    "url": "https://www.zhihu.com/question/12345678",
    "publishedAt": iso(+1),
    "content": long_content("热榜"),
    "images": ["https://pic1.zhimg.com/v2-abc123.jpg"]}]},
    ensure_ascii=False)


def route_http(tool_calls):
    def fake_http_json(url, **kw):
        if "/v1/runs/" in url:
            return 200, {"session_id": "sess-ff"}, ""
        if "/api/sessions/" in url:
            return 200, {"tool_call_count": tool_calls}, ""
        return 404, None, ""
    return fake_http_json


mod._hermes_submit_run = lambda prompt, key: ("run-ff-1", None)
mod._hermes_poll_run = lambda run_id: (SOCIAL_BAD, None)
REAL_PROBE = mod._material_url_status
mod._http_json = route_http(0)
cands, extracts, gate = mod._social_material(
    ["知乎 热榜"], "20990101", 0)
check("R1 zero-tool-call social submission discarded whole",
      cands == [] and extracts == {} and gate is not None
      and gate["discarded"] is True
      and gate["toolCalls"] == 0
      and any("零工具调用" in n for n in gate["notes"]),
      f"{cands} {gate}")

# ---------- R2: verified positive, A2 screens -------------
AGENT_MIX = json.dumps({"candidates": [
    {"title": "未来帖", "url": "https://example.com/future",
     "publishedAt": iso(+1), "content": long_content("未来"),
     "images": []},
    {"title": "死链帖", "url": "https://example.com/dead",
     "publishedAt": iso(-1), "content": long_content("死链"),
     "images": []},
    {"title": "好帖", "url": "https://example.com/good",
     "publishedAt": iso(-1), "content": long_content("好"),
     "images": []}]}, ensure_ascii=False)
mod._hermes_poll_run = lambda run_id: (AGENT_MIX, None)
mod._http_json = route_http(5)
mod._material_url_status = lambda url: (
    404 if url.endswith("/dead") else 200)
cands, extracts, gate = mod._agent_material(
    ["q"], "20990101", 1)
check("R2 future + dead drop, good survives, gate names them",
      [c["url"] for c in cands] == ["https://example.com/good"]
      and gate["futureUrls"] == ["https://example.com/future"]
      and gate["deadUrls"] == ["https://example.com/dead"]
      and gate["discarded"] is False
      and gate["toolCalls"] == 5,
      f"{cands} {gate}")

# ---------- R3: unverifiable is not zero ------------------
mod._http_json = lambda url, **kw: (404, None, "")
cands, extracts, gate = mod._agent_material(
    ["q"], "20990101", 2)
check("R3 unverifiable count keeps material, notes unaudited",
      len(cands) == 1 and gate["toolCalls"] is None
      and gate["discarded"] is False
      and any("未过 A1 审计" in n for n in gate["notes"]),
      f"{cands} {gate}")
mod._material_url_status = REAL_PROBE  # restore the probe

# ---------- R4: the probe itself, local server ------------


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _code(self):
        return {"/ok": 200, "/gone": 404,
                "/head-shy": 200}[self.path]

    def do_HEAD(self):
        if self.path == "/head-shy":
            self.send_response(405)
        else:
            self.send_response(self._code())
        self.end_headers()

    def do_GET(self):
        self.send_response(self._code())
        self.end_headers()
        self.wfile.write(b"x")


srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]
check("R4 probe: 200 alive, 404 dead, HEAD-shy GET-rescued, "
      "refused is None",
      mod._material_url_status(f"http://127.0.0.1:{port}/ok")
      == 200
      and mod._material_url_status(
          f"http://127.0.0.1:{port}/gone") == 404
      and mod._material_url_status(
          f"http://127.0.0.1:{port}/head-shy") == 200
      and mod._material_url_status(
          "http://127.0.0.1:1/nope") is None)
srv.shutdown()

# ---------- R5: Chinese-form future date ------------------
mod._material_url_status = lambda url: 200
kept, kept_ex, screen = mod._validate_material_cands([
    {"title": "未来", "url": "https://example.com/cn-future",
     "publishedAt": cn_date(+2)},
    {"title": "过去", "url": "https://example.com/cn-past",
     "publishedAt": cn_date(-2)}],
    {"https://example.com/cn-future": {"content": "x"},
     "https://example.com/cn-past": {"content": "y"}})
check("R5 Chinese long-form future date drops, past keeps",
      [c["url"] for c in kept]
      == ["https://example.com/cn-past"]
      and screen["futureUrls"]
      == ["https://example.com/cn-future"],
      f"{kept} {screen}")
mod._material_url_status = REAL_PROBE

# ---------- R6: A3 classification + releases road ---------
check("R6 model-release vs project classification",
      mod._is_github_direction(
          {"name": "GitHub 模型发布", "queries": ["llm"]})
      and mod._is_model_release_direction(
          {"name": "GitHub 模型发布", "angle": "本周新模型",
           "queries": ["llm release"]})
      and mod._is_github_direction(
          {"name": "开源项目", "queries": ["github trending"]})
      and not mod._is_model_release_direction(
          {"name": "开源项目", "angle": "本周热门仓库",
           "queries": ["github trending"]}))

REL_NEW = (datetime.fromtimestamp(NOW - 2 * DAY, tz=timezone.utc)
           .strftime("%Y-%m-%dT%H:%M:%SZ"))
REL_OLD = (datetime.fromtimestamp(NOW - 30 * DAY,
                                  tz=timezone.utc)
           .strftime("%Y-%m-%dT%H:%M:%SZ"))


def github_http(url, **kw):
    if "search/repositories" in url:
        return 200, {"items": [
            {"full_name": "octo/model-x",
             "html_url": "https://github.com/octo/model-x",
             "description": "a model repo",
             "created_at": iso(-2)},
            {"full_name": "octo/old-y",
             "html_url": "https://github.com/octo/old-y",
             "description": "an old repo",
             "created_at": iso(-40)}]}, ""
    if "/repos/octo/model-x/releases" in url:
        return 200, [{
            "tag_name": "v2.0", "name": "Model X 2.0",
            "html_url": "https://github.com/octo/model-x"
                        "/releases/tag/v2.0",
            "published_at": REL_NEW, "draft": False,
            "body": "release notes " * 30}], ""
    if "/repos/octo/old-y/releases" in url:
        return 200, [{
            "tag_name": "v0.9", "name": "Old Y",
            "html_url": "https://github.com/octo/old-y"
                        "/releases/tag/v0.9",
            "published_at": REL_OLD, "draft": False,
            "body": "old notes"}], ""
    if "/readme" in url:
        return 200, None, "# readme body"
    return 404, None, ""


mod._http_json = github_http
cands, extracts, gate = mod._github_releases_material(
    ["llm model release"], "20990101", 0)
check("R6 releases road keeps only the in-window release",
      len(cands) == 1
      and cands[0]["url"] == "https://github.com/octo/model-x"
                              "/releases/tag/v2.0"
      and cands[0]["publishedAt"] == REL_NEW[:10]
      and "model-x" in extracts.get(cands[0]["url"], {})
      .get("content", ""),
      f"{cands}")
cands2, _, _ = mod._github_material(
    ["github trending"], "20990101", 0)
check("R6 repo road still serves project directions",
      len(cands2) == 2
      and all(c["url"].startswith("https://github.com/octo/")
              for c in cands2),
      f"{cands2}")

# ---------- R7: B3 avoid list -----------------------------
now = NOW
with mod._lock:
    mod._db["feedPosts"] = [
        {"kind": "research", "title": "研究帖甲",
         "createdAt": now - DAY,
         "links": [{"url": "https://example.com/r1"}],
         "sourceCard": None},
        {"kind": "event", "title": "今日动态 · 3 件",
         "createdAt": now - DAY,
         "links": [{"url": "https://example.com/e1"}],
         "sourceCard": {"url": "https://example.com/e2"}},
        {"kind": "digest", "title": "今日小结 · 6 件",
         "createdAt": now - DAY,
         "links": [{"url": "https://example.com/d1"}],
         "sourceCard": None},
        {"kind": "research", "title": "研究帖旧",
         "createdAt": now - 31 * DAY,
         "links": [{"url": "https://example.com/r-old"}],
         "sourceCard": None}]
    titles, urls = mod._feed_avoid_locked()
check("R7 avoid list carries research posts only",
      titles == ["研究帖甲"]
      and urls == {"https://example.com/r1"},
      f"{titles} {urls}")

# ---------- R8: B1 angle window + versions ----------------
with mod._lock:
    mod._db["feedPosts"] = [
        {"kind": "research", "title": "六天前帖",
         "direction": "副业", "angle": "角度·六天前",
         "createdAt": now - 6 * DAY, "links": []},
        {"kind": "research", "title": "月前帖",
         "direction": "副业", "angle": "角度·月前",
         "createdAt": now - 31 * DAY, "links": []}]
    lines30 = mod._recent_angle_lines_locked()
    lines3 = mod._recent_angle_lines_locked(days=3)
check("R8 used-angle window is 30d by default, 3d on ask",
      any("角度·六天前" in ln for ln in lines30)
      and not any("角度·月前" in ln for ln in lines30)
      and not any("角度·六天前" in ln for ln in lines3),
      f"{lines30} {lines3}")
check("R8 prompt versions bumped, editor seat untouched",
      mod.FEED_PROMPT_VERSIONS["assignment"]
      == "feed_seat_assignment_v2"
      and mod.FEED_PROMPT_VERSIONS["reconcile"]
      == "feed_reconcile_v2"
      and mod.FEED_PROMPT_VERSIONS["material"]
      == "feed_material_v2"
      and mod.FEED_PROMPT_VERSIONS["social"]
      == "feed_social_material_v2"
      and mod.FEED_PROMPT_VERSIONS["editor"]
      == "feed_seat_editor_v2"
      and "与近 30 天已发内容的差异点"
      in mod.RESEARCH_PLAN_PROMPT
      and "防反推" in mod.TASTE_ROLLUP_PROMPT,
      f"{mod.FEED_PROMPT_VERSIONS}")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
