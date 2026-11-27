"""Crash-report ingest (local patch, hermes-deploy 1.7.0, demand-ledger 131).

Receiving end for the OneDay app's runtime crash collection (DESIGN
section 384): the app gathers MetricKit diagnostics behind its own
privacy gate (``CrashReportRecord.make`` -- whitelist fields only,
scrubbed again before anything is stored on device) and, per the
2026-11-14 ruling, a server endpoint may only ever receive records
that already passed that gate. This module is that endpoint's store:

- ``POST /v1/diagnostics/crash-reports`` (handler in api_server.py)
  accepts one record object, a ``{"reports": [...]}`` envelope, or a
  bare list, and appends the accepted records to
  ``/opt/data/diagnostics/crash_reports.jsonl``.
- ``GET /v1/diagnostics/crash-reports`` returns them newest-first.

Design dead-lines:

- WHITELIST, re-checked server-side. Only the section-384 record
  fields are stored (id / capturedAt / kind / exceptionType /
  exceptionSignal / terminationNamespace / terminationCode /
  appVersion / osVersion / faultingTopSymbols). Unknown fields are
  dropped, never stored -- the endpoint does not trust that every
  client really passed the app-side gate.
- SCRUB, again. Every stored string passes the same three regex
  families as the app gate and the CI extractor (user paths, UUID
  shapes, hex addresses). Defense in depth: a record that somehow
  carries a home path or a binary UUID loses those bytes here, not
  in some later reader.
- The store is a plain append-only JSONL plus a newest-500 cap
  enforced on write (the app-side store caps at 50; the server keeps
  more history but still bounded -- crash metadata is diagnostics,
  not an archive). ``receivedAt`` is stamped server-side; client
  clocks are never trusted for ordering.
- This module sits in NO decision chain. A fault degrades only the
  two diagnostics endpoints (api_server answers 503 when the module
  cannot be imported); nothing else in the gateway reads this file.
"""

import json
import logging
import os
import re
import threading
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger("gateway.platforms.crash_reports")

STORE_PATH = Path(os.environ.get(
    "CRASH_REPORTS_PATH", "/opt/data/diagnostics/crash_reports.jsonl"))
MAX_RECORDS = 500          # retention cap, newest kept (sweep on write)
MAX_BATCH = 50             # mirrors the api_server handler cap
MAX_SYMBOLS = 8            # section 384: faulting-thread top symbols cap
_KINDS = frozenset({"crash", "hang", "cpuException",
                    "diskWriteException", "other"})
_STR_FIELDS = ("exceptionType", "exceptionSignal",
               "terminationNamespace", "terminationCode",
               "appVersion", "osVersion")
_MAX_STR = 200
_MAX_SYMBOL = 300

# Scrub families (app gate / CI extractor caliber, section 241.4/384):
# user home paths (whole path dropped), UUID shapes, hex addresses.
_SCRUBS = (
    re.compile(r"(?:/Users/|/home/|[A-Za-z]:\\Users\\)[^\s\"']*"),
    re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
               r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"),
    re.compile(r"\b0x[0-9a-fA-F]{6,}\b"),
)

_lock = threading.RLock()


def _scrub(value: str) -> str:
    out = value
    for rx in _SCRUBS:
        out = rx.sub("<scrubbed>", out)
    return out


def _clean_str(value, cap: int) -> str | None:
    if not isinstance(value, str):
        return None
    out = _scrub(value).strip()[:cap]
    return out or None


def _validate(record) -> dict | None:
    """Project one inbound record onto the whitelist, or None to reject.

    A record is accepted when it is an object carrying at least a
    usable kind or timestamp; every stored field is re-derived here,
    nothing is passed through by reference.
    """
    if not isinstance(record, dict):
        return None
    kind = record.get("kind")
    if kind not in _KINDS:
        kind = "other" if kind is not None else None
    captured = _clean_str(record.get("capturedAt"), 64)
    if kind is None and captured is None:
        return None
    out: dict = {}
    rid = _clean_str(record.get("id"), 64)
    if rid is not None:
        out["id"] = rid
    if captured is not None:
        out["capturedAt"] = captured
    out["kind"] = kind or "other"
    for field in _STR_FIELDS:
        cleaned = _clean_str(record.get(field), _MAX_STR)
        if cleaned is not None:
            out[field] = cleaned
    symbols = record.get("faultingTopSymbols")
    if isinstance(symbols, list):
        cleaned_symbols = []
        for sym in symbols[:MAX_SYMBOLS]:
            cleaned = _clean_str(sym, _MAX_SYMBOL)
            if cleaned is not None:
                cleaned_symbols.append(cleaned)
        out["faultingTopSymbols"] = cleaned_symbols
    else:
        out["faultingTopSymbols"] = []
    out["receivedAt"] = datetime.now(tz=timezone.utc).isoformat().replace(
        "+00:00", "Z")
    return out


def _read_lines() -> list[str]:
    try:
        return STORE_PATH.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    except Exception:
        logger.exception("crash_reports: store read failed")
        return []


def append_reports(records) -> dict:
    """Validate + append a batch; returns {"accepted": n, "rejected": m}."""
    accepted = []
    rejected = 0
    for record in list(records)[:MAX_BATCH]:
        cleaned = _validate(record)
        if cleaned is None:
            rejected += 1
        else:
            accepted.append(cleaned)
    if not accepted:
        return {"accepted": 0, "rejected": rejected}
    with _lock:
        STORE_PATH.parent.mkdir(parents=True, exist_ok=True)
        lines = _read_lines()
        lines.extend(json.dumps(r, ensure_ascii=False) for r in accepted)
        if len(lines) > MAX_RECORDS:
            # Retention sweep on write: keep the newest MAX_RECORDS,
            # rewrite atomically (grant_projection sweep shape).
            lines = lines[-MAX_RECORDS:]
            tmp = STORE_PATH.with_suffix(".tmp")
            with open(tmp, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, STORE_PATH)
        else:
            with open(STORE_PATH, "a", encoding="utf-8") as f:
                for r in accepted:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
                f.flush()
                os.fsync(f.fileno())
    return {"accepted": len(accepted), "rejected": rejected}


def list_reports(limit: int = 50) -> list[dict]:
    """Newest-first stored records (at most ``limit``)."""
    out = []
    for line in reversed(_read_lines()):
        try:
            row = json.loads(line)
        except Exception:
            continue
        if isinstance(row, dict):
            out.append(row)
        if len(out) >= limit:
            break
    return out
