"""Minimal proof that approval resolution exceptions cross the public error boundary."""
import asyncio
import ast
import json
import sys
import types
from pathlib import Path
from unittest.mock import patch

PATCHES = Path(__file__).resolve().parent / "patches"
sys.path.insert(0, str(PATCHES))
from error_boundary import error_response

tree = ast.parse((PATCHES / "api_server_runs.py").read_text())
function = next(node for node in tree.body if isinstance(node, ast.AsyncFunctionDef)
                and node.name == "_handle_run_approval")
module = ast.Module(body=[function], type_ignores=[])
ast.fix_missing_locations(module)
namespace = {"error_response": error_response, "logger": __import__("logging").getLogger(__name__),
             "web": types.SimpleNamespace(Request=object, Response=object,
                 json_response=lambda body, status=200: types.SimpleNamespace(
                     text=json.dumps(body, ensure_ascii=False), status=status)), "_load_owned_run": None,
             "_APPROVAL_CHOICE_ALIASES": {"approve": "once", "approved": "once", "allow": "once"},
             "_json_error": lambda *args, **kwargs: None}
exec(compile(module, str(PATCHES / "api_server_runs.py"), "exec"), namespace)
approval_handler = namespace["_handle_run_approval"]


class _Request:
    match_info = {"run_id": "run-selftest"}

    async def json(self):
        return {"choice": "once"}


class _Handler:
    gateway_runner = types.SimpleNamespace(session_authority=None)
    _run_approval_sessions = {"run-selftest": "approval-selftest"}

    def _load_owned_run(self, request, **kwargs):
        return "run-selftest", {"status": "running"}, None, None, None

    def _room_grant_token(self, request):
        return None


class _APIServer:
    _openai_error = None

    @staticmethod
    def _coerce_request_bool(value, *, default=False):
        return default


namespace["_load_owned_run"] = lambda self, request, **kwargs: self._load_owned_run(request, **kwargs)


async def _check():
    leaked = "RuntimeError: approval secret /srv/private/approval.py queue depth=41"
    approval_module = types.ModuleType("tools.approval")
    approval_module.resolve_gateway_approval = lambda *a, **kw: (_ for _ in ()).throw(RuntimeError(leaked))
    with patch.dict(sys.modules, {"tools.approval": approval_module}):
        response = await approval_handler(_Handler(), _Request(), _api_server=_APIServer())
    body = json.loads(response.text)
    assert response.status == 500
    assert body["code"] == "internal_error"
    assert body["error"] == "服务器内部错误，请稍后重试"
    assert leaked not in response.text and "/srv/private/approval.py" not in response.text


if __name__ == "__main__":
    asyncio.run(_check())
