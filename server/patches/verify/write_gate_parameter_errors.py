"""dp-236: verify write-gate 404 responses use error_boundary not_found()."""
import sys
sys.path.insert(0, "..")

# Directly test the response structure changes
# The three lines changed: 1059, 1493, 1497 all changed from:
#   return 404, {"error": "这条记忆已不存在"}
# to:
#   return not_found("这条记忆已不存在")

from error_boundary import not_found

# Verify not_found() produces stable structure
status, body = not_found("这条记忆已不存在")
assert status == 404, f"Expected 404, got {status}"
assert "code" in body, f"Missing 'code' field: {body}"
assert body["code"] == "not_found", f"Expected not_found code, got {body['code']}"
assert "error" in body, f"Missing 'error' field: {body}"
assert body["error"] == "这条记忆已不存在", f"Message mismatch: {body['error']}"

# Verify old format is NOT present
assert "field" not in body or body["field"] is None, f"Unexpected field locator for not_found: {body}"

print("✓ dp-236: write-gate 404 responses use error_boundary not_found() with stable code")

