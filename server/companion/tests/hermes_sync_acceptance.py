#!/usr/bin/env python3
"""Three-question acceptance for the device sync tool surface
(spec device-sync-design-20261110.md section 5.3).

DEPLOYMENT-WINDOW TOOL ONLY. It talks to a live Hermes gateway and
creates one fresh session; never run it against production outside
an approved window. It changes no configuration.

Env: HERMES_BASE (gateway base, e.g. http://127.0.0.1:8642),
     HERMES_API_KEY (the deployment's login key).

The three questions (expected answers are pinned by the spec):
1. "你现在能用哪些设备工具？" -- the model must name the device
   tool group including the copy-query tools.
2. "我通讯录里一共有多少人？数据是什么时候的？" -- must answer
   with a count and a sync time; a "cannot reach any contacts"
   style answer is an automatic failure.
3. "帮我看看我下周有什么安排。" -- must use the calendar copy
   tool and state coverage / sync time.

Keyword checks are heuristics to speed up reading; the printed raw
answers are the evidence and a human makes the final call.
"""
import json
import os
import re
import sys
import urllib.request
import urllib.error

BASE = os.environ.get("HERMES_BASE", "http://127.0.0.1:8642")
KEY = os.environ.get("HERMES_API_KEY", "")

QUESTIONS = [
    ("Q1 工具点名", "你现在能用哪些设备工具？",
     lambda a: all(k in a for k in ("contacts_count", "contacts_stats"))
     or all(k in a for k in ("通讯录", "日历", "提醒"))),
    ("Q2 通讯录计数", "我通讯录里一共有多少人？数据是什么时候的？",
     lambda a: bool(re.search(r"\d+\s*(人|个|条)", a))
     and ("同步" in a)
     and not any(bad in a for bad in
                 ("联系不上", "没有任何通讯录", "无法访问通讯录",
                  "没有可用的通讯录"))),
    ("Q3 下周安排", "帮我看看我下周有什么安排。",
     lambda a: ("覆盖" in a or "同步" in a)
     and not any(bad in a for bad in
                 ("联系不上", "无法访问日历", "没有可用的日历"))),
]


def req(method, path, body=None, headers=None, timeout=120):
    data = json.dumps(body).encode() if body is not None else None
    h = {"Authorization": f"Bearer {KEY}"}
    if data:
        h["Content-Type"] = "application/json"
    if headers:
        h.update(headers)
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers=h)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def main() -> int:
    if not KEY:
        print("HERMES_API_KEY is required", file=sys.stderr)
        return 2
    sid = f"sync-acceptance"
    code, out = req("POST", "/api/sessions",
                    {"id": sid, "title": "同步制三问验收"})
    if code not in (200, 201):
        print(f"session create failed: {code} {out}", file=sys.stderr)
        return 2
    print(f"fresh session: {sid}")
    failed = 0
    for label, question, expect in QUESTIONS:
        code, out = req(
            "POST", "/v1/chat/completions",
            {"model": "hermes-agent",
             "messages": [{"role": "user", "content": question}]},
            headers={"X-Hermes-Session-Id": sid})
        answer = ""
        try:
            answer = out["choices"][0]["message"]["content"] or ""
        except Exception:
            pass
        ok = code == 200 and bool(answer) and expect(answer)
        print(f"\n== {label}: {'PASS' if ok else 'CHECK'} "
              f"(http {code})")
        print(f"问：{question}")
        print(f"答：{answer[:800]}")
        if not ok:
            failed += 1
    print(f"\n{3 - failed}/3 heuristic pass; read the raw answers "
          "above before signing off.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
