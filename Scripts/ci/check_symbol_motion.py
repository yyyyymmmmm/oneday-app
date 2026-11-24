#!/usr/bin/env python3
"""符号动效登记核查（DESIGN-V4 §247.1）。

全仓符号动效接入点只许出现在登记册
（Sources/OneDayDesign/SymbolMotionRegistry.swift）
登记过的位置。本脚本逐处扫描源码的动效接入原语，
与登记册按「文件 × 条数」比对：

- 源码有接入点、登记册无对应条目（或条数不足）
  → 未登记接入点，判红；
- 登记册有条目、源码接入点已消失（或条数过剩）
  → 过期条目，判红；
- 白名单未落项（无代码接入点）不在本脚本范围，
  账在 DESIGN-V4 §247.1。

扫描原语（计数口径＝出现次数）：
- ``symbolEffect(``——含 .symbolEffect 修饰符与
  .contentTransition(.symbolEffect(...)) 两形；
- ``LottieView`` / ``import Lottie``——LORD 本体
  接入面（当前应为 0，落点前先入册）。

用法：
    python3 Scripts/ci/check_symbol_motion.py [--root .]
    python3 Scripts/ci/check_symbol_motion.py --selftest
退出码：0 通过；1 有未登记/过期条目；2 脚本自身错误。
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

REGISTRY_REL = "Sources/OneDayDesign/SymbolMotionRegistry.swift"
PRIMITIVES = {
    "symbolEffect": re.compile(r"symbolEffect\("),
    "lottie": re.compile(r"LottieView|import Lottie"),
}
ENTRY_RE = re.compile(
    r'SymbolMotionSite\(\s*id:\s*"(?P<id>[^"]+)",\s*'
    r'file:\s*"(?P<file>[^"]+)"',
    re.DOTALL,
)


def parse_registry(text: str) -> Counter:
    """登记册 → {文件: 条数}。"""
    counts: Counter = Counter()
    for m in ENTRY_RE.finditer(text):
        counts[m.group("file")] += 1
    return counts


def scan_sources(root: Path) -> Counter:
    """源码接入点 → {文件（相对路径）: 次数}。"""
    counts: Counter = Counter()
    sources = root / "Sources"
    for path in sorted(sources.rglob("*.swift")):
        rel = path.relative_to(root).as_posix()
        if rel == REGISTRY_REL:
            continue
        text = path.read_text(encoding="utf-8")
        hits = sum(
            len(rx.findall(text)) for rx in PRIMITIVES.values()
        )
        if hits:
            counts[rel] += hits
    return counts


def compare(registered: Counter, found: Counter) -> list[str]:
    problems: list[str] = []
    for file in sorted(set(registered) | set(found)):
        reg = registered.get(file, 0)
        got = found.get(file, 0)
        if got > reg:
            problems.append(
                f"未登记接入点：{file} 源码 {got} 处、登记 {reg} 处"
                "——先入 SymbolMotionRegistry 再落码（§247.1）"
            )
        elif reg > got:
            problems.append(
                f"过期登记：{file} 登记 {reg} 处、源码仅 {got} 处"
                "——接入点已移除/迁移，同步删改登记条目"
            )
    return problems


def selftest() -> int:
    sample_registry = """
    SymbolMotionSite(
        id: "SM-1",
        file: "Sources/OneDayApp/A.swift",
    SymbolMotionSite(
        id: "SM-2",
        file: "Sources/OneDayApp/A.swift",
    SymbolMotionSite(
        id: "SM-3",
        file: "Sources/OneDayApp/B.swift",
    """
    reg = parse_registry(sample_registry)
    assert reg == {"Sources/OneDayApp/A.swift": 2,
                   "Sources/OneDayApp/B.swift": 1}, reg
    ok = compare(reg, Counter({"Sources/OneDayApp/A.swift": 2,
                                "Sources/OneDayApp/B.swift": 1}))
    assert ok == [], ok
    bad = compare(reg, Counter({"Sources/OneDayApp/A.swift": 3}))
    assert len(bad) == 2, bad  # A 未登记 + B 过期
    hits = sum(len(rx.findall(
        ".contentTransition(.symbolEffect(.replace)) "
        ".symbolEffect(.bounce) import Lottie"))
        for rx in PRIMITIVES.values())
    assert hits == 3, hits
    print("selftest OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return selftest()

    root = Path(args.root)
    registry_path = root / REGISTRY_REL
    if not registry_path.is_file():
        print(f"登记册缺失：{REGISTRY_REL}", file=sys.stderr)
        return 2
    registered = parse_registry(
        registry_path.read_text(encoding="utf-8"))
    if not registered:
        print("登记册解析出 0 条——格式已变或册为空", file=sys.stderr)
        return 2
    found = scan_sources(root)
    problems = compare(registered, found)
    if problems:
        print("符号动效登记核查未过：")
        for p in problems:
            print(f"  - {p}")
        return 1
    total = sum(found.values())
    print(
        f"符号动效登记核查通过：{total} 处接入点全在册"
        f"（{len(registered)} 个文件）"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
