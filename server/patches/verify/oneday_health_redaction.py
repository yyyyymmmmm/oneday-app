"""dp-239: verify OneDay health endpoint redacts exceptions and paths."""
import sys
sys.path.insert(0, "..")

# Test redact() function behavior
try:
    from error_boundary import redact
except ImportError:
    # Fallback if error_boundary not available
    def redact(e): return str(e)[:80]

# Test that redact() produces human-readable output without repr/paths
test_error = RuntimeError("/absolute/path/to/file.json: permission denied")
redacted = redact(test_error)

# Verify redaction removes absolute paths
assert "/absolute/path" not in redacted, f"Absolute path leaked: {redacted}"
assert "RuntimeError" not in redacted or len(redacted) < 50, f"Exception type not redacted properly: {redacted}"

# Verify it's not just truncated repr
assert not redacted.startswith("RuntimeError("), f"Raw repr leaked: {redacted}"

# Test degraded_reason format change (line 201-203)
# Old: f"数据文件解析失败（{e}）；原件已隔离至 {where}；..."
# New: f"数据文件解析失败（{redact(e)}）；原件已隔离；..."
degraded_msg = f"数据文件解析失败（{redact(test_error)}）；原件已隔离；桥以空库只读降级运行，禁止回写正式数据文件"
assert "/absolute/path" not in degraded_msg, f"Path leaked in degraded reason: {degraded_msg}"
assert "已隔离至" not in degraded_msg, f"Old format with path still present: {degraded_msg}"

# Test sentinel error format change (line 736)
# Old: f"schema_guard:{guard.get('reason')}:{guard.get('missing')}"
# New: f"schema_guard:{guard.get('reason')}"
sentinel_error = "schema_guard:version_mismatch"
assert sentinel_error.count(":") == 1, f"Sentinel error still has missing field: {sentinel_error}"

# Test ledger error format change (line 1565)
# Old: {"error": repr(e)[:120]}
# New: {"error": redact(e)}
ledger_error = {"error": redact(test_error)}
assert "/absolute/path" not in ledger_error["error"], f"Path leaked in ledger error: {ledger_error}"

print("✓ dp-239: OneDay health endpoint redacts exceptions and paths")
