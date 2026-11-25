#!/usr/bin/env python3
"""Self-test for server/patches/auth_tokens.py (ADR #1 short-lived tokens)."""

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "patches"))
import auth_tokens  # noqa: E402


def main() -> None:
    api_key = "test-master-api-key-1234567890"
    t0 = 1_700_000_000.0

    with tempfile.TemporaryDirectory() as tmp:
        auth_tokens.STORE_PATH = Path(tmp) / "auth" / "sessions.json"

        # 1. Exchange API key -> short-lived pair (24h access, 30d refresh)
        pair1 = auth_tokens.exchange_key_for_tokens(
            api_key=api_key, device_name="iPhone 17 Pro", app_version="0.50.126", now=t0
        )
        assert pair1["expires_in"] == 86400
        assert pair1["access_token"].startswith("odt1.")
        assert pair1["refresh_token"].startswith("odr1.")
        assert (os.stat(auth_tokens.STORE_PATH).st_mode & 0o777) == 0o600

        # 2. Verify valid access token & reject expired access token
        ok, sid, err = auth_tokens.verify_access_token(
            pair1["access_token"], api_key=api_key, now=t0 + 100
        )
        assert ok and sid == pair1["session_id"] and err is None
        ok_exp, _, err_exp = auth_tokens.verify_access_token(
            pair1["access_token"], api_key=api_key, now=t0 + 86401
        )
        assert not ok_exp and err_exp == "access_token_expired"

        # 3. Rotate refresh token -> new pair minted
        st, pair2 = auth_tokens.refresh_tokens(
            refresh_token=pair1["refresh_token"], api_key=api_key, now=t0 + 3600
        )
        assert st == 200
        assert pair2["refresh_token"] != pair1["refresh_token"]

        # 4. Concurrent refresh within 10s grace window returns same pair2 (no false kill)
        st_g, pair2_grace = auth_tokens.refresh_tokens(
            refresh_token=pair1["refresh_token"], api_key=api_key, now=t0 + 3605
        )
        assert st_g == 200 and pair2_grace["refresh_token"] == pair2["refresh_token"]

        # 5. Reuse of old refresh token AFTER 10s grace window triggers Reuse Detection!
        st_reuse, body_reuse = auth_tokens.refresh_tokens(
            refresh_token=pair1["refresh_token"], api_key=api_key, now=t0 + 3615
        )
        assert st_reuse == 401 and body_reuse["code"] == "refresh_token_reused"

        # 6. Entire session family is now revoked (both access & newer refresh fail)
        ok_after, _, err_after = auth_tokens.verify_access_token(
            pair2["access_token"], api_key=api_key, now=t0 + 3620
        )
        assert not ok_after and err_after == "session_revoked"
        st_rev, body_rev = auth_tokens.refresh_tokens(
            refresh_token=pair2["refresh_token"], api_key=api_key, now=t0 + 3620
        )
        assert st_rev == 401 and body_rev["code"] == "session_revoked"

        # 7. Multi-device listing + revoke all_other_devices keeps current session
        s_a = auth_tokens.exchange_key_for_tokens(api_key=api_key, device_name="Phone A", now=t0 + 4000)
        s_b = auth_tokens.exchange_key_for_tokens(api_key=api_key, device_name="iPad B", now=t0 + 4001)
        st_r, res_r = auth_tokens.revoke_session(
            all_other_devices=True, keep_session_id=s_a["session_id"]
        )
        assert st_r == 200 and s_b["session_id"] in res_r["session_ids"]
        ok_a, _, _ = auth_tokens.verify_access_token(s_a["access_token"], api_key=api_key, now=t0 + 4010)
        ok_b, _, _ = auth_tokens.verify_access_token(s_b["access_token"], api_key=api_key, now=t0 + 4010)
        assert ok_a and not ok_b

    print("auth_tokens_selftest: ALL PASSED")


if __name__ == "__main__":
    main()
