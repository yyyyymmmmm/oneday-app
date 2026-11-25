#!/usr/bin/env python3
"""G-2 self-test: goalEntries title/origin (storage + view whitelist
+ facade-facing REST contract) and the bookkeeping daily cap.
Run from a flat staging copy of modules/ + this file (same
convention as the sibling oneday_bridge_*_selftest.py files)."""
import json, os, subprocess, sys, time, urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
import tempfile
TD = tempfile.mkdtemp(prefix="g2-selftest-")
env = dict(os.environ, ONEDAY_BRIDGE_KEY="smoke-key", DATA_PATH=os.path.join(TD, "data.json"), ONEDAY_PORT="18799")
p = subprocess.Popen([sys.executable, os.path.join(HERE, "oneday_bridge.py")], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
BASE="http://127.0.0.1:18799"
def req(method, path, body=None, code=None):
    r = urllib.request.Request(BASE+path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization":"Bearer smoke-key","Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(r, timeout=5) as resp: return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")
ok=fail=0
def check(name, cond, extra=""):
    global ok, fail
    if cond: ok+=1; print("PASS", name)
    else: fail+=1; print("FAIL", name, extra)
try:
    for _ in range(50):
        try:
            s,_=req("GET","/goals"); break
        except Exception: time.sleep(0.2)
    s,g = req("POST","/goals",{"title":"冒烟目标","source":"manual"})
    check("create goal", s==201, str((s,g)))
    gid = g["id"]
    s,e1 = req("POST",f"/goals/{gid}/entries",{"body":"第一条进展正文","source":"agent","title":"冒烟标题","origin":"bookkeeping"})
    check("create entry w/ title+origin", s==201 and e1.get("title")=="冒烟标题" and e1.get("origin")=="bookkeeping", str((s,e1)))
    s,e2 = req("POST",f"/goals/{gid}/entries",{"body":"第二条提炼","source":"agent","origin":"bookkeeping"})
    check("bookkeeping daily cap 409", s==409, str((s,e2)))
    s,e3 = req("POST",f"/goals/{gid}/entries",{"body":"普通条目无标题","source":"user"})
    check("plain entry title null", s==201 and e3.get("title") is None and e3.get("origin") is None, str((s,e3)))
    s,lst = req("GET",f"/goals/{gid}/entries")
    items = lst.get("items",[])
    check("list exposes title/origin", s==200 and items and items[0].get("title")=="冒烟标题", str((s,lst))[:200])
    s,gl = req("GET","/goals")
    ge = [x for x in gl.get("items",[]) if x["id"]==gid]
    le = (ge[0].get("latestEntry") or {}) if ge else {}
    check("latestEntry is newest + has title key", le.get("body")=="普通条目无标题" and "title" in le, str(le)[:200])
finally:
    p.terminate()
print(f"RESULT {ok} passed {fail} failed")
sys.exit(1 if fail else 0)
