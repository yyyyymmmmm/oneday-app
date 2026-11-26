from error_boundary import error_response, invalid_argument, redact

def test_redact():
    assert "/secret/file" not in redact("open /secret/file failed")

def test_codes_and_fields():
    status, body = invalid_argument("动作不合法", "action")
    assert status == 400 and body["code"] == "invalid_argument" and body["field"] == "action"

def test_internal_is_stable():
    status, body = error_response(RuntimeError("token /opt/app/x"))
    assert status == 500 and body == {"code": "internal_error", "error": "服务器内部错误，请稍后重试"}

if __name__ == "__main__":
    test_redact(); test_codes_and_fields(); test_internal_is_stable()
