#!/usr/bin/env python3
"""Selftest for the OneDay semantic-recall module (DESIGN section 445).

Builds a stub memory root in a temp dir with a four-entry corpus
whose score margins were probed against the real model beforehand,
then exercises the section 445 claims end to end:

- incremental vector index over the section 439 layered files
  (embed on change only, drop vanished ids, rebuild from scratch);
- the paraphrase gap is real: pure trigram search (oneday_memory)
  cannot see the diet-taboo entry from a colloquial query, hybrid
  recall surfaces it first, with provenance intact;
- the literal guard: an exact-phrase hit is never displaced by a
  purely-semantic competitor (unit-level on the pure ranker, plus
  an end-to-end exact query);
- retired entries stay hidden by default and surface with
  include_retired, exactly like section 439;
- heat is recorded for hybrid hits (same ledger as section 439);
- recency is a real factor in the fused score (hermes-deploy
  1.14.0 merge condition): two entries with identical text --
  hence identical trigram, semantic and heat -- rank newest
  first, the older one's score discounted by oneday_memory's
  own decay (30-day half-life, floor 0.2);
- the degraded hashing embedder is deterministic (cosine 1.0 on
  identical text) -- it is a fallback, never the graded path.

Requires a Python with fastembed installed and the embedding model
cached (ONEDAY_SEM_CACHE / FASTEMBED_CACHE_PATH): the graded path
is the real local model, per the section 445 selection.

Run: python3 oneday_semantic_selftest.py   (exit 0 = all passed)
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PKG = Path(__file__).resolve().parent
OM_PATH = PKG / "patches" / "oneday_memory.py"
SEM_PATH = PKG / "patches" / "oneday_semantic.py"

CHECKS = []


def check(name, cond, detail=""):
    CHECKS.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name
          + ((" -- " + str(detail)) if detail and not cond else ""))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


WORK_V1 = (
    "## 部署窗口\n"
    "生产部署只在凌晨两点到四点之间进行，其他时段不动。发版前先查服务器内存。\n"
    "<!-- odmem: id=scenes/work#1, first=2026-11-20, last=2026-11-20, "
    "src=user, status=active -->\n\n"
    "## 上线安排\n"
    "夜里没人的时候再把新版本推上去，白天不要动生产环境。\n"
    "<!-- odmem: id=scenes/work#2, first=2026-11-18, last=2026-11-18, "
    "src=user, status=active -->\n")

PEOPLE_V1 = (
    "## 秦源一的饮食禁忌\n"
    "秦源一不吃香菜，点菜时要避开。\n"
    "<!-- odmem: id=people/qinyuanyi#1, first=2026-11-16, "
    "last=2026-11-16, src=user, status=active -->\n\n"
    "## 口味偏好\n"
    "用户喜欢吃辣的火锅，偏好毛肚和黄喉。\n"
    "<!-- odmem: id=people/user#1, first=2026-11-10, last=2026-11-10, "
    "src=user, status=active -->\n")

Q_SEM = "媳妇儿吃饭有什么忌口"
Q_EXACT = "生产部署只在凌晨两点到四点"


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="odsem-stub-"))
    memories = tmp / "memories"
    scenes = memories / "oneday" / "scenes"
    people = memories / "oneday" / "people"
    scenes.mkdir(parents=True)
    people.mkdir(parents=True)
    (scenes / "work.md").write_text(WORK_V1, encoding="utf-8")
    (people / "qinyuanyi.md").write_text(PEOPLE_V1, encoding="utf-8")

    os.environ["ONEDAY_MEMORY_ROOT"] = str(memories)
    om = load("oneday_memory", OM_PATH)
    sem = load("oneday_semantic", SEM_PATH)

    # ---- 1. index build: real model, all four entries ----
    stats = sem.ensure_index()
    check("index: fastembed backend (real model)",
          stats["backend"] == "fastembed" and not stats["degraded"], stats)
    check("index: 4 entries embedded", stats["entries"] == 4
          and stats["embedded"] == 4, stats)
    index_file = memories / "oneday" / "state" / "semantic_index.json"
    check("index: sidecar on disk", index_file.is_file())
    st = sem.status()
    check("index: status reports dim 512 + model",
          st["dim"] == 512 and "bge-small-zh" in (st["model"] or ""), st)

    # ---- 2. the paraphrase gap: keyword route is blind, hybrid sees ----
    kw = om.search(Q_SEM)
    check("gap: trigram search misses the taboo entry",
          "people/qinyuanyi#1" not in [h["id"] for h in kw["hits"]],
          kw["hits"])
    hy = sem.hybrid_search(Q_SEM)
    ids = [h["id"] for h in hy["hits"]]
    check("hybrid: taboo entry ranked first", ids[:1] == ["people/qinyuanyi#1"],
          ids)
    hit = hy["hits"][0]
    check("hybrid: semantic route credited",
          "semantic" in hit["routes"], hit)
    check("hybrid: semantic score clears the bar",
          hit["scores"]["semantic"] >= 0.45, hit["scores"])
    check("hybrid: provenance echoed (src=user)",
          hit["meta"].get("src") == "user"
          and hit["file"] == "oneday/people/qinyuanyi.md", hit)
    if "people/user#1" in ids:
        check("hybrid: taboo outranks mere food preference",
              ids.index("people/qinyuanyi#1") < ids.index("people/user#1"),
              ids)

    # ---- 3. literal guard: exact hit cannot be displaced ----
    hy = sem.hybrid_search(Q_EXACT)
    top = hy["hits"][0] if hy["hits"] else {}
    check("guard: exact-phrase entry ranked first",
          top.get("id") == "scenes/work#1", hy["hits"])
    check("guard: top hit flagged guarded + trigram route",
          top.get("guarded") is True and "trigram" in top.get("routes", []),
          top)
    rows = [{"id": "A", "trigram": 1.0, "semantic": 0.40, "heat": 1.0},
            {"id": "B", "trigram": 0.0, "semantic": 0.95, "heat": 1.0}]
    ranked = sem._rank([dict(r) for r in rows])
    check("guard: pure ranker pins literal hit above semantic-only hit",
          ranked[0]["id"] == "A", ranked)

    # ---- 4. incremental index: change + add, then remove ----
    (people / "qinyuanyi.md").write_text(
        PEOPLE_V1.replace("用户喜欢吃辣的火锅，偏好毛肚和黄喉。",
                          "用户喜欢吃麻辣的串串，偏好牛肉和土豆。"),
        encoding="utf-8")
    (scenes / "work.md").write_text(
        WORK_V1 + "\n## 备份策略\n"
        "服务器每天凌晨自动备份数据库，保留最近七天。\n"
        "<!-- odmem: id=scenes/work#3, first=2026-11-21, "
        "last=2026-11-21, src=user, status=active -->\n",
        encoding="utf-8")
    stats = sem.ensure_index()
    check("incremental: only changed+new re-embedded (2)",
          stats["embedded"] == 2 and stats["dropped"] == 0
          and stats["entries"] == 5, stats)
    (scenes / "work.md").write_text(WORK_V1, encoding="utf-8")
    stats = sem.ensure_index()
    check("incremental: vanished id dropped",
          stats["dropped"] == 1 and stats["entries"] == 4, stats)

    # ---- 5. retired filtering matches section 439 ----
    (scenes / "work.md").write_text(
        WORK_V1.replace("id=scenes/work#2, first=2026-11-18, "
                        "last=2026-11-18, src=user, status=active",
                        "id=scenes/work#2, first=2026-11-18, "
                        "last=2026-11-21, src=distill:2026-11-21, "
                        "status=superseded, superseded_by=scenes/work#1"),
        encoding="utf-8")
    hy = sem.hybrid_search("半夜把新版本推上去")
    check("retired: superseded hidden by default",
          "scenes/work#2" not in [h["id"] for h in hy["hits"]], hy["hits"])
    hy = sem.hybrid_search("半夜把新版本推上去", include_retired=True)
    check("retired: include_retired surfaces it",
          "scenes/work#2" in [h["id"] for h in hy["hits"]], hy["hits"])

    # ---- 6. heat recorded on the shared ledger ----
    heat = json.loads(
        (memories / "oneday" / "state" / "heat.json").read_text())
    check("heat: hybrid hits recorded",
          heat.get("people/qinyuanyi#1", {}).get("count", 0) >= 1, heat)

    # ---- 7. sidecar is a pure cache: delete + rebuild ----
    index_file.unlink()
    stats = sem.ensure_index()
    check("cache: rebuild from scratch after delete",
          stats["entries"] == 4 and stats["embedded"] == 4, stats)

    # ---- 8. degraded embedder determinism (fallback contract) ----
    h = sem._HashEmbedder()
    v1 = h.embed(["部署窗口在凌晨"])[0]
    v2 = h.embed(["部署窗口在凌晨"])[0]
    check("hash embedder: identical text cosine 1.0",
          abs(sem._cosine(v1, v2) - 1.0) < 1e-9)

    # ---- 9. CLI smoke ----
    env = dict(os.environ)
    proc = subprocess.run(
        [sys.executable, str(SEM_PATH), "hybrid", Q_SEM],
        capture_output=True, text=True, env=env, timeout=300)
    cli = json.loads(proc.stdout) if proc.returncode == 0 else {}
    check("cli: hybrid runs, taboo entry found",
          proc.returncode == 0
          and any(x["id"] == "people/qinyuanyi#1"
                  for x in cli.get("hits", [])),
          proc.stderr[-300:] if proc.returncode else "")

    # ---- 10. recency: identical text, different ages ----
    # Same title+body -> trigram, semantic and heat are all equal;
    # only the odmem `last` dates differ (today vs 180 days ago),
    # so any order between the two can only come from recency.
    from datetime import datetime, timedelta, timezone
    today = datetime.now(tz=timezone.utc).date()
    d_new = today.isoformat()
    d_old = (today - timedelta(days=180)).isoformat()
    entry_text = ("## 值班安排\n"
                  "周末值班表每周五下午公布，有事提前在群里说。\n")
    (scenes / "recency.md").write_text(
        entry_text
        + "<!-- odmem: id=scenes/recency#new, first=%s, last=%s, "
          "src=user, status=active -->\n\n" % (d_new, d_new)
        + entry_text
        + "<!-- odmem: id=scenes/recency#old, first=%s, last=%s, "
          "src=user, status=active -->\n" % (d_old, d_old),
        encoding="utf-8")
    hy = sem.hybrid_search("值班表什么时候公布")
    pair = [h for h in hy["hits"]
            if h["id"] in ("scenes/recency#new", "scenes/recency#old")]
    check("recency: both identical-text entries surface",
          len(pair) == 2, hy["hits"])
    if len(pair) == 2:
        check("recency: routes equal (trigram/semantic/heat tied)",
              pair[0]["scores"]["trigram"] == pair[1]["scores"]["trigram"]
              and pair[0]["scores"]["semantic"]
              == pair[1]["scores"]["semantic"]
              and pair[0]["scores"]["heat"] == pair[1]["scores"]["heat"],
              pair)
        check("recency: newer entry ranks first",
              pair[0]["id"] == "scenes/recency#new", pair)
        check("recency: newer score strictly higher",
              pair[0]["score"] > pair[1]["score"], pair)
        check("recency: factors match section 439 decay "
              "(new ~1.0, 180d ~0.2125)",
              pair[0]["scores"]["recency"] >= 0.98
              and 0.19 <= pair[1]["scores"]["recency"] <= 0.24, pair)

    failed = [c for c in CHECKS if not c[1]]
    print("\n%d/%d passed" % (len(CHECKS) - len(failed), len(CHECKS)))
    shutil.rmtree(tmp, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
