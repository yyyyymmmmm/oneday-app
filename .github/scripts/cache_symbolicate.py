"""lldb 命令 cache-sym：对已 target create 的 dyld 共享缓存，
按「镜像名＋文件偏移」解析函数名（模拟器运行时框架只在缓存里、
无独立二进制文件，atos 无从下手时的点名路）。

用法（lldb batch）：
  target create <dyld_shared_cache_arm64>
  command script import cache_symbolicate.py
  cache-sym SwiftData 502888 569200 645616
"""
import lldb


def cache_sym(debugger, command, result, internal_dict):
    args = command.split()
    if len(args) < 2:
        result.PutCString(
            "usage: cache-sym <ModuleName> <offset> [offset...]"
        )
        return
    name = args[0]
    try:
        offsets = [int(a) for a in args[1:]]
    except ValueError:
        result.PutCString("<bad offset>")
        return
    target = debugger.GetSelectedTarget()
    if not target:
        result.PutCString("<no target>")
        return
    mod = None
    for m in target.module_iter():
        fs = m.GetFileSpec()
        if fs and fs.GetFilename() == name:
            mod = m
            break
    if mod is None:
        result.PutCString("<module %s not in target>" % name)
        return
    header = mod.GetObjectFileHeaderAddress()
    base = header.GetFileAddress()
    result.PutCString(
        "module %s header file addr = 0x%x" % (name, base)
    )
    for off in offsets:
        addr = target.ResolveFileAddress(base + off)
        sym = addr.GetSymbol()
        func = addr.GetFunction()
        label = None
        if func:
            label = func.GetName()
        elif sym:
            label = "%s +%d" % (
                sym.GetName(),
                (base + off) - sym.GetStartAddress().GetFileAddress(),
            )
        le = addr.GetLineEntry()
        loc = ""
        if le and le.GetFileSpec():
            loc = " %s:%d" % (
                le.GetFileSpec().GetFilename(), le.GetLineNumber()
            )
        result.PutCString("  +%-8d -> %s%s" % (off, label, loc))


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f cache_symbolicate.cache_sym cache-sym"
    )
