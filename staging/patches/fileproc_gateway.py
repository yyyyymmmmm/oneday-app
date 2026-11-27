"""File processing (local module, hermes-deploy 1.8.0, bridge-retirement batch 1).

Gateway home of the two read-only file-processing endpoints that
used to live in the companion's fileproc bridge module (8652):

- ``GET /v1/files/spreadsheet?path=<abs>`` -- xlsx -> per-sheet CSV
  (value semantics; section 125 contract)
- ``GET /v1/media/rendition?path=<abs>&w=<360|1080|2048>&kind=<image|poster>``
  -- JPEG rendition / video poster, disk-cached by content key
  (section 138 contract, capability registry #18)

api_server.py also mounts both handlers under the shape-preserving
``/api/fileproc-bridge/...`` prefix, so already-shipped apps keep
working byte-for-byte while the bridge process stands by for
rollback (nginx flips the public location between the two).

The processing code below the header is the bridge's, moved
verbatim (the code moved; the contracts did not): same path
discipline (containment root, sensitive-name policy), same size
caps, same cache keying / single-flight / concurrency cap, same
error strings and statuses. What changed is only the shell:

- Auth is the gateway's (``@_require_auth`` in api_server.py);
  the module carries no key of its own.
- The rendition cache defaults to ``/opt/data/fileproc-cache/``
  (``FILEPROC_CACHE_DIR``; ``RENDITION_CACHE_DIR`` still wins when
  set, e.g. to inherit the bridge's warm cache at apply time).
- The memory-pressure guard still reads /proc/meminfo, which in
  the hermes container reflects the host -- the same reading the
  companion container produced; a container-caliber reading is a
  recorded follow-up (bridge-retirement spec section 8.2), not
  silently changed here.

This module sits in NO decision chain. A fault degrades only the
two file endpoints (api_server answers 503 when the module cannot
be imported); nothing else in the gateway reads this file.
"""

from __future__ import annotations

import csv
import hashlib
import io
import os
import re
import threading
import zipfile
from datetime import datetime, timedelta
from pathlib import Path
import xml.etree.ElementTree as ET




class _Err(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


# ---------------------------------------------------------------------------
# Spreadsheet transcode (§125): xlsx -> per-sheet CSV, value semantics.
# Stdlib only (zipfile + XML): the companion image carries no
# spreadsheet library, and a new dependency is not worth it for a
# read-only value extraction. Formula cells yield their cached <v>;
# a formula without a cached value renders empty and is counted into
# "notes" (never invented). Merged cells store their value in the
# top-left cell only -- the rest stay empty, which is exactly how the
# CSV reads. Dates are recognised through styles.xml number formats
# and rendered ISO. Path rules mirror the Hermes files download
# endpoint (files.py): root-locked to SPREADSHEET_ROOT (/opt/data),
# must exist (404), must be a regular file (400), sensitive names
# refused (403, same lists as the App's SensitiveFilePolicy),
# >100MiB refused (413), unparseable or legacy .xls refused (422).
# Per sheet at most _SPREADSHEET_ROW_LIMIT data rows are emitted;
# truncation is reported (truncated + total_rows), never silent.
# ---------------------------------------------------------------------------

_SPREADSHEET_ROW_LIMIT = 500
_SPREADSHEET_SIZE_LIMIT = 100 * 1024 * 1024
_SPREADSHEET_SHEET_LIMIT = 50
_XLSX_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_XLSX_NS_R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
_BUILTIN_DATE_FMT_IDS = (
    set(range(14, 23)) | set(range(27, 37)) | {45, 46, 47, 50, 57}
)
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


def _resolve_spreadsheet_path(raw: str) -> Path:
    if not raw or not raw.strip():
        raise _Err(400, "缺少 path 参数")
    candidate = Path(raw)
    if not candidate.is_absolute():
        raise _Err(400, "路径必须是绝对路径")
    root = Path(os.environ.get("SPREADSHEET_ROOT", "/opt/data")).resolve()
    resolved = candidate.resolve()
    if resolved != root and root not in resolved.parents:
        raise _Err(400, "路径不在允许范围内")
    if _is_sensitive_name(resolved.name):
        raise _Err(403, "敏感文件不允许转换")
    if not resolved.exists():
        raise _Err(404, "文件不存在")
    if not resolved.is_file():
        raise _Err(400, "路径不是文件")
    if resolved.stat().st_size > _SPREADSHEET_SIZE_LIMIT:
        raise _Err(413, "文件太大，无法转换")
    return resolved


def _fmt_number(value: float) -> str:
    if value == int(value) and abs(value) < 1e15:
        return str(int(value))
    return repr(value)


def _serial_to_string(value: float) -> str:
    # Excel serial dates: base 1899-12-31 for serials < 61, base
    # 1899-12-30 from 61 on (the format's fictitious 1900-02-29 is
    # folded away -- serial 60 lands on 1900-03-01, an acceptable
    # read-only rendering compromise).
    base = datetime(1899, 12, 31) if value < 61 else datetime(1899, 12, 30)
    moment = base + timedelta(
        days=int(value), seconds=round((value - int(value)) * 86400))
    if value == int(value):
        return moment.strftime("%Y-%m-%d")
    if int(value) == 0:
        return moment.strftime("%H:%M:%S")
    return moment.strftime("%Y-%m-%d %H:%M:%S")


def _is_date_format(fmt_id: int, code) -> bool:
    if fmt_id in _BUILTIN_DATE_FMT_IDS:
        return True
    if not code:
        return False
    cleaned = re.sub(r'"[^"]*"', "", code)
    cleaned = re.sub(r"\[[^\]]*\]", "", cleaned).lower()
    if "yy" in cleaned:
        return True
    return bool(re.search(
        r"m{1,2}\s*[/\-.]\s*d{1,2}|d{1,2}\s*[/\-.]\s*m{1,2}",
        cleaned))


def _load_shared_strings(zf) -> list:
    try:
        raw = zf.read("xl/sharedStrings.xml")
    except KeyError:
        return []
    root = ET.fromstring(raw)
    return [
        "".join(t.text or "" for t in si.iter(f"{_XLSX_NS}t"))
        for si in root.findall(f"{_XLSX_NS}si")
    ]


def _load_date_styles(zf) -> list:
    """Per cellXfs index: does the number format render a date?"""
    try:
        raw = zf.read("xl/styles.xml")
    except KeyError:
        return []
    root = ET.fromstring(raw)
    custom = {}
    numfmts = root.find(f"{_XLSX_NS}numFmts")
    if numfmts is not None:
        for nf in numfmts.findall(f"{_XLSX_NS}numFmt"):
            try:
                custom[int(nf.get("numFmtId"))] = nf.get("formatCode") or ""
            except (TypeError, ValueError):
                continue
    out = []
    xfs = root.find(f"{_XLSX_NS}cellXfs")
    if xfs is not None:
        for xf in xfs.findall(f"{_XLSX_NS}xf"):
            try:
                fmt_id = int(xf.get("numFmtId") or 0)
            except ValueError:
                fmt_id = 0
            out.append(_is_date_format(fmt_id, custom.get(fmt_id)))
    return out


def _workbook_sheets(zf) -> list:
    wb = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    relmap = {}
    for rel in rels.iter():
        rid, target = rel.get("Id"), rel.get("Target")
        if rid and target:
            relmap[rid] = target
    sheets = []
    sheets_el = wb.find(f"{_XLSX_NS}sheets")
    if sheets_el is None:
        return sheets
    for sh in sheets_el.findall(f"{_XLSX_NS}sheet"):
        target = relmap.get(sh.get(f"{_XLSX_NS_R}id") or "", "")
        if target.startswith("/"):
            part = target.lstrip("/")
        elif target.startswith("xl/"):
            part = target
        else:
            part = "xl/" + target
        sheets.append((sh.get("name") or "Sheet", part))
    return sheets


def _cell_text(cell, shared, date_styles):
    """(text, missing_cache_count) for one <c> element."""
    ctype = cell.get("t")
    if ctype == "inlineStr":
        is_el = cell.find(f"{_XLSX_NS}is")
        if is_el is not None:
            return "".join(
                t.text or "" for t in is_el.iter(f"{_XLSX_NS}t")), 0
        return "", 0
    v_el = cell.find(f"{_XLSX_NS}v")
    if v_el is None or v_el.text is None:
        # A formula without a cached value: honestly empty, counted.
        return "", 1 if cell.find(f"{_XLSX_NS}f") is not None else 0
    raw = v_el.text
    if ctype == "s":
        try:
            return shared[int(raw)], 0
        except (ValueError, IndexError):
            return "", 0
    if ctype == "b":
        return ("TRUE" if raw in ("1", "true") else "FALSE"), 0
    if ctype in ("str", "e"):
        return raw, 0
    try:
        num = float(raw)
    except ValueError:
        return raw, 0
    style_idx = cell.get("s")
    if style_idx is not None:
        try:
            idx = int(style_idx)
            if idx < len(date_styles) and date_styles[idx]:
                return _serial_to_string(num), 0
        except ValueError:
            pass
    return _fmt_number(num), 0


def _sheet_rows(zf, part, shared, date_styles):
    root = ET.fromstring(zf.read(part))
    data = root.find(f"{_XLSX_NS}sheetData")
    rows, missing = [], 0
    if data is None:
        return rows, missing
    for row_el in data.findall(f"{_XLSX_NS}row"):
        cells, max_col, next_col = {}, -1, 0
        for cell in row_el.findall(f"{_XLSX_NS}c"):
            ref = cell.get("r") or ""
            match = re.match(r"([A-Z]+)", ref)
            if match:
                col = 0
                for ch in match.group(1):
                    col = col * 26 + (ord(ch) - 64)
                col -= 1
            else:
                col = next_col
            next_col = col + 1
            text, miss = _cell_text(cell, shared, date_styles)
            missing += miss
            cells[col] = text
            max_col = max(max_col, col)
        rows.append([cells.get(i, "") for i in range(max_col + 1)])
    return rows, missing


def _spreadsheet_convert(path: Path) -> dict:
    with open(path, "rb") as fh:
        head = fh.read(8)
    if head.startswith(b"\xd0\xcf\x11\xe0"):
        raise _Err(422, "这是旧版 .xls 格式，无法转换；"
                        "请另存为 .xlsx 后再打开")
    try:
        zf = zipfile.ZipFile(path)
    except Exception:
        raise _Err(422, "文件不是有效的 xlsx 表格")
    notes = []
    sheets = []
    with zf:
        try:
            sheets_meta = _workbook_sheets(zf)
        except Exception:
            raise _Err(422, "文件不是有效的 xlsx 表格")
        if not sheets_meta:
            raise _Err(422, "文件不是有效的 xlsx 表格")
        if len(sheets_meta) > _SPREADSHEET_SHEET_LIMIT:
            notes.append(
                f"工作表过多，只转换前 {_SPREADSHEET_SHEET_LIMIT} 个")
            sheets_meta = sheets_meta[:_SPREADSHEET_SHEET_LIMIT]
        shared = _load_shared_strings(zf)
        date_styles = _load_date_styles(zf)
        total_missing = 0
        for name, part in sheets_meta:
            try:
                rows, missing = _sheet_rows(
                    zf, part, shared, date_styles)
            except KeyError:
                raise _Err(422, "表格内容不完整，无法转换")
            total_missing += missing
            while rows and all(not c for c in rows[-1]):
                rows.pop()
            total_data = max(0, len(rows) - 1)
            truncated = total_data > _SPREADSHEET_ROW_LIMIT
            emit = rows[:1 + _SPREADSHEET_ROW_LIMIT] if truncated \
                else rows
            buf = io.StringIO()
            writer = csv.writer(buf, lineterminator="\n")
            writer.writerows(emit)
            sheets.append({
                "name": name,
                "csv": buf.getvalue(),
                "total_rows": total_data,
                "truncated": truncated,
            })
        if total_missing:
            notes.append(
                f"有 {total_missing} 个公式单元格没有缓存值，"
                "已按空值显示")
    return {"name": path.name, "sheets": sheets, "notes": notes}


# ---------------------------------------------------------------------------
# §138 image renditions + video posters (media-perf spec §5.1/§5.2).
#
# GET /media/rendition?path=<abs>&w=<360|1080|2048>&kind=<image|poster>
# First request generates a JPEG rendition (long edge <= w, never
# upscaled, EXIF orientation applied) and caches it on disk; later
# requests serve the cached bytes. The cache key embeds the source
# path + mtime + size + tier + kind, so a changed source is a new
# key and stale bytes are never served. Path discipline mirrors the
# §125 spreadsheet endpoint (containment root, sensitive names,
# size cap). Generation is single-flight per key with a global
# concurrency cap of 2, and refuses to run when system memory
# pressure is high (the box-wide patrol red line).

_RENDITION_WIDTHS = (360, 1080, 2048)
_RENDITION_SIZE_LIMIT = 100 * 1024 * 1024
_RENDITION_GEN_SLOTS = threading.Semaphore(2)
_RENDITION_KEY_LOCKS: dict[str, threading.Lock] = {}
_RENDITION_KEY_LOCKS_GUARD = threading.Lock()


def _rendition_cache_dir() -> Path:
    # Gateway home for the cache (bridge-retirement batch 1): the
    # bridge kept it next to the oneday data file; the gateway
    # module keeps it under the Hermes data root. RENDITION_CACHE_DIR
    # still overrides (an apply step may point it at the bridge's
    # old directory to inherit the warm cache).
    raw = os.environ.get("RENDITION_CACHE_DIR", "")
    if raw:
        return Path(raw)
    return Path(os.environ.get(
        "FILEPROC_CACHE_DIR", "/opt/data/fileproc-cache"))


def _resolve_rendition_path(raw: str) -> Path:
    """Same containment discipline as _resolve_spreadsheet_path."""
    if not raw:
        raise _Err(400, "缺少 path 参数")
    root = Path(os.environ.get(
        "RENDITION_ROOT", "/opt/data")).resolve()
    p = Path(raw)
    if not p.is_absolute():
        p = root / p
    rp = p.resolve()
    if rp != root and root not in rp.parents:
        raise _Err(400, "文件路径不在允许范围内")
    if _is_sensitive_name(rp.name):
        raise _Err(403, "该文件不提供预览")
    if not rp.exists():
        raise _Err(404, "文件不存在")
    if not rp.is_file():
        raise _Err(400, "目标不是文件")
    if rp.stat().st_size > _RENDITION_SIZE_LIMIT:
        raise _Err(413, "文件过大，暂不生成预览")
    return rp


def _rendition_key(rp: Path, width: int, kind: str) -> tuple[str, Path]:
    st = rp.stat()
    raw = f"{rp}|{st.st_mtime_ns}|{st.st_size}|{width}|{kind}"
    key = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]
    return key, _rendition_cache_dir() / f"{key}.jpg"


def _rendition_lock(key: str) -> threading.Lock:
    with _RENDITION_KEY_LOCKS_GUARD:
        lock = _RENDITION_KEY_LOCKS.get(key)
        if lock is None:
            lock = threading.Lock()
            _RENDITION_KEY_LOCKS[key] = lock
        return lock


def _mem_used_percent() -> float:
    try:
        info: dict[str, int] = {}
        with open("/proc/meminfo", "r", encoding="ascii") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 2:
                    info[parts[0].rstrip(":")] = int(parts[1])
        total = info.get("MemTotal", 0)
        avail = info.get("MemAvailable", 0)
        if total > 0:
            return (total - avail) * 100.0 / total
    except Exception:
        pass
    return 0.0


def _generate_rendition_image(rp: Path, width: int, out: Path) -> None:
    try:
        from PIL import Image, ImageOps
    except ImportError:
        raise _Err(501, "服务器未安装图像组件")
    try:
        import pillow_heif  # type: ignore
        pillow_heif.register_heif_opener()
    except Exception:
        pass
    tmp = out.with_suffix(".tmp.jpg")
    try:
        with Image.open(rp) as im:
            im = ImageOps.exif_transpose(im)
            if im.mode != "RGB":
                im = im.convert("RGB")
            im.thumbnail((width, width), Image.LANCZOS)
            im.save(tmp, "JPEG", quality=80)
    except _Err:
        raise
    except Exception:
        tmp.unlink(missing_ok=True)
        raise _Err(415, "该格式暂不支持预览")
    tmp.replace(out)


def _generate_rendition_poster(rp: Path, width: int, out: Path) -> None:
    import shutil
    import subprocess
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise _Err(501, "服务器未安装视频组件")
    tmp = out.with_suffix(".tmp.jpg")
    try:
        subprocess.run(
            [ffmpeg, "-v", "error", "-ss", "1", "-i", str(rp),
             "-frames:v", "1",
             "-vf", f"scale='min({width},iw)':-2",
             "-f", "image2", "-y", str(tmp)],
            timeout=10, capture_output=True, check=False)
    except subprocess.TimeoutExpired:
        tmp.unlink(missing_ok=True)
        raise _Err(502, "预览生成超时，请稍后重试")
    if not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        raise _Err(415, "该视频暂无法生成预览")
    tmp.replace(out)


# ------------------------------------------------------------ public API
# The two behavior bodies the api_server handlers call (via
# asyncio.to_thread). Each mirrors the bridge's dispatch branch
# for its endpoint, including refusal order and error strings.

def spreadsheet(raw_path: str) -> dict:
    """Spreadsheet transcode: resolve under the bridge's path
    discipline, then convert. Raises _Err on every refusal."""
    path = _resolve_spreadsheet_path(raw_path or "")
    return _spreadsheet_convert(path)


def rendition(raw_path: str, width_raw: str, kind_raw: str,
              if_none_match: str = "") -> tuple[int, bytes | None, str]:
    """Media rendition: returns (status, body, etag) -- (304, None,
    etag) when the client's If-None-Match already names the current
    rendition, else (200, jpeg_bytes, etag). Raises _Err on every
    refusal the bridge answered with a JSON error."""
    rp = _resolve_rendition_path(raw_path or "")
    kind = kind_raw or "image"
    if kind not in ("image", "poster"):
        raise _Err(400, "kind 参数不合法")
    try:
        width = int(width_raw or "1080")
    except ValueError:
        raise _Err(400, "w 参数不合法")
    if width not in _RENDITION_WIDTHS:
        raise _Err(400, "w 参数不合法")
    key, cache_file = _rendition_key(rp, width, kind)
    etag = f'"{key}"'
    if (if_none_match or "").strip() == etag:
        return 304, None, etag
    if not cache_file.exists():
        if _mem_used_percent() > 85:
            raise _Err(503, "服务器繁忙，请稍后重试")
        with _rendition_lock(key):
            if not cache_file.exists():
                cache_file.parent.mkdir(parents=True, exist_ok=True)
                with _RENDITION_GEN_SLOTS:
                    if kind == "poster":
                        _generate_rendition_poster(rp, width, cache_file)
                    else:
                        _generate_rendition_image(rp, width, cache_file)
    return 200, cache_file.read_bytes(), etag
