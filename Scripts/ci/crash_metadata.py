#!/usr/bin/env python3
"""DiagnosticReports 崩溃元数据提取（§234，大厂九项③隐私门口径）。

只收元数据：扫描 .ips 只提取崩溃判读所需的结构化字段
（时刻/进程/版本/异常类型/终止原因/出错线程顶部符号名），
绝不复制 .ips 原文。两层脱敏：
1. 字段白名单——设备名、slice_uuid、incident、文件路径、
   寄存器、内存地址、线程名等一律不进输出；
2. 全文兜底清洗——输出 JSON 再过一遍正则，把残留的
   /Users/<name>、/home/<name> 路径与 UUID 形字符串抹掉。

开关与留存在 workflow 侧：vars.CRASH_METADATA_COLLECTION
=off 即整步跳过（可关）；artifact retention-days 限期。

用法：
  crash_metadata.py --out OUTDIR DIR [DIR ...]
  crash_metadata.py --selftest
"""
import json
import re
import sys
import tempfile
from pathlib import Path

TOP_FRAMES = 8
_UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
_USER_PATH_RE = re.compile(r"/(?:Users|home)/[^/\"\\\s]+")


def _scrub(text: str) -> str:
    text = _USER_PATH_RE.sub("/<redacted>", text)
    return _UUID_RE.sub("<redacted-uuid>", text)


def extract_metadata(path: Path) -> dict | None:
    """从单个 .ips 提取白名单元数据；解析不了返回 None。"""
    try:
        raw = path.read_text(errors="replace")
        header_line, _, body = raw.partition("\n")
        header = json.loads(header_line)
        report = json.loads(body)
    except Exception:
        return None
    meta: dict = {}
    if isinstance(header, dict):
        meta["capturedAt"] = header.get("timestamp")
        meta["process"] = header.get("app_name")
        meta["bundleID"] = header.get("bundleID")
        meta["appVersion"] = header.get("app_version")
        meta["osVersion"] = header.get("os_version")
    if isinstance(report, dict):
        meta.setdefault("process", report.get("procName"))
        bundle = report.get("bundleInfo") or {}
        if isinstance(bundle, dict):
            meta.setdefault(
                "bundleID", bundle.get("CFBundleIdentifier"))
        exception = report.get("exception") or {}
        if isinstance(exception, dict):
            meta["exceptionType"] = exception.get("type")
            meta["exceptionSignal"] = exception.get("signal")
        termination = report.get("termination") or {}
        if isinstance(termination, dict):
            meta["terminationNamespace"] = termination.get("namespace")
            meta["terminationCode"] = termination.get("code")
        for thread in report.get("threads") or []:
            if isinstance(thread, dict) and thread.get("triggered"):
                symbols = []
                for frame in thread.get("frames") or []:
                    if isinstance(frame, dict) and frame.get("symbol"):
                        symbols.append(str(frame["symbol"]))
                    if len(symbols) >= TOP_FRAMES:
                        break
                meta["faultingTopSymbols"] = symbols
                break
    return {k: v for k, v in meta.items() if v is not None}


def collect(directories: list[str]) -> list[dict]:
    reports: list[dict] = []
    seen: set[Path] = set()
    for directory in directories:
        root = Path(directory).expanduser()
        if not root.is_dir():
            continue
        for ips in sorted(root.rglob("*.ips")):
            if ips in seen:
                continue
            seen.add(ips)
            meta = extract_metadata(ips)
            if meta is not None:
                reports.append(meta)
    reports.sort(key=lambda m: str(m.get("capturedAt") or ""))
    return reports


def run(out_dir: str, directories: list[str]) -> int:
    reports = collect(directories)
    payload = {"count": len(reports), "reports": reports}
    text = _scrub(json.dumps(payload, ensure_ascii=False, indent=2))
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "crash-metadata.json").write_text(text + "\n")
    print(f"crash_metadata: {len(reports)} report(s) -> "
          f"{out / 'crash-metadata.json'}")
    return 0


SAMPLE_IPS = """{"app_name":"OneDay","timestamp":"2026-11-14 06:00:00.000 +0000","app_version":"0.50.39","build_version":"167","bundleID":"site.didichou.oneday","name":"Alice的iPhone","slice_uuid":"123e4567-e89b-12d3-a456-426614174000","os_version":"iPhone OS 26.0 (23A000)"}
{"procName":"OneDay","exception":{"type":"EXC_CRASH","signal":"SIGABRT","codes":"0x0000000000000000, 0x0000000000000000"},"termination":{"namespace":"SIGNAL","code":6},"threads":[{"id":0,"triggered":true,"frames":[{"symbol":"__pthread_kill","imageIndex":0,"sourceFile":"/Users/alice/work/pthread.c"},{"symbol":"abort","imageIndex":0},{"symbol":"OneDay.ChatView.body.getter","imageIndex":1}]}],"usedImages":[{"name":"OneDay","path":"/Users/alice/Library/OneDay.app/OneDay"}]}
"""


def selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in"
        src.mkdir()
        (src / "OneDay-2026-11-14.ips").write_text(SAMPLE_IPS)
        out = Path(tmp) / "out"
        run(str(out), [str(src)])
        text = (out / "crash-metadata.json").read_text()
    failures = []
    for leaked in ("Alice", "slice_uuid", "123e4567", "/Users/",
                   "pthread.c", "usedImages", "Alice的iPhone"):
        if leaked in text:
            failures.append(f"leaked: {leaked}")
    for expected in ("OneDay", "EXC_CRASH", "SIGABRT",
                     "OneDay.ChatView.body.getter", "site.didichou.oneday"):
        if expected not in text:
            failures.append(f"missing: {expected}")
    if failures:
        print("SELFTEST FAILED:", "; ".join(failures))
        return 1
    print("SELFTEST OK: metadata kept, PII scrubbed")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    out_dir = "crash-metadata"
    directories: list[str] = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out" and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
        else:
            directories.append(argv[i])
            i += 1
    if not directories:
        print("usage: crash_metadata.py --out DIR DIR [DIR ...]",
              file=sys.stderr)
        return 2
    return run(out_dir, directories)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
