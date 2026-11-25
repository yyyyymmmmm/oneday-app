#!/usr/bin/env python3
"""Self-test for server/patches/push_tokens.py (batch 4b push token registry)."""

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "patches"))
import push_tokens  # noqa: E402


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        push_tokens.STORE_PATH = Path(tmp) / "push" / "tokens.json"

        # 1. Valid upsert
        token_a = "ab" * 32
        status, resp = push_tokens.register_token({
            "device_token": token_a.upper(),
            "environment": "production",
            "bundle_id": "com.oneday.app",
            "app_version": "0.50.126",
        })
        assert status == 200, (status, resp)
        assert resp["registered"] is True
        assert resp["environment"] == "production"
        assert (os.stat(push_tokens.STORE_PATH).st_mode & 0o777) == 0o600

        # 2. Idempotent upsert updates app_version while keeping single entry
        status, resp = push_tokens.register_token({
            "device_token": token_a,
            "environment": "sandbox",
            "bundle_id": "com.oneday.app",
            "app_version": "0.50.127",
        })
        assert status == 200 and resp["registered"] is True
        rows = push_tokens.list_tokens()
        assert len(rows) == 1
        assert rows[0]["environment"] == "sandbox"
        assert rows[0]["app_version"] == "0.50.127"
        assert "device_token" not in rows[0]
        assert rows[0]["token_preview"].startswith("abababab...")

        # 3. Validation rejects bad tokens / environments / missing bundle_id
        for bad in (
            {"device_token": "not-hex", "environment": "production", "bundle_id": "com.oneday.app"},
            {"device_token": "abc", "environment": "production", "bundle_id": "com.oneday.app"},
            {"device_token": token_a, "environment": "staging", "bundle_id": "com.oneday.app"},
            {"device_token": token_a, "environment": "production", "bundle_id": "  "},
        ):
            st, _ = push_tokens.register_token(bad)
            assert st == 400, (bad, st)

        # 4. Delete is idempotent
        st, resp = push_tokens.delete_token(token_a)
        assert st == 200 and resp["deleted"] is True
        st, resp = push_tokens.delete_token(token_a)
        assert st == 200 and resp["deleted"] is False
        assert push_tokens.list_tokens() == []

    print("push_tokens_selftest: ALL PASSED")


if __name__ == "__main__":
    main()
