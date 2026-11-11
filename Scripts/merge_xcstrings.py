#!/usr/bin/env python3
"""xcstrings 三方并集对账工具（§133 固化，复杂度审计第 13 项）。

用法：
  python3 Scripts/merge_xcstrings.py BASE OURS THEIRS -o MERGED [--conflicts REPORT.json]
  python3 Scripts/merge_xcstrings.py --self-test

背景：§119/§120 两次分支合并各耗一轮人肉对 Localizable.xcstrings
做三方并集对账。本工具把对账固化成确定性脚本：

合并粒度＝键 × 单元。单元有两类：条目元数据（localizations 之外
的全部字段，记为 "(entry)"）与每种语言的 localization。三方
（base/ours/theirs）逐单元比对：

- 只有一方改（或增、或删）→ 取改动方；
- 双方同改 → 取共同结果；
- 双方异改（含一方删、一方改）→ 冲突：输出先取我方（ours），
  并把「键＋单元」写进冲突点名清单，交人工裁——工具不替人选边。

键级删除先判：一侧整键删除、另一侧未动 → 删除；另一侧已改 →
整键冲突（逐个已改单元点名），输出按我方（删或留）落。

输出键序＝base 原序，其后我方新增键（我方文件序）、他方新增键
（他方文件序）；顶层字段（sourceLanguage/version）取 base。
退出码：0＝无冲突；2＝有冲突（合并结果照常写出）；1＝用法/读
写错误。合并后仍须跑 validate_i18n.py 校验三语完整性。

--self-test 用 Scripts/fixtures/xcstrings-merge/ 的样本自验：
样本以 §119/§120 两次真实合并的三方版本（git 历史 a11c52f/
18c6b39/029fa05 与 669e5bb/3885578/bfddcbd）中的真实条目为
主——含 §120 唯一一处真冲突「默认服务商（经网关）」zh-Hant
（網關/閘道之争，历史合并人工裁定取了他方）；「改既有键」与
「删改相撞」两类在两次历史里未出现，用构造样本补齐并在样本
目录 README 注明。
"""
import argparse
import json
import sys
from pathlib import Path

ENTRY_UNIT = "(entry)"
MISSING = object()  # 单元不存在（键被删或该语言未提供）


def load_catalog(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"读不了 {path}：{exc}")
    if not isinstance(data.get("strings"), dict):
        raise SystemExit(f"{path}：缺 strings 字典，不是 xcstrings")
    return data


def split_entry(entry):
    """条目 → (元数据 dict, {语言: localization})；entry 为 None 回 (MISSING, {})。"""
    if entry is None:
        return MISSING, {}
    meta = {k: v for k, v in entry.items() if k != "localizations"}
    return meta, dict(entry.get("localizations") or {})


def merge_unit(b, o, t):
    """单单元三方：回 (结果, 是否冲突)。"""
    if o == t:
        return o, False
    if b == o:
        return t, False
    if b == t:
        return o, False
    return o, True  # 冲突：先取我方，点名交人工裁


def merge_catalogs(base: dict, ours: dict, theirs: dict):
    """回 (合并后 strings, 冲突清单[{key, unit}])。"""
    b_all, o_all, t_all = base["strings"], ours["strings"], theirs["strings"]
    merged: dict = {}
    conflicts: list = []

    ordered_keys = list(b_all)
    ordered_keys += [k for k in o_all if k not in b_all]
    ordered_keys += [k for k in t_all if k not in b_all and k not in o_all]

    for key in ordered_keys:
        b, o, t = b_all.get(key), o_all.get(key), t_all.get(key)
        # 键级删除先判
        if b is not None and (o is None) != (t is None):
            survivor = t if o is None else o
            if survivor == b:
                continue  # 一侧删、另一侧未动 → 删除成立
            # 删与改相撞：逐个已改单元点名，输出按我方（o 为 None 即删）
            _, s_loc = split_entry(survivor)
            _, b_loc = split_entry(b)
            for lang in sorted(set(b_loc) | set(s_loc)):
                if b_loc.get(lang, MISSING) != s_loc.get(lang, MISSING):
                    conflicts.append({"key": key, "unit": lang})
            b_meta, _ = split_entry(b)
            s_meta, _ = split_entry(survivor)
            if b_meta != s_meta:
                conflicts.append({"key": key, "unit": ENTRY_UNIT})
            if o is not None:
                merged[key] = o
            continue
        if b is None and (o is None) != (t is None):
            merged[key] = o if o is not None else t  # 单侧新增
            continue
        if o is None and t is None:
            continue  # 双方都删（或仅 base 有）
        # 三方（或双方新增）逐单元合并
        b_meta, b_loc = split_entry(b)
        o_meta, o_loc = split_entry(o)
        t_meta, t_loc = split_entry(t)
        meta, bad = merge_unit(b_meta, o_meta, t_meta)
        if bad:
            conflicts.append({"key": key, "unit": ENTRY_UNIT})
        locs = {}
        for lang in sorted(set(b_loc) | set(o_loc) | set(t_loc)):
            val, bad = merge_unit(
                b_loc.get(lang, MISSING),
                o_loc.get(lang, MISSING),
                t_loc.get(lang, MISSING),
            )
            if bad:
                conflicts.append({"key": key, "unit": lang})
            if val is not MISSING:
                locs[lang] = val
        entry = {}
        if meta is not MISSING:
            entry.update(meta)
        if locs:
            entry["localizations"] = locs
        if entry:
            merged[key] = entry
    conflicts.sort(key=lambda c: (c["key"], c["unit"]))
    return merged, conflicts


def dump_catalog(base: dict, strings: dict) -> str:
    out = {k: v for k, v in base.items() if k != "strings"}
    out["strings"] = strings
    return json.dumps(out, ensure_ascii=False, indent=2) + "\n"


def run_merge(base_p: Path, ours_p: Path, theirs_p: Path,
              out_p: Path, conflicts_p: Path | None) -> int:
    base = load_catalog(base_p)
    ours = load_catalog(ours_p)
    theirs = load_catalog(theirs_p)
    merged, conflicts = merge_catalogs(base, ours, theirs)
    out_p.write_text(dump_catalog(base, merged), encoding="utf-8")
    print(f"合并完成：base {len(base['strings'])} 键 → 结果 {len(merged)} 键"
          f"（ours {len(ours['strings'])}／theirs {len(theirs['strings'])}）")
    if conflicts:
        print(f"冲突 {len(conflicts)} 处（输出先取我方，须人工裁）：")
        for c in conflicts:
            print(f"  冲突 键={c['key']} 单元={c['unit']}")
        if conflicts_p:
            conflicts_p.write_text(
                json.dumps(conflicts, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8")
            print(f"冲突清单已写 {conflicts_p}")
        return 2
    print("无冲突。")
    return 0


def run_self_test() -> int:
    root = Path(__file__).resolve().parent / "fixtures" / "xcstrings-merge"
    base = load_catalog(root / "base.xcstrings")
    ours = load_catalog(root / "ours.xcstrings")
    theirs = load_catalog(root / "theirs.xcstrings")
    merged, conflicts = merge_catalogs(base, ours, theirs)
    expected = load_catalog(root / "expected-merged.xcstrings")["strings"]
    expected_conflicts = json.loads(
        (root / "expected-conflicts.json").read_text(encoding="utf-8"))
    ok = True
    if merged != expected:
        ok = False
        print("合并结果与期望不一致：")
        for k in sorted(set(merged) | set(expected)):
            if merged.get(k) != expected.get(k):
                print(f"  键 {k}：得到 {merged.get(k)} 期望 {expected.get(k)}")
    if conflicts != expected_conflicts:
        ok = False
        print(f"冲突清单与期望不一致：得到 {conflicts} 期望 {expected_conflicts}")
    print("自测通过。" if ok else "自测失败。")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="xcstrings 三方并集对账")
    parser.add_argument("base", nargs="?", type=Path)
    parser.add_argument("ours", nargs="?", type=Path)
    parser.add_argument("theirs", nargs="?", type=Path)
    parser.add_argument("-o", "--output", type=Path, help="合并结果写出路径")
    parser.add_argument("--conflicts", type=Path, help="冲突清单 JSON 写出路径")
    parser.add_argument("--self-test", action="store_true", help="跑样本自测")
    args = parser.parse_args()
    if args.self_test:
        return run_self_test()
    if not (args.base and args.ours and args.theirs and args.output):
        parser.error("需要 BASE OURS THEIRS 与 -o 输出路径（或 --self-test）")
    return run_merge(args.base, args.ours, args.theirs,
                     args.output, args.conflicts)


if __name__ == "__main__":
    sys.exit(main())
