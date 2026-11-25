"""OneDay semantic memory recall -- gateway service module (local
patch, hermes-deploy DESIGN section 445).

Companion to oneday_memory (section 439). That module's search is
character-trigram overlap x heat: strong on literal recall, blind to
paraphrase -- a query whose wording shares no 3-gram with the entry
("what does my wife avoid eating" vs an entry that says she never
touches cilantro) scores exactly zero. This module closes the gap
registered as section 436 item M5 / the section 439 follow-up:

- Every entry of the SAME layered Markdown memory (parsed by
  oneday_memory, same ids, same provenance trailers) is embedded
  with a LOCAL model -- fastembed + BAAI/bge-small-zh-v1.5 (512-dim
  ONNX, ~91 MB, fetched once at install time). Inference is fully
  on-box: no memory text ever leaves the instance, no API key, no
  per-call cost. Upstream external providers were evaluated and
  rejected for this job (selection record in
  semsearch-spec-20261124.md): RetainDB's Hermes plugin is a cloud
  API with its own store, ByteRover keeps its own knowledge tree --
  neither indexes these files, and section 439's dead-line is that
  the files are the memory and there is no second store.
- The vectors live in ONE machine sidecar next to the other section
  439 state (memories/oneday/state/semantic_index.json): entry id ->
  {text hash, vector}. It is a pure cache: human-readable, safe to
  delete, rebuilt incrementally -- an entry is re-embedded only when
  its title+body hash changes; vanished ids are dropped.
- Recall is HYBRID, never a replacement: trigram and semantic
  scores are fused (0.55 literal / 0.45 semantic by default) and
  multiplied by the same heat weight AND the same recency decay
  oneday_memory uses -- recency is imported from oneday_memory
  (_entry_timestamp / _recency_weight, 30-day half-life, floor
  0.2), never re-implemented here, so the keyword and hybrid
  routes can never drift apart on age weighting (merge condition
  of hermes-deploy 1.14.0, user ruling 2026-11-24). A literal
  guard keeps a strong literal hit (trigram sim >= 0.5) ranked
  above every purely-semantic hit. Probes showed a raw embedding
  model alone ranks a fluent paraphrase ABOVE the literal source
  entry (0.51 vs 0.42), which is exactly the failure the guard
  exists to prevent.
- Hits carry the same provenance as oneday_memory.search (entry id,
  layer, file, odmem trailer) plus a per-route score breakdown, so
  a caller can see WHY an entry surfaced.

Degradation contract (same shape as section 439): if fastembed or
the model is unavailable, the module still imports and answers with
a deterministic char-ngram hashing embedder, clearly flagged
``degraded: true`` -- paraphrase recall is then NOT guaranteed and
status() says so. Nothing outside the memory surface reads this
module; the section 439 search handler dispatches to it only when
the caller asks for mode=semantic|hybrid.

Runnable as a CLI inside the container:
``python3 oneday_semantic.py reindex|hybrid|semantic|status``.
"""

import hashlib
import json
import logging
import math
import os
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

try:  # gateway layout (patches mounted into gateway/platforms/)
    from gateway.platforms import oneday_memory as om
except Exception:  # standalone / selftest layout (same directory)
    import oneday_memory as om

logger = logging.getLogger("gateway.platforms.oneday_semantic")

MODEL_NAME = os.environ.get("ONEDAY_SEM_MODEL", "BAAI/bge-small-zh-v1.5")
BACKEND = os.environ.get("ONEDAY_SEM_BACKEND", "auto")  # auto|fastembed|hash
SEM_MIN = float(os.environ.get("ONEDAY_SEM_MIN", "0.40"))
W_TRI = float(os.environ.get("ONEDAY_SEM_W_TRI", "0.55"))
W_SEM = float(os.environ.get("ONEDAY_SEM_W_SEM", "0.45"))
GUARD_TRI = 0.5  # trigram sim at/above this = strong literal hit

INDEX_PATH = om._STATE_DIR / "semantic_index.json"
_STATE_DIR = om._STATE_DIR

_lock = threading.RLock()
_embedder = None
_embedder_failed = False


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")


def _embed_text(entry: dict) -> str:
    return entry["title"] + "\n" + entry["body"]


# Cap on the text actually handed to an embedder (1.15.0 calibration).
# The model window is 512 tokens, so the head of an entry carries the
# recall signal; the uncapped tail is pure hazard -- the production
# corpus contains parser mega-entries (bank/reflections.md#1 is a
# single ~8.8M-char entry), and tokenizing one such text ballooned an
# embedding worker past 1.4 GB RSS into the cgroup OOM killer. Change
# detection (_text_hash) deliberately keeps hashing the FULL text, so
# edits beyond the cap still trigger re-embedding.
EMBED_TEXT_MAX = 2000


def _embed_input(entry: dict) -> str:
    return _embed_text(entry)[:EMBED_TEXT_MAX]


def _text_hash(entry: dict) -> str:
    return hashlib.sha256(_embed_text(entry).encode("utf-8")).hexdigest()


# ---------------------------------------------------------------- embedders

class _HashEmbedder:
    """Deterministic char-ngram hashing embedder (degraded fallback).

    No model, no dependency, cosine of identical text is 1.0 -- but
    it has NO paraphrase ability; it exists so the module degrades
    loudly instead of dying when the real model is missing.
    """

    name = "hash"
    model = "char-ngram-hashing"
    dim = 256
    degraded = True

    def _vec(self, text: str) -> list:
        vec = [0.0] * self.dim
        grams = om._trigrams(text)
        for g in grams:
            h = hashlib.sha256(g.encode("utf-8")).digest()
            idx = int.from_bytes(h[:2], "little") % self.dim
            vec[idx] += 1.0 if h[2] % 2 == 0 else -1.0
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        return [v / norm for v in vec]

    def embed(self, texts: list) -> list:
        return [self._vec(t) for t in texts]

    def embed_query(self, text: str) -> list:
        return self._vec(text)


class _FastEmbedEmbedder:
    """Local ONNX embedding via fastembed (bge-small-zh by default)."""

    name = "fastembed"
    degraded = False

    def __init__(self, model_name: str):
        # Memory discipline (1.14.0 apply-day fix): the production
        # corpus is ~3250 entries and the gateway container is capped
        # at 2 GiB -- fastembed's default multi-session parallel embed
        # ballooned a full-corpus build to ~1.26 GiB RSS and the
        # cgroup OOM-killed it. Cap threads and embed in small chunks
        # on a single session; semantics are unchanged.
        os.environ.setdefault("OMP_NUM_THREADS", "2")
        # Offline discipline (1.14.0 apply-day fix 2): the model
        # snapshot is an install-time artifact (install 3e pre-fetches
        # it through the HF mirror, constructing TextEmbedding
        # directly, never via this module). At runtime, huggingface
        # hub's online etag check hangs for minutes on this host's
        # stalled route to huggingface.co -- cache-warm builds sat at
        # ~0% CPU indefinitely, while HF_HUB_OFFLINE=1 resolves the
        # cached snapshot in <1s (both measured on production).
        # Runtime therefore never touches the network for model
        # resolution; a missing cache fails fast and the module
        # degrades loudly to the hashing embedder instead of hanging
        # a search request. HF_ENDPOINT stays as the mirror for any
        # embedding-library fetch path that honours it.
        os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
        # Import-path discipline (1.15.0 fix): the deployment installs
        # fastembed into a plain target dir (ONEDAY_SEM_PKG_DIR, default
        # /opt/data/python-packages), but the gateway process cannot see
        # it via PYTHONPATH -- the Hermes venv launcher runs python -P
        # and unsets PYTHONPATH/PYTHONHOME, keeping only its own repo +
        # site-packages. 1.14.0 wired PYTHONPATH into the compose env,
        # which the supervised gateway never honours (only ad-hoc
        # `docker exec` shells do), so in-gateway resolution fell back
        # to the degraded hashing embedder and overwrote the good
        # fastembed index. Put the target dir on sys.path directly --
        # valid in every interpreter this module runs under.
        pkg_dir = os.environ.get("ONEDAY_SEM_PKG_DIR",
                                 "/opt/data/python-packages")
        if pkg_dir and os.path.isdir(pkg_dir) and pkg_dir not in sys.path:
            sys.path.insert(0, pkg_dir)
        from fastembed import TextEmbedding

        self.model = model_name
        cache_dir = os.environ.get("ONEDAY_SEM_CACHE") or None
        kwargs = {"model_name": model_name}
        if cache_dir:
            kwargs["cache_dir"] = cache_dir
        try:
            self._model = TextEmbedding(threads=2, **kwargs)
        except TypeError:
            self._model = TextEmbedding(**kwargs)
        self.dim = None  # learned from the first vector

    def embed(self, texts: list) -> list:
        out = []
        for i in range(0, len(texts), 64):
            chunk = texts[i:i + 64]
            # Process-pool embedding, small batches (1.15.0 calibration;
            # both failure modes measured on apply day in this 2 GiB
            # container): fastembed's pool serves each embed() call from
            # a fresh worker, so the ONNX memory arena -- which grows
            # monotonically across calls in a long-lived process --
            # resets every call. In-process embedding (parallel=None)
            # accumulated the arena to ~1.9 GB over a full-corpus build
            # and was OOM-killed; a pool worker at batch_size=64 was
            # likewise OOM-killed (~780 MB RSS, caller left blocked on
            # the pool pipe). parallel=1 + batch_size=16 keeps the
            # worker's transient footprint in bounds.
            try:
                vecs = list(self._model.embed(chunk, batch_size=16,
                                              parallel=1))
            except TypeError:
                vecs = list(self._model.embed(chunk, batch_size=16))
            out.extend([float(x) for x in v] for v in vecs)
        if out and self.dim is None:
            self.dim = len(out[0])
        return out

    def embed_query(self, text: str) -> list:
        fn = getattr(self._model, "query_embed", None)
        if fn is not None:
            vec = [float(x) for x in next(iter(fn(text)))]
        else:
            vec = self.embed([text])[0]
        if self.dim is None:
            self.dim = len(vec)
        return vec


def _get_embedder():
    """Resolve the configured embedder once (lazy, thread-safe)."""
    global _embedder, _embedder_failed
    with _lock:
        if _embedder is not None:
            return _embedder
        if BACKEND in ("auto", "fastembed") and not _embedder_failed:
            try:
                _embedder = _FastEmbedEmbedder(MODEL_NAME)
                logger.info("oneday_semantic: embedder=fastembed model=%s",
                            MODEL_NAME)
                return _embedder
            except Exception:
                _embedder_failed = True
                logger.exception(
                    "oneday_semantic: fastembed unavailable, "
                    "falling back to degraded hashing embedder")
                if BACKEND == "fastembed":
                    raise
        _embedder = _HashEmbedder()
        return _embedder


def _cosine(a: list, b: list) -> float:
    dot = 0.0
    na = 0.0
    nb = 0.0
    for x, y in zip(a, b):
        dot += x * y
        na += x * x
        nb += y * y
    if na <= 0.0 or nb <= 0.0:
        return 0.0
    return dot / (math.sqrt(na) * math.sqrt(nb))


# ---------------------------------------------------------------- index

def _load_index() -> dict:
    try:
        data = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("entries"), dict):
            return data
    except Exception:
        pass
    return {"version": 1, "model": None, "backend": None, "dim": None,
            "built_at": None, "entries": {}}


def _save_index(index: dict) -> None:
    _STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = INDEX_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, INDEX_PATH)


def ensure_index() -> dict:
    """Bring the vector sidecar in sync with the layered files.

    Incremental: only entries whose title+body hash changed (or
    whose stored vector belongs to another model/backend) are
    re-embedded; ids that vanished from the files are dropped.
    """
    embedder = _get_embedder()
    entries = om._all_entries()
    current = {}
    for entry in entries:  # duplicate ids: last wins, as in heat ledger
        current[entry["id"]] = entry
    with _lock:
        index = _load_index()
        stored = index.get("entries") or {}
        same_model = (index.get("model") == embedder.model
                      and index.get("backend") == embedder.name)
        if not same_model:
            stored = {}
        todo = []
        for entry_id, entry in current.items():
            row = stored.get(entry_id)
            if row is None or row.get("h") != _text_hash(entry):
                todo.append(entry)
        dropped = [i for i in stored if i not in current]
        embedded = 0
        for i in range(0, len(todo), 256):
            part = todo[i:i + 256]
            vectors = embedder.embed([_embed_input(e) for e in part])
            for entry, vec in zip(part, vectors):
                stored[entry["id"]] = {
                    "h": _text_hash(entry),
                    "v": [round(float(x), 6) for x in vec],
                }
            embedded += len(part)
        for entry_id in dropped:
            stored.pop(entry_id, None)
        if todo or dropped or not same_model:
            index = {"version": 1, "model": embedder.model,
                     "backend": embedder.name,
                     "dim": embedder.dim, "built_at": _now_iso(),
                     "entries": stored}
            _save_index(index)
        return {"entries": len(stored), "embedded": embedded,
                "dropped": len(dropped), "backend": embedder.name,
                "model": embedder.model, "dim": embedder.dim,
                "degraded": bool(getattr(embedder, "degraded", False))}


# ---------------------------------------------------------------- ranking

def _fuse(tri: float, sem: float) -> float:
    """Weighted fusion of the two recall routes (pre-heat)."""
    return W_TRI * tri + W_SEM * max(0.0, sem)


def _final(row: dict) -> float:
    """Composed score: fusion x heat x recency (section 439 order).

    Recency comes from oneday_memory's own implementation; rows
    built by hand (unit tests) may omit it and default to the same
    neutral 1.0 _recency_weight gives an unknown age.
    """
    return (_fuse(row["trigram"], row["semantic"]) * row["heat"]
            * row.get("recency", 1.0))


def _rank(rows: list) -> list:
    """Order scored rows: literal-guard partition first, then score.

    A row with trigram sim >= GUARD_TRI is a strong literal hit; it
    must never be pushed below a purely-semantic hit (probes showed
    the raw model doing exactly that to the literal source entry).
    Pure function of its input -- unit-testable without a model.
    """
    def key(row):
        return (0 if row["trigram"] >= GUARD_TRI else 1, -_final(row))

    return sorted(rows, key=key)


def _candidates(include_retired: bool) -> list:
    out = []
    for entry in om._all_entries():
        status = (entry["meta"].get("status") or "active").lower()
        if status in om._RETIRED_STATUSES and not include_retired:
            continue
        out.append(entry)
    return out


def _score_rows(query: str, include_retired: bool) -> list:
    entries = _candidates(include_retired)
    if not entries:
        return []
    ensure_index()
    embedder = _get_embedder()
    index = _load_index()
    stored = index.get("entries") or {}
    qvec = embedder.embed_query(query)
    q = om._trigrams(query or "")
    heat = om._load_heat()
    now = time.time()
    mtime_cache: dict = {}
    rows = []
    for entry in entries:
        tri = om._sim(q, om._trigrams(_embed_text(entry))) if q else 0.0
        row = stored.get(entry["id"])
        sem = _cosine(qvec, row["v"]) if row and row.get("v") else 0.0
        recency = om._recency_weight(
            om._entry_timestamp(entry, mtime_cache), now)
        rows.append({"entry": entry, "trigram": tri, "semantic": sem,
                     "heat": om._heat_weight(heat, entry["id"]),
                     "recency": recency})
    return rows


def _hits(rows: list, limit: int) -> list:
    hits = []
    for row in rows[:max(1, min(int(limit or 20), 100))]:
        entry = row["entry"]
        routes = []
        if row["trigram"] > 0:
            routes.append("trigram")
        if row["semantic"] >= SEM_MIN:
            routes.append("semantic")
        hits.append({
            "id": entry["id"],
            "title": entry["title"],
            "layer": entry["layer"],
            "file": entry["file"],
            "score": round(_final(row), 4),
            "recency": round(row.get("recency", 1.0), 4),
            "scores": {"trigram": round(row["trigram"], 4),
                       "semantic": round(row["semantic"], 4),
                       "heat": round(row["heat"], 4),
                       "recency": round(row.get("recency", 1.0), 4)},
            "routes": routes,
            "guarded": row["trigram"] >= GUARD_TRI,
            "snippet": entry["body"][:280],
            "meta": entry["meta"],
            "plain": entry["plain"],
        })
    return hits


# ---------------------------------------------------------------- reads

def hybrid_search(query: str, limit: int = 20,
                  include_retired: bool = False) -> dict:
    """Hybrid recall: trigram + semantic fused, heat- and
    recency-weighted (oneday_memory's own factors), literal-guarded.
    Same envelope as oneday_memory.search."""
    rows = [r for r in _score_rows(query, include_retired)
            if r["trigram"] > 0 or r["semantic"] >= SEM_MIN]
    hits = _hits(_rank(rows), limit)
    om._record_heat([h["id"] for h in hits])
    return {"object": "oneday_memory.search", "mode": "hybrid",
            "query": query, "hits": hits}


def semantic_search(query: str, limit: int = 20,
                    include_retired: bool = False) -> dict:
    """Pure semantic recall (diagnostics / comparison surface)."""
    rows = [r for r in _score_rows(query, include_retired)
            if r["semantic"] >= SEM_MIN]
    rows.sort(key=lambda r: -(_fuse(0.0, r["semantic"]) * r["heat"]
                              * r.get("recency", 1.0)))
    hits = _hits(rows, limit)
    om._record_heat([h["id"] for h in hits])
    return {"object": "oneday_memory.search", "mode": "semantic",
            "query": query, "hits": hits}


def status() -> dict:
    index = _load_index()
    try:
        size = INDEX_PATH.stat().st_size
    except Exception:
        size = 0
    embedder = _embedder
    return {
        "object": "oneday_memory.semantic_status",
        "model": index.get("model") or MODEL_NAME,
        "backend": index.get("backend"),
        "dim": index.get("dim"),
        "indexed_entries": len(index.get("entries") or {}),
        "index_bytes": size,
        "built_at": index.get("built_at"),
        "index_path": str(INDEX_PATH),
        "sem_min": SEM_MIN,
        "weights": {"trigram": W_TRI, "semantic": W_SEM},
        "recency": {"half_life_days": om.RECENCY_HALF_LIFE_DAYS,
                    "floor": om.RECENCY_FLOOR},
        "guard_tri": GUARD_TRI,
        "degraded": (bool(getattr(embedder, "degraded", False))
                     if embedder is not None else None),
    }


# ---------------------------------------------------------------- CLI

def _main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="oneday_semantic")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("reindex")
    sub.add_parser("status")
    for name in ("hybrid", "semantic"):
        p = sub.add_parser(name)
        p.add_argument("query")
        p.add_argument("--limit", type=int, default=20)
        p.add_argument("--include-retired", action="store_true")
    args = parser.parse_args(argv)
    if args.cmd == "reindex":
        out = ensure_index()
    elif args.cmd == "status":
        out = status()
    elif args.cmd == "hybrid":
        out = hybrid_search(args.query, limit=args.limit,
                            include_retired=args.include_retired)
    else:
        out = semantic_search(args.query, limit=args.limit,
                              include_retired=args.include_retired)
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
