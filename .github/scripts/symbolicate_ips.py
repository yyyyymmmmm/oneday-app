#!/usr/bin/env python3
"""§184 取证补口：.ips 全量解析＋帧符号化。

对每份 .ips：打印异常、usedImages 全表、故障线程全部帧；
无符号帧按镜像分组找二进制（本机构建产物 DerivedData、
模拟器运行时卷、Xcode 模拟器 SDK），UUID 对上后用 atos 符号化。
只读，不改任何文件。
"""
import glob
import json
import os
import subprocess
import sys


def load_ips(path):
    with open(path, "rb") as fh:
        data = fh.read().decode("utf-8", "replace")
    nl = data.find("\n")
    return json.loads(data[nl + 1:])


def sdk_roots():
    roots = []
    for sdk in ("iphonesimulator", "macosx"):
        try:
            r = subprocess.run(
                ["xcrun", "--sdk", sdk, "--show-sdk-path"],
                capture_output=True, text=True, timeout=30,
            )
            path = r.stdout.strip()
            if path:
                roots.append(path)
        except Exception:
            pass
    for pat in (
        "/Applications/Xcode*.app/Contents/Developer/Platforms/"
        "iPhoneSimulator.platform/Developer/SDKs/*.sdk",
    ):
        roots.extend(glob.glob(pat))
    return roots


def find_binary(name):
    if not name:
        return []
    dd = os.path.expanduser(
        "~/Library/Developer/Xcode/DerivedData/*/Build/Products/"
        "Debug-iphonesimulator"
    )
    pats = [
        dd + "/**/" + name,
        dd + "/" + name + ".framework/" + name,
        dd + "/" + name + ".app/" + name,
        "/Library/Developer/CoreSimulator/Volumes/*/System/Library/"
        "Frameworks/" + name + ".framework/" + name,
        "/Library/Developer/CoreSimulator/Volumes/*/System/Library/"
        "PrivateFrameworks/" + name + ".framework/" + name,
        "/Library/Developer/CoreSimulator/Volumes/*/usr/lib/" + name,
        "/Library/Developer/CoreSimulator/Volumes/*/usr/lib/swift/" + name,
    ]
    vol = "/Volumes"
    pats += [
        vol + "/*/System/Library/Frameworks/" + name + ".framework/"
        + name,
        vol + "/*/System/Library/PrivateFrameworks/" + name
        + ".framework/" + name,
        vol + "/*/*/" + name + ".framework/" + name,
        vol + "/*/usr/lib/" + name,
        vol + "/*/usr/lib/swift/" + name,
    ]
    for sdk in sdk_roots():
        pats += [
            sdk + "/System/Library/Frameworks/" + name + ".framework/"
            + name,
            sdk + "/System/Library/PrivateFrameworks/" + name
            + ".framework/" + name,
            sdk + "/usr/lib/" + name,
            sdk + "/usr/lib/swift/" + name,
        ]
    seen, out = set(), []
    for pat in pats:
        for cand in glob.glob(pat, recursive=True):
            if os.path.isfile(cand) and cand not in seen:
                seen.add(cand)
                out.append(cand)
    if not out:
        try:
            r = subprocess.run(
                ["find", "/Library/Developer/CoreSimulator",
                 "-maxdepth", "8", "-name", name + ".framework"],
                capture_output=True, text=True, timeout=90,
            )
            for line in r.stdout.splitlines():
                cand = os.path.join(line.strip(), name)
                if os.path.isfile(cand) and cand not in seen:
                    seen.add(cand)
                    out.append(cand)
        except Exception:
            pass
    return out


def uuid_of(binary):
    try:
        r = subprocess.run(
            ["dwarfdump", "--uuid", binary],
            capture_output=True, text=True, timeout=60,
        )
        for tok in r.stdout.replace(":", " ").split():
            if len(tok) == 36 and tok.count("-") == 4:
                return tok.lower()
    except Exception:
        pass
    return None


def atos(binary, base, offsets):
    addrs = [str(base + o) for o in offsets]
    try:
        r = subprocess.run(
            ["atos", "-o", binary, "-arch", "arm64", "-l", str(base)] + addrs,
            capture_output=True, text=True, timeout=120,
        )
        lines = r.stdout.strip().split("\n") if r.stdout.strip() else []
        return lines
    except Exception as exc:  # noqa: BLE001
        return ["<atos failed: %s>" % exc]


def main():
    print("sdk_roots: %s" % sdk_roots())
    for path in sys.argv[1:]:
        print("##### IPS: %s" % path)
        try:
            rep = load_ips(path)
        except Exception as exc:  # noqa: BLE001
            print("  <parse failed: %s>" % exc)
            continue
        print("  exception: %s" % rep.get("exception"))
        print("  termination: %s" % rep.get("termination"))
        imgs = rep.get("usedImages", [])
        print("  usedImages (%d):" % len(imgs))
        for i, im in enumerate(imgs):
            print(
                "    [%d] %s base=%s size=%s uuid=%s"
                % (i, im.get("name"), im.get("base"), im.get("size"),
                   im.get("uuid"))
            )
        fidx = rep.get("faultingThread", 0)
        threads = rep.get("threads", [])
        if fidx >= len(threads):
            continue
        th = threads[fidx]
        frames = th.get("frames", [])
        print("  faultingThread %d frames (%d):" % (fidx, len(frames)))
        missing = {}
        for i, fr in enumerate(frames):
            idx = fr.get("imageIndex")
            im = imgs[idx] if idx is not None and idx < len(imgs) else {}
            sym = fr.get("symbol")
            print(
                "    f%-3d img%-3s %-28s off=%-9s %s"
                % (i, idx, im.get("name"), fr.get("imageOffset"),
                   (sym or "<no symbol>"))
            )
            if not sym and idx is not None:
                missing.setdefault(idx, []).append((i, fr.get("imageOffset")))
        for idx, flist in sorted(missing.items()):
            im = imgs[idx]
            name = im.get("name")
            base = im.get("base") or 0
            want_uuid = (im.get("uuid") or "").lower()
            print(
                "  -- symbolicate img %d (%s), %d frames --"
                % (idx, name, len(flist))
            )
            bins = find_binary(name)
            if not bins:
                print("     <no binary found for %s>" % name)
                continue
            for binary in bins[:3]:
                bu = uuid_of(binary)
                match = "UUID MATCH" if bu == want_uuid else (
                    "uuid mismatch (bin=%s want=%s)" % (bu, want_uuid)
                )
                print("     binary: %s [%s]" % (binary, match))
                if bu != want_uuid:
                    continue
                results = atos(binary, base, [o for _, o in flist])
                for (fi, off), res in zip(flist, results):
                    print("     f%-3d off=%-9s -> %s" % (fi, off, res))
                break


if __name__ == "__main__":
    main()
