#!/usr/bin/env python3
"""Selftest for the OneDay layered-memory module (DESIGN section 439).

Builds a stub HERMES_HOME in a temp dir, lays the SHIPPED seed into
it (so the seed layout itself is under test), then exercises every
mechanism the spec claims: layered inventory, entry search with
provenance echo, dual-temporal retirement, Mem0-style reconcile
suggestions, heat recording + decay, ExpeL insight governance,
Voyager admission audit, INDEX regeneration, and the module CLI.

Run: python3 oneday_memory_selftest.py   (exit 0 = all passed)
"""

import importlib.util
import json
from datetime import date, timedelta
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PKG = Path(__file__).resolve().parent
MODULE_PATH = PKG / "patches" / "oneday_memory.py"
SEED = PKG / "seed-memory"

CHECKS = []


def check(name, cond, detail=""):
    CHECKS.append((name, bool(cond), detail))
    print(("PASS " if cond else "FAIL ") + name + ((" -- " + str(detail)) if detail and not cond else ""))


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="odmem-stub-"))
    home = tmp / "data"
    memories = home / "memories"
    skills = home / "skills"

    # ---- lay the shipped seed exactly as install.sh will ----
    shutil.copytree(SEED / "memories", memories)
    shutil.copy2(SEED / "SOUL.md", home / "SOUL.md")
    shutil.copytree(SEED / "skills", skills)
    (home / "cron").mkdir(parents=True, exist_ok=True)
    jobs = json.loads((PKG / "cron" / "oneday-memory-jobs.json").read_text())
    (home / "cron" / "jobs.json").write_text(json.dumps({"jobs": jobs}))

    os.environ["ONEDAY_MEMORY_ROOT"] = str(memories)
    os.environ["ONEDAY_SKILLS_DIR"] = str(skills)
    spec = importlib.util.spec_from_file_location("oneday_memory", MODULE_PATH)
    om = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(om)

    # ---- 1. layer inventory over the fresh seed ----
    inv = om.list_layers()
    layers = {row["layer"]: row for row in inv["layers"]}
    check("layers: all 9 present", set(layers) == {
        "core", "inbox", "scenes", "people", "groups",
        "journal", "bank", "insights", "identity"}, sorted(layers))
    check("layers: core sees upstream pair", layers["core"]["files"] == 2,
          layers["core"])
    check("layers: identity files counted", layers["identity"]["files"] == 2,
          layers["identity"])
    check("layers: scenes templates counted", layers["scenes"]["files"] == 2,
          layers["scenes"])

    # ---- 2. write entries, search with provenance ----
    scene = memories / "oneday" / "scenes" / "work.md"
    scene.write_text(
        "# 场景：工作\n\n"
        "## work#1 · 部署窗口在凌晨\n"
        "生产部署只在凌晨两点到四点之间进行，其他时段不动。\n"
        "<!-- odmem: id=scenes/work#1, first=2026-11-20, last=2026-11-20, "
        "src=user, status=active, valid_from=2026-11-20, invalid_from=-, "
        "superseded_by=- -->\n\n"
        "## work#2 · 旧口径条目\n"
        "部署窗口曾经定在中午十二点。\n"
        "<!-- odmem: id=scenes/work#2, first=2026-10-01, last=2026-10-01, "
        "src=user, status=active, valid_from=2026-10-01, invalid_from=-, "
        "superseded_by=- -->\n", encoding="utf-8")
    res = om.search("部署窗口凌晨")
    hit_ids = [h["id"] for h in res["hits"]]
    check("search: finds active entry", "scenes/work#1" in hit_ids, hit_ids)
    hit = next(h for h in res["hits"] if h["id"] == "scenes/work#1")
    check("search: provenance echoed", hit["meta"].get("src") == "user"
          and hit["meta"].get("first") == "2026-11-20", hit["meta"])
    check("search: structured entry not plain", hit["plain"] is False)

    # ---- 2b. recency: equal relevance + heat -> newer first; the
    # decay floor keeps very old entries findable, never zero-killed --
    today = date.today()
    def _d(days_ago):
        return (today - timedelta(days=days_ago)).isoformat()
    rec_file = memories / "oneday" / "scenes" / "recency.md"
    rec_file.write_text(
        "# 场景：新近度样本\n\n"
        "## rec#new · 同文新条\n"
        "紫外线消毒柜放在茶水间东侧墙边，每周三更换灯管。\n"
        "<!-- odmem: id=scenes/rec#new, first=%s, last=%s, "
        "src=user, status=active, valid_from=%s, invalid_from=-, "
        "superseded_by=- -->\n\n"
        "## rec#old · 同文旧条\n"
        "紫外线消毒柜放在茶水间东侧墙边，每周三更换灯管。\n"
        "<!-- odmem: id=scenes/rec#old, first=%s, last=%s, "
        "src=user, status=active, valid_from=%s, invalid_from=-, "
        "superseded_by=- -->\n\n"
        "## rec#ancient · 远古唯一条\n"
        "远古样本墨绿色铁皮柜编号庚七，存放在旧楼地下室。\n"
        "<!-- odmem: id=scenes/rec#ancient, first=%s, last=%s, "
        "src=user, status=active, valid_from=%s, invalid_from=-, "
        "superseded_by=- -->\n"
        % (_d(0), _d(0), _d(0), _d(400), _d(400), _d(400),
           _d(4000), _d(4000), _d(4000)), encoding="utf-8")
    res = om.search("紫外线消毒柜茶水间")
    pair = [h["id"] for h in res["hits"]
            if h["id"] in ("scenes/rec#new", "scenes/rec#old")]
    check("recency: newer entry outranks identical older one",
          pair == ["scenes/rec#new", "scenes/rec#old"], pair)
    res = om.search("墨绿色铁皮柜庚七")
    ancient = next((h for h in res["hits"]
                    if h["id"] == "scenes/rec#ancient"), None)
    check("recency: ancient entry still returned, floor not zero",
          ancient is not None and ancient["score"] > 0
          and 0.2 <= ancient["recency"] < 0.21, ancient)

    # ---- 3. dual-temporal supersede: retire work#2, default search hides it ----
    text = scene.read_text(encoding="utf-8").replace(
        "id=scenes/work#2, first=2026-10-01, last=2026-10-01, "
        "src=user, status=active, valid_from=2026-10-01, invalid_from=-, "
        "superseded_by=-",
        "id=scenes/work#2, first=2026-10-01, last=2026-11-20, "
        "src=distill:2026-11-20, status=superseded, valid_from=2026-10-01, "
        "invalid_from=2026-11-20, superseded_by=scenes/work#1")
    scene.write_text(text, encoding="utf-8")
    res = om.search("部署窗口中午十二点")
    check("search: superseded hidden by default",
          "scenes/work#2" not in [h["id"] for h in res["hits"]], res["hits"])
    res = om.search("部署窗口中午十二点", include_retired=True)
    retired_hit = next((h for h in res["hits"] if h["id"] == "scenes/work#2"), None)
    check("search: include_retired surfaces it with chain",
          retired_hit is not None
          and retired_hit["meta"].get("superseded_by") == "scenes/work#1",
          retired_hit)

    # ---- 4. reconcile suggestions ----
    rec = om.reconcile_check("生产部署只在凌晨两点到四点之间进行")
    check("reconcile: near-duplicate -> update_candidate",
          rec["suggestion"] == "update_candidate"
          and rec["candidates"]
          and rec["candidates"][0]["id"] == "scenes/work#1", rec)
    rec = om.reconcile_check("用户喜欢吃辣的火锅")
    check("reconcile: unrelated -> add", rec["suggestion"] == "add", rec)

    # ---- 5. heat: searches recorded, sweep decays ----
    heat = json.loads((memories / "oneday" / "state" / "heat.json").read_text())
    check("heat: access recorded", heat.get("scenes/work#1", {}).get("count", 0) >= 1,
          heat)
    before = heat["scenes/work#1"]["count"]
    out = om.sweep_once()
    heat2 = json.loads((memories / "oneday" / "state" / "heat.json").read_text())
    check("heat: sweep decays", heat2["scenes/work#1"]["count"] <= before, out)
    index_text = (memories / "oneday" / "INDEX.md").read_text(encoding="utf-8")
    check("sweep: INDEX regenerated with layers",
          "| scenes |" in index_text and "自动再生" in index_text)

    # ---- 6. insight governance lifecycle ----
    r = om.insight_apply({"op": "add", "rule": "部署前先查内存", "src": "selftest"})
    check("insight: add candidate", r.get("ok") and r.get("status") == "candidate", r)
    iid = r["id"]
    om.insight_apply({"op": "upvote", "id": iid})
    r = om.insight_apply({"op": "upvote", "id": iid})
    check("insight: 2 upvotes -> active", r.get("status") == "active", r)
    r2 = om.insight_apply({"op": "add", "rule": "坏规则示例", "src": "selftest"})
    om.insight_apply({"op": "downvote", "id": r2["id"]})
    r = om.insight_apply({"op": "downvote", "id": r2["id"]})
    check("insight: downvotes -> retired", r.get("status") == "retired", r)
    rows = om.insights_list()
    check("insight: ledger readable", len(rows) == 2, rows)

    # ---- 7. admission audit: seed skill unregistered, then registered ----
    audit = om.admission_audit()
    check("admission: seed skill flagged unregistered",
          "oneday-memory" in audit["unregistered"], audit)
    ledger = memories / "oneday" / "admission" / "skill_admission.jsonl"
    with open(ledger, "a", encoding="utf-8") as f:
        f.write(json.dumps({
            "skill": "oneday-memory", "created_by": "agent",
            "verify": {"method": "selftest",
                       "evidence": "oneday_memory_selftest.py",
                       "at": "2026-11-24T00:00:00Z"},
            "status": "admitted", "first": "2026-11-24T00:00:00Z"}) + "\n")
    audit = om.admission_audit()
    check("admission: registered+verified clears flags",
          audit["unregistered"] == [] and audit["unverified"] == [], audit)

    # ---- 8. CLI smoke (agent-side trigger path) ----
    env = dict(os.environ)
    proc = subprocess.run(
        [sys.executable, str(MODULE_PATH), "search", "部署窗口"],
        capture_output=True, text=True, env=env, timeout=60)
    cli = json.loads(proc.stdout) if proc.returncode == 0 else {}
    check("cli: search runs", proc.returncode == 0
          and any(h["id"] == "scenes/work#1" for h in cli.get("hits", [])),
          proc.stderr[-300:] if proc.returncode else "")

    failed = [c for c in CHECKS if not c[1]]
    print("\n%d/%d passed" % (len(CHECKS) - len(failed), len(CHECKS)))
    shutil.rmtree(tmp, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
