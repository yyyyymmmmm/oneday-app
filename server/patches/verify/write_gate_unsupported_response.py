"""dp-235: verify write-gate unsupported response uses error_boundary."""
import sys
sys.path.insert(0, "..")

# Simulate unsupported state
import write_gate_gateway as wg
original_supported = wg.SUPPORTED
wg.SUPPORTED = False

# Test _propose_memory when unsupported
status, body = wg._propose_memory({"operation": "create", "target": "memory", "content": "test"})
assert status == 409, f"Expected 409, got {status}"
assert "code" in body, f"Missing 'code' field: {body}"
assert body["code"] == "internal_error", f"Expected internal_error, got {body['code']}"
assert "error" in body, f"Missing 'error' field: {body}"
assert "写入服务当前不可用" in body["error"], f"Expected human message, got: {body['error']}"
assert "SUPPORT_ERROR" not in body["error"], f"Raw SUPPORT_ERROR leaked: {body}"
assert "write gate unsupported" not in body["error"], f"Old format leaked: {body}"

# Test get_memory when unsupported
status, body = wg.get_memory("test-id")
assert status == 409, f"Expected 409, got {status}"
assert "code" in body, f"Missing 'code' field: {body}"
assert body["code"] == "internal_error", f"Expected internal_error, got {body['code']}"
assert "写入服务当前不可用" in body["error"], f"Expected human message, got: {body['error']}"

wg.SUPPORTED = original_supported
print("✓ dp-235: write-gate unsupported responses use error_boundary")
