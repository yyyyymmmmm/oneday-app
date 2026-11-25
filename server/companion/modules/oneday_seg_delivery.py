# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_delivery.py -- part of modules/oneday_bridge.py,
# split out by the C-8 single-file split (2026-11-14).
#
# This file is NOT a standalone module and must never be imported:
# oneday_bridge.py exec-loads it in its OWN namespace at this
# segment's original position (see _load_segment there), so every
# name defined here lives in oneday_bridge's globals, in the
# original definition order, sharing the same _db, locks and
# monkeypatch seams the selftests use. Do not add imports of
# oneday_bridge here (that would build a second module instance);
# names from the core head and earlier segments are simply in
# scope, exactly as when this code lived in the single file.
# ---------------------------------------------------------------------




# ------------------------------------------------------------------
# Delivery registry (delivery-registry-spec-20261111.md): the one
# sanctioned way for the agent to hand a file to the user. The
# agent registers a file it has really written; this bridge reads
# the file back, fingerprints it, derives metadata + covers,
# appends an immutable line to the delivery ledger and returns a
# high-entropy id + marker. The App renders ONLY from registry
# records -- paths in body text are never upgraded (the section
# 129/136 existence-check rendering stays as a legacy fallback
# for old messages). Registration inherits the bridge-wide
# degraded-mode write stop in _dispatch.
# ------------------------------------------------------------------

DELIVERY_ROOT = Path(os.environ.get("DELIVERY_ROOT", "/opt/data"))
DELIVERY_LEDGER_PATH = Path(os.environ.get(
    "DELIVERY_LEDGER_PATH", str(DATA_PATH.parent / "deliveries.jsonl")))
DELIVERY_ASSET_DIR = Path(os.environ.get(
    "DELIVERY_ASSET_DIR", str(DATA_PATH.parent / "deliveries")))
_DELIVERY_FONT_PATH = Path(os.environ.get(
    "DELIVERY_FONT",
    str(Path(__file__).with_name("assets") / "NotoSansSC-subset.ttf")))
_DELIVERY_LOCK = threading.Lock()
_DELIVERY_COVER_LIMIT = 64 * 1024 * 1024  # covers skipped above this
_DELIVERY_PIXEL_LIMIT = 100_000_000
_DELIVERY_ID_RE = re.compile(r"^dlv_[0-9a-f]{20}$")

_DELIVERY_IMAGE_EXTS = {"png", "jpg", "jpeg", "gif", "webp", "heic",
                        "heif", "bmp", "tif", "tiff", "svg", "ico"}
_DELIVERY_VIDEO_EXTS = {"mp4", "mov", "m4v", "webm", "mkv", "avi"}
_DELIVERY_AUDIO_EXTS = {"mp3", "m4a", "wav", "flac", "ogg", "aac"}
_DELIVERY_SHEET_EXTS = {"xlsx", "xls", "ods", "csv", "tsv"}
_DELIVERY_SLIDES_EXTS = {"pptx", "ppt", "odp", "key"}
_DELIVERY_WORD_EXTS = {"docx", "doc", "odt", "rtf"}
_DELIVERY_ARCHIVE_EXTS = {"zip", "rar", "7z", "tar", "gz", "bz2", "xz"}
_DELIVERY_APP_EXTS = {"ipa", "apk", "dmg", "pkg", "exe", "msi", "app"}
_DELIVERY_CODE_EXTS = {"py", "swift", "js", "ts", "jsx", "tsx", "java",
                       "kt", "c", "h", "cpp", "hpp", "cs", "go", "rs",
                       "rb", "php", "sh", "sql", "json", "yaml", "yml",
                       "toml", "xml", "html", "htm", "css"}
_DELIVERY_TEXT_EXTS = {"md", "markdown", "txt", "log", "csv", "tsv"}
_DELIVERY_MIMES = {
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
    "heif": "image/heif", "bmp": "image/bmp", "tif": "image/tiff",
    "tiff": "image/tiff", "svg": "image/svg+xml", "ico": "image/x-icon",
    "mp4": "video/mp4", "mov": "video/quicktime", "m4v": "video/x-m4v",
    "webm": "video/webm", "mkv": "video/x-matroska",
    "avi": "video/x-msvideo", "mp3": "audio/mpeg", "m4a": "audio/mp4",
    "wav": "audio/wav", "flac": "audio/flac", "ogg": "audio/ogg",
    "aac": "audio/aac", "pdf": "application/pdf",
    "md": "text/markdown", "markdown": "text/markdown",
    "txt": "text/plain", "log": "text/plain", "csv": "text/csv",
    "tsv": "text/tab-separated-values",
    "xlsx": "application/vnd.openxmlformats-officedocument."
            "spreadsheetml.sheet",
    "docx": "application/vnd.openxmlformats-officedocument."
            "wordprocessingml.document",
    "pptx": "application/vnd.openxmlformats-officedocument."
            "presentationml.slideshow",
    "zip": "application/zip", "json": "application/json",
    "html": "text/html", "htm": "text/html",
}


def _delivery_kind(ext: str) -> str:
    if ext in _DELIVERY_IMAGE_EXTS:
        return "image"
    if ext in _DELIVERY_VIDEO_EXTS:
        return "video"
    if ext in _DELIVERY_AUDIO_EXTS:
        return "audio"
    if ext == "pdf":
        return "pdf"
    if ext in _DELIVERY_SHEET_EXTS:
        return "sheet"
    if ext in _DELIVERY_SLIDES_EXTS:
        return "slides"
    if ext in _DELIVERY_WORD_EXTS or ext in (
            "md", "markdown", "txt", "log", "epub"):
        return "document"
    if ext in _DELIVERY_CODE_EXTS:
        return "code"
    if ext in _DELIVERY_ARCHIVE_EXTS:
        return "archive"
    if ext in _DELIVERY_APP_EXTS:
        return "app"
    return "other"


# ------------------------------------------------------------
# Sensitive-name policy (mirror of the App's SensitiveFilePolicy).
# Moved here 2026-11-14 (API-direct package B): this segment
# is the policy's only remaining consumer in the oneday
# bridge; the spreadsheet/rendition copy lives in
# fileproc_bridge.py, which owns those endpoints now.
# ------------------------------------------------------------

_SENSITIVE_NAMES = {
    "config.yaml", ".env", "auth.json", "soul.md", "agents.md",
    "user.md", "memory.md", "identity.md",
}
_SENSITIVE_EXTS = {"pem", "key", "p12", "keystore"}
_SENSITIVE_TOKENS = {
    "credential", "credentials", "secret", "secrets", "token",
    "tokens", "key", "keys", "password", "passwd",
}
_SENSITIVE_SUBSTRINGS = ("credential", "secret", "token")


def _is_sensitive_name(name: str) -> bool:
    """Mirror of the App's SensitiveFilePolicy.isSensitive."""
    low = name.lower()
    if low in _SENSITIVE_NAMES:
        return True
    if low == ".env" or low.startswith(".env."):
        return True
    ext = low.rsplit(".", 1)[-1] if "." in low else ""
    if ext in _SENSITIVE_EXTS:
        return True
    if any(s in low for s in _SENSITIVE_SUBSTRINGS):
        return True
    tokens = [t for t in re.split(r"[^a-z0-9]+", low) if t]
    return any(t in _SENSITIVE_TOKENS for t in tokens)


def _delivery_resolve(raw) -> Path:
    """Mirror of _resolve_spreadsheet_path, root = DELIVERY_ROOT."""
    if not isinstance(raw, str) or not raw.strip():
        raise _Err(400, "缺少 path")
    candidate = Path(raw)
    if not candidate.is_absolute():
        raise _Err(400, "路径必须是绝对路径")
    root = DELIVERY_ROOT.resolve()
    resolved = candidate.resolve()
    if resolved != root and root not in resolved.parents:
        raise _Err(400, "路径不在允许范围内")
    if _is_sensitive_name(resolved.name):
        raise _Err(403, "敏感文件不允许登记")
    if not resolved.exists():
        raise _Err(404, "文件不存在")
    if not resolved.is_file():
        raise _Err(400, "路径不是文件")
    return resolved


def _delivery_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _delivery_load() -> list:
    try:
        raw = DELIVERY_LEDGER_PATH.read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if isinstance(rec, dict) and rec.get("id"):
            out.append(rec)
    return out


def _delivery_find(rid: str):
    for rec in _delivery_load():
        if rec.get("id") == rid:
            return rec
    return None


def _delivery_append(rec: dict) -> None:
    DELIVERY_LEDGER_PATH.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(rec, ensure_ascii=False) + "\n"
    fd = os.open(DELIVERY_LEDGER_PATH,
                 os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, line.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)


def _delivery_blank(img) -> bool:
    """Section 32 CoverBlankAudit caliber: >=98% near-white after a
    hard downscale means the render is a white card, not a cover.
    Applied only to server-RENDERED covers (text renders, video
    posters) -- never to real image files, whose content may
    legitimately be mostly white (a document screenshot)."""
    small = img.convert("RGB").resize((16, 16))
    px = list(small.getdata())
    near_white = sum(1 for r, g, b in px
                     if r >= 248 and g >= 248 and b >= 248)
    return near_white / max(len(px), 1) >= 0.98


def _delivery_rendition(img, dest: Path, long_edge: int,
                        guard_blank: bool = False) -> bool:
    from PIL import Image
    im = img.convert("RGB")
    w, h = im.size
    scale = long_edge / max(w, h)
    if scale < 1:
        im = im.resize((max(1, round(w * scale)),
                        max(1, round(h * scale))), Image.LANCZOS)
    if guard_blank and _delivery_blank(im):
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, "JPEG", quality=80)
    return True


def _delivery_probe_image(path: Path):
    """(width, height, PIL image | None): header facts always when
    the file is a readable image; pixels only within the cover
    pixel budget. EXIF orientation is applied to both."""
    try:
        from PIL import Image, ImageOps
        with Image.open(path) as raw:
            w, h = raw.size
            try:
                orient = raw.getexif().get(0x0112)
            except Exception:
                orient = None
            if orient in (5, 6, 7, 8):
                w, h = h, w
            if w * h > _DELIVERY_PIXEL_LIMIT:
                return w, h, None
            img = ImageOps.exif_transpose(raw)
            img.load()
            return w, h, img.copy()
    except Exception:
        return None, None, None


def _delivery_video_poster(path: Path):
    """First usable poster frame as a PIL image, or None."""
    import shutil
    import subprocess
    import tempfile
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        for ss in ("1", "0"):
            try:
                subprocess.run(
                    [ffmpeg, "-y", "-ss", ss, "-i", str(path),
                     "-frames:v", "1", "-f", "image2", tmp],
                    capture_output=True, timeout=25)
            except Exception:
                continue
            if os.path.getsize(tmp) > 0:
                from PIL import Image
                with Image.open(tmp) as im:
                    im.load()
                    return im.copy()
        return None
    except Exception:
        return None
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def _delivery_read_text(path: Path):
    try:
        raw = path.read_bytes()[:65536]
    except OSError:
        return None
    for enc in ("utf-8", "gb18030"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _delivery_text_cover(path: Path, cover_dest: Path,
                         thumb_dest: Path) -> tuple:
    """Section 32 canvas (840x560 paper) first-screen render for
    text-shaped files: title = first heading/line, body = the
    following lines, char-wrapped by pixel width. Returns
    (thumb_ok, cover_ok)."""
    text = _delivery_read_text(path)
    if text is None or not text.strip():
        return False, False
    try:
        from PIL import Image, ImageDraw, ImageFont
        font_title = ImageFont.truetype(str(_DELIVERY_FONT_PATH), 36)
        font_body = ImageFont.truetype(str(_DELIVERY_FONT_PATH), 25)
    except Exception:
        return False, False
    lines = [ln.rstrip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return False, False
    title = re.sub(r"^#+\s*", "", lines[0]).strip() or path.name
    body = [re.sub(r"^#+\s*", "", ln) for ln in lines[1:]]
    img = Image.new("RGB", (840, 560), (250, 248, 243))
    draw = ImageDraw.Draw(img)
    margin = 56
    max_w = 840 - margin * 2

    def wrap(s, font):
        out, cur = [], ""
        for ch in s:
            if draw.textlength(cur + ch, font=font) <= max_w:
                cur += ch
            elif cur:
                out.append(cur)
                cur = ch
            else:
                out.append(ch)
        if cur:
            out.append(cur)
        return out or [""]

    y = margin
    for ln in wrap(title, font_title)[:2]:
        draw.text((margin, y), ln, font=font_title, fill=(28, 28, 30))
        y += 50
    y += 14
    stop = 560 - margin - 34
    for ln in body:
        if y > stop:
            break
        for piece in wrap(ln, font_body):
            if y > stop:
                break
            draw.text((margin, y), piece, font=font_body,
                      fill=(60, 60, 64))
            y += 38
    if _delivery_blank(img):
        return False, False
    cover_dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(cover_dest, "JPEG", quality=82)
    thumb_ok = _delivery_rendition(img, thumb_dest, 360)
    return thumb_ok, True


def _delivery_public(rec: dict, status: str) -> dict:
    return {
        "id": rec["id"], "status": status, "name": rec["name"],
        "path": rec["path"], "size": rec["size"], "mime": rec["mime"],
        "kind": rec["kind"], "width": rec.get("width"),
        "height": rec.get("height"), "sha256": rec["sha256"],
        "registeredAt": rec["registeredAt"],
        "cover": rec.get("cover") or {"thumb": False, "cover": False},
    }


def _delivery_status(rec: dict) -> str:
    try:
        st = os.stat(rec["path"])
    except OSError:
        return "gone"
    if st.st_size != rec["size"] or int(st.st_mtime) != rec["mtime"]:
        return "stale"
    return "ok"


def _delivery_register(body: dict) -> tuple:
    """(status_code, response). The response is the ONLY source of
    a delivery marker: metadata is read back from the real file,
    never taken from the caller's word."""
    path = _delivery_resolve(body.get("path"))
    st = path.stat()
    sha = _delivery_sha256(path)
    for rec in _delivery_load():
        if rec.get("path") == str(path) and rec.get("sha256") == sha \
                and rec.get("size") == st.st_size:
            out = _delivery_public(rec, "ok")
            out["marker"] = f"[[deliver:{rec['id']}]]"
            out["deduped"] = True
            return 200, out
    ext = path.suffix.lower().lstrip(".")
    kind = _delivery_kind(ext)
    rid = "dlv_" + secrets.token_hex(10)
    width = height = None
    thumb_ok = cover_ok = False
    asset_dir = DELIVERY_ASSET_DIR / rid
    if st.st_size <= _DELIVERY_COVER_LIMIT:
        try:
            if kind == "image":
                width, height, img = _delivery_probe_image(path)
                if img is not None:
                    cover_ok = _delivery_rendition(
                        img, asset_dir / "cover.jpg", 1080)
                    thumb_ok = _delivery_rendition(
                        img, asset_dir / "thumb.jpg", 360)
            elif kind == "video":
                poster = _delivery_video_poster(path)
                if poster is not None:
                    width, height = poster.size
                    cover_ok = _delivery_rendition(
                        poster, asset_dir / "cover.jpg", 1080,
                        guard_blank=True)
                    thumb_ok = _delivery_rendition(
                        poster, asset_dir / "thumb.jpg", 360,
                        guard_blank=True)
            elif ext in _DELIVERY_TEXT_EXTS or kind == "code":
                thumb_ok, cover_ok = _delivery_text_cover(
                    path, asset_dir / "cover.jpg",
                    asset_dir / "thumb.jpg")
        except Exception as e:
            # A cover failure never blocks the delivery itself.
            print(f"delivery cover failed for {path}: {e!r}",
                  file=sys.stderr, flush=True)
            thumb_ok = cover_ok = False
    rec = {
        "id": rid, "path": str(path), "name": path.name,
        "size": st.st_size,
        "mime": _DELIVERY_MIMES.get(ext, "application/octet-stream"),
        "kind": kind, "width": width, "height": height,
        "sha256": sha, "mtime": int(st.st_mtime),
        "registeredAt": datetime.now(timezone.utc).isoformat(),
        "cover": {"thumb": thumb_ok, "cover": cover_ok},
    }
    _delivery_append(rec)
    out = _delivery_public(rec, "ok")
    out["marker"] = f"[[deliver:{rid}]]"
    return 201, out


# ------------------------------------------------------------------
# Delivery sentinel (structured-delivery-benchmark-20261111.md,
# plan A): the registry above only fires when the agent remembers
# to call it, and production proved it forgets (2026-11-11 19:22:
# a bare "/opt/data/cloud_pc.jpg" body, never registered). The
# industry fix -- and Hermes' own choice on its messaging gateway
# (Deliverable Mode) -- is host-side scanning: the agent only has
# to MENTION a file's absolute path; the host picks it out and
# attaches it. This sentinel moves that scan to the companion: it
# tails state.db (read-only) for new assistant messages, masks
# out code fences / inline code, extracts MEDIA: targets and bare
# absolute paths, keeps only the deliverable extension whitelist
# (source-code and log extensions deliberately excluded, mirroring
# Deliverable Mode), runs every candidate through the very same
# resolve/exists rules as a manual registration, registers it via
# _delivery_register, and appends a link line to the SAME ledger
# ({"link": true, "kind": "auto", ...}; link lines carry no "id"
# key, so _delivery_load and every existing reader skip them).
# The App asks GET /deliveries/by-message?session_id=&message_id=
# for a message's attachments. Hermes is untouched and message
# rows are never modified; the only writes are registry records
# and link lines in the companion's own ledger. Manual and auto
# registrations share one ledger and one fingerprint dedup: a
# file the agent registered itself is linked, never re-registered.
#
# Message locator (pre-flight verified 2026-11-11 on production
# state.db): messages.id is a global autoincrement primary key,
# immutable once written, so (session_id, id) is a stable locator
# for the index. The watermark (last processed id) persists next
# to the ledger. The initial floor DELIVERY_SENTINEL_START_ID
# marks the first message of the sentinel era -- production 1851,
# so message 1852 (the cloud_pc.jpg one) is the first scanned.
# Older history is NOT backfilled.
# ------------------------------------------------------------------

_SENTINEL_DB_PATH = Path(os.environ.get(
    "DELIVERY_SENTINEL_DB", "/opt/data/state.db"))
_SENTINEL_STATE_PATH = Path(os.environ.get(
    "DELIVERY_SENTINEL_STATE",
    str(DATA_PATH.parent / "delivery-sentinel.json")))
_SENTINEL_INTERVAL = float(os.environ.get(
    "DELIVERY_SENTINEL_INTERVAL", "20"))
_SENTINEL_START_ID = int(os.environ.get(
    "DELIVERY_SENTINEL_START_ID", "1851"))
_SENTINEL_BATCH = 500
_SENTINEL_MIN_AGE = 2.0  # let a fresh row settle before scanning

# Auto-attach whitelist: everything a manual registration accepts
# EXCEPT the code/source set and .log -- Deliverable Mode excludes
# those deliberately so a mentioned source file is never mistaken
# for a deliverable. Manual POST /deliveries is unchanged.
_SENTINEL_EXTS = (
    _DELIVERY_IMAGE_EXTS | _DELIVERY_VIDEO_EXTS
    | _DELIVERY_AUDIO_EXTS | _DELIVERY_SHEET_EXTS
    | _DELIVERY_SLIDES_EXTS | _DELIVERY_WORD_EXTS
    | _DELIVERY_ARCHIVE_EXTS | _DELIVERY_APP_EXTS
    | {"pdf", "md", "markdown", "txt", "epub"})

_SENTINEL_MEDIA_RE = re.compile(r"MEDIA:\s*(\S+)")
_SENTINEL_PATH_RE = re.compile(r"(?:~|)/(?:[^\s\"'<>`\\|\[\]{}()*]+)")
_SENTINEL_TRAIL_CHARS = ".,;:!?…\"'”’)]}>·、。，：；！？"

_sentinel_status = {"lastRunAt": None, "lastMessageId": None,
                    "lastError": None, "autoLinks": 0}


def _sentinel_mask_code(text: str) -> str:
    """Blank out fenced code blocks and inline code spans: paths
    quoted as code are mentions, not deliveries (Deliverable Mode
    rule). Fences first, then single-backtick spans."""
    out = []
    in_fence = False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return re.sub(r"`[^`\n]*`", " ", "\n".join(out))


def _sentinel_extract(content: str) -> list:
    """Ordered, de-duplicated path candidates a message offers as
    deliveries: MEDIA: targets plus bare absolute (or ~/) paths,
    code-masked, extension-whitelisted, trailing prose punctuation
    trimmed. Root/existence/sensitivity are NOT judged here --
    the caller runs every candidate through _delivery_resolve."""
    if not content:
        return []
    text = _sentinel_mask_code(content)
    found = []
    seen = set()

    def offer(raw):
        p = raw.strip()
        while p and p[-1] in _SENTINEL_TRAIL_CHARS:
            p = p[:-1]
        if not p or p in seen or p.startswith("//"):
            return
        tail = p.rsplit("/", 1)[-1]
        ext = tail.rsplit(".", 1)[-1].lower() if "." in tail else ""
        if ext not in _SENTINEL_EXTS:
            return
        seen.add(p)
        found.append(p)

    for m in _SENTINEL_MEDIA_RE.finditer(text):
        offer(m.group(1))
    for m in _SENTINEL_PATH_RE.finditer(text):
        offer(m.group(0))
    return found


def _sentinel_load_watermark() -> int:
    try:
        data = json.loads(
            _SENTINEL_STATE_PATH.read_text(encoding="utf-8"))
        return int(data["lastMessageId"])
    except Exception:
        return _SENTINEL_START_ID


def _sentinel_save_watermark(mid: int) -> None:
    _SENTINEL_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = _SENTINEL_STATE_PATH.with_name(
        _SENTINEL_STATE_PATH.name + ".tmp")
    tmp.write_text(json.dumps({"lastMessageId": mid}),
                   encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(_SENTINEL_STATE_PATH)


def _delivery_links_load() -> list:
    """Link lines of the delivery ledger (manual registration
    records are _delivery_load's business; the two share the file
    and are told apart by shape, see the section header)."""
    try:
        raw = DELIVERY_LEDGER_PATH.read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if isinstance(rec, dict) and rec.get("link") is True \
                and rec.get("deliveryId"):
            out.append(rec)
    return out


def _delivery_index(session_id: str, message_id=None) -> list:
    """[(messageId, [delivery public meta, ...]), ...] ordered by
    message id; the by-message endpoint's single source."""
    by_msg = {}
    for link in _delivery_links_load():
        if link.get("sessionId") != session_id:
            continue
        mid = link.get("messageId")
        if message_id is not None and mid != message_id:
            continue
        rec = _delivery_find(link["deliveryId"])
        if rec is None:
            continue
        slot = by_msg.setdefault(mid, [])
        if any(d["id"] == rec["id"] for d in slot):
            continue
        slot.append(_delivery_public(rec, _delivery_status(rec)))
    return sorted(by_msg.items())


def _sentinel_pass() -> None:
    """One tail pass: scan every assistant message past the
    watermark, auto-register what it offers, link it, advance."""
    import sqlite3
    if _degraded_reason:
        return
    watermark = _sentinel_load_watermark()
    try:
        from db_schema_guard import verify_state_db_schema
    except ImportError:
        try:
            from modules.db_schema_guard import verify_state_db_schema
        except ImportError:
            verify_state_db_schema = None
    if verify_state_db_schema is not None:
        guard = verify_state_db_schema(_SENTINEL_DB_PATH)
        if not guard.get("ok"):
            _sentinel_status.update(
                lastRunAt=_now(),
                lastError=f"schema_guard:{guard.get('reason')}:{guard.get('missing')}",
            )
            return
    conn = sqlite3.connect(
        f"file:{_SENTINEL_DB_PATH}?mode=ro", uri=True, timeout=2.0)
    try:
        rows = conn.execute(
            "SELECT id, session_id, content FROM messages"
            " WHERE id > ? AND role = 'assistant'"
            " AND COALESCE(active, 1) = 1"
            " AND (timestamp IS NULL OR timestamp <= ?)"
            " ORDER BY id ASC LIMIT ?",
            (watermark, time.time() - _SENTINEL_MIN_AGE,
             _SENTINEL_BATCH)).fetchall()
    finally:
        conn.close()
    if not rows:
        _sentinel_status.update(
            lastRunAt=_now(), lastMessageId=watermark,
            lastError=None)
        return
    new_links = 0
    with _DELIVERY_LOCK:
        linked = {(l.get("sessionId"), l.get("messageId"),
                   l.get("deliveryId"))
                  for l in _delivery_links_load()}
        for mid, sid, content in rows:
            for cand in _sentinel_extract(content or ""):
                raw = cand
                if raw.startswith("~/"):
                    raw = str(DELIVERY_ROOT / raw[2:])
                try:
                    path = _delivery_resolve(raw)
                    _, out = _delivery_register({"path": str(path)})
                except Exception as e:
                    # Missing/vanished/off-limits candidates are
                    # the normal case here, never a pass failure.
                    print(f"sentinel skip {raw!r}: {e!r}",
                          file=sys.stderr, flush=True)
                    continue
                key = (sid, mid, out["id"])
                if key in linked:
                    continue
                _delivery_append({
                    "link": True, "kind": "auto",
                    "deliveryId": out["id"], "sessionId": sid,
                    "messageId": mid, "path": str(path),
                    "linkedAt": datetime.now(
                        timezone.utc).isoformat(),
                })
                linked.add(key)
                new_links += 1
        top = rows[-1][0]
        _sentinel_save_watermark(top)
    _sentinel_status.update(
        lastRunAt=_now(), lastMessageId=top, lastError=None,
        autoLinks=_sentinel_status["autoLinks"] + new_links)


def _sentinel_loop() -> None:
    while True:
        try:
            _sentinel_pass()
        except Exception as e:
            _sentinel_status.update(
                lastRunAt=_now(), lastError=repr(e)[:160])
            print(f"delivery sentinel pass failed: {e!r}",
                  file=sys.stderr, flush=True)
        time.sleep(_SENTINEL_INTERVAL)


def _sentinel_start() -> None:
    threading.Thread(target=_sentinel_loop, daemon=True,
                     name="delivery-sentinel").start()
