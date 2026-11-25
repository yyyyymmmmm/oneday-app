#!/usr/bin/env python3
"""§138 self-test for the fileproc_bridge media rendition endpoint
(GET /media/rendition?path=&w=&kind=): JPEG renditions at three
tiers + ffmpeg video posters, disk-cached by content key.

HTTP contract against a subprocess bridge with RENDITION_ROOT and
RENDITION_CACHE_DIR pointed at scratch dirs:
- auth required (401 without the bridge key)
- path rules mirror the §125 spreadsheet endpoint: missing 404,
  escape 400, sensitive name 403
- bad w / bad kind -> 400; non-image bytes -> 415
- 200 carries image/jpeg, ETag, immutable Cache-Control
- long edge <= w and never upscaled
- second request serves the same cache file (mtime unchanged);
  If-None-Match -> 304
- poster: first frame of a tiny mp4 when ffmpeg is available
"""
# Moved 2026-11-14 with the endpoint: API-direct package B4/B5
# split /files/spreadsheet + /media/rendition out of the oneday
# bridge into the standalone fileproc module; contract unchanged.
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "fileproc_bridge.py")
KEY = "rendition-selftest-key"
PORT = 18752
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


def call_raw(path, key=KEY, headers=None):
    req = urllib.request.Request(BASE + path, method="GET")
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def make_png(path, width, height):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            row += bytes([x % 256, y % 256, (x + y) % 256])
        rows.append(b"\x00" + bytes(row))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(b"".join(rows)))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def jpeg_size(data):
    try:
        from PIL import Image
        import io
        with Image.open(io.BytesIO(data)) as im:
            return im.size
    except Exception:
        return None


def main():
    tmp = tempfile.mkdtemp(prefix="rendition-root-")
    cache = tempfile.mkdtemp(prefix="rendition-cache-")
    data_tmp = tempfile.mkdtemp(prefix="rendition-data-")
    big = os.path.join(tmp, "big.png")
    make_png(big, 120, 80)
    # upscale the fixture dimensions by rewriting IHDR is not
    # possible; generate a genuinely large PNG via PIL if present,
    # else keep 120x80 and only assert the no-upscale rule.
    try:
        from PIL import Image
        Image.new("RGB", (1200, 800), (200, 30, 30)).save(big)
        have_pil = True
    except Exception:
        have_pil = False
    small = os.path.join(tmp, "small.png")
    make_png(small, 100, 50)
    text = os.path.join(tmp, "note.txt")
    with open(text, "w") as f:
        f.write("not an image")
    sensitive = os.path.join(tmp, "config.yaml")
    shutil.copyfile(small, sensitive)
    video = os.path.join(tmp, "clip.mp4")
    have_ffmpeg = shutil.which("ffmpeg") is not None
    if have_ffmpeg:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
             "color=c=blue:s=320x240:d=1.5", "-pix_fmt", "yuv420p",
             "-y", video],
            check=False, capture_output=True, timeout=20)

    env = dict(os.environ, FILEPROC_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(data_tmp, "data.json"),
               FILEPROC_PORT=str(PORT), RENDITION_ROOT=tmp,
               RENDITION_CACHE_DIR=cache)
    env.pop("HERMES_API_KEY", None)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        up = False
        for _ in range(50):
            try:
                s, _, _ = call_raw("/health", key=None)
                if s == 200:
                    up = True
                    break
            except Exception:
                pass
            time.sleep(0.2)
        check("bridge up", up)

        q = urllib.request.quote(big, safe="")
        s, _, _ = call_raw(f"/media/rendition?path={q}", key=None)
        check("no key -> 401", s == 401, f"{s}")

        s, _, body = call_raw(
            f"/media/rendition?path={urllib.request.quote('/etc/passwd', safe='')}")
        check("escape -> 400", s == 400, f"{s}")

        s, _, _ = call_raw(
            f"/media/rendition?path={urllib.request.quote(tmp + '/nope.png', safe='')}")
        check("missing -> 404", s == 404, f"{s}")

        s, _, _ = call_raw(
            f"/media/rendition?path={urllib.request.quote(sensitive, safe='')}")
        check("sensitive -> 403", s == 403, f"{s}")

        s, _, _ = call_raw(f"/media/rendition?path={q}&w=999")
        check("bad w -> 400", s == 400, f"{s}")

        s, _, _ = call_raw(f"/media/rendition?path={q}&kind=thumb")
        check("bad kind -> 400", s == 400, f"{s}")

        s, _, _ = call_raw(
            f"/media/rendition?path={urllib.request.quote(text, safe='')}")
        check("non-image -> 415", s == 415, f"{s}")

        s, hdrs, body = call_raw(f"/media/rendition?path={q}&w=360")
        check("rendition 200", s == 200, f"{s}")
        check("content-type jpeg",
              "image/jpeg" in hdrs.get("Content-Type", ""),
              hdrs.get("Content-Type", ""))
        check("etag present", bool(hdrs.get("ETag")))
        check("cache-control immutable",
              "immutable" in hdrs.get("Cache-Control", ""))
        check("jpeg magic", body[:2] == b"\xff\xd8")
        size = jpeg_size(body)
        if have_pil and size:
            check("long edge <= 360",
                  max(size) <= 360, f"{size}")
        files1 = sorted(os.listdir(cache))
        check("one cache file", len(files1) == 1, f"{files1}")
        mtime1 = os.path.getmtime(os.path.join(cache, files1[0]))

        time.sleep(0.05)
        s, hdrs2, body2 = call_raw(f"/media/rendition?path={q}&w=360")
        check("second 200 same bytes", s == 200 and body2 == body)
        mtime2 = os.path.getmtime(os.path.join(cache, files1[0]))
        check("cache not regenerated", mtime1 == mtime2)

        etag = hdrs.get("ETag", "")
        s, _, body3 = call_raw(
            f"/media/rendition?path={q}&w=360",
            headers={"If-None-Match": etag})
        check("if-none-match -> 304", s == 304 and body3 == b"",
              f"{s}")

        qs = urllib.request.quote(small, safe="")
        s, _, bodys = call_raw(f"/media/rendition?path={qs}&w=360")
        sizes = jpeg_size(bodys) if s == 200 else None
        check("small 200", s == 200, f"{s}")
        if sizes:
            check("never upscaled", max(sizes) == 100, f"{sizes}")

        if have_ffmpeg and os.path.exists(video):
            qv = urllib.request.quote(video, safe="")
            s, _, bodyp = call_raw(
                f"/media/rendition?path={qv}&w=360&kind=poster")
            check("poster 200 jpeg",
                  s == 200 and bodyp[:2] == b"\xff\xd8", f"{s}")
            s, _, _ = call_raw(f"/media/rendition?path={qv}&w=360")
            check("video as image -> 415", s == 415, f"{s}")
        else:
            print("SKIP poster checks (no ffmpeg)")

        print(f"RENDITION SELFTEST: {passed} passed, {failed} failed")
        return 1 if failed else 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
