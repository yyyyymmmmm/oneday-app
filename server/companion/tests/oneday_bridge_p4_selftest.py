#!/usr/bin/env python3
"""P4 self-test for oneday_bridge.py 0.38.0 feed changes.

Phase A: HTTP contract for the two-layer brief against a
subprocess bridge (temp data, no Hermes key): PUT interest is
accepted and stored, the expansion failure is recorded
honestly (expandError, never a fake prompt), a re-PUT of the
same interest starts nothing, PUT brief sets the execution
layer verbatim, and GET returns the full document shape.
Phase B: in-process units -- the expansion landing path
(changed prompt triggers a research round; a stale interest
never lands), _norm_url canonicalisation, the 30-day avoid
set, the GitHub card fetcher (stubbed HTTP), the research
plan parser caps, and the feed view/generation shapes.
"""
import importlib.util
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
KEY = "p4-selftest-key"
PORT = 18748
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok  {name}")
    else:
        failed += 1
        print(f"FAIL  {name}  {extra}")


def call(method, path, body=None, key=KEY):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data,
                                 method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read() or b"{}"
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {}


def phase_a():
    tmp = tempfile.mkdtemp(prefix="p4a-")
    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(tmp, "data.json"),
               ONEDAY_PORT=str(PORT))
    env.pop("HERMES_API_KEY", None)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                s, _ = call("GET", "/health", key=None)
                if s == 200:
                    break
            except Exception:
                pass
            time.sleep(0.2)
        s, doc = call("GET", "/meta/brief")
        check("A brief doc shape",
              s == 200 and doc.get("brief") == ""
              and doc.get("interest") == ""
              and doc.get("expanding") is False
              and "expandError" in doc, f"{s} {doc}")
        s, doc = call("PUT", "/meta/brief",
                      {"interest": "我想看开源项目和 AI 进展"})
        check("A PUT interest accepted",
              s == 200 and doc.get("interest")
              == "我想看开源项目和 AI 进展"
              and doc.get("interestUpdatedAt") is not None,
              f"{s} {doc}")
        check("A expansion attempted", doc.get("expandStarted")
              is True, f"{doc}")
        settled = None
        for _ in range(30):
            s, doc = call("GET", "/meta/brief")
            if doc.get("expanding") is False \
                    and doc.get("expandError"):
                settled = doc
                break
            time.sleep(0.5)
        check("A expansion failure recorded honestly",
              settled is not None
              and "HERMES_API_KEY" in settled["expandError"]
              and settled["brief"] == "", f"{settled}")
        s, doc = call("PUT", "/meta/brief",
                      {"interest": "我想看开源项目和 AI 进展"})
        check("A same interest starts nothing",
              s == 200 and doc.get("expandStarted") is False,
              f"{s} {doc}")
        s, doc = call("PUT", "/meta/brief",
                      {"brief": "执行层：只写开源项目。"})
        check("A PUT brief sets execution layer",
              s == 200 and doc.get("brief") == "执行层：只写开源项目。"
              and doc.get("briefUpdatedAt") is not None,
              f"{s} {doc}")
        s, _ = call("PUT", "/meta/brief", {"other": 1})
        check("A PUT without known fields rejected", s == 400,
              f"{s}")
        s, _ = call("PUT", "/meta/brief",
                    {"interest": "x" * 2001})
        check("A overlong interest rejected", s == 400, f"{s}")
        s, gen = call("GET", "/feed/generation")
        check("A generation view carries research key only",
              s == 200 and "research" in gen
              and "morning" not in gen, f"{s} {gen}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


def load_mod(name):
    spec = importlib.util.spec_from_file_location(name, BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    return mod


def phase_b():
    tmp = tempfile.mkdtemp(prefix="p4b-")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    os.environ["HERMES_API_KEY"] = "fake-key"
    mod = load_mod("ob_p4")
    triggered = []
    mod._start_research = lambda trigger: triggered.append(
        trigger) or True
    mod._hermes_submit_run = lambda prompt, idem: ("run_x", None)
    mod._hermes_poll_run = lambda run_id: (
        "方向一：开源项目。\n方向二：AI 进展。", None)
    with mod._lock:
        mod._db["meta"]["briefInterest"] = "看开源和 AI"
        mod._save_locked()
    mod._run_brief_expand("看开源和 AI")
    with mod._lock:
        landed = str(mod._db["meta"].get("brief", "") or "")
    check("B expansion lands execution prompt",
          landed.startswith("方向一：开源项目。"), landed)
    check("B landed change triggers research round",
          triggered == ["brief"], f"{triggered}")
    with mod._lock:
        mod._db["meta"]["briefInterest"] = "改主意了"
        mod._save_locked()
    mod._run_brief_expand("看开源和 AI")
    with mod._lock:
        after = str(mod._db["meta"].get("brief", "") or "")
    check("B stale interest never lands",
          after == landed and triggered == ["brief"], after)

    check("B norm url strips tracking and fragment",
          mod._norm_url("HTTPS://Example.com/a/?utm_source=x"
                        "&b=1#frag")
          == "https://example.com/a?b=1",
          mod._norm_url("HTTPS://Example.com/a/?utm_source=x"
                        "&b=1#frag"))

    with mod._lock:
        mod._db["feedPosts"].append({
            "id": "p_old", "kind": "research", "title": "旧帖甲",
            "body": "", "refs": [], "links": [
                {"title": "t", "url": "https://example.com/a"}],
            "why": None, "createdAt": mod._now(),
            "expiresAt": mod._now() + 1000, "readAt": None})
        mod._save_locked()
        titles, urls = mod._feed_avoid_locked()
    check("B avoid set covers recent titles and links",
          "旧帖甲" in titles
          and "https://example.com/a" in urls, f"{titles} {urls}")

    def fake_http_json(url, *, method="GET", body=None,
                       headers=None, timeout=20):
        if url.endswith("/repos/octo/hello"):
            return 200, {
                "full_name": "octo/hello",
                "description": "打招呼仓库",
                "html_url": "https://github.com/octo/hello",
                "stargazers_count": 12345, "forks_count": 67,
                "language": "Python",
                "owner": {"avatar_url":
                          "https://avatars.example/o.png"}}, ""
        return 404, {}, ""

    mod._http_json = fake_http_json
    card = mod._github_card("https://github.com/octo/hello")
    check("B github card built from real fields",
          card is not None and card["name"] == "octo/hello"
          and card["facts"][0] == {"label": "星标",
                                   "value": "12.3k"}
          and card["imageUrl"]
          == "https://avatars.example/o.png", f"{card}")
    check("B github reserved path yields no card",
          mod._github_card("https://github.com/explore") is None)
    check("B non-github url yields no card",
          mod._github_card("https://example.com/octo/hello")
          is None)

    plan, _perr = mod._parse_research_plan(json.dumps(
        {"directions": [
        {"name": "d1", "queries": ["a", "b", "c"]},
        {"name": "d2", "queries": ["q"]},
        {"name": "d3", "queries": ["q"]},
        {"name": "d4", "queries": ["q"]},
        {"name": "d5", "queries": ["q"]}]}))
    check("B plan parser caps directions and queries",
          len(plan) == 5 and len(plan[0]["queries"]) == 2
          and plan[0]["name"] == "d1", f"{plan}")
    # spec §127: the parser also settles angle/diff and the
    # single-dual-direction cap (a second dual is demoted)
    plan2, err2 = mod._parse_research_plan(json.dumps(
        {"directions": [
            {"name": "甲", "angle": "角度甲", "diff": "不同点",
             "dual": True, "angle2": "角度甲二",
             "queries": ["q"]},
            {"name": "乙", "angle": "角度乙",
             "dual": True, "angle2": "角度乙二",
             "queries": ["q"]}]}, ensure_ascii=False))
    check("B plan parser settles angle/diff/dual cap (§127)",
          err2 is None and plan2[0]["angle"] == "角度甲"
          and plan2[0]["diff"] == "不同点"
          and plan2[0]["dual"] is True
          and plan2[0]["angle2"] == "角度甲二"
          and plan2[1]["dual"] is False
          and plan2[1]["angle2"] == "", f"{plan2} {err2}")

    with mod._lock:
        mod._db["feedPosts"].append({
            "id": "p_card", "kind": "research", "title": "带卡帖",
            "body": "b", "refs": [], "links": [], "why": "w",
            "images": [{"url": "https://img.example/x.png",
                        "sourceUrl": "https://example.com/a"}],
            "sourceCard": card, "direction": "开源",
            "createdAt": mod._now(),
            "expiresAt": mod._now() + 1000, "readAt": None})
        mod._save_locked()
        view = mod._feed_view(
            mod._db["feedPosts"][-1])
    check("B feed view carries images and source card",
          view["images"][0]["url"]
          == "https://img.example/x.png"
          and view["sourceCard"]["name"] == "octo/hello"
          and view["direction"] == "开源", f"{view}")


def main():
    print("phase A: two-layer brief HTTP")
    phase_a()
    print("phase B: expansion and pipeline units")
    phase_b()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
