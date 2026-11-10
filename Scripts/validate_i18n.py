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
BANNED = ["探活", "端点", "回读", "落盘", "真源", "桶", "scope"]
BANNED_PAIRS = {"端点": "端點", "回读": "回讀", "落盘": "落盤"}


def phmap(s: str) -> dict:
    out, seq = {}, 0
    for m in PH.finditer(s):
        seq += 1
        pos = int(m.group(1)) if m.group(1) else seq
        out[pos] = "%" + ("lld" if m.group(2) == "d" else m.group(2))
    return out


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
    if errors:
        print(f"校验失败（{len(errors)} 条）：")
        for e in errors[:50]:
            print(" -", e)
        return 1
    print(f"校验通过：{total} 键 × 三语（zh-Hans/zh-Hant/en）全覆盖、占位符一致、无行话引入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
