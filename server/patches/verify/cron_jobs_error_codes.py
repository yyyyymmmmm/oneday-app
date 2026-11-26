"""dp-242: verify cron jobs API errors have stable codes and Chinese messages."""
import sys
sys.path.insert(0, "..")

# Verify error response structure at code level
# All 4xx errors should now have:
# - "error": human-readable Chinese message
# - "code": stable machine-readable code
# - "param": field name (for field-level errors)

# Test cases mapping old English messages to new structure:
test_cases = [
    # (old_english, new_chinese, new_code, param_field)
    ("Invalid job ID format", "任务 ID 格式无效", "invalid_job_id", None),
    ("Prompt must be ≤", "提示词不能超过", "prompt_too_long", "prompt"),
    ("Job not found", "未找到该任务", "job_not_found", None),
    ("Name is required", "任务名称不能为空", "name_required", "name"),
    ("Schedule is required", "执行计划不能为空", "schedule_required", "schedule"),
    ("Repeat must be a positive integer", "重复次数必须是正整数", "repeat_invalid", "repeat"),
    ("No valid fields to update", "没有可更新的有效字段", "no_valid_fields", None),
    ("Name must be ≤", "任务名称不能超过", "name_too_long", "name"),
]

# Verify that all old English messages are replaced
import re
api_server_path = "../api_server.py"
with open(api_server_path, "r", encoding="utf-8") as f:
    content = f.read()

# Check that old English messages are gone from cron jobs section
# (between line ~5100 and ~5300)
cron_section = content[content.find("def _cron_request_guard"):content.find("def _handle_cron_fire") + 1000]

for old_msg, new_msg, new_code, param in test_cases:
    # Old English message should not appear in error responses
    if old_msg in ["Prompt must be ≤", "Name must be ≤"]:
        # These are partial matches - check the full pattern isn't present
        old_pattern = f'"{old_msg}.*characters"'
        assert not re.search(old_pattern + r'["\}](?!.*"code")', cron_section), \
            f"Old English message still present without code: {old_msg}"
    else:
        old_pattern = f'"{old_msg}"'
        # Ensure if the message exists, it's accompanied by a code
        matches = re.finditer(old_pattern, cron_section)
        for match in matches:
            # Check if "code" appears nearby (within 100 chars)
            context = cron_section[match.start():match.start()+100]
            assert '"code"' in context or new_msg in context, \
                f"Old message '{old_msg}' found without code or replacement"

    # New Chinese message and code should be present
    assert new_msg in cron_section, f"New Chinese message missing: {new_msg}"
    assert new_code in cron_section, f"New error code missing: {new_code}"

    # If param is specified, verify it's in the response
    if param:
        # Find the error response with this code
        code_pos = cron_section.find(f'"{new_code}"')
        if code_pos > 0:
            # Check surrounding context for param field
            context = cron_section[max(0, code_pos-200):code_pos+100]
            assert f'"param": "{param}"' in context, \
                f"param field '{param}' missing for code '{new_code}'"

print("✓ dp-242: cron jobs API errors have stable codes and Chinese messages")
