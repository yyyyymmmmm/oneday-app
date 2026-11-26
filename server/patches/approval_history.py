"""Unified approval-history projection (local patch, approval bar 1).

Presents the two approval decision histories as ONE read-only timeline
(``GET /v1/approval-history``), per proposal 177 section 2.1 as revised
by probe 180:

- exec line: the batch-2 approval ledger
  (``/opt/data/approvals/approval_ledger.jsonl``), folded exactly the
  way approval_projection folds it (last snapshot per request_id wins,
  ``purged`` removes). It holds parked approvals (queue / submit_pending
  captures, with their settlements) plus, since bar 1, the guard events
  approval_projection records for instantly-resolved decisions
  (cron / unattended instant denies, guard allow hits).
- write-gate line: ``<HERMES_HOME>/write-gate/decisions.jsonl``, the
  append-only decision log owned by write_gate_gateway.

Design dead-lines (grant_projection precedent):

- The projection NEVER sits in any decision chain and never writes
  either source. Both sources are read from disk on every call, so the
  answer reflects the ledgers, not some process's memory.
- A source that cannot be read honestly is an explicit error, never a
  fake empty list: when both sources fail, list_approval_history
  raises RuntimeError (the handler answers 503); when exactly one
  fails, the other half is returned with ``partial: true`` and
  ``source_errors`` naming the failed half. A missing file is NOT a
  failure -- a fresh instance legitimately has no ledger yet (zero
  records, stated as such). A file whose every line is corrupt IS a
  failure: zero parseable rows out of a non-empty file cannot be told
  apart from a read problem, so it is surfaced, not zeroed.
- Anti-fake-green reconciliation: the response carries, per source,
  the count folded from the source itself AND the count the
  projection emitted for that source, computed independently;
  ``reconciled`` is true only when both equations hold. An exec total
  of 0 is therefore a stated, checkable fact (with the per-kind
  breakdown alongside), never a silent empty table -- the 0 = 0 trap
  probe 180 warned about.
- This surface supplies title MATERIAL, not titles: each item carries
  the raw fields the activity-feed title engine (proposal 174) builds
  from (command / description / pattern keys for exec; the structured
  op fields for write-gate) plus the initiator material (origin /
  session anchor / guard context). Wording belongs to the engine.
"""

import json
import logging
import os
from datetime import datetime

logger = logging.getLogger("gateway.platforms.approval_history")

_MAX_LIMIT = 500


def _exec_ledger_path():
    return os.environ.get(
        "HERMES_APPROVAL_LEDGER_PATH",
        "/opt/data/approvals/approval_ledger.jsonl")


def _writegate_decisions_path():
    override = os.environ.get("HERMES_WRITEGATE_DECISIONS_PATH")
    if override:
        return override
    try:
        from hermes_constants import get_hermes_home
        return os.path.join(get_hermes_home(), "write-gate",
                            "decisions.jsonl")
    except Exception:
        return "/opt/data/write-gate/decisions.jsonl"


def _iso_to_epoch(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except Exception:
            pass
        try:
            return datetime.fromisoformat(
                value.replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    return None


# ---------------------------------------------------------------- sources

def _read_exec_source():
    """Fold the approval ledger. Returns a stats dict with records.

    Raises OSError on a read failure of an existing file, and
    ValueError when a non-empty file yields zero parseable records.
    """
    path = _exec_ledger_path()
    stats = {"path": path, "lines": 0, "corrupt_lines": 0,
             "records": 0, "guard_events": 0, "parked": 0}
    if not os.path.exists(path):
        stats["records_list"] = []
        return stats
    folded = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            stats["lines"] += 1
            try:
                obj = json.loads(line)
                rec = obj["record"]
                rid = rec["request_id"]
            except Exception:
                stats["corrupt_lines"] += 1
                continue
            if obj.get("event") == "purged":
                folded.pop(rid, None)
            else:
                folded[rid] = rec
    if stats["lines"] and not folded and stats["corrupt_lines"]:
        raise ValueError("approval ledger unreadable: %d/%d lines corrupt"
                         % (stats["corrupt_lines"], stats["lines"]))
    records = list(folded.values())
    stats["records"] = len(records)
    stats["guard_events"] = sum(
        1 for r in records if r.get("source") == "guard")
    stats["parked"] = stats["records"] - stats["guard_events"]
    stats["records_list"] = records
    return stats


def _read_writegate_source():
    """Read the write-gate decision log (append-only, one row per line)."""
    path = _writegate_decisions_path()
    stats = {"path": path, "lines": 0, "corrupt_lines": 0, "records": 0}
    if not os.path.exists(path):
        stats["rows"] = []
        return stats
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            stats["lines"] += 1
            try:
                row = json.loads(line)
                if not isinstance(row, dict) or not row.get("id"):
                    raise ValueError("decision row without id")
            except Exception:
                stats["corrupt_lines"] += 1
                continue
            rows.append(row)
    if stats["lines"] and not rows and stats["corrupt_lines"]:
        raise ValueError("write-gate decisions unreadable: %d/%d lines "
                         "corrupt" % (stats["corrupt_lines"],
                                      stats["lines"]))
    stats["records"] = len(rows)
    stats["rows"] = rows
    return stats


# ---------------------------------------------------------------- mapping

def _exec_item(rec):
    kind = rec.get("event_kind")
    if not kind:
        kind = "parked" if rec.get("source") in ("queue", "pending") \
            else (rec.get("source") or "parked")
    status = rec.get("status")
    if kind == "guard_allow":
        tier = "pre_approved"
    elif kind in ("cron_deny", "unattended_deny"):
        tier = "deny"
    else:
        tier = rec.get("choice")
    if kind in ("cron_deny", "unattended_deny"):
        initiator_type = {"cron": "scheduled",
                          "single_query": "system",
                          "unattended": "background"}.get(
                              rec.get("guard_context"), "background")
    else:
        initiator_type = "session"
    return {
        "id": "exec:" + str(rec.get("request_id")),
        "line": "exec",
        "record_id": rec.get("request_id"),
        "event_kind": kind,
        "status": status,
        "outcome": status,
        "choice": rec.get("choice"),
        "tier": tier,
        "decision": rec.get("choice") if status == "answered" else None,
        "via_rule": None,
        "title_material": {
            "command": rec.get("command", ""),
            "description": rec.get("description", ""),
            "pattern_keys": rec.get("pattern_keys", []),
            "scopes": rec.get("scopes"),
        },
        "initiator": {
            "type": initiator_type,
            "session_key": rec.get("session_key"),
            "session_id": rec.get("session_id"),
            "run_id": rec.get("run_id"),
            "guard_context": rec.get("guard_context"),
            "name": None,
        },
        "created_at": rec.get("created_at"),
        "decided_at": rec.get("decided_at"),
        "payload_ref": None,
    }


_WG_TITLE_KEYS = ("op", "op_count", "op_kinds", "target_name",
                  "content_preview", "mem_target", "summary", "action",
                  "subsystem")


def _writegate_item(row):
    via_rule = row.get("via_rule") or None
    origin = row.get("origin", "foreground")
    anchor = row.get("anchor") if isinstance(row.get("anchor"), dict) \
        else {}
    material = {k: row.get(k) for k in _WG_TITLE_KEYS
                if row.get(k) is not None}
    return {
        "id": "writegate:" + str(row.get("id")),
        "line": "writegate",
        "record_id": row.get("id"),
        "event_kind": "write_decision",
        "status": "answered",
        "outcome": "answered",
        "choice": None,
        "tier": "rule" if via_rule else "once",
        "decision": row.get("decision"),
        "via_rule": via_rule,
        "title_material": material,
        "initiator": {
            "type": "background" if origin == "background_review"
                    else "session",
            "origin": origin,
            "session_id": anchor.get("sessionId"),
            "name": None,
        },
        "created_at": _iso_to_epoch(row.get("created_at")),
        "decided_at": _iso_to_epoch(row.get("decided_at")),
        "payload_ref": None,
    }


# ---------------------------------------------------------------- public API

def list_approval_history(limit=200):
    """Unified approval history from both decision sources.

    Raises RuntimeError when BOTH sources are unreadable (the handler
    turns that into an explicit 503 -- never a fake empty list). When
    exactly one source fails, returns the other source's items with
    ``partial: true`` and ``source_errors`` naming the failed half.
    """
    try:
        limit = int(limit)
    except Exception:
        limit = 200
    limit = max(1, min(limit, _MAX_LIMIT))

    errors = []
    exec_stats = None
    wg_stats = None
    try:
        exec_stats = _read_exec_source()
    except Exception:
        errors.append("exec")
        logger.warning("approval history: exec ledger read failed",
                       exc_info=True)
    try:
        wg_stats = _read_writegate_source()
    except Exception:
        errors.append("writegate")
        logger.warning("approval history: write-gate decisions read "
                       "failed", exc_info=True)
    if exec_stats is None and wg_stats is None:
        raise RuntimeError("approval history sources unavailable")

    items = []
    if exec_stats is not None:
        items.extend(_exec_item(r) for r in exec_stats["records_list"])
    if wg_stats is not None:
        items.extend(_writegate_item(r) for r in wg_stats["rows"])
    items.sort(key=lambda i: float(i.get("decided_at")
                                   or i.get("created_at") or 0),
               reverse=True)

    exec_projected = sum(1 for i in items if i["line"] == "exec")
    wg_projected = sum(1 for i in items if i["line"] == "writegate")
    reconciled = (
        (exec_stats is None or exec_projected == exec_stats["records"])
        and (wg_stats is None or wg_projected == wg_stats["records"]))

    sources = {}
    if exec_stats is not None:
        sources["exec"] = {
            "ledger_records": exec_stats["records"],
            "ledger_lines": exec_stats["lines"],
            "corrupt_lines": exec_stats["corrupt_lines"],
            "parked": exec_stats["parked"],
            "guard_events": exec_stats["guard_events"],
            "projected": exec_projected,
        }
    if wg_stats is not None:
        sources["writegate"] = {
            "decision_rows": wg_stats["records"],
            "corrupt_lines": wg_stats["corrupt_lines"],
            "projected": wg_projected,
        }
    total = len(items)
    return {
        "object": "hermes.approval_history",
        "history": items[:limit],
        "total": total,
        "returned": min(total, limit),
        "counts": {
            "exec": exec_projected,
            "writegate": wg_projected,
            "via_rule": sum(1 for i in items if i.get("via_rule")),
            "human_decided": sum(1 for i in items
                                 if not i.get("via_rule")),
        },
        "sources": sources,
        "reconciled": reconciled,
        "partial": bool(errors),
        "source_errors": errors,
    }
