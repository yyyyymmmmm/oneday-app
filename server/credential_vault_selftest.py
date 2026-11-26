#!/usr/bin/env python3
"""Credential vault package selftest. Run: python3 credential_vault_selftest.py"""

import json
import tempfile
import time
from pathlib import Path

from patches import credential_vault as vault

fails = []
skips = []


def check(name, cond):
    print(f"  {'ok' if cond else 'FAIL'} {name}")
    if not cond:
        fails.append(name)


def skip(name, reason):
    print(f"  SKIP {name}: {reason}")
    skips.append(name)


tmp = Path(tempfile.mkdtemp(prefix="credential-vault-selftest-"))
vault.STORE_PATH = tmp / "vault.json"
vault.AUDIT_PATH = tmp / "audit.jsonl"
vault._requests.clear()
key = "selftest-existing-api-server-key"
secret = "NEVER-LOG-THIS-SECRET"

print("== metadata allowlist and write-only response ==")
entry_id = ""
if vault.AESGCM is None:
    skip("encrypted storage and vault_use checks", "AESGCM provider unavailable")
else:
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
audit_card = vault.create_request("Audit demo", "example.test", "Sign in", ["password"], "sess-audit")
audit_status, audit_receipt = vault.fulfill_request(
    audit_card["request_id"], {"decision": "reject"}, key, "sess-audit")
audit_rows = [json.loads(line) for line in vault.AUDIT_PATH.read_text().splitlines()]
check("request create and reject audited", audit_status == 200
      and audit_receipt == {"status": "rejected"}
      and [r["action"] for r in audit_rows if r.get("id") == audit_card["request_id"]]
      == ["request.created", "request.rejected"])
check("request audit excludes secret", secret not in vault.AUDIT_PATH.read_text())
if vault.AESGCM is not None:
    card = vault.create_request("Demo", "example.test", "Sign in", ["password"], "sess-a")
    status, receipt = vault.fulfill_request(card["request_id"], {"decision": "fulfill", "values": {"password": secret}}, key, "sess-a")
    check("one-time fulfill returns no value", status == 200 and secret not in json.dumps(receipt))
    audit_rows = [json.loads(line) for line in vault.AUDIT_PATH.read_text().splitlines()]
    check("request create and fulfill audited", [r["action"] for r in audit_rows if r.get("id") == card["request_id"]]
          == ["request.created", "request.fulfilled"])
    status2, repeat = vault.fulfill_request(card["request_id"], {"decision": "fulfill", "values": {"password": secret}}, key, "sess-a")
    check("replay rejected", status2 == 409 and repeat == {"status": "consumed"})
    rejected = vault.create_request("Demo", "example.test", "Sign in", ["password"], "sess-reject")
    reject_status, reject_receipt = vault.fulfill_request(
        rejected["request_id"], {"decision": "reject"}, key, "sess-reject")
    audit_rows = [json.loads(line) for line in vault.AUDIT_PATH.read_text().splitlines()]
    check("request reject audited", reject_status == 200 and reject_receipt == {"status": "rejected"}
          and [r["action"] for r in audit_rows if r.get("id") == rejected["request_id"]]
          == ["request.created", "request.rejected"])
    check("request audit excludes secret", secret not in vault.AUDIT_PATH.read_text())
    expired = vault.create_request("Demo", "example.test", "Sign in", ["password"], "sess-b")
    vault._requests[expired["request_id"]]["expires_at"] = time.time() - 1
    status3, expired_result = vault.fulfill_request(expired["request_id"], {"decision": "fulfill", "values": {"password": secret}}, key, "sess-b")
    check("TTL expiry rejected", status3 == 410 and expired_result == {"status": "expired"})

print("== request list contract ==")
vault._requests.clear()
now = time.time()
def seed_request(request_id, service, session_id="list-sess", scope="scope-a", status="pending", created_at=now, expires_at=now + 60):
    vault._requests[request_id] = {
        "service": service, "domain": service.lower() + ".example", "reason": service,
        "fields": ["password"], "session_id": session_id, "created_at": created_at,
        "expires_at": expires_at, "status": status, "scope": scope,
    }
seed_request("vreq_old", "Old", status="superseded", created_at=now - 2)
seed_request("vreq_new", "New", created_at=now - 1)
seed_request("vreq_other_session", "Other session", session_id="other-sess")
seed_request("vreq_other_scope", "Other scope", scope="scope-b")
seed_request("vreq_expired", "Expired", expires_at=now - 1)
pending_rows = vault.list_requests("list-sess", "scope-a")
check("session and scope isolation", [r["request_id"] for r in pending_rows] == ["vreq_new"])
all_rows = vault.list_requests("list-sess", "scope-a", None)
check("newest first", [r["request_id"] for r in all_rows] == ["vreq_expired", "vreq_new", "vreq_old"])
expected_keys = {"request_id", "service", "domain", "reason", "fields", "status", "expires_at"}
check("client metadata exact keys", bool(pending_rows) and all(set(row) == expected_keys for row in all_rows))
check("metadata field types", pending_rows[0]["fields"] == ["password"] and isinstance(pending_rows[0]["expires_at"], (int, float)))
check("status filter and no-filter", vault.list_requests("list-sess", "scope-a", "expired")[0]["status"] == "expired"
      and len(all_rows) == 3
      and vault.list_requests("list-sess", "scope-a", "")[0]["request_id"] == "vreq_expired")
check("lazy expiry mutates pending", vault._requests["vreq_expired"]["status"] == "expired")

print("== vault_use authorization ==")
if entry_id:
    denied = vault.vault_use(entry_id, "evil.test", "login", "submit", api_key=key)
    check("domain mismatch denied", denied.get("status") == "denied" and "domain" in denied.get("summary", ""))
    check("unknown operation denied", vault.vault_use(entry_id, "example.test", "login", "submit", api_key=key).get("status") == "denied")

print(f"credential_vault_selftest: {len(fails)} failures, {len(skips)} skipped")
raise SystemExit(1 if fails else 0)
