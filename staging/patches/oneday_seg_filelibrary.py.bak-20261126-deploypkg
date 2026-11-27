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


# ------------------------------------------------------------------
# File library read surface (A-06, 1.0.66): the one sanctioned
# aggregated read for the App's file page. Up to 0.50.60 the App
# assembled this set itself: eight hard-coded output roots walked
# recursively over GET /api/files (BFS, depth 3, a silent
# 600-entry cap), admission filtering, dedupe and sorting all
# client-side -- dozens of serial directory requests per page
# open, and the root list / admission rules lived only in the
# client (three curation generations: P8, 0.22.0 F1, 0.36.31).
# The aggregation now lives here, next to the data: one GET
# returns the full admitted set (roots, admission, dedupe and
# mtime-descending order all applied server-side), with offset/
# limit paging on top. There is NO count cap and no silent
# truncation: the response always carries the true total.
#
# Admission below is a line-for-line port of the retired client
# rules (OneDayCore DeliverableAdmission + the root-loose
# SensitiveFilePolicy.protectedNames gate the client applied on
# top), so the admitted set is unchanged by the move; the
# selftest pins the 2026-11-10 pollutant samples the client
# tests used to pin. This segment is the single source now --
# the App only consumes the list.
# ------------------------------------------------------------------

FILE_LIBRARY_ROOT = Path(os.environ.get(
    "FILE_LIBRARY_ROOT",
    os.environ.get("DELIVERY_ROOT", "/opt/data")))

# (relative path, source label) -- the curated output roots,
# exactly the set the client hard-coded through 0.50.60
# (P8 roots, 0.22.0 F1 curation, 0.36.31 added attachments).
_FILE_LIBRARY_ROOTS = [
    ("uploads", "App 上传"),
    ("attachments", "聊天发送"),
    ("cache/images", "生成图片"),
    ("cache/documents", "生成文档"),
    ("cache/screenshots", "浏览器截图"),
    ("cache/videos", "生成的视频"),
    ("cache/audio", "生成的音频"),
    ("cron/output", "定时任务产出"),
]
_FILE_LIBRARY_LOOSE_LABEL = "工作区根目录"
# The client recursed at most 3 levels below each root; kept so
# the admitted set does not change with the move.
_FILE_LIBRARY_MAX_DEPTH = 3

# --- admission (port of OneDayCore DeliverableAdmission) ------

# Root-loose files only: extension whitelist ("finished
# deliverable" shapes; data-pipeline extensions stay out).
_FL_ROOT_EXTS = {
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    "pages", "numbers", "key", "md", "txt", "rtf",
    "html", "htm", "csv", "zip", "7z", "tar", "gz", "epub",
    "png", "jpg", "jpeg", "gif", "webp", "heic",
    "mp4", "mov", "m4v", "mp3", "wav", "m4a", "aac",
}

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

# Root-loose second gate, mirroring the client's
# SensitiveFilePolicy.protectedNames.contains(name): exact,
# case-sensitive membership in the original-case set, exactly
# as the client applied it (the case quirk is preserved on
# purpose -- parity of the admitted set, noted in the A-06
# report; hidden names like .env never reach this gate anyway
# because admission rejects dotfiles for every source).
_FL_PROTECTED_NAMES = {
    "config.yaml", ".env", "auth.json",
    "SOUL.md", "AGENTS.md", "USER.md", "MEMORY.md", "IDENTITY.md",
}


def _fl_stem_ext(lower: str):
    """(stem, ext) with NSString deletingPathExtension /
    pathExtension semantics: only the last extension splits
    off; a name without a dot has stem == name and ext == ""."""
    if "." in lower:
        stem, ext = lower.rsplit(".", 1)
        return stem, ext
    return lower, ""


def _file_library_admitted(name: str, is_root_loose: bool) -> bool:
    """Port of DeliverableAdmission.isAdmitted: hidden files
    rejected for every source; internal suffix/stem shapes
    rejected for every source; root-loose files additionally
    need a whitelisted deliverable extension."""
    lower = name.lower()
    if lower.startswith("."):
        return False
    for suffix in _FL_INTERNAL_SUFFIXES:
        if lower.endswith(suffix):
            return False
    stem, ext = _fl_stem_ext(lower)
    if stem in _FL_INTERNAL_STEMS:
        return False
    if is_root_loose:
        return ext in _FL_ROOT_EXTS
    return True


def _file_library_collect() -> list:
    """Walk the curated roots + the workspace root's loose
    files and return the admitted set as /api/files-shaped
    entries plus a source label, deduped by path (earlier
    roots win, loose files last -- the client's absorb order)
    and sorted by mtime descending (missing mtime = 0, the
    client's sort key). No count cap."""
    items: list = []
    seen: set = set()

    def absorb(path_str: str, name: str, size, mtime,
               source: str) -> None:
        if path_str in seen:
            return
        seen.add(path_str)
        items.append({
            "name": name,
            "path": path_str,
            "is_directory": False,
            "size": size,
            "mtime": mtime,
            "mime_type": mimetypes.guess_type(name)[0],
            "source": source,
        })

    for rel, label in _FILE_LIBRARY_ROOTS:
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
                        if not _file_library_admitted(
                                entry.name, False):
                            continue
                        st = entry.stat()
                        absorb(entry.path, entry.name,
                               st.st_size, st.st_mtime, label)
                except OSError:
                    continue

    try:
        loose = sorted(
            os.scandir(FILE_LIBRARY_ROOT), key=lambda e: e.name)
    except OSError:
        loose = []
    for entry in loose:
        try:
            if not entry.is_file():
                continue
        except OSError:
            continue
        if not _file_library_admitted(entry.name, True):
            continue
        if entry.name in _FL_PROTECTED_NAMES:
            continue
        try:
            st = entry.stat()
        except OSError:
            continue
        absorb(entry.path, entry.name, st.st_size, st.st_mtime,
               _FILE_LIBRARY_LOOSE_LABEL)

    items.sort(key=lambda i: -(i["mtime"] or 0))
    return items


def _file_library_view(offset: int, limit) -> dict:
    """One page of the aggregated set. limit=None returns the
    whole set (the App's normal call); total always reports
    the full admitted count and truncated is always False --
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
