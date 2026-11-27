#!/usr/bin/env python3
"""查询 /v1/capabilities 确认草稿端点清单"""
import json
import os
import sys
import requests

# 从环境变量读取服务器配置
base_url = os.getenv("HERMES_BASE_URL", "").rstrip("/")
api_key = os.getenv("HERMES_API_KEY", "")

if not base_url or not api_key:
    print("错误：需要环境变量 HERMES_BASE_URL 和 HERMES_API_KEY", file=sys.stderr)
    sys.exit(1)

try:
    resp = requests.get(
        f"{base_url}/v1/capabilities",
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=10
    )
    resp.raise_for_status()
    data = resp.json()

    print("=== Capabilities 端点清单（mail 相关） ===\n")
    endpoints = data.get("endpoints", {})

    # 只打印邮件相关端点
    mail_endpoints = {k: v for k, v in endpoints.items() if "mail" in k.lower()}

    if mail_endpoints:
        for key, ep in sorted(mail_endpoints.items()):
            method = ep.get("method", "?")
            path = ep.get("path", "?")
            print(f"{key:30s} {method:6s} {path}")
    else:
        print("（无 mail 相关端点）")

    print("\n=== 草稿端点核查结果 ===")
    has_list = "mail_drafts" in endpoints or "mail_draft_list" in endpoints
    has_create = "mail_draft_create" in endpoints or "mail_drafts_create" in endpoints
    has_send = "mail_draft_send" in endpoints
    has_update = "mail_draft_update" in endpoints
    has_delete = "mail_draft_delete" in endpoints

    print(f"草稿列表（GET）:   {'✓' if has_list else '✗'}")
    print(f"创建草稿（POST）:  {'✓' if has_create else '✗'}")
    print(f"发送草稿（POST）:  {'✓' if has_send else '✗'}")
    print(f"更新草稿（PUT）:   {'✓' if has_update else '✗'}")
    print(f"删除草稿（DELETE）: {'✓' if has_delete else '✗'}")

    # 写 JSON 文件供后续读取
    with open("/tmp/capabilities_mail.json", "w") as f:
        json.dump({
            "has_list": has_list,
            "has_create": has_create,
            "has_send": has_send,
            "has_update": has_update,
            "has_delete": has_delete,
            "mail_endpoints": mail_endpoints
        }, f, indent=2)

    print("\n结果已写入 /tmp/capabilities_mail.json")

except Exception as e:
    print(f"查询失败: {e}", file=sys.stderr)
    sys.exit(1)
