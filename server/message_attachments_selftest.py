#!/usr/bin/env python3
"""Focused contract checks for api_server message attachment projection."""
import ast
from pathlib import Path

PKG = Path(__file__).resolve().parent
API = PKG / "patches" / "api_server.py"
DELIVERY = PKG / "patches" / "oneday_seg_delivery.py"


def main():
    tree = ast.parse(API.read_text(encoding="utf-8"))
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef)
               and n.name == "APIServerAdapter")
    method = next(n for n in cls.body if isinstance(n, ast.FunctionDef)
                  and n.name == "_message_response")
    ns = {
        "Any": object, "dict": dict, "str": str, "logger": type(
            "Logger", (), {"debug": lambda *a, **k: None})(),
        "_reactions_from_display_metadata": lambda _: [],
        "_options_from_display_metadata": lambda _: {},
        "_project_client_message": lambda m: m,
    }
    exec(compile(ast.Module(body=[method], type_ignores=[]), str(API), "exec"), ns)
    records = [{"id": "dlv_0123456789abcdefabcd", "status": "ok",
                "name": "report.pdf", "size": 123, "mime": "application/pdf",
                "kind": "pdf", "cover": {"thumb": True, "cover": False}}]
    delivery_ns = {}
    delivery_tree = ast.parse(DELIVERY.read_text(encoding="utf-8"))
    public_fn = next(n for n in delivery_tree.body
                     if isinstance(n, ast.FunctionDef)
                     and n.name == "_delivery_public")
    exec(compile(ast.Module(body=[public_fn], type_ignores=[]), str(DELIVERY), "exec"),
         delivery_ns)
    rec = {"id": records[0]["id"], "path": "/tmp/report.pdf",
           "name": records[0]["name"],
           "size": records[0]["size"], "mime": records[0]["mime"],
           "kind": records[0]["kind"], "cover": records[0]["cover"],
           "sha256": "0" * 64, "registeredAt": "now"}
    meta = delivery_ns["_delivery_public"](rec, "ok")
    import sys
    import types
    import os
    import tempfile
    import sys
    root = Path(tempfile.mkdtemp(prefix="message-attachments-register-"))
    home = root / "home"
    home.mkdir()
    os.environ.update({
        "HERMES_HOME": str(home),
        "DATA_PATH": str(root / "data.json"),
        "DELIVERY_ROOT": str(root),
        "DELIVERY_LEDGER_PATH": str(root / "deliveries.jsonl"),
        "DELIVERY_ASSET_DIR": str(root / "assets"),
        "DELIVERY_SENTINEL_DB": str(root / "state.db"),
    })
    sys.path.insert(0, str(PKG / "patches"))
    import oneday_gateway as gateway_runtime

    gateway = types.ModuleType("gateway")
    platforms = types.ModuleType("gateway.platforms")
    gateway.__path__ = []
    platforms.__path__ = []
    gateway.platforms = platforms
    platforms.oneday_gateway = gateway_runtime
    sys.modules.update({"gateway": gateway, "gateway.platforms": platforms,
                        "gateway.platforms.oneday_gateway": gateway_runtime})

    target = root / "attachment.bin"
    target.write_bytes(b"patches register anchor test")
    register = gateway_runtime._delivery_register
    code, first = register({"path": str(target), "session_id": "sid-a",
                            "message_id": 101})
    indexed = gateway_runtime._delivery_index("sid-a", 101)
    assert code == 201 and indexed and indexed[0][1][0]["id"] == first["id"]
    expected = {"id", "name", "size", "mime", "kind", "cover"}
    projected = ns["_message_response"]({"id": 101, "session_id": "sid-a",
                                          "role": "assistant", "content": "x"})
    attachment = projected["attachments"][0]
    meta = indexed[0][1][0]
    assert expected.issubset(attachment)
    assert all(attachment[k] == meta[k] for k in expected)
    assert set(attachment["cover"]) >= {"thumb", "cover"}
    assert ns["_message_response"]({"id": 999, "session_id": "sid-a"})[
        "attachments"] == []

    code, deduped = register({"path": str(target), "session_id": "sid-b",
                              "message_id": 202})
    assert code == 200 and deduped.get("deduped") is True
    assert gateway_runtime._delivery_index("sid-b", 202)[0][1][0]["id"] == first["id"]
    register({"path": str(target), "session_id": "sid-b", "message_id": 202})
    duplicate_links = [link for link in gateway_runtime._delivery_links_load()
                       if (link.get("sessionId"), link.get("messageId"),
                           link.get("deliveryId")) ==
                       ("sid-b", 202, first["id"])]
    assert len(duplicate_links) == 1

    invalid = [
        {"path": str(target), "session_id": "sid-half"},
        {"path": str(target), "message_id": 303},
        {"path": str(target), "session_id": "", "message_id": 304},
        {"path": str(target), "session_id": "sid-b", "message_id": True},
        {"path": str(target), "session_id": "sid-b", "message_id": "202"},
    ]
    before_records = len(gateway_runtime._delivery_load())
    before_links = len(gateway_runtime._delivery_links_load())
    assert all(register(body)[0] == 400 for body in invalid)
    assert len(gateway_runtime._delivery_load()) == before_records
    assert len(gateway_runtime._delivery_links_load()) == before_links

    code, unanchored = register({"path": str(target)})
    assert code == 200 and unanchored.get("deduped") is True
    assert len(gateway_runtime._delivery_links_load()) == before_links
    print("message_attachments_selftest: 8/8 passed (patches register anchors/dedup/validation/unanchored baseline + runtime projection)")


if __name__ == "__main__":
    main()
