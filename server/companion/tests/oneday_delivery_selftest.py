#!/usr/bin/env python3
"""Self-test for the delivery registry (delivery-registry-spec):
POST /deliveries + GET meta/thumb/cover against a scratch bridge.

Boots the module copy staged next to this file (run via
run_bridge_selftests.sh) or the repo module directly. Asserts:
auth, path rules mirrored from the spreadsheet route, metadata
read back from the real file (size/sha/dimensions), fingerprint
dedup, covers really generated (JPEG bytes, expected geometry,
840x560 text canvas), and the ok -> stale -> gone status flow.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
CANDIDATES = [os.path.join(HERE, "oneday_bridge.py"),
              os.path.join(HERE, "..", "modules", "oneday_bridge.py")]
BRIDGE = next(p for p in CANDIDATES if os.path.exists(p))
KEY = "delivery-selftest-key"
PORT = 18761
BASE = f"http://127.0.0.1:{PORT}"
ID_RE = re.compile(r"^dlv_[0-9a-f]{20}$")

FAILURES = []


def check(name, cond, extra=""):
    if cond:
        print(f"  ok: {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL: {name} {extra}")


def call(method, path, key=KEY, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            payload = r.read()
            return r.status, (payload if raw
                              else json.loads(payload or b"{}"))
    except urllib.error.HTTPError as e:
        payload = e.read()
        if raw:
            return e.code, payload
        try:
            return e.code, json.loads(payload or b"{}")
        except Exception:
            return e.code, {}


def main():
    from PIL import Image, ImageDraw

    root = tempfile.mkdtemp(prefix="delivery-root-")
    data_tmp = tempfile.mkdtemp(prefix="delivery-data-")
    outside = tempfile.mkdtemp(prefix="delivery-outside-")

    photo = os.path.join(root, "photo.png")
    img = Image.new("RGB", (800, 600), (30, 90, 160))
    d = ImageDraw.Draw(img)
    d.rectangle([80, 80, 720, 520], fill=(230, 120, 40))
    d.ellipse([300, 200, 500, 400], fill=(240, 230, 60))
    img.save(photo)

    note = os.path.join(root, "说明.md")
    with open(note, "w", encoding="utf-8") as f:
        f.write("# 通讯录人数口径\n\n"
                "总数按去重后的联系人计算，同一人多号合并。\n"
                "第二行正文，用来验证封面渲染不是空白。\n"
                "第三行：数据来源为手机同步副本。\n")

    code = os.path.join(root, "tool.py")
    with open(code, "w", encoding="utf-8") as f:
        f.write("def main():\n    print('hello delivery registry')\n")

    arch = os.path.join(root, "pack.zip")
    with zipfile.ZipFile(arch, "w") as z:
        z.writestr("a.txt", "inside")

    blank = os.path.join(root, "blank.md")
    with open(blank, "w", encoding="utf-8") as f:
        f.write("   \n\n")

    sensitive = os.path.join(root, "api_token.txt")
    with open(sensitive, "w", encoding="utf-8") as f:
        f.write("not a real secret")

    alien = os.path.join(outside, "alien.png")
    img.save(alien)

    ledger = os.path.join(data_tmp, "deliveries.jsonl")

    env = dict(os.environ, ONEDAY_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(data_tmp, "data.json"),
               ONEDAY_PORT=str(PORT), DELIVERY_ROOT=root)
    env.pop("HERMES_API_KEY", None)
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

        s, _ = call("POST", "/deliveries", key=None,
                    body={"path": photo})
        check("no key -> 401", s == 401, f"{s}")
        s, _ = call("POST", "/deliveries", key="wrong-key",
                    body={"path": photo})
        check("wrong key -> 401", s == 401, f"{s}")

        s, body = call("POST", "/deliveries", body={"path": photo})
        check("register photo 201", s == 201, f"{s} {body}")
        rid = body.get("id", "")
        check("id shape", bool(ID_RE.match(rid)), rid)
        check("marker shape",
              body.get("marker") == f"[[deliver:{rid}]]",
              body.get("marker", ""))
        check("meta name", body.get("name") == "photo.png")
        check("meta size from real file",
              body.get("size") == os.path.getsize(photo),
              f"{body.get('size')} vs {os.path.getsize(photo)}")
        with open(photo, "rb") as f:
            want_sha = hashlib.sha256(f.read()).hexdigest()
        check("meta sha256 from real file",
              body.get("sha256") == want_sha)
        check("meta dims", (body.get("width"), body.get("height"))
              == (800, 600), f"{body.get('width')}x{body.get('height')}")
        check("meta kind/mime", body.get("kind") == "image"
              and body.get("mime") == "image/png")
        check("covers promised",
              body.get("cover") == {"thumb": True, "cover": True},
              str(body.get("cover")))
        check("status ok", body.get("status") == "ok")

        # Optional locator binds at registration time.
        bound_path = os.path.join(root, "bound.txt")
        with open(bound_path, "w", encoding="utf-8") as f:
            f.write("bound attachment")
        s, bound = call("POST", "/deliveries", body={
            "path": bound_path, "session_id": "bound-session",
            "message_id": 71})
        s2, indexed = call(
            "GET", "/deliveries/by-message?session_id=bound-session&message_id=71")
        check("registration anchor is immediately indexed",
              s in (200, 201) and s2 == 200
              and [x.get("id") for x in indexed.get("deliveries", [])]
              == [bound.get("id")], f"{s} {s2} {indexed}")
        expected_meta_fields = {"id", "name", "size", "mime", "kind", "cover"}
        check("bound attachment metadata contract",
              len(indexed.get("deliveries", [])) == 1
              and expected_meta_fields.issubset(indexed["deliveries"][0])
              and set(indexed["deliveries"][0]["cover"]) >= {"thumb", "cover"},
              str(indexed))
        bound_meta = indexed["deliveries"][0]
        check("attachment contract fields match GET meta",
              all(bound_meta.get(k) == call("GET", f"/deliveries/{bound['id']}")[1].get(k)
                  for k in ("id", "name", "size", "mime", "kind", "cover"))
              and all(k in bound_meta["cover"] for k in ("thumb", "cover")),
              str(bound_meta))
        with open(ledger, encoding="utf-8") as f:
            before_invalid_anchor = sum(1 for line in f if line.strip())
        s, _ = call("POST", "/deliveries", body={
            "path": photo, "session_id": "bound-session", "message_id": "bad"})
        with open(ledger, encoding="utf-8") as f:
            after_invalid_anchor = sum(1 for line in f if line.strip())
        check("invalid anchor rejected before registration",
              s == 400 and after_invalid_anchor == before_invalid_anchor,
              f"status={s} ledger={before_invalid_anchor}->{after_invalid_anchor}")

        s, meta = call("GET", f"/deliveries/{rid}")
        check("get meta 200 + same id",
              s == 200 and meta.get("id") == rid, f"{s}")

        s, raw = call("GET", f"/deliveries/{rid}/thumb", raw=True)
        check("thumb 200 jpeg", s == 200 and raw[:2] == b"\xff\xd8",
              f"{s} {raw[:4]!r}")
        import io
        timg = Image.open(io.BytesIO(raw))
        check("thumb long edge 360", max(timg.size) == 360,
              str(timg.size))
        s, raw = call("GET", f"/deliveries/{rid}/cover", raw=True)
        cimg = Image.open(io.BytesIO(raw))
        check("cover is source size (only shrinks)",
              s == 200 and cimg.size == (800, 600),
              f"{s} {cimg.size}")

        with open(ledger, encoding="utf-8") as f:
            lines_before = sum(1 for _ in f)
        s, body2 = call("POST", "/deliveries", body={"path": photo})
        check("re-register deduped 200",
              s == 200 and body2.get("deduped") is True
              and body2.get("id") == rid, f"{s} {body2}")
        with open(ledger, encoding="utf-8") as f:
            lines_after = sum(1 for _ in f)
        check("dedup appends nothing", lines_before == lines_after,
              f"{lines_before} -> {lines_after}")

        s, nbody = call("POST", "/deliveries", body={"path": note})
        check("register note 201", s == 201, f"{s} {nbody}")
        nid = nbody.get("id", "")
        check("note kind/mime", nbody.get("kind") == "document"
              and nbody.get("mime") == "text/markdown",
              str(nbody.get("kind")))
        check("note has no dims", nbody.get("width") is None)
        check("note cover shape",
              nbody.get("cover") == {"thumb": True, "cover": True}
              or nbody.get("cover") == {"thumb": False, "cover": False},
              str(nbody.get("cover")))
        s, raw = call("GET", f"/deliveries/{nid}/cover", raw=True)
        if s == 200:
            nimg = Image.open(io.BytesIO(raw))
            check("note cover canvas 840x560",
                  nimg.size == (840, 560), str(nimg.size))
        else:
            check("unavailable note cover reports 404", s == 404, str(s))

        s, cbody = call("POST", "/deliveries", body={"path": code})
        check("code kind + optional cover shape", s == 201
              and cbody.get("kind") == "code"
              and cbody.get("cover") in (
                  {"thumb": True, "cover": True},
                  {"thumb": False, "cover": False}),
              f"{s} {cbody}")

        s, abody = call("POST", "/deliveries", body={"path": arch})
        check("archive kind, no cover", s == 201
              and abody.get("kind") == "archive"
              and abody.get("cover") == {"thumb": False,
                                         "cover": False},
              f"{s} {abody}")
        s, _ = call("GET", f"/deliveries/{abody.get('id')}/cover")
        check("archive cover 404", s == 404, f"{s}")

        s, bbody = call("POST", "/deliveries", body={"path": blank})
        check("blank text registers, no cover", s == 201
              and bbody.get("cover") == {"thumb": False,
                                         "cover": False},
              f"{s} {bbody}")

        s, _ = call("POST", "/deliveries", body={"path": "photo.png"})
        check("relative path 400", s == 400, f"{s}")
        s, _ = call("POST", "/deliveries", body={"path": alien})
        check("outside root 400", s == 400, f"{s}")
        s, _ = call("POST", "/deliveries",
                    body={"path": os.path.join(root, "nope.png")})
        check("missing file 404", s == 404, f"{s}")
        s, _ = call("POST", "/deliveries", body={"path": sensitive})
        check("sensitive name 403", s == 403, f"{s}")
        s, _ = call("POST", "/deliveries", body={})
        check("missing path field 400", s == 400, f"{s}")
        s, _ = call("GET", "/deliveries")
        check("GET collection 405", s == 405, f"{s}")
        s, _ = call("GET", "/deliveries/dlv_00000000000000000000")
        check("unknown id 404", s == 404, f"{s}")
        s, _ = call("GET", "/deliveries/garbage")
        check("malformed id 404", s == 404, f"{s}")

        with open(photo, "ab") as f:
            f.write(b"\x00")
        s, meta = call("GET", f"/deliveries/{rid}")
        check("edited file -> stale", s == 200
              and meta.get("status") == "stale", str(meta.get("status")))
        s, raw = call("GET", f"/deliveries/{rid}/thumb", raw=True)
        check("stale still serves snapshot", s == 200, f"{s}")

        os.unlink(note)
        s, meta = call("GET", f"/deliveries/{nid}")
        check("deleted file -> gone", s == 200
              and meta.get("status") == "gone", str(meta.get("status")))
        s, _ = call("GET", f"/deliveries/{nid}/cover")
        check("gone cover 410", s == 410, f"{s}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    print(f"\n{'ALL PASS' if not FAILURES else 'FAILURES: ' + str(FAILURES)}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
