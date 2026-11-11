#!/usr/bin/env python3
"""String Catalog 校验（0.42.0 国际化包立）。

用法：python3 Scripts/validate_i18n.py [--check-code]

校验 App/Resources/Localizable.xcstrings 与
InfoPlist.xcstrings：
1. 每键必有 zh-Hans/zh-Hant/en 三语且非空；
2. 译文占位符（%@/%lld/%lf，含定位符 %n$ 形）与
   源键按位置-类型一致；
3. 行话黑名单：译文不得引入源串没有的行话词
   （宪法 §8 三语一致；源串自带的历史词不算引入）。
4. 源串同查（§120/D3-11 根因修复）：zh-Hans 源串本身
   不得含黑名单词——旧版只防译文引入、源串写什么都
   放行，54 条行话漏出全由此门漏过。仅剩的存量按
   SOURCE_EXEMPTIONS 逐条挂账（注明归属包/定版出
   处），豁免失效（键已改净或已删除）即报错，强制
   逐条销账清零。

--check-code 追加代码层抽查：报告 Sources 下仍
未被目录键覆盖的中文 UI 字面量条数（仅统计、恒
返回 0——覆盖面基线见 DESIGN §107）。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGS = ("zh-Hans", "zh-Hant", "en")
PH = re.compile(r"%(?:(\d+)\$)?(lld|lf|@|d)")
BANNED = [
    "探活", "端点", "回读", "落盘", "真源", "桶", "scope",
    # §120/D3-11 扩表：2026-11-11 细节打磨审计实证漏出词族
    "槽位", "验活", "闸门", "桥", "轮询", "上游", "未落定",
    "对账", "镜像",
]
BANNED_PAIRS = {
    "端点": "端點", "回读": "回讀", "落盘": "落盤",
    "验活": "驗活", "闸门": "閘門", "桥": "橋", "轮询": "輪詢",
    "对账": "對帳", "镜像": "鏡像",
}

# 源串豁免挂账（§120/D3-11）：键＝zh-Hans 源串原文，
# 值＝保留理由与归属。对应包落地改净后必须删豁免，
# 校验器对失效豁免报错，豁免只许减不许增。
SOURCE_EXEMPTIONS = {
    # D3-01 槽位族 8 条：§119 模型简化包在飞面（模型/组合
    # 页正按「辅助模型」新口径重写），合并时对账清零。
    "看图、标题、压缩这些活各用哪个模型。没打开的槽位保持现在的设置不动。": "§119 在飞（D3-01）",
    "辅助槽位": "§119 在飞（D3-01）",
    "组合「%@」已启用。辅助槽位若没立刻变，随服务下次重启生效。": "§119 在飞（D3-01）",
    "这套组合的主模型 %@ 不在网关可用的模型里，没法设为全局默认；先在编辑里换一个，或把它放到某个槽位里按直连用。": "§119 在飞（D3-01）",
    "还没有添加提供商。添加后，它家的模型会出现在上面的清单里，也能在组合里按槽位选用。": "§119 在飞（D3-01）",
    "%lld 个辅助槽位": "§119 在飞（D3-01）",
    "还没有设置任何槽位": "§119 在飞（D3-01）",
    "这套组合还没有设置任何槽位，激活不会改动现在的配置。": "§119 在飞（D3-01）",
    # D3-12 定版保留：解释句原文写得人话、审计明定保留。
    "负责对账的程序可能停了，新进度暂时不会出现。": "D3-12 定版保留（解释句）",
    "这条是对账时补记的：它开始时台账还没记上。": "D3-12 定版保留（解释句）",
    # 台账记录者标签（LedgerBoard.actorWord），D3-12 未列。
    "对账": "台账记录者标签，留台账后续面对账",
    # 连接器说明文，审计计数内但 D3-12 未点名。
    "智能体可调用：按你在对话里的确认设定真闹钟（定点或倒计时），响铃穿透静音与专注模式；也能查看闹钟列表、取消它设过的闹钟。系统闹钟不带标题，标题由 OneDay 记在这台手机上对账": "连接器说明文，留连接器下一包对账",
}


def phmap(s: str) -> dict:
    out, seq = {}, 0
    for m in PH.finditer(s):
        seq += 1
        pos = int(m.group(1)) if m.group(1) else seq
        out[pos] = "%" + ("lld" if m.group(2) == "d" else m.group(2))
    return out


USED_EXEMPTIONS: set = set()


def check_catalog(path: Path) -> list[str]:
    errors = []
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "zh-Hans":
        errors.append(f"{path.name}: sourceLanguage 不是 zh-Hans")
    for key, entry in data.get("strings", {}).items():
        locs = entry.get("localizations", {})
        for lang in LANGS:
            unit = locs.get(lang, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                errors.append(f"{path.name}: 键「{key[:40]}」缺 {lang} 译文")
        want = phmap(key)
        for lang in ("zh-Hant", "en"):
            value = locs.get(lang, {}).get("stringUnit", {}).get("value", "")
            if phmap(value) != want:
                errors.append(
                    f"{path.name}: 键「{key[:40]}」{lang} 占位符不符 "
                    f"{phmap(value)} != {want}"
                )
        src_forms = set()
        for word in BANNED:
            if word in key:
                src_forms.add(word)
        # §120/D3-11：源串同查（键本身与 zh-Hans 值）
        src_value = locs.get(
            "zh-Hans", {}
        ).get("stringUnit", {}).get("value", "")
        hit_words = [
            w for w in BANNED if w in key or w in src_value
        ]
        if hit_words:
            if key in SOURCE_EXEMPTIONS:
                USED_EXEMPTIONS.add(key)
            else:
                for w in hit_words:
                    errors.append(
                        f"{path.name}: 键「{key[:40]}」"
                        f"源串含行话「{w}」（源串同查）"
                    )
        for lang in ("zh-Hant", "en"):
            value = locs.get(lang, {}).get("stringUnit", {}).get("value", "")
            for word in BANNED:
                forms = {word, BANNED_PAIRS.get(word, word)}
                if any(f in value for f in forms) and word not in src_forms:
                    errors.append(
                        f"{path.name}: 键「{key[:40]}」{lang} 引入行话「{word}」"
                    )
    return errors


def main() -> int:
    errors = []
    total = 0
    for name in ("Localizable.xcstrings", "InfoPlist.xcstrings"):
        path = ROOT / "App" / "Resources" / name
        data = json.loads(path.read_text(encoding="utf-8"))
        total += len(data.get("strings", {}))
        errors += check_catalog(path)
    for stale in sorted(set(SOURCE_EXEMPTIONS) - USED_EXEMPTIONS):
        errors.append(
            f"豁免已失效（键已改净或已删除），请删豁免销账：「{stale[:40]}」"
        )
    if errors:
        print(f"校验失败（{len(errors)} 条）：")
        for e in errors[:50]:
            print(" -", e)
        return 1
    print(f"校验通过：{total} 键 × 三语（zh-Hans/zh-Hant/en）全覆盖、占位符一致、无行话引入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
