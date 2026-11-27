#!/usr/bin/env python3
"""Feed image self-hosting self-test (hermes-deploy 2.6.0).

Covers the 2.6.0 additions to oneday_seg_feed.py by exec'ing
the REAL segment file in a stub namespace (the segment is
not standalone-importable; this mirrors ledgerfix Part B):

 1. a valid wide PNG is hosted: content-hash filename,
    file written under FEED_MEDIA_DIR, entry rewritten
    {url: hosted, sourceUrl: "", originUrl, originImageUrl}
 2. an already-hosted entry passes through unchanged
 3. a failed download drops the image (None)
 4. a tall-screenshot shape (h/w > 1.2) drops
 5. a sub-400px-wide image drops
 6. non-image bytes (no magic, html type) drop
 7. JPEG bytes with a wrong content-type are sniffed to .jpg
 8. _selfhost_post_images keeps only hostable images
 9. fallback search: no TAVILY_API_KEY -> []
10. fallback search: hits are HEAD+shape gated, capped at 2
11. _download_image_bytes against a real local HTTP server
12. landing fallback hosts a searched image (origin = the
    post's first link); no hit / unhostable hit -> the post
    stays imageless

Run: python3 feed_media_selftest.py
"""
import hashlib
import hmac
import io
import json
import os
import re
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from urllib.parse import (parse_qs, parse_qsl, quote, unquote,
                          urlencode, urljoin, urlparse, urlunparse)

HERE = os.path.dirname(os.path.abspath(__file__))
SEG = os.path.join(HERE, "patches", "oneday_seg_feed.py")

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def load_seg():
    src = open(SEG, encoding="utf-8").read()
    ns = {"__name__": "feed_seg_selftest", "os": os, "re": re,
          "json": json, "time": time, "threading": threading,
          "hashlib": hashlib, "hmac": hmac, "io": io,
          "urllib": urllib, "datetime": datetime,
          "timedelta": timedelta, "timezone": timezone,
          "urlparse": urlparse, "parse_qs": parse_qs,
          "parse_qsl": parse_qsl, "quote": quote,
          "unquote": unquote, "urljoin": urljoin,
          "urlunparse": urlunparse,
          "urlencode": urlencode, "print": print,
          "_print": print}
    exec(compile(src, "oneday_seg_feed.py", "exec"), ns)
    return ns


def png_bytes(w, h):
    """Minimal PNG: signature + IHDR with the given dims
    (enough for _parse_image_dimensions)."""
    ihdr = (w.to_bytes(4, "big") + h.to_bytes(4, "big")
            + bytes([8, 2, 0, 0, 0]))
    return (b"\x89PNG\r\n\x1a\n" + len(ihdr).to_bytes(4, "big")
            + b"IHDR" + ihdr + b"\x00\x00\x00\x00")


def main():
    ns = load_seg()
    tmp = tempfile.mkdtemp(prefix="feedmedia-")
    ns["FEED_MEDIA_DIR"] = tmp
    base = ns["FEED_MEDIA_BASE"]
    entry = ns["_selfhost_image_entry"]
    PAGE = "https://example.com/article"
    REMOTE = "https://cdn.example.com/hero.png"

    good_png = png_bytes(1200, 800)
    real_download = ns["_download_image_bytes"]
    # 1. valid wide PNG is hosted + rewritten
    ns["_download_image_bytes"] = lambda url: (good_png, "image/png")
    out = entry({"url": REMOTE, "sourceUrl": PAGE})
    want_name = hashlib.sha256(good_png).hexdigest() + ".png"
    check("host: url rewritten", bool(out) and out["url"] == base + want_name,
          str(out))
    check("host: sourceUrl emptied", bool(out) and out["sourceUrl"] == "")
    check("host: origin kept", bool(out) and out["originUrl"] == PAGE
          and out["originImageUrl"] == REMOTE)
    check("host: file on disk",
          os.path.isfile(os.path.join(tmp, want_name)))
    # 2. already hosted passes through
    again = entry({"url": base + want_name, "sourceUrl": ""})
    check("host: idempotent", again == {"url": base + want_name,
                                        "sourceUrl": ""})
    # 3. failed download drops
    ns["_download_image_bytes"] = lambda url: (None, None)
    check("drop: download failure", entry({"url": REMOTE,
                                           "sourceUrl": PAGE}) is None)
    # 4. tall shape drops
    ns["_download_image_bytes"] = lambda url: (png_bytes(800, 1200),
                                               "image/png")
    check("drop: tall shape", entry({"url": REMOTE,
                                     "sourceUrl": PAGE}) is None)
    # 5. narrow drops
    ns["_download_image_bytes"] = lambda url: (png_bytes(320, 200),
                                               "image/png")
    check("drop: narrow", entry({"url": REMOTE,
                                 "sourceUrl": PAGE}) is None)
    # 6. non-image bytes drop
    ns["_download_image_bytes"] = lambda url: (b"<html>nope</html>",
                                               "text/html")
    check("drop: not an image", entry({"url": REMOTE,
                                       "sourceUrl": PAGE}) is None)
    # 7. JPEG magic sniffed despite wrong content type
    jpg = b"\xff\xd8\xff\xe0" + b"\x00" * 64
    ns["_download_image_bytes"] = lambda url: (jpg, "application/octet-stream")
    out7 = entry({"url": "https://cdn.example.com/x", "sourceUrl": PAGE})
    check("host: jpeg sniffed", bool(out7) and out7["url"].endswith(".jpg"),
          str(out7))
    # 8. post-level transform keeps only hostable images
    ns["_download_image_bytes"] = (
        lambda url: (good_png, "image/png") if url == REMOTE else (None, None))
    post = {"images": [{"url": REMOTE, "sourceUrl": PAGE},
                       {"url": "https://dead.example.com/a.png",
                        "sourceUrl": PAGE}]}
    ns["_selfhost_post_images"](post)
    check("post: only hostable survives",
          len(post["images"]) == 1
          and post["images"][0]["url"].startswith(base), str(post))
    # 9. fallback without a key returns []
    saved_key = ns["TAVILY_API_KEY"]
    ns["TAVILY_API_KEY"] = ""
    check("fallback: no key", ns["_fallback_search_images"]("t", {}) == [])
    ns["TAVILY_API_KEY"] = "selftest-key"
    # 10. fallback gates + caps hits
    def fake_http_json(url, method=None, body=None, headers=None,
                       timeout=None):
        return 200, {"images": [
            {"url": "https://img.example.com/1.png"},
            {"url": "https://img.example.com/2.png"},
            {"url": "https://img.example.com/3.png"}]}, None
    ns["_http_json"] = fake_http_json
    ns["_http_head_ok"] = lambda u: True
    ns["_image_shape_ok"] = lambda u: not u.endswith("2.png")
    counts = {}
    got = ns["_fallback_search_images"]("某标题", counts)
    check("fallback: gated hits",
          got == ["https://img.example.com/1.png",
                  "https://img.example.com/3.png"], str(got))
    check("fallback: counted", counts.get("tavilySearch") == 1)
    # 11. real download via local HTTP server
    from http.server import BaseHTTPRequestHandler, HTTPServer

    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(good_png)))
            self.end_headers()
            self.wfile.write(good_png)

        def log_message(self, *a):
            pass

    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    data, ctype = real_download(
        f"http://127.0.0.1:{srv.server_port}/hero.png")
    srv.shutdown()
    check("download: real bytes", data == good_png and ctype == "image/png")
    # 12. landing fallback hosts a searched image for an
    # imageless post, origin = first link
    ns["_fallback_search_images"] = lambda q, c: [REMOTE]
    ns["_download_image_bytes"] = lambda url: (good_png, "image/png")
    post2 = {"title": "t", "links": [{"url": PAGE}], "images": []}
    ns["_landing_fallback_image"](post2)
    check("landing: fallback hosted",
          len(post2["images"]) == 1
          and post2["images"][0]["url"].startswith(base)
          and post2["images"][0]["sourceUrl"] == ""
          and post2["images"][0]["originUrl"] == PAGE, str(post2))
    # 13. landing fallback with no hits leaves the post imageless
    ns["_fallback_search_images"] = lambda q, c: []
    post3 = {"title": "t", "links": [{"url": PAGE}], "images": []}
    ns["_landing_fallback_image"](post3)
    check("landing: no hit stays imageless", post3["images"] == [])
    # 14. landing fallback whose hit cannot be hosted also
    # leaves the post imageless
    ns["_fallback_search_images"] = (
        lambda q, c: ["https://dead.example.com/a.png"])
    ns["_download_image_bytes"] = lambda url: (None, None)
    post4 = {"title": "t", "links": [{"url": PAGE}], "images": []}
    ns["_landing_fallback_image"](post4)
    check("landing: unhostable stays imageless", post4["images"] == [])

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
