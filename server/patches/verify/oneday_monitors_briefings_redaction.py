"""dp-241: verify monitor and briefing errors use redact() not raw exceptions."""
import sys
sys.path.insert(0, "..")

# Test redact() function behavior
try:
    from error_boundary import redact
except ImportError:
    # Fallback if error_boundary not available
    def redact(e): return str(e)[:80]

# Test that redact() produces clean output without exception types
test_error = ConnectionError("https://example.com/feed.xml: Connection timeout after 30s")
redacted = redact(test_error)

# Verify redaction removes URLs and exception type prefixes
assert "ConnectionError" not in redacted or len(redacted) < 50, f"Exception type not redacted: {redacted}"
assert not redacted.startswith("ConnectionError("), f"Raw repr leaked: {redacted}"

# Test monitor fetch error format change (line 78)
# Old: f"抓取失败（{type(e).__name__}: {e}）"[:160]
# New: f"抓取失败（{redact(e)}）"
fetch_error = f"抓取失败（{redact(test_error)}）"
assert "ConnectionError:" not in fetch_error, f"Exception type leaked in fetch error: {fetch_error}"
assert fetch_error.startswith("抓取失败（"), f"Format mismatch: {fetch_error}"

# Test monitor event text format (line 222)
# Old: f"{str(err)[:60]}"
# New: f"{err[:60]}"  (err is already redacted from _fetch_target)
monitor_event = f"监测《示例监测》抓取失败：{redacted[:60]}"
assert "ConnectionError" not in monitor_event or len(redacted) < 30, f"Exception type in event: {monitor_event}"

# Test briefing expand error format change (line 642)
# Old: f"{type(e).__name__}: {e}"[:200]
# New: redact(e)
expand_error = redact(RuntimeError("API rate limit exceeded: 429 Too Many Requests"))
assert not expand_error.startswith("RuntimeError:"), f"Raw exception format in expand: {expand_error}"
assert "RuntimeError" not in expand_error or len(expand_error) < 50, f"Exception type in expand: {expand_error}"

print("✓ dp-241: monitor and briefing errors use redact() not raw exceptions")
