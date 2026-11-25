#!/usr/bin/env python3
"""ID-2 self-test for oneday_bridge.py (2026-11-14).

In-process coverage of the rev2 ch.2 pool machinery:
fingerprint normalisation, quality folding, fingerprint +
vector merge mapping, fast/terminal feedback ledgers, pool
score + scoreWhy, snapshot build (sections / positions /
explore floor), list order + merged exclusion, anchor-liveness
retirement, the built outcome, and the bootstrap snapshot.
The generation round itself needs a live Hermes and is not
exercised here; the K-3 downgrade (embedding off) is the
production state these tests assume.
"""
import os
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_SIBLING = os.path.join(_HERE, "oneday_bridge.py")
BRIDGE = _SIBLING if os.path.exists(_SIBLING) else os.path.abspath(
    os.path.join(_HERE, "..", "modules", "oneday_bridge.py"))
KEY = "id2-selftest-key"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def load_module(tmp):
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = os.path.join(tmp, "data.json")
    sys.path.insert(0, os.path.dirname(BRIDGE))
    import oneday_bridge as ob
    ob._load()
    return ob


def gen_card(ob, title, detail, anchor, category="career",
             quality=None, created=1_700_000_000.0):
    return {
        "id": "i_" + os.urandom(4).hex(),
        "title": title, "detail": detail, "emoji": None,
        "category": category, "deliverables": [], "goalId": None,
        "createdAt": created, "source": "generated",
        "evidence": "x", "evidenceRef": "S1", "anchorId": anchor,
        "dismissReason": None, "status": "pending", "taskId": None,
        "contentFingerprint": ob._idea_fingerprint(title, detail,
                                                   anchor),
        "quality": quality, "poolScore": None, "scoreWhy": None,
        "mergedInto": None, "mergeReason": None,
        "origin": "native", "embedding": None,
        "expiresAt": created + 14 * 24 * 3600,
    }


def main():
    tmp = tempfile.mkdtemp(prefix="id2-")
    ob = load_module(tmp)

    # 1. fingerprint: pattern prefix + punctuation normalise away
    fp1 = ob._idea_fingerprint("我可以整理发票", "按 11 月 3 日口径整理。",
                               "S:ses_1")
    fp2 = ob._idea_fingerprint("整理发票。", "按 11 月 3 日口径整理",
                               "S:ses_1")
    fp3 = ob._idea_fingerprint("整理发票", "按 11 月 3 日口径整理。",
                               "S:ses_2")
    check("fp prefix/punct normalised", fp1 == fp2, f"{fp1} {fp2}")
    check("fp anchor-sensitive", fp1 != fp3)

    # 2. quality folding
    q = ob._clean_quality({"relevance": 80, "novelty": 60,
                           "feasibility": 100})
    check("quality composite weighted",
          q is not None and q["composite"] == 80
          and q["policy"] == "ideas_quality_oneday_v1", f"{q}")
    check("quality malformed -> None",
          ob._clean_quality({"relevance": "高"}) is None
          and ob._clean_quality(None) is None)

    q90 = {"relevance": 90, "novelty": 90, "feasibility": 90,
           "composite": 90, "policy": "ideas_quality_oneday_v1"}
    q30 = {"relevance": 30, "novelty": 30, "feasibility": 30,
           "composite": 30, "policy": "ideas_quality_oneday_v1"}

    with ob._lock:
        canon = gen_card(ob, "我可以整理发票", "按 11 月 3 日口径整理。",
                         "S:ses_1", quality=q90)
        ob._db["ideas"].append(canon)

        # 3. merge: fingerprint hit, miss, and the vector path
        hit, reason = ob._merge_target_locked(
            ob._idea_fingerprint("整理发票", "按 11 月 3 日口径整理。",
                                 "S:ses_1"), None)
        check("merge fingerprint hit",
              hit is not None and hit["id"] == canon["id"]
              and reason == "fingerprint", f"{hit} {reason}")
        miss, _ = ob._merge_target_locked("0" * 32, None)
        check("merge fingerprint miss", miss is None)
        canon["embedding"] = [1.0, 0.0]
        vhit, vreason = ob._merge_target_locked(
            "1" * 32, [0.999, 0.01])
        check("merge vector hit >= 0.92",
              vhit is not None and vreason == "vector",
              f"{vhit} {vreason}")
        canon["embedding"] = None

        # 4. feedback ledgers via the real patch surface
        card_a = gen_card(ob, "我可以写周报", "按本周进展写。",
                          "K:t_9", quality=q90,
                          created=1_700_000_100.0)
        ob._db["ideas"].append(card_a)
        ob._patch_idea(card_a["id"], {"status": "adopted"})
        pool = ob._pool_meta_locked()
        term = pool["feedback"]["terminal"]
        check("adopt -> terminal ledger + bonus flag",
              term.get("pair:K|career", {}).get("events") == 1
              and pool["eventBonusPending"] is True, f"{term}")
        card_b = gen_card(ob, "我可以泛泛建议", "随便看看。",
                          "S:ses_7", created=1_700_000_200.0)
        ob._db["ideas"].append(card_b)
        ob._patch_idea(card_b["id"], {
            "status": "dismissed", "dismissReason": "tooGeneric"})
        fast = pool["feedback"]["fast"]
        check("tooGeneric -> fast ledger negative",
              fast.get("pair:S|career", {}).get("rewardSum") == -1.0,
              f"{fast}")

        # 5. signal intake
        ob._idea_signal_locked(canon["id"], {"type": "open"})
        fast2 = ob._pool_meta_locked()["feedback"]["fast"]
        check("signal open -> fast ledger",
              fast2.get("pair:S|career", {}).get("events") == 2
              and fast2.get("pair:S|career", {}).get("rewardSum")
              == -0.75,
              f"{fast2}")
        try:
            ob._idea_signal_locked(canon["id"], {"type": "poke"})
            check("signal bad type rejected", False)
        except ob._Err:
            check("signal bad type rejected", True)

        # 6. pool score: terminal history + quality outranks
        fresh = gen_card(ob, "我可以订机票", "按行程订。",
                         "K:t_10", quality=q30,
                         created=1_700_000_300.0)
        ob._db["ideas"].append(fresh)
        s_canon, why_canon = ob._idea_pool_score_locked(canon, pool)
        s_fresh, _ = ob._idea_pool_score_locked(fresh, pool)
        check("pool score ranks adopted-kind + quality first",
              s_canon > s_fresh, f"{s_canon} vs {s_fresh}")
        check("scoreWhy names the terminal source",
              "采纳过同类" in why_canon, why_canon)

        # 7. snapshot: sections ordered, positions complete,
        # explore floor on the new batch
        snap = ob._build_ideas_snapshot_locked(
            "selftest", new_ids=[canon["id"], fresh["id"]])
        doms = [s["domain"] for s in snap["sections"]]
        check("snapshot sections in domain order (§459)",
              doms == sorted(doms, key=ob.IDEAS_DOMAINS.index),
              f"{doms}")
        pending_ids = {i["id"] for i in ob._db["ideas"]
                       if i.get("status") == "pending"
                       and i.get("source") == "generated"}
        check("snapshot positions cover the pool",
              set(snap["positions"]) == pending_ids,
              f"{snap['positions']} vs {pending_ids}")
        check("explore floor >= ceil(new/3)",
              snap["exploreCount"] >= 1, f"{snap['exploreCount']}")

        # 8. list: snapshot order + merged excluded
        merged = gen_card(ob, "整理发票", "按 11 月 3 日口径整理。",
                          "S:ses_1", created=1_700_000_400.0)
        merged["status"] = "merged"
        merged["mergedInto"] = canon["id"]
        merged["mergeReason"] = "fingerprint"
        ob._db["ideas"].append(merged)
        views = ob._list_ideas()
        ids = [v["id"] for v in views]
        check("merged card leaves the list",
              merged["id"] not in ids and canon["id"] in ids)
        check("list follows snapshot positions",
              ids[0] == canon["id"], f"{ids}")
        view = next(v for v in views if v["id"] == canon["id"])
        check("view carries pool fields",
              view["contentFingerprint"] == canon["contentFingerprint"]
              and view["quality"]["composite"] == 90
              and view["origin"] == "native", f"{view}")

        # 9. merged id resolves to canonical on patch
        got = ob._patch_idea(merged["id"], {"taskId": "t_x"})
        check("patch on merged id hits canonical",
              got["id"] == canon["id"]
              and canon.get("taskId") == "t_x", f"{got['id']}")

        # 10. anchor liveness: completed goal retires its card
        g = ob._create_goal({"title": "收尾目标"})
        gcard = gen_card(ob, "我可以收尾", "按目标收尾。",
                         f"G:{g['id']}", created=1_700_000_500.0)
        ob._db["ideas"].append(gcard)
        ob._patch_goal(g["id"], {"status": "completed"})
        n = ob._retire_dead_anchor_ideas_locked()
        check("dead goal anchor retires anchorGone",
              n >= 1 and gcard["status"] == "expired"
              and gcard.get("expireReason") == "anchorGone",
              f"{n} {gcard.get('status')}")

        # 11. built outcome via the poll recorder
        adopted = gen_card(ob, "我可以交付报告", "按模板交付。",
                           "S:ses_9", created=1_700_000_600.0)
        adopted["status"] = "adopted"
        adopted["taskId"] = "t_done"
        ob._db["ideas"].append(adopted)
        ob._record_idea_task_outcomes_locked(
            {"t_done": ("交付报告", "done")}, 1_700_000_700.0)
        check("task done -> idea built + terminal reward",
              adopted["status"] == "built"
              and ob._pool_meta_locked()["feedback"]["terminal"]
              .get("pair:S|career", {}).get("events", 0) >= 1,
              f"{adopted['status']}")

    # 12. bootstrap snapshot for a pre-pool store
    tmp2 = tempfile.mkdtemp(prefix="id2-boot-")
    os.environ["DATA_PATH"] = os.path.join(tmp2, "data.json")
    import importlib
    importlib.reload(ob)
    ob._load()
    with ob._lock:
        import time as _time
        c = gen_card(ob, "我可以盘库存", "按仓单盘。",
                     "S:ses_b", created=_time.time())
        ob._db["ideas"].append(c)
        ob._expire_ideas_locked()
        pool2 = ob._pool_meta_locked()
        check("bootstrap snapshot built on tick",
              pool2.get("activeSnapshotId") is not None
              and pool2["snapshots"][0]["reason"] == "bootstrap",
              f"{pool2.get('activeSnapshotId')}")

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
