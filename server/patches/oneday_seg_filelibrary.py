# ---------------------------------------------------------------------
# oneday_bridge segment: oneday_seg_filelibrary.py -- part of
# modules/oneday_bridge.py, split out by the C-8 single-file split
# (2026-11-14).
#
# This file is NOT a standalone module and must never be imported:
# oneday_gateway.py exec-loads it in its OWN namespace at this
# segment's original position (see _load_segment there), so every
# name defined here lives in oneday_bridge's globals, in the
# original definition order, sharing the same _db, locks and
# monkeypatch seams the selftests use. Do not add imports of
# oneday_bridge here (that would build a second module instance);
# names from the core head and earlier segments are simply in
# scope, exactly as when this code lived in the single file.
# ---------------------------------------------------------------------

import mimetypes
import stat


# ------------------------------------------------------------------
# File library read surface (Big-Tech Chat-Centric Model):
#
# Single Source of Truth = files actually sent/received in chat or
# explicitly uploaded by the user, verified to exist on disk:
#   1. User-sent / uploaded: `uploads/` ("App 上传") and
#      `attachments/` ("聊天发送") under FILE_LIBRARY_ROOT.
#   2. AI-delivered: records in DELIVERY_LEDGER_PATH (deliveries.jsonl)
#      that are referenced by an active assistant message in state.db
#      (`[[deliver:dlv_...]]` or sentinel link lines) and still exist
#      on disk (`os.stat` regular file).
#
# Internal/scratch/cron directories (cache/documents, cache/images,
# cache/screenshots, cron/output, root loose files) are NEVER scanned,
# so unsent AI scratch files and stale/deleted cache files never
# appear as ghost items in the user's Resource Library.
# ------------------------------------------------------------------

FILE_LIBRARY_ROOT = Path(os.environ.get(
    "FILE_LIBRARY_ROOT",
    os.environ.get("DELIVERY_ROOT", "/opt/data")))

# User-uploaded / chat-sent roots only.
_FILE_LIBRARY_USER_ROOTS = [
    ("uploads", "App 上传"),
    ("attachments", "聊天发送"),
]
_FILE_LIBRARY_AI_LABEL = "智能体发送"
_FILE_LIBRARY_MAX_DEPTH = 3

# Internal suffix shapes (all sources): database bodies and
# companions, cache fingerprints, lock/pid/temp files.
_FL_INTERNAL_SUFFIXES = (
    ".db", ".db-wal", ".db-shm", ".sqlite", ".sqlite3",
    ".etag", ".lock", ".pid", ".tmp",
)

# Internal stems (all sources): Hermes state/gateway/channel/
# model-cache/kanban/session/auth/config bodies and variants.
_FL_INTERNAL_STEMS = {
    "state", "gateway_state", "channel_directory",
    "models_dev_cache", "kanban", "sessions", "auth", "config",
}


def _fl_stem_ext(lower: str):
    """(stem, ext) with NSString deletingPathExtension /
    pathExtension semantics: only the last extension splits
    off; a name without a dot has stem == name and ext == ""."""
    if "." in lower:
        stem, ext = lower.rsplit(".", 1)
        return stem, ext
    return lower, ""


def _file_library_admitted(name: str, is_root_loose: bool = False) -> bool:
    """Reject dotfiles, internal DB/lock/state suffixes and stems,
    and sensitive names."""
    lower = name.lower()
    if lower.startswith("."):
        return False
    for suffix in _FL_INTERNAL_SUFFIXES:
        if lower.endswith(suffix):
            return False
    stem, _ = _fl_stem_ext(lower)
    if stem in _FL_INTERNAL_STEMS:
        return False
    if "_is_sensitive_name" in globals() and _is_sensitive_name(name):
        return False
    return True


def _file_library_chat_delivery_ids():
    """Return the set of delivery IDs actually sent in active chat
    messages (via `[[deliver:dlv_...]]` or sentinel link lines), or
    None if state.db does not exist (standalone/test mode)."""
    db_path = globals().get("_SENTINEL_DB_PATH")
    if db_path is None or not Path(db_path).is_file():
        return None
    ids = set()
    try:
        links_fn = globals().get("_delivery_links_load")
        if callable(links_fn):
            for link in links_fn():
                did = link.get("deliveryId")
                if did:
                    ids.add(did)
    except Exception:
        pass
    import sqlite3
    try:
        conn = sqlite3.connect(
            f"file:{db_path}?mode=ro", uri=True, timeout=2.0)
        try:
            rows = conn.execute(
                "SELECT content FROM messages"
                " WHERE role = 'assistant'"
                " AND COALESCE(active, 1) = 1"
                " AND content LIKE '%[[deliver:%'"
            ).fetchall()
        finally:
            conn.close()
        marker_re = globals().get("_DELIVERY_MARKER_RE") or re.compile(
            r"\[\[deliver:(dlv_[0-9a-f]{20})\]\]")
        for (content,) in rows:
            if not content:
                continue
            for rid in marker_re.findall(content):
                ids.add(rid)
    except Exception:
        return None
    return ids


def _file_library_collect() -> list:
    """Collect user-sent attachments/uploads + AI-delivered chat files
    that actually exist on disk, deduped by path and sorted by mtime
    descending. No count cap."""
    items: list = []
    seen: set = set()

    def absorb(path_str: str, name: str, size, mtime,
               source: str, delivery_id=None, mime_type=None) -> None:
        if path_str in seen:
            return
        seen.add(path_str)
        items.append({
            "name": name,
            "path": path_str,
            "is_directory": False,
            "size": size,
            "mtime": mtime,
            "mime_type": mime_type or mimetypes.guess_type(name)[0],
            "source": source,
            "delivery_id": delivery_id,
        })

    # 1. User-uploaded & chat-sent files (uploads/, attachments/)
    for rel, label in _FILE_LIBRARY_USER_ROOTS:
        base = FILE_LIBRARY_ROOT / rel
        if not base.is_dir():
            continue
        stack = [(base, 0)]
        while stack:
            dirpath, depth = stack.pop()
            try:
                entries = sorted(
                    os.scandir(dirpath), key=lambda e: e.name)
            except OSError:
                continue
            for entry in entries:
                try:
                    if entry.is_dir():
                        if depth < _FILE_LIBRARY_MAX_DEPTH:
                            stack.append(
                                (Path(entry.path), depth + 1))
                    elif entry.is_file():
                        if not _file_library_admitted(entry.name):
                            continue
                        st = entry.stat()
                        absorb(entry.path, entry.name,
                               st.st_size, st.st_mtime, label)
                except OSError:
                    continue

    # 2. AI-delivered files from delivery ledger (deliveries.jsonl)
    load_fn = globals().get("_delivery_load")
    if callable(load_fn):
        chat_ids = _file_library_chat_delivery_ids()
        records = load_fn()
        # Iterate newest-first so latest delivery wins on same path
        for rec in reversed(records):
            rid = rec.get("id")
            path_str = rec.get("path")
            name = rec.get("name") or (
                os.path.basename(path_str) if path_str else "")
            if not rid or not path_str or not name:
                continue
            if chat_ids is not None and rid not in chat_ids:
                continue
            if not _file_library_admitted(name):
                continue
            try:
                st = os.stat(path_str)
                if not stat.S_ISREG(st.st_mode):
                    continue
            except OSError:
                # File no longer exists on disk -> never emit ghost 404
                continue
            absorb(
                path_str,
                name,
                st.st_size,
                st.st_mtime,
                _FILE_LIBRARY_AI_LABEL,
                delivery_id=rid,
                mime_type=rec.get("mime"),
            )

    items.sort(key=lambda i: -(i["mtime"] or 0))
    return items


def _file_library_view(offset: int, limit) -> dict:
    """One page of the aggregated set. limit=None returns the
    whole set (the App's normal call); total always reports the
    full admitted count and truncated is always False --
    paging is the caller's choice, never a silent cap."""
    items = _file_library_collect()
    total = len(items)
    if limit is None:
        page = items[offset:]
    else:
        page = items[offset:offset + limit]
    return {
        "items": page,
        "total": total,
        "offset": offset,
        "limit": limit,
        "truncated": False,
    }
