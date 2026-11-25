#!/usr/bin/env python3
"""Deploy-time one-off (companion 1.0.34): give every
non-terminal idea card a category.

Reads the bridge data file, classifies the pending cards
that carry no legal category (model pass -> keyword rules
-> "other"; see scripts/idea_category_backfill.py), writes
the values back atomically and leaves the full per-card
ledger in meta.ideasCategoryBackfill of the same file.

MUST run while the oneday bridge process is stopped (the
bridge holds the store in memory and would overwrite the
file on its next save). The deploy runs it between the old
container's stop and the new container's start.

Credentials: HERMES_API_KEY / HERMES_BASE_URL come from the
process env, else from the mounted companion.env file (the
same file the supervisor distributes by segment). Values
are never printed.
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
for cand in (os.path.join(HERE, "scripts"), HERE):
    if cand not in sys.path:
        sys.path.insert(0, cand)

from idea_category_backfill import (CATEGORIES, classify_cards,
                                    is_backfill_target)

GEN_MODEL = "deepseek-flash"
POLL_SECONDS = 5
TIMEOUT_SECONDS = 300


def _env_file_value(path: str, key: str):
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith(key + "="):
                    return line[len(key) + 1:].strip()
    except OSError:
        pass
    return None


def _http_json(url, method="GET", body=None, headers=None,
               timeout=30):
    data = None
    hdrs = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=hdrs,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, raw
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, f"{type(e).__name__}: {e}"


def _make_model_fn(base_url: str, api_key: str):
    def call(prompt: str):
        headers = {"Authorization": f"Bearer {api_key}",
                   "Idempotency-Key":
                       f"ideas-cat-backfill-{int(time.time())}"}
        status, raw = _http_json(
            base_url + "/v1/runs", method="POST",
            body={"input": prompt, "model": GEN_MODEL},
            headers=headers, timeout=60)
        run_id = None
        try:
            payload = json.loads(raw)
            if status in (200, 201, 202) \
                    and isinstance(payload, dict):
                run_id = payload.get("run_id")
        except Exception:
            run_id = None
        if not run_id:
            raise RuntimeError(f"submit failed HTTP {status}")
        deadline = time.time() + TIMEOUT_SECONDS
        while time.time() < deadline:
            status, raw = _http_json(
                base_url + f"/v1/runs/{run_id}",
                headers={"Authorization": f"Bearer {api_key}"},
                timeout=30)
            if status == 200:
                try:
                    payload = json.loads(raw)
                except Exception:
                    payload = None
                if isinstance(payload, dict):
                    state = str(payload.get("status", ""))
                    if state == "completed":
                        return str(payload.get("output") or "")
                    if state in ("failed", "cancelled",
                                 "interrupted"):
                        raise RuntimeError(f"run {state}")
                    if state == "waiting_for_approval":
                        _http_json(
                            base_url + f"/v1/runs/{run_id}/stop",
                            method="POST", body={},
                            headers={
                                "Authorization":
                                    f"Bearer {api_key}"},
                            timeout=30)
                        raise RuntimeError(
                            "run hit an approval gate; stopped")
            time.sleep(POLL_SECONDS)
        raise RuntimeError("run timeout")
    return call


def main(argv) -> int:
    data_path = os.environ.get("DATA_PATH",
                               "/opt/oneday-data/data.json")
    env_file = "/opt/companion/companion.env"
    dry_run = "--dry-run" in argv
    for i, a in enumerate(argv):
        if a == "--data" and i + 1 < len(argv):
            data_path = argv[i + 1]
        if a == "--env-file" and i + 1 < len(argv):
            env_file = argv[i + 1]
    with open(data_path, encoding="utf-8") as f:
        data = json.load(f)
    ideas = data.get("ideas")
    if not isinstance(ideas, list):
        print("ERROR: data file has no ideas list")
        return 2
    targets = [i for i in ideas if is_backfill_target(i)]
    print(f"targets: {len(targets)}")
    if not targets:
        print(json.dumps({"total": 0, "model": 0, "rules": 0,
                          "default": 0, "entries": []}))
        return 0
    api_key = os.environ.get("HERMES_API_KEY") or \
        _env_file_value(env_file, "HERMES_API_KEY")
    base_url = (os.environ.get("HERMES_BASE_URL") or
                _env_file_value(env_file, "HERMES_BASE_URL") or
                "https://hermes.example.com").rstrip("/")
    model_fn = _make_model_fn(base_url, api_key) \
        if api_key else None
    if model_fn is None:
        print("note: no HERMES_API_KEY; rules-only pass")
    results = classify_cards(targets, model_fn)
    by_id = {r["id"]: r for r in results}
    counts = {"model": 0, "rules": 0, "default": 0}
    for r in results:
        counts[r["source"]] += 1
    if not dry_run:
        for idea in ideas:
            r = by_id.get(idea.get("id"))
            if r:
                idea["category"] = r["category"]
        meta = data.setdefault("meta", {})
        meta["ideasCategoryBackfill"] = {
            "at": time.time(),
            "total": len(results),
            "counts": counts,
            "entries": results,
        }
        tmp = data_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, data_path)
        try:
            os.chmod(data_path, 0o600)
        except OSError:
            pass
        with open(data_path, encoding="utf-8") as f:
            after = json.load(f)
        remaining = [i for i in after.get("ideas", [])
                     if is_backfill_target(i)]
        bad = [i for i in after.get("ideas", [])
               if i.get("status", "pending") == "pending"
               and i.get("category") not in CATEGORIES]
        print(f"verify: targets remaining={len(remaining)} "
              f"pending without legal category={len(bad)}")
        if remaining or bad:
            print("ERROR: backfill incomplete")
            return 3
    print(json.dumps({"total": len(results), **counts,
                      "entries": results},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
