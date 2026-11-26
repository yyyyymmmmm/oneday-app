#!/usr/bin/env python3
"""Import smoke self-test for hermes-deploy packages.

Attempts to import all MODULES and web_routers patches according to the
container mount layout in install.sh. Any import failure means the package
is broken (missing dependencies or wrong import paths) and cannot deploy.

Usage (inside hermes container):
    python3 /opt/hermes/gateway/platforms/import_smoke_selftest.py

Exit codes:
    0: all imports succeeded
    1: at least one import failed (details in stderr)
"""
import sys
import traceback

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

if __name__ == "__main__":
    total_modules = (len(GATEWAY_PLATFORMS_MODULES) + len(TOOLS_MODULES) +
                     len(AGENT_MODULES) + len(WEB_ROUTERS_MODULES))

    print(f"导入冒烟测试开始（共 {total_modules} 个模块）...", file=sys.stderr)
    passed, failed = test_imports()

    if failed == 0:
        print(f"✓ 全部 {passed} 个模块导入成功", file=sys.stderr)
        sys.exit(0)
    else:
        print(f"✗ {failed}/{total_modules} 个模块导入失败", file=sys.stderr)
        sys.exit(1)
