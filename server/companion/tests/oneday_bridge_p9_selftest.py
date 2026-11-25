#!/usr/bin/env python3
"""P9 self-test for oneday_bridge.py idea categories (1.0.34).

Every idea card carries one of the seven GOAL_CATEGORIES
values (the bridge's single-source enum, shared with the
goal creation flow). Coverage:

1. _clean_idea_category folds: legal -> itself, anything
   else (None / illegal / wrong type) -> "other"; never
   raises.
2. _idea_view always emits a legal category: stored value
   surfaces, a missing/illegal stored value reads "other".
3. POST /ideas (_create_idea) takes the category key: a
   legal value is stored, a missing key defaults to
   "other", an illegal value folds to "other" -- no 400.
4. The generation parser keeps a legal category, folds a
   missing/illegal one to "other", and never drops a card
   over its category.
5. The prompts carry the category contract (gen requires
   it, rewrite lists it among the carried fields).
6. The backfill classifier (idea_category_backfill):
   model answers win, illegal/unknown model answers fall
   back per card to keyword rules, rules miss -> "other";
   is_backfill_target picks exactly the non-terminal
   (pending) cards without a legal category.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def _sibling(name):
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        return p
    p = os.path.join(HERE, "..", "modules", name)
    if os.path.exists(p):
        return p
    return os.path.join(HERE, "..", "scripts", name)


BRIDGE = _sibling("oneday_bridge.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(BRIDGE)))
KEY = "p9-selftest-key"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def load_bridge():
    tmp = tempfile.mkdtemp(prefix="ob-p9-")
    data_path = os.path.join(tmp, "data.json")
    os.environ["ONEDAY_BRIDGE_KEY"] = KEY
    os.environ["DATA_PATH"] = data_path
    os.environ.pop("HERMES_API_KEY", None)
    spec = importlib.util.spec_from_file_location(
        "ob_p9", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._load()
    return mod


def main():
    mod = load_bridge()

    # 1. the fold
    check("1 legal values pass through",
          all(mod._clean_idea_category(c) == c
              for c in mod.GOAL_CATEGORIES))
    check("1 None/illegal/wrong-type fold to other",
          mod._clean_idea_category(None) == "other"
          and mod._clean_idea_category("bogus") == "other"
          and mod._clean_idea_category(7) == "other"
          and mod._clean_idea_category("") == "other")
    check("1 enum is the goal enum (single source)",
          mod.IDEA_DEFAULT_CATEGORY == "other"
          and set(mod.CATEGORY_LABELS)
          == set(mod.GOAL_CATEGORIES))

    # 2. the view
    base = {"id": "i_abc123", "title": "t", "createdAt": 1.0}
    check("2 view surfaces stored category",
          mod._idea_view({**base,
                          "category": "finance"})["category"]
          == "finance")
    check("2 view folds missing category to other",
          mod._idea_view(dict(base))["category"] == "other")
    check("2 view folds illegal stored category to other",
          mod._idea_view({**base,
                          "category": "nope"})["category"]
          == "other")

    # 3. create surface
    with mod._lock:
        v1 = mod._create_idea({"title": "带分类的手建卡",
                               "category": "health"})
        v2 = mod._create_idea({"title": "无键的旧调用卡"})
        v3 = mod._create_idea({"title": "非法分类卡",
                               "category": "bogus"})
    check("3 create stores a legal category",
          v1["category"] == "health", f"{v1}")
    check("3 create defaults a missing key to other",
          v2["category"] == "other", f"{v2}")
    check("3 create folds an illegal value to other",
          v3["category"] == "other", f"{v3}")
    stored = {i["id"]: i for i in mod._db["ideas"]}
    check("3 stored records carry the category",
          stored[v1["id"]]["category"] == "health"
          and stored[v2["id"]]["category"] == "other")

    # 4. generation parser
    anchors = {
        "S1": {"kind": "S", "objectId": "sess_a",
               "title": "聊了年会主持稿定稿"},
        "S2": {"kind": "S", "objectId": "sess_b",
               "title": "体检报告出来了"},
        "S3": {"kind": "S", "objectId": "sess_c",
               "title": "副业账号十月结算"},
    }
    lines = {
        "S1": "S1 会话：10 月 29 日聊了年会主持稿定稿",
        "S2": "S2 会话：11 月 3 日体检报告出来了",
        "S3": "S3 会话：10 月 31 日副业账号结算 2300 元",
    }

    def card(title, detail, evidence, ref, **kw):
        d = {"title": title, "detail": detail,
             "evidence": evidence, "evidenceRef": ref,
             "goalId": None}
        d.update(kw)
        return d

    output = json.dumps([
        card("我可以把定稿发言存成文件",
             "把 10 月 29 日定稿的发言原文存成一份文件，"
             "年会当天直接打开就能念。",
             "10月29日定稿的发言还没落盘", "S1",
             category="relationships"),
        card("我可以把体检指标整理成表",
             "11 月 3 日体检报告已经出来，把关键指标"
             "整理成一张对照表存好。",
             "11月3日体检报告还没整理", "S2"),
        card("我可以把副业结算做成月表",
             "10 月 31 日副业账号结算 2300 元，"
             "把这笔做成月度结算表。",
             "10月31日结算 2300 元未入账", "S3",
             category="bogus"),
    ], ensure_ascii=False)
    cards, dropped, reasons, perr = mod._parse_generated_cards(
        output, set(), anchors, [], lines)
    by_ref = {c["evidenceRef"]: c for c in cards}
    check("4 all three cards land (none dropped over category)",
          perr is None and len(cards) == 3,
          f"cards={cards} dropped={dropped} err={perr}")
    check("4 legal category kept",
          by_ref.get("S1", {}).get("category")
          == "relationships", f"{by_ref}")
    check("4 missing category folds to other",
          by_ref.get("S2", {}).get("category") == "other",
          f"{by_ref}")
    check("4 illegal category folds to other",
          by_ref.get("S3", {}).get("category") == "other",
          f"{by_ref}")

    # 5. prompt contract
    check("5 gen prompt requires category with the enum",
          "category" in mod.IDEAS_GEN_PROMPT
          and all(c in mod.IDEAS_GEN_PROMPT
                  for c in mod.GOAL_CATEGORIES))
    check("5 rewrite prompt carries category",
          "category" in mod.IDEAS_REWRITE_PROMPT)

    # 6. backfill classifier
    spec = importlib.util.spec_from_file_location(
        "idea_category_backfill",
        _sibling("idea_category_backfill.py"))
    bf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bf)

    wedding = {"id": "i_1", "title": "把年会主持稿做成当天包",
               "evidence": "11月16日年会", "detail": "发言稿存盘"}
    health = {"id": "i_2", "title": "整理体检报告",
              "evidence": "", "detail": "指标对照"}
    money = {"id": "i_3", "title": "副业月度结算表",
             "evidence": "", "detail": ""}
    plain = {"id": "i_4", "title": "把那件事处理一下",
             "evidence": "", "detail": "就是那件事"}
    check("6 rules hit wedding -> relationships",
          bf.classify_by_rules(wedding) == "relationships")
    check("6 rules hit checkup -> health",
          bf.classify_by_rules(health) == "health")
    check("6 rules hit side-income -> finance",
          bf.classify_by_rules(money) == "finance")
    check("6 rules miss -> None",
          bf.classify_by_rules(plain) is None)

    good = json.dumps([
        {"id": "i_1", "category": "career"},
        {"id": "i_2", "category": "bogus"},
        {"id": "i_zzz", "category": "health"},
    ])
    parsed = bf.parse_model_output(good, {"i_1", "i_2"})
    check("6 model parse keeps legal+known only",
          parsed == {"i_1": "career"}, f"{parsed}")

    batch = [wedding, health, money, plain]
    res = bf.classify_cards(batch, lambda prompt: good)
    src = {r["id"]: (r["category"], r["source"]) for r in res}
    check("6 model answer wins over rules",
          src["i_1"] == ("career", "model"), f"{src}")
    check("6 illegal model answer falls back to rules",
          src["i_2"] == ("health", "rules"), f"{src}")
    check("6 unanswered card falls back to rules",
          src["i_3"] == ("finance", "rules"), f"{src}")
    check("6 no rule hit -> other/default",
          src["i_4"] == ("other", "default"), f"{src}")

    def boom(prompt):
        raise RuntimeError("model down")

    res2 = bf.classify_cards(batch, boom)
    src2 = {r["id"]: r["source"] for r in res2}
    check("6 model outage degrades to rules/default",
          src2 == {"i_1": "rules", "i_2": "rules",
                   "i_3": "rules", "i_4": "default"},
          f"{src2}")
    res3 = bf.classify_cards(batch, None)
    check("6 no model fn at all still classifies",
          [r["category"] for r in res3]
          == ["relationships", "health", "finance", "other"],
          f"{res3}")

    check("6 targets: pending without category only",
          bf.is_backfill_target(
              {"id": "i_1", "status": "pending"})
          and bf.is_backfill_target({"id": "i_1"})
          and bf.is_backfill_target(
              {"id": "i_1", "status": "pending",
               "category": "bogus"})
          and not bf.is_backfill_target(
              {"id": "i_1", "status": "pending",
               "category": "health"})
          and not bf.is_backfill_target(
              {"id": "i_1", "status": "adopted"})
          and not bf.is_backfill_target(
              {"id": "i_1", "status": "dismissed"})
          and not bf.is_backfill_target(
              {"id": "i_1", "status": "expired"}))

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
