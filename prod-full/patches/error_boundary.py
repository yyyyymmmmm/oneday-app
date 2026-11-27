"""Shared user-facing error boundary for gateway patches."""
from __future__ import annotations

import re
from dataclasses import dataclass

ERROR_CODES = {
    "invalid_argument": "invalid_argument",
    "permission_denied": "permission_denied",
    "not_found": "not_found",
    "upstream_error": "upstream_error",
    "internal_error": "internal_error",
}

_PATH = re.compile(r"(?:[A-Za-z]:)?/(?:[^\s/]+/)+[^\s]+")

@dataclass(frozen=True)
class BoundaryError:
    code: str
    message: str
    field: str | None = None

    def as_dict(self) -> dict:
        out = {"code": self.code, "error": self.message}
        if self.field:
            out["field"] = self.field
        return out

def redact(value: object) -> str:
    text = str(value or "")
    text = _PATH.sub("[内部路径]", text)
    text = re.sub(r"https?://[^\s]+", "[上游地址]", text)
    return re.sub(r"\s+", " ", text).strip()[:160]

def error_response(exc: BaseException, *, status: int = 500) -> tuple[int, dict]:
    """Return a stable, non-sensitive response; details remain server logs."""
    code = "upstream_error" if isinstance(exc, (TimeoutError, ConnectionError)) else "internal_error"
    message = "上游服务暂时不可用，请稍后重试" if code == "upstream_error" else "服务器内部错误，请稍后重试"
    return status, BoundaryError(ERROR_CODES[code], message).as_dict()

def invalid_argument(message: str, field: str) -> tuple[int, dict]:
    return 400, BoundaryError(ERROR_CODES["invalid_argument"], message, field).as_dict()

def not_found(message: str = "未找到请求的记录") -> tuple[int, dict]:
    return 404, BoundaryError(ERROR_CODES["not_found"], message).as_dict()

def unavailable() -> tuple[int, dict]:
    return 409, BoundaryError(ERROR_CODES["internal_error"], "写入服务当前不可用，请稍后重试").as_dict()
