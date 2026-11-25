"""OneDay layered memory -- gateway service module (local patch,
hermes-deploy 1.11.0, DESIGN section 439).

Service half of the OneDay memory mechanism designed in
memory-mechanism-spec-20261124.md (section 439). The memory itself is
plain Markdown files under the instance's memories/ tree -- the
upstream-curated pair (MEMORY.md / USER.md) plus the package-owned
layered subtree memories/oneday/ (inbox / scenes / people / groups /
journal / bank / insights / identity). Agents write those files with
the native memory tool and file tools, following the oneday-memory
skill's procedures; THIS module is the deterministic machinery around
the files:

- ``GET /v1/memory/layers`` (handler in api_server.py) -- layer
  inventory: file/entry counts, sizes, newest mtimes, provenance
  coverage (share of entries carrying an ``odmem`` trailer).
- ``GET /v1/memory/search`` -- entry-level search across every layer:
  character-trigram overlap scored, weighted by the heat ledger
  (MemoryOS-style access heat) and recency (exponential decay,
  30-day half-life, floor 0.2); hits echo their
  provenance trailer (first/last seen, source, dual-temporal
  validity, supersede chain). A search also records heat for the
  entries it returns.
- ``GET /v1/memory/insights`` -- the ExpeL-style insight ledger
  (behavior-rule candidates with vote governance) read in full.
- ``POST /v1/memory/reconcile-check`` -- Mem0-style mechanical
  reconciliation: given a candidate fact, rank near-duplicate active
  entries by trigram similarity and suggest ADD / UPDATE / REVIEW.
  Pure computation, nothing is written; the semantic verdict stays
  with the distilling agent (two-stage pipeline, spec section 3.2).

A lazy-started sweep thread (``start()``, write_gate_gateway
precedent) runs the mechanical upkeep hourly: heat decay, subtree
INDEX.md regeneration, and the skill-admission audit (skills/
vs the admission ledger -- Voyager-style admission bookkeeping).
The sweep never edits memory content; semantic changes belong to
the agent pipelines (daily distillation cron + weekly review cron,
both driven by the oneday-memory skill).

Design dead-lines:

- FILES ARE THE MEMORY. This module owns no second store: layer
  files are parsed on demand, machine state lives in small JSON
  sidecars under memories/oneday/state/ (heat, admission audit),
  every one of them human-readable and safe to delete (they rebuild).
- PROVENANCE OR PLAIN. Entries without an ``odmem`` trailer stay
  searchable with file-level provenance; nothing is rejected for
  lacking structure -- structure accretes through distillation.
- RETIRED MEANS INVISIBLE, NOT GONE. Entries whose trailer status is
  superseded/retired are excluded from default search (dual-temporal
  invalidation, Zep-style) and remain readable with include_retired.
- This module sits in NO decision chain. A fault degrades only the
  four memory endpoints (api_server answers 503 when the module
  cannot be imported); nothing else in the gateway reads this file.
- The module is also runnable as a CLI inside the container
  (``python3 oneday_memory.py search|reconcile|insight|sweep``) so
  the agent pipelines can use the same machinery from a terminal.
"""

import json
import logging
import math
import os
import re
import time
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger("gateway.platforms.oneday_memory")

MEMORY_ROOT = Path(os.environ.get("ONEDAY_MEMORY_ROOT", "/opt/data/memories"))
SUBTREE = MEMORY_ROOT / "oneday"
SKILLS_DIR = Path(os.environ.get("ONEDAY_SKILLS_DIR", "/opt/data/skills"))

LAYERS = ("core", "inbox", "scenes", "people", "groups",
          "journal", "bank", "insights", "identity")
_LAYER_DIRS = {
    "inbox": SUBTREE / "inbox",
    "scenes": SUBTREE / "scenes",
    "people": SUBTREE / "people",
    "groups": SUBTREE / "groups",
    "journal": SUBTREE / "journal",
    "bank": SUBTREE / "bank",
    "identity": SUBTREE / "identity",
}
_STATE_DIR = SUBTREE / "state"
HEAT_PATH = _STATE_DIR / "heat.json"
ADMISSION_PATH = SUBTREE / "admission" / "skill_admission.jsonl"
ADMISSION_AUDIT_PATH = _STATE_DIR / "admission_audit.json"
INSIGHTS_PATH = SUBTREE / "insights" / "insights.jsonl"
INDEX_PATH = SUBTREE / "INDEX.md"

_RETIRED_STATUSES = frozenset({"superseded", "retired"})
_ODMEM_RE = re.compile(r"<!--\s*odmem:\s*(.*?)\s*-->", re.DOTALL)
_HEADING_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)

_lock = threading.RLock()
_sweep_started = False


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_odmem(raw: str) -> dict:
    out = {}
    for part in raw.split(","):
        if "=" in part:
            key, value = part.split("=", 1)
            out[key.strip()] = value.strip()
    return out


def _trigrams(text: str) -> set:
    norm = re.sub(r"\s+", "", text.lower())
    if len(norm) < 3:
        return {norm} if norm else set()
    return {norm[i:i + 3] for i in range(len(norm) - 2)}


def _sim(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / float(min(len(a), len(b)))


def _layer_files(layer: str) -> list:
    if layer == "core":
        return [p for p in (MEMORY_ROOT / "MEMORY.md", MEMORY_ROOT / "USER.md")
                if p.is_file()]
    if layer == "insights":
        return [INSIGHTS_PATH] if INSIGHTS_PATH.is_file() else []
    base = _LAYER_DIRS.get(layer)
    if base is None or not base.is_dir():
        return []
    return sorted(base.rglob("*.md"))


def parse_entries(path: Path, layer: str) -> list:
    """Split one layer file into entries (``## `` sections).

    An entry is a heading section; the preamble before the first
    heading counts as one entry when non-empty. The ``odmem``
    trailer, when present, is parsed into ``meta`` and stripped
    from the searchable body.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        logger.exception("oneday_memory: read failed %s", path)
        return []
    rel = str(path.relative_to(MEMORY_ROOT)) if path.is_relative_to(
        MEMORY_ROOT) else path.name
    chunks = []
    matches = list(_HEADING_RE.finditer(text))
    if not matches:
        if text.strip():
            chunks.append(("(file)", text))
    else:
        preamble = text[:matches[0].start()]
        if preamble.strip():
            chunks.append(("(file head)", preamble))
        for i, m in enumerate(matches):
            end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
            chunks.append((m.group(1), text[m.end():end]))
    entries = []
    for n, (title, body) in enumerate(chunks, start=1):
        meta = {}
        m = _ODMEM_RE.search(body)
        if m:
            meta = _parse_odmem(m.group(1))
            body = (body[:m.start()] + body[m.end():]).strip()
        entry_id = meta.get("id") or "%s#%d" % (rel, n)
        entries.append({
            "id": entry_id,
            "title": title.strip(),
            "body": body.strip(),
            "layer": layer,
            "file": rel,
            "meta": meta,
            "plain": not meta,
        })
    return entries


def _all_entries() -> list:
    out = []
    for layer in LAYERS:
        if layer == "insights":
            continue  # ledger rows are served by insights_list(), not search
        for path in _layer_files(layer):
            out.extend(parse_entries(path, layer))
    return out


# ---------------------------------------------------------------- heat

def _load_heat() -> dict:
    try:
        data = json.loads(HEAT_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_heat(heat: dict) -> None:
    _STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = HEAT_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(heat, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, HEAT_PATH)


def _record_heat(entry_ids: list) -> None:
    if not entry_ids:
        return
    with _lock:
        heat = _load_heat()
        now = _now_iso()
        for entry_id in entry_ids:
            row = heat.get(entry_id) or {"count": 0, "last": None}
            row["count"] = int(row.get("count", 0)) + 1
            row["last"] = now
            heat[entry_id] = row
        try:
            _save_heat(heat)
        except Exception:
            logger.exception("oneday_memory: heat save failed")


def _heat_weight(heat: dict, entry_id: str) -> float:
    row = heat.get(entry_id)
    if not row:
        return 1.0
    return 1.0 + math.log1p(max(0, int(row.get("count", 0)))) * 0.25


# Recency (spec section 3.3): exponential decay on the entry's age with
# a 30-day half-life -- memory entries are long-lived, so a month-scale
# half-life separates "this week" from "last quarter" without burying
# older facts that are still the only record.  The 0.2 floor keeps very
# old entries findable: recency downweights, it never zeroes a hit out.
RECENCY_HALF_LIFE_DAYS = 30.0
RECENCY_FLOOR = 0.2


def _parse_dateish(raw) -> float | None:
    """Best-effort epoch seconds for odmem date fields (YYYY-MM-DD or
    ISO datetime); naive values are read as UTC."""
    if not raw or not isinstance(raw, str):
        return None
    raw = raw.strip()
    if not raw or raw == "-":
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def _entry_timestamp(entry: dict, mtime_cache: dict) -> float | None:
    """Timestamp for recency, in priority order: the entry's odmem
    ``last`` (last confirmed), then ``first``; for journal files the
    date in the file name; finally the file's mtime."""
    meta = entry.get("meta") or {}
    for key in ("last", "first"):
        ts = _parse_dateish(meta.get(key))
        if ts is not None:
            return ts
    name = Path(entry.get("file") or "").name
    m = re.match(r"(\d{4}-\d{2}-\d{2})", name)
    if m:
        ts = _parse_dateish(m.group(1))
        if ts is not None:
            return ts
    rel = entry.get("file")
    if rel:
        if rel not in mtime_cache:
            try:
                mtime_cache[rel] = (MEMORY_ROOT / rel).stat().st_mtime
            except Exception:
                mtime_cache[rel] = None
        return mtime_cache[rel]
    return None


def _recency_weight(ts: float | None, now: float) -> float:
    """floor + (1 - floor) * 0.5 ** (age_days / half_life).  An entry
    whose age cannot be determined is neutral (1.0): unknown age must
    neither boost nor bury it."""
    if ts is None:
        return 1.0
    age_days = max(0.0, (now - ts) / 86400.0)
    return RECENCY_FLOOR + (1.0 - RECENCY_FLOOR) * (
        0.5 ** (age_days / RECENCY_HALF_LIFE_DAYS))


# ---------------------------------------------------------------- reads

def list_layers() -> dict:
    """Layer inventory for the app surface and verify probes."""
    layers = []
    for layer in LAYERS:
        files = _layer_files(layer)
        total_bytes = 0
        newest = None
        for p in files:
            try:
                st = p.stat()
            except Exception:
                continue
            total_bytes += st.st_size
            mt = datetime.fromtimestamp(
                st.st_mtime, tz=timezone.utc).isoformat().replace("+00:00", "Z")
            if newest is None or mt > newest:
                newest = mt
        if layer == "insights":
            rows = insights_list()
            entries_n, with_meta = len(rows), len(rows)
        else:
            entries = []
            for p in files:
                entries.extend(parse_entries(p, layer))
            entries_n = len(entries)
            with_meta = sum(1 for e in entries if not e["plain"])
        layers.append({
            "layer": layer,
            "files": len(files),
            "entries": entries_n,
            "bytes": total_bytes,
            "newest_mtime": newest,
            "provenance_coverage": (
                round(with_meta / entries_n, 3) if entries_n else None),
        })
    return {"object": "oneday_memory.layers", "layers": layers}


def search(query: str, limit: int = 20, include_retired: bool = False) -> dict:
    """Entry-level search: trigram overlap x heat x recency.

    Recency is the exponential age decay in _recency_weight (30-day
    half-life, floor 0.2, timestamps per _entry_timestamp); each hit
    echoes its recency factor alongside the composed score."""
    q = _trigrams(query or "")
    if not q:
        return {"object": "oneday_memory.search", "query": query, "hits": []}
    heat = _load_heat()
    now = time.time()
    mtime_cache: dict = {}
    hits = []
    for entry in _all_entries():
        status = (entry["meta"].get("status") or "active").lower()
        if status in _RETIRED_STATUSES and not include_retired:
            continue
        score = _sim(q, _trigrams(entry["title"] + "\n" + entry["body"]))
        if score <= 0:
            continue
        score *= _heat_weight(heat, entry["id"])
        recency = _recency_weight(_entry_timestamp(entry, mtime_cache), now)
        score *= recency
        hits.append({
            "id": entry["id"],
            "title": entry["title"],
            "layer": entry["layer"],
            "file": entry["file"],
            "score": round(score, 4),
            "recency": round(recency, 4),
            "snippet": entry["body"][:280],
            "meta": entry["meta"],
            "plain": entry["plain"],
        })
    hits.sort(key=lambda h: h["score"], reverse=True)
    hits = hits[:max(1, min(int(limit or 20), 100))]
    _record_heat([h["id"] for h in hits])
    return {"object": "oneday_memory.search", "query": query, "hits": hits}


def reconcile_check(text: str, layer: str = None, limit: int = 5) -> dict:
    """Mem0-style mechanical reconciliation (suggestion only).

    Ranks active entries by trigram similarity to the candidate and
    maps the best score onto a suggested pipeline action; the
    distilling agent makes the semantic ADD/UPDATE/SUPERSEDE/NOOP
    verdict (spec section 3.2, stage 3 of the nightly pipeline).
    """
    cand = _trigrams(text or "")
    if not cand:
        return {"object": "oneday_memory.reconcile", "suggestion": "add",
                "candidates": []}
    ranked = []
    for entry in _all_entries():
        if layer and entry["layer"] != layer:
            continue
        status = (entry["meta"].get("status") or "active").lower()
        if status in _RETIRED_STATUSES:
            continue
        sim = _sim(cand, _trigrams(entry["title"] + "\n" + entry["body"]))
        if sim > 0:
            ranked.append({"id": entry["id"], "title": entry["title"],
                           "layer": entry["layer"], "file": entry["file"],
                           "similarity": round(sim, 4)})
    ranked.sort(key=lambda r: r["similarity"], reverse=True)
    ranked = ranked[:max(1, min(int(limit or 5), 20))]
    best = ranked[0]["similarity"] if ranked else 0.0
    if best >= 0.55:
        suggestion = "update_candidate"
    elif best >= 0.30:
        suggestion = "review"
    else:
        suggestion = "add"
    return {"object": "oneday_memory.reconcile", "suggestion": suggestion,
            "candidates": ranked}


# ---------------------------------------------------------------- insights

def _read_jsonl(path: Path) -> list:
    rows = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return rows
    except Exception:
        logger.exception("oneday_memory: jsonl read failed %s", path)
        return rows
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def insights_list() -> list:
    """The full insight ledger (ExpeL-style rule governance)."""
    return _read_jsonl(INSIGHTS_PATH)


def insight_apply(op: dict) -> dict:
    """Apply one governance op to the insight ledger.

    Ops: ``add`` (new candidate row), ``upvote`` / ``downvote``
    (vote + relapse bookkeeping), ``retire``. Status transitions are
    deterministic: a candidate with votes_up >= 2 becomes active; a
    row whose downvotes exceed upvotes by 2+ is retired. The ledger
    file is rewritten atomically; RULES.md sync stays the agent's
    job (the ledger is the governance account, RULES the text
    source of truth -- spec section 3.6).
    """
    if not isinstance(op, dict):
        return {"ok": False, "error": "op must be an object"}
    action = op.get("op")
    rows = insights_list()
    now = _now_iso()
    if action == "add":
        rule = (op.get("rule") or "").strip()
        if not rule:
            return {"ok": False, "error": "rule required"}
        rid = op.get("id") or "ins-%s-%s" % (
            now.replace(":", "").replace("-", "").replace(".", "")[:15],
            uuid.uuid4().hex[:6])
        if any(r.get("id") == rid for r in rows):
            return {"ok": False, "error": "duplicate id"}
        rows.append({
            "id": rid, "rule": rule, "scope": op.get("scope") or "general",
            "votes_up": 0, "votes_down": 0, "relapse_count": 0,
            "status": "candidate", "src": op.get("src") or "",
            "first": now, "last": now,
        })
        result = {"ok": True, "id": rid, "status": "candidate"}
    elif action in ("upvote", "downvote", "retire"):
        rid = op.get("id")
        row = next((r for r in rows if r.get("id") == rid), None)
        if row is None:
            return {"ok": False, "error": "unknown id"}
        if action == "upvote":
            row["votes_up"] = int(row.get("votes_up", 0)) + 1
            if op.get("relapse"):
                row["relapse_count"] = int(row.get("relapse_count", 0)) + 1
        elif action == "downvote":
            row["votes_down"] = int(row.get("votes_down", 0)) + 1
        else:
            row["status"] = "retired"
        row["last"] = now
        if row.get("status") == "candidate" and int(
                row.get("votes_up", 0)) >= 2:
            row["status"] = "active"
        if (row.get("status") != "retired"
                and int(row.get("votes_down", 0))
                >= int(row.get("votes_up", 0)) + 2):
            row["status"] = "retired"
        result = {"ok": True, "id": rid, "status": row.get("status")}
    else:
        return {"ok": False, "error": "unknown op"}
    with _lock:
        INSIGHTS_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = INSIGHTS_PATH.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, INSIGHTS_PATH)
    return result


# ---------------------------------------------------------------- sweep

def _decay_heat(factor: float = 0.9) -> int:
    with _lock:
        heat = _load_heat()
        for row in heat.values():
            row["count"] = int(int(row.get("count", 0)) * factor)
        heat = {k: v for k, v in heat.items() if int(v.get("count", 0)) > 0}
        try:
            _save_heat(heat)
        except Exception:
            logger.exception("oneday_memory: heat decay save failed")
        return len(heat)


def _regen_index() -> dict:
    inv = list_layers()
    lines = [
        "# OneDay 记忆索引（模块自动再生，勿手改本文件）",
        "",
        "再生态：oneday_memory 清扫线程；正文真源在各层文件。",
        "",
        "| 层 | 文件 | 条目 | 字节 | 溯源覆盖 | 最近更新 |",
        "|---|---|---|---|---|---|",
    ]
    for row in inv["layers"]:
        cov = row["provenance_coverage"]
        lines.append("| %s | %d | %d | %d | %s | %s |" % (
            row["layer"], row["files"], row["entries"], row["bytes"],
            "-" if cov is None else "%.0f%%" % (cov * 100),
            row["newest_mtime"] or "-"))
    lines.append("")
    SUBTREE.mkdir(parents=True, exist_ok=True)
    tmp = INDEX_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, INDEX_PATH)
    return {"layers": len(inv["layers"])}


def admission_audit() -> dict:
    """Voyager-admission bookkeeping audit: skills/ vs the ledger.

    A skill directory counts as registered when the ledger holds a
    row with its name and a non-empty verify record. The audit only
    reports; admission itself is the skill procedure's job and the
    write-time hard gate is a registered blocker (spec section 3.6).
    """
    registered = {}
    for row in _read_jsonl(ADMISSION_PATH):
        name = row.get("skill")
        if name:
            registered[name] = row
    on_disk = []
    if SKILLS_DIR.is_dir():
        for child in sorted(SKILLS_DIR.iterdir()):
            if child.is_dir() and (child / "SKILL.md").is_file():
                on_disk.append(child.name)
            elif child.is_file() and child.suffix == ".md":
                on_disk.append(child.stem)
    unregistered = [n for n in on_disk if n not in registered]
    unverified = [n for n in on_disk
                  if n in registered
                  and not (registered[n].get("verify") or {}).get("evidence")]
    stale = [n for n in registered if n not in on_disk]
    report = {
        "object": "oneday_memory.admission_audit",
        "at": _now_iso(),
        "skills_on_disk": len(on_disk),
        "registered": len(registered),
        "unregistered": unregistered,
        "unverified": unverified,
        "stale_records": stale,
    }
    with _lock:
        _STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = ADMISSION_AUDIT_PATH.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, ADMISSION_AUDIT_PATH)
    return report


def sweep_once() -> dict:
    """One mechanical upkeep pass (no memory content is edited)."""
    return {
        "heat_entries": _decay_heat(),
        "index": _regen_index(),
        "admission": admission_audit(),
    }


def start() -> None:
    """Lazy-start the hourly sweep thread (idempotent)."""
    global _sweep_started
    with _lock:
        if _sweep_started:
            return
        _sweep_started = True

    def _loop():
        while True:
            try:
                sweep_once()
            except Exception:
                logger.exception("oneday_memory: sweep failed")
            threading.Event().wait(3600)

    threading.Thread(target=_loop, name="oneday-memory-sweep",
                     daemon=True).start()
    logger.info("oneday_memory: sweep thread started")


# ---------------------------------------------------------------- CLI

def _main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="oneday_memory")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_search = sub.add_parser("search")
    p_search.add_argument("query")
    p_search.add_argument("--limit", type=int, default=20)
    p_search.add_argument("--include-retired", action="store_true")
    p_rec = sub.add_parser("reconcile")
    p_rec.add_argument("text")
    p_rec.add_argument("--layer", default=None)
    p_ins = sub.add_parser("insight")
    p_ins.add_argument("op_json")
    sub.add_parser("layers")
    sub.add_parser("sweep")
    args = parser.parse_args(argv)
    if args.cmd == "search":
        out = search(args.query, limit=args.limit,
                     include_retired=args.include_retired)
    elif args.cmd == "reconcile":
        out = reconcile_check(args.text, layer=args.layer)
    elif args.cmd == "insight":
        out = insight_apply(json.loads(args.op_json))
    elif args.cmd == "layers":
        out = list_layers()
    else:
        out = sweep_once()
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
