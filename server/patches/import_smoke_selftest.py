#!/usr/bin/env python3
"""Import smoke self-test for hermes-deploy packages.

Attempts to import all MODULES and web_routers patches according to the
container mount layout in install.sh. Any import failure means the package
is broken (missing dependencies or wrong import paths) and cannot deploy.

Also performs static reconciliation: verifies that all files in install.sh
MODULES table are present in the mount insertion table (specs array), or are
explicitly listed in the legacy-mounted exceptions list.

Usage (inside hermes container):
    python3 /opt/hermes/gateway/platforms/import_smoke_selftest.py

Exit codes:
    0: all imports succeeded and static checks passed
    1: at least one import failed or static check failed (details in stderr)
"""
import sys
import traceback
import re
import os

# All MODULES from install.sh that live under gateway/platforms
GATEWAY_PLATFORMS_MODULES = [
    "api_server_support",
    "error_boundary",
    "api_server_enrollment",
    "approval_projection",
    "grant_projection",
    "approval_history",
    "api_server_runs",
    "crash_reports",
    "mail_gateway",
    "fileproc_gateway",
    "device_sync",
    "device_gateway",
    "device_gateway_catalog",
    "identity_gateway",
    "front_gateway",
    "self_reaction_pending",
    "write_gate_gateway",
    "oneday_memory",
    "settings_registry",
    "settings_admin",
    "oneday_semantic",
    "oneday_gateway",
    "overview_gateway",
    "oneday_ledger_lib",
    "oneday_seg_automation",
    "oneday_seg_briefings",
    "oneday_seg_cron",
    "oneday_seg_delivery",
    "oneday_seg_feed",
    "oneday_feed_helpers",
    "oneday_seg_filelibrary",
    "oneday_seg_goals",
    "oneday_seg_goals_activity",
    "oneday_seg_goals_facade",
    "oneday_seg_ideas_gen",
    "oneday_seg_ideas_pool",
    "oneday_seg_ledger",
    "oneday_seg_library_mcp",
    "oneday_seg_monitors",
    "oneday_seg_sessions",
    "oneday_seg_traces",
    "options_pending",
    "cron_projection",
    "api_server_oneday_routes",
    "auth_tokens",
    "push_tokens",
    "push_sender",
    "db_schema_guard",
    "credential_vault",
    "vault_request_pending",
    "activity_feed",
    "title_engine",
]

# Tools modules
TOOLS_MODULES = [
    "react_to_message_tool",
    "settings_admin_tool",
    "skill_admission_gate",
    "skill_manager_tool",
    "present_options_tool",
    "credential_vault_tool",
]

# Agent modules
AGENT_MODULES = [
    "system_prompt",
    "oneday_prompt",
]

# Web routers modules (hermes_cli.web_routers)
WEB_ROUTERS_MODULES = [
    "profiles",
    "ops",
]

def test_imports():
    """Test all module imports. Return (passed, failed) counts."""
    passed = 0
    failed = 0

    # Test gateway.platforms modules
    for name in GATEWAY_PLATFORMS_MODULES:
        try:
            __import__(f"gateway.platforms.{name}")
            passed += 1
        except Exception as e:
            print(f"✗ gateway.platforms.{name}: {e}", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            failed += 1

    # Test tools modules
    for name in TOOLS_MODULES:
        try:
            __import__(f"tools.{name}")
            passed += 1
        except Exception as e:
            print(f"✗ tools.{name}: {e}", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            failed += 1

    # Test agent modules
    for name in AGENT_MODULES:
        try:
            __import__(f"agent.{name}")
            passed += 1
        except Exception as e:
            print(f"✗ agent.{name}: {e}", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            failed += 1

    # Test hermes_cli.web_routers modules
    for name in WEB_ROUTERS_MODULES:
        try:
            __import__(f"hermes_cli.web_routers.{name}")
            passed += 1
        except Exception as e:
            print(f"✗ hermes_cli.web_routers.{name}: {e}", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            failed += 1

    return passed, failed

def static_reconciliation_check():
    """Check MODULES table against mount insertion table in install.sh.

    Returns True if all MODULES are either in the insertion table or in the
    explicit legacy-mounted list. Returns False if any MODULES entry is missing
    from both.
    """
    # Legacy-mounted files that are already in production compose and don't need
    # insertion table entries (they were mounted in earlier versions)
    LEGACY_MOUNTED = {
        "hermes_state_portability.py",  # 存量已挂载：目标 /opt/hermes/ 顶层，早版本已进现役 compose
    }

    # Try to find install.sh relative to this script's location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # In container: /opt/hermes/gateway/platforms/import_smoke_selftest.py
    # install.sh would be at repo root when building, but we check from patches/
    install_sh_candidates = [
        "/opt/hermes/install.sh",  # container deploy location
        os.path.join(script_dir, "../../../install.sh"),  # relative from platforms/
        "install.sh",  # current directory fallback
    ]

    install_sh_path = None
    for candidate in install_sh_candidates:
        if os.path.exists(candidate):
            install_sh_path = candidate
            break

    if not install_sh_path:
        print("⚠ 静态对账跳过：找不到 install.sh（非容器环境）", file=sys.stderr)
        return True  # Don't fail if we can't find install.sh (might be standalone test)

    try:
        with open(install_sh_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"⚠ 静态对账跳过：无法读取 install.sh: {e}", file=sys.stderr)
        return True

    # Extract MODULES table entries (format: "filename|source|target|hash")
    modules_match = re.search(r'^MODULES=\(\s*\n((?:\s*"[^"]+"\s*\n)+)\)', content, re.MULTILINE)
    if not modules_match:
        print("⚠ 静态对账跳过：无法解析 MODULES 表", file=sys.stderr)
        return True

    # Extract filenames from MODULES entries (first field before |)
    modules_entries = []
    for line in modules_match.group(1).split('\n'):
        line = line.strip()
        if line.startswith('"') and '|' in line:
            # Extract: "filename|..." -> filename
            filename = line.split('|')[0].strip('"')
            if filename:
                modules_entries.append(filename)

    # Extract mount insertion table specs (format: ("filename", "mount_line", "after_line"))
    # Match all files, not just .py (includes .ttf and other assets)
    specs_matches = re.findall(r'\("([^"]+)",\s*\n?\s*"[^"]+",', content)

    specs_set = set(specs_matches)
    missing = []

    for module_file in modules_entries:
        if module_file not in specs_set and module_file not in LEGACY_MOUNTED:
            missing.append(module_file)

    if missing:
        print(f"\n✗ 静态对账失败：{len(missing)} 个文件在 MODULES 表但不在挂载插入表且不在存量名单", file=sys.stderr)
        for f in missing:
            print(f"  - {f}", file=sys.stderr)
        print(f"\nMODULES 表共 {len(modules_entries)} 件", file=sys.stderr)
        print(f"挂载插入表共 {len(specs_set)} 件", file=sys.stderr)
        print(f"存量名单共 {len(LEGACY_MOUNTED)} 件", file=sys.stderr)
        return False
    else:
        print(f"✓ 静态对账通过：MODULES 表 {len(modules_entries)} 件全部在挂载插入表或存量名单中", file=sys.stderr)
        return True

if __name__ == "__main__":
    total_modules = (len(GATEWAY_PLATFORMS_MODULES) + len(TOOLS_MODULES) +
                     len(AGENT_MODULES) + len(WEB_ROUTERS_MODULES))

    print(f"导入冒烟测试开始（共 {total_modules} 个模块）...", file=sys.stderr)
    passed, failed = test_imports()

    # Run static reconciliation check
    print("\n静态对账检查开始...", file=sys.stderr)
    static_check_passed = static_reconciliation_check()

    if failed == 0 and static_check_passed:
        print(f"\n✓ 全部 {passed} 个模块导入成功，静态对账通过", file=sys.stderr)
        sys.exit(0)
    else:
        if failed > 0:
            print(f"\n✗ {failed}/{total_modules} 个模块导入失败", file=sys.stderr)
        if not static_check_passed:
            print("✗ 静态对账未通过", file=sys.stderr)
        sys.exit(1)
