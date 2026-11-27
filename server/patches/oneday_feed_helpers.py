"""Pure helper functions extracted from oneday_seg_feed.py (#44).

Kept dependency-free (stdlib only) so both ``oneday_seg_feed.py`` (exec-loaded
into ``oneday_gateway``) and standalone tests can import these helpers cleanly.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from urllib.parse import parse_qsl, urlencode, urlparse

FEED_BODY_MAX_CHARS = 260
FEED_TITLE_MAX_CHARS = 30

_TRACKING_PARAMS = ("fbclid", "gclid", "mc_cid", "mc_eid")

_JPEG_SOF_MARKERS = {
    0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
    0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
}

_FEED_SENTENCE_ENDS = ("。", "！", "？", "；")
_FEED_TITLE_SEPS = (" ", "，", "、", "：", "；", "·", "—", "|", "/")


def _feed_category_for(direction) -> str | None:
    """A post's category (§459): the brief direction it was written under."""
    d = str(direction or "").strip()
    return d[:60] if d else None


def _feed_usefulness(p: dict, now: float) -> float:
    """One post's usefulness score — pure function of recorded engagement."""
    score = 0.0
    if p.get("likedAt"):
        score += 50.0
    score += 15.0 * min(int(p.get("discussCount") or 0), 3)
    if p.get("readAt"):
        score += 10.0
    age_days = max(0.0, (now - float(p.get("createdAt") or now)) / 86400.0)
    score += max(0.0, 20.0 - 5.0 * age_days)
    return round(score, 1)


def _norm_url(url) -> str:
    """Canonical form for dedupe/avoid comparisons."""
    try:
        p = urlparse(str(url or "").strip())
    except Exception:
        return ""
    if p.scheme not in ("http", "https") or not p.netloc:
        return ""
    path = p.path or "/"
    if len(path) > 1:
        path = path.rstrip("/")
    pairs = [
        (k, v)
        for k, v in parse_qsl(p.query, keep_blank_values=True)
        if not k.startswith("utm_") and k not in _TRACKING_PARAMS
    ]
    query = urlencode(pairs)
    return f"{p.scheme}://{p.netloc.lower()}{path}" + (f"?{query}" if query else "")


def _extract_json_object(output: str):
    """Strict-fold a model run's output into one JSON object (fence-tolerant)."""
    text = (output or "").strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        item = json.loads(text[start:end + 1])
    except Exception:
        return None
    return item if isinstance(item, dict) else None


def _parse_image_dimensions(data: bytes):
    """(width, height) from PNG, JPEG, GIF, WebP, or BMP headers; None if unknown."""
    if not data:
        return None
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24 and data[12:16] == b"IHDR":
        return (
            int.from_bytes(data[16:20], "big"),
            int.from_bytes(data[20:24], "big"),
        )
    if data[:6] in (b"GIF87a", b"GIF89a") and len(data) >= 10:
        return (
            int.from_bytes(data[6:8], "little"),
            int.from_bytes(data[8:10], "little"),
        )
    if data[:2] == b"BM" and len(data) >= 26:
        return (
            abs(int.from_bytes(data[18:22], "little", signed=True)),
            abs(int.from_bytes(data[22:26], "little", signed=True)),
        )
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP" and len(data) >= 30:
        kind = data[12:16]
        if kind == b"VP8X":
            return (
                int.from_bytes(data[24:27], "little") + 1,
                int.from_bytes(data[27:30], "little") + 1,
            )
        if kind == b"VP8L" and len(data) >= 25 and data[20] == 0x2F:
            v = int.from_bytes(data[21:25], "little")
            return ((v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1)
        if kind == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
            return (
                int.from_bytes(data[26:28], "little") & 0x3FFF,
                int.from_bytes(data[28:30], "little") & 0x3FFF,
            )
        return None
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in _JPEG_SOF_MARKERS:
                return (
                    int.from_bytes(data[i + 7:i + 9], "big"),
                    int.from_bytes(data[i + 5:i + 7], "big"),
                )
            if marker in (0xD9, 0xDA):
                break
            if marker == 0x01 or 0xD0 <= marker <= 0xD8:
                i += 2
                continue
            seglen = int.from_bytes(data[i + 2:i + 4], "big")
            if seglen < 2:
                break
            i += 2 + seglen
        return None
    return None


def _clamp_feed_body(body: str) -> str:
    """Body ceiling at landing (1.0.13): cut at last sentence boundary inside limit."""
    body = (body or "").strip()
    if len(body) <= FEED_BODY_MAX_CHARS:
        return body
    window = body[:FEED_BODY_MAX_CHARS]
    cut = max([window.rfind(s) for s in _FEED_SENTENCE_ENDS] + [window.rfind("\n")])
    kept = window[:cut + 1] if cut >= 0 else window
    lb = kept.rfind("[")
    if lb != -1:
        tail = kept[lb:]
        if "]" not in tail or ("](" in tail and ")" not in tail.split("](", 1)[1]):
            kept = kept[:lb].rstrip()
    return kept.strip()


def _clamp_feed_title(title: str) -> str:
    """One-line title ceiling at landing (1.0.13)."""
    title = (title or "").strip()
    if len(title) <= FEED_TITLE_MAX_CHARS:
        return title
    window = title[:FEED_TITLE_MAX_CHARS]
    cut = max(window.rfind(s) for s in _FEED_TITLE_SEPS)
    if cut >= 10:
        kept = window[:cut].rstrip("".join(_FEED_TITLE_SEPS))
        if kept:
            return kept
    return window


def _compact_count(n: int) -> str:
    if n >= 1000:
        return f"{n / 1000:.1f}k".replace(".0k", "k")
    return str(n)


def _query_key(q: str) -> str:
    """Normalized identity of a search query."""
    s = re.sub(r"[^\w\u4e00-\u9fff]+", " ", str(q or "").lower())
    return " ".join(s.split())


def _image_identity(url: str) -> str:
    """Normalized identity of an image: host + path only."""
    try:
        p = urlparse(str(url or ""))
    except Exception:
        return ""
    if not p.netloc:
        return ""
    return (p.netloc.lower() + (p.path or "/")).rstrip("/")


def _parse_stated_date(text):
    """A source page's self-stated ISO date prefix -> date, else None."""
    if not text:
        return None
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", str(text))
    if not m:
        return None
    try:
        return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3))).date()
    except ValueError:
        return None


def _why_names_date(why: str, stated: str) -> bool:
    """True when ``why`` explicitly names ``stated`` in ISO or Chinese date form."""
    d = _parse_stated_date(stated)
    if d is None:
        return False
    why = why or ""
    return (
        f"{d.year:04d}-{d.month:02d}-{d.day:02d}" in why
        or f"{d.year}年{d.month}月{d.day}日" in why
        or f"{d.month}月{d.day}日" in why
    )
