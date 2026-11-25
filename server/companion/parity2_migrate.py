#!/usr/bin/env python3
"""§459 phase-2 one-shot data migration (2026-11-24).

Backfills the two new field families onto the stored records
in data.json, deterministically (no model calls):

- feed posts: `category` := the post's own direction text
  (None when the post has no direction -- event/digest
  posts); `discussCount` := 0 where missing.
- ideas: `domain` := the Muse domain folded from the legacy
  category (same table the bridge view folds with);
  `kind` := "chat" for every stock card (the pre-§459
  adoption surface only ever opened a conversation + a
  kanban task, which IS the chat kind's landing);
  `categoryLabel` := a keyword rule over title+detail
  (server/wedding/training/subscription/...), else None --
  an honest "no label", never an invented one.

Run it ONCE, inside the deploy window, with the companion
stopped (or at least with no writer active):

    python3 parity2_migrate.py --data /path/to/data.json

It writes a timestamped backup next to the data file first,
prints the per-card ledger (id -> values -> source), and
records meta.parity2Migration in the store. --dry-run prints
the same ledger without touching the file. Re-running is
idempotent: fields already present are kept verbatim.
"""
import argparse
import json
import os
import shutil
import sys
import time

IDEAS_DOMAINS = (
    "personal_productivity", "entertainment", "shopping",
    "finance", "relationships", "health", "career",
    "home_automation", "connect_devices", "creation_media",
    "family", "goal_scoped",
)
LEGACY_CATEGORY_DOMAIN = {
    "health": "health",
    "relationships": "relationships",
    "finance": "finance",
    "career": "career",
    "efficiency": "personal_productivity",
    "interest": "entertainment",
    "other": "personal_productivity",
}
IDEA_KINDS = ("chat", "routine", "goal")
DEFAULT_DOMAIN = "personal_productivity"

# ordered: first hit wins; the label set mirrors the free
# labels observed on Muse's own cards
LABEL_RULES = (
    (("服务器", "运维", "证书", "vps", "节点", "域名"), "服务器运维"),
    (("婚礼",), "婚礼"),
    (("小红书",), "小红书运营"),
    (("培训", "课程", "老师", "批改"), "Ai 培训"),
    (("订阅", "会员", "续费"), "订阅选购"),
    (("会议", "纪要"), "会议纪要"),
    (("学习", "复习", "考试"), "学习整理"),
    (("目标", "里程碑"), "目标推进"),
    (("家人", "家庭", "父母", "孩子"), "家庭日常"),
    (("订机票", "行程", "酒店", "旅行"), "出行安排"),
    (("记账", "账单", "预算", "还款"), "财务整理"),
)


def fold_domain(idea):
    dom = idea.get("domain")
    if isinstance(dom, str) and dom in IDEAS_DOMAINS:
        return dom, "kept"
    cat = idea.get("category")
    if isinstance(cat, str) and cat in LEGACY_CATEGORY_DOMAIN:
        return LEGACY_CATEGORY_DOMAIN[cat], f"legacy:{cat}"
    return DEFAULT_DOMAIN, "default"


def guess_label(idea):
    lab = idea.get("categoryLabel")
    if isinstance(lab, str) and lab.strip():
        return lab.strip()[:24], "kept"
    text = (str(idea.get("title") or "") + " "
            + str(idea.get("detail") or "")).lower()
    for keys, label in LABEL_RULES:
        if any(k in text for k in keys):
            return label, "keyword"
    return None, "none"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.environ.get(
        "DATA_PATH", "data.json"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(args.data, encoding="utf-8") as f:
        db = json.load(f)

    ledger = []
    feed_filled = 0
    for p in db.get("feedPosts") or []:
        if "category" not in p:
            d = p.get("direction")
            p["category"] = (
                " ".join(str(d).split())[:24]
                if isinstance(d, str) and d.strip() else None)
            feed_filled += 1
            ledger.append(
                f"feed {p.get('id')}: category={p['category']!r}"
                " (from direction)")
        if "discussCount" not in p:
            p["discussCount"] = 0

    ideas_filled = 0
    for i in db.get("ideas") or []:
        dom, dom_src = fold_domain(i)
        kind = i.get("kind")
        kind_src = "kept"
        if kind not in IDEA_KINDS:
            kind, kind_src = "chat", "stock-default"
        lab, lab_src = guess_label(i)
        changed = (i.get("domain") != dom
                   or i.get("kind") != kind
                   or i.get("categoryLabel") != lab)
        i["domain"], i["kind"], i["categoryLabel"] = dom, kind, lab
        if changed:
            ideas_filled += 1
        ledger.append(
            f"idea {i.get('id')}: domain={dom} ({dom_src}), "
            f"kind={kind} ({kind_src}), "
            f"categoryLabel={lab!r} ({lab_src})")

    meta = db.setdefault("meta", {})
    meta["parity2Migration"] = {
        "at": time.time(),
        "feedFilled": feed_filled,
        "ideasTouched": ideas_filled,
        "dryRun": bool(args.dry_run),
    }
    for line in ledger:
        print(line)
    print(f"feed posts backfilled: {feed_filled}; "
          f"ideas touched: {ideas_filled}; "
          f"ideas total: {len(db.get('ideas') or [])}")

    if args.dry_run:
        print("dry-run: file untouched")
        return 0
    backup = f"{args.data}.bak-parity2-{int(time.time())}"
    shutil.copy2(args.data, backup)
    tmp = args.data + ".tmp-parity2"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(db, f, ensure_ascii=False)
    os.replace(tmp, args.data)
    print(f"backup: {backup}")
    print(f"written: {args.data}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
