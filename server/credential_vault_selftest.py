#!/usr/bin/env python3
"""Credential vault package selftest. Run: python3 credential_vault_selftest.py"""

import json
import tempfile
import time
from pathlib import Path

from patches import credential_vault as vault

fails = []


def check(name, cond):
    print(f"  {'ok' if cond else 'FAIL'} {name}")
    if not cond:
        fails.append(name)


tmp = Path(tempfile.mkdtemp(prefix="credential-vault-selftest-"))
vault.STORE_PATH = tmp / "vault.json"
vault.AUDIT_PATH = tmp / "audit.jsonl"
vault._requests.clear()
key = "selftest-existing-api-server-key"
secret = "NEVER-LOG-THIS-SECRET"

print("== metadata allowlist and write-only response ==")
status, receipt = vault.write_entry({
    "name": "Demo", "service": "Demo", "domains": ["example.test"],
    "username": "alice", "values": {"password": secret},
    "secret_ref": "should-not-survive",
}, key)
check("write accepted", status == 200 and set(receipt) == {"id", "version", "updated_at", "status"})
entry_id = receipt.get("id", "")
metadata = vault.get_entry(entry_id)
check("metadata exact whitelist", set(metadata or {}) == {
    "id", "name", "service", "domains", "username", "field_names",
    "updated_at", "version", "has_secret"})
check("metadata has no secret values", secret not in json.dumps(metadata))
raw = vault.STORE_PATH.read_text()
check("disk ciphertext only", secret not in raw and "ciphertext" in raw and "sealed" in raw)
check("store mode 0600", vault.STORE_PATH.stat().st_mode & 0o777 == 0o600)
check("audit excludes secret", secret not in vault.AUDIT_PATH.read_text())

print("== request card lifecycle ==")
card = vault.create_request("Demo", "example.test", "Sign in", ["password"], "sess-a")
status, receipt = vault.fulfill_request(card["request_id"], {"decision": "fulfill", "values": {"password": secret}}, key, "sess-a")
check("one-time fulfill returns no value", status == 200 and secret not in json.dumps(receipt))
status2, repeat = vault.fulfill_request(card["request_id"], {"decision": "fulfill", "values": {"password": secret}}, key, "sess-a")
check("replay rejected", status2 == 409 and repeat == {"status": "consumed"})
expired = vault.create_request("Demo", "example.test", "Sign in", ["password"], "sess-b")
vault._requests[expired["request_id"]]["expires_at"] = time.time() - 1
status3, expired_result = vault.fulfill_request(expired["request_id"], {"decision": "fulfill", "values": {"password": secret}}, key, "sess-b")
check("TTL expiry rejected", status3 == 410 and expired_result == {"status": "expired"})

print("== vault_use authorization ==")
denied = vault.vault_use(entry_id, "evil.test", "login", "submit", api_key=key)
check("domain mismatch denied", denied.get("status") == "denied" and "domain" in denied.get("summary", ""))
check("unknown operation denied", vault.vault_use(entry_id, "example.test", "login", "submit", api_key=key).get("status") == "denied")

print(f"credential_vault_selftest: {len(fails)} failures")
raise SystemExit(1 if fails else 0)
