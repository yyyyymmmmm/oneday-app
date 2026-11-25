"""One-off category classification for pre-1.0.34 idea cards.

Pure helpers shared by the deploy-time backfill script
(backfill_idea_categories.py) and its selftest. The enum is
the bridge's GOAL_CATEGORIES (single source of truth); this
module only decides WHICH value an existing card gets:

1. model pass -- one batched generation call reads each
   card's title / why (evidence) / detail and answers with
   enum values only;
2. keyword rules -- deterministic fallback when the model is
   unavailable or its answer for a card is missing/illegal;
3. "other" -- the floor. Every target card leaves with a
   category; none is dropped, none is left null.
"""
import json
import re

CATEGORIES = ("health", "relationships", "finance",
              "career", "interest", "efficiency", "other")
DEFAULT_CATEGORY = "other"

#: Ordered: the first bucket with a keyword hit wins. The
#: order encodes the overlaps seen in real cards -- a wedding
#: budget card is a relationships card, a course-pricing card
#: is a career card.
RULES = (
    ("health", (
        "健康", "体检", "睡眠", "睡不好", "运动", "锻炼", "健身",
        "体重", "减肥", "医院", "看病", "吃药", "血压", "心率",
        "步数", "熬夜", "休息", "眼睛", "颈椎", "腰",
    )),
    ("relationships", (
        "婚礼", "结婚", "婚宴", "未婚妻", "妻子", "老婆", "媳妇",
        "父母", "妈妈", "爸爸", "母亲", "父亲", "家人", "亲戚",
        "朋友", "宾客", "伴郎", "伴娘", "岳父", "岳母", "丈母娘",
        "姥姥", "姥爷", "舅舅", "舅妈", "礼记", "礼谱", "随礼",
        "发言稿", "请柬",
    )),
    ("interest", (
        "小说", "写章", "写作", "故事", "音乐", "电影", "游戏",
        "旅行", "旅游", "摄影", "阅读", "读书", "看书", "美食",
        "做饭", "烹饪", "宠物", "钓鱼", "露营", "收藏", "画画",
    )),
    ("finance", (
        "收入", "赚钱", "搞钱", "副业", "返佣", "佣金", "存款",
        "理财", "投资", "股票", "基金", "外汇", "账单", "预算",
        "省钱", "支出", "花费", "房贷", "贷款", "首付", "买房",
        "租金", "工资", "成本", "虚拟卡", "信用卡", "U卡",
        "变现", "保险",
    )),
    ("career", (
        "工作", "事业", "客户", "培训", "课程", "学员", "公司",
        "项目", "上线", "发布", "版本", "开发", "代码", "运营",
        "推广", "讲课", "交付", "产品", "功能", "构建", "部署",
        "服务器", "账号", "小红书", "oneday", "hermes", "app",
        "x-dun",
    )),
    ("efficiency", (
        "效率", "自动化", "整理", "清理", "待办", "清单", "提醒",
        "日程", "归档", "备份", "同步", "定时", "脚本", "流程",
        "模板", "批量", "工作流",
    )),
)

MODEL_PROMPT = """你是 OneDay 点子卡的分类员。下面给出若干张已有的点子卡（编号、标题、依据、正文）。

为每张卡选一个分类，只能取七个值之一：health（健康）、relationships（人际关系）、finance（财务）、career（事业）、interest（兴趣）、efficiency（效率提升）、other（其他）。按卡的主题选最贴切的一类，实在归不进前六类才用 other。

只输出一个 JSON 数组：[{"id":"卡编号","category":"分类值"}]，每张卡一行，不要任何解释文字、不要 Markdown 代码围栏。

点子卡：
"""


def card_text(card: dict) -> str:
    """The text a classifier (rules or human) judges by:
    title + why(evidence) + detail, in that order."""
    return "\n".join(str(card.get(k) or "") for k in
                     ("title", "evidence", "detail"))


def classify_by_rules(card: dict):
    """First-bucket keyword hit over title/why/detail, or
    None when no rule fires."""
    text = card_text(card).lower()
    for category, keywords in RULES:
        for kw in keywords:
            if kw.lower() in text:
                return category
    return None


def build_model_prompt(cards: list) -> str:
    parts = [MODEL_PROMPT]
    for c in cards:
        parts.append(
            f"- id：{c.get('id')}\n  标题：{c.get('title') or ''}"
            f"\n  依据：{c.get('evidence') or ''}"
            f"\n  正文：{c.get('detail') or ''}")
    return "\n".join(parts)


def parse_model_output(output: str, want_ids: set) -> dict:
    """{id: category} for answers that name a wanted id AND a
    legal enum value. Anything else is ignored -- the caller
    falls back per card, never wholesale."""
    if not isinstance(output, str):
        return {}
    text = output.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end <= start:
        return {}
    try:
        items = json.loads(text[start:end + 1])
    except Exception:
        return {}
    if not isinstance(items, list):
        return {}
    out = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        cid = item.get("id")
        cat = item.get("category")
        if cid in want_ids and cat in CATEGORIES:
            out[cid] = cat
    return out


def classify_cards(cards: list, model_fn) -> list:
    """[{id, category, source}] -- source is "model", "rules"
    or "default". model_fn(prompt) -> output str, or None /
    raise when the model is unavailable; a parse that yields
    nothing also degrades to rules per card."""
    model_map = {}
    if cards and model_fn is not None:
        try:
            output = model_fn(build_model_prompt(cards))
        except Exception:
            output = None
        if output:
            model_map = parse_model_output(
                output, {c.get("id") for c in cards})
    results = []
    for c in cards:
        cid = c.get("id")
        if cid in model_map:
            results.append({"id": cid,
                            "category": model_map[cid],
                            "source": "model"})
            continue
        ruled = classify_by_rules(c)
        if ruled is not None:
            results.append({"id": cid, "category": ruled,
                            "source": "rules"})
        else:
            results.append({"id": cid,
                            "category": DEFAULT_CATEGORY,
                            "source": "default"})
    return results


_ID_RE = re.compile(r"^i_[0-9a-f]+$")


def is_backfill_target(idea: dict) -> bool:
    """Non-terminal (pending; a missing status reads pending
    in _idea_view) and not already carrying a legal category."""
    if not isinstance(idea, dict) or not _ID_RE.match(
            str(idea.get("id") or "")):
        return False
    if idea.get("status", "pending") != "pending":
        return False
    return idea.get("category") not in CATEGORIES
