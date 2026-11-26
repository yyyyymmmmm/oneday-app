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
vault.REQUESTS_PATH = tmp / "requests.json"
vault._requests.clear()
vault._requests_loaded.clear()
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

print("== owner mode (2.13.0: session_id=None, master-key callers) ==")
owner_rows = vault.list_requests(None, "scope-a")
check("owner lists across sessions in scope", [r["request_id"] for r in owner_rows] == ["vreq_other_session", "vreq_new"])
check("owner still scope-filtered", all(r["request_id"] != "vreq_other_scope" for r in vault.list_requests(None, "scope-a", None)))
check("owner request_status sees other session", (vault.request_status("vreq_other_session", None, "scope-a") or {}).get("status") == "pending")
check("device session still isolated", vault.request_status("vreq_other_session", "list-sess", "scope-a") is None)
owner_reject_status, owner_reject = vault.fulfill_request("vreq_other_session", {"decision": "reject"}, key, None, "scope-a")
check("owner reject settles other-session request", owner_reject_status == 200 and owner_reject.get("status") == "rejected")
check("owner-settled request leaves pending list", [r["request_id"] for r in vault.list_requests(None, "scope-a")] == ["vreq_new"])

print("== vault_use authorization ==")
if entry_id:
    denied = vault.vault_use(entry_id, "evil.test", "login", "submit", api_key=key)
    check("domain mismatch denied", denied.get("status") == "denied" and "domain" in denied.get("summary", ""))
    check("unknown operation denied", vault.vault_use(entry_id, "example.test", "login", "submit", api_key=key).get("status") == "denied")

print("== optional domains (2.17.2) ==")
if vault.AESGCM is None:
    skip("optional-domain write checks", "AESGCM provider unavailable")
else:
    status, receipt = vault.write_entry({
        "name": "NoDomain", "service": "NoDomain", "domains": [],
        "values": {"password": secret},
    }, key)
    check("empty domains accepted", status == 200)
    meta = vault.get_entry(receipt.get("id", "")) if status == 200 else None
    check("empty domains stored as []", (meta or {}).get("domains") == [])
    status, receipt = vault.write_entry({
        "name": "NoDomainKey", "service": "NoDomainKey",
        "values": {"password": secret},
    }, key)
    check("absent domains accepted", status == 200)
    status, _ = vault.write_entry({
        "name": "BadDomain", "service": "BadDomain",
        "domains": ["not a domain!!"], "values": {"password": secret},
    }, key)
    check("malformed domain still rejected", status == 400)
    status, _ = vault.write_entry({
        "name": "BadDomainType", "service": "BadDomainType",
        "domains": "example.test", "values": {"password": secret},
    }, key)
    check("non-list domains still rejected", status == 400)

print("== request durability (2.17.2: persists across restart, TTL absolute) ==")
durable = vault.create_request("Durable", "durable.test", "Sign in", ["password"], "sess-durable")
check("requests file written", vault.REQUESTS_PATH.exists()
      and durable["request_id"] in vault.REQUESTS_PATH.read_text())
check("requests file mode 0600", vault.REQUESTS_PATH.stat().st_mode & 0o777 == 0o600)
# Simulate a gateway restart: drop every in-process trace, keep the disk.
vault._requests.clear()
vault._requests_loaded.clear()
rows = vault.list_requests("sess-durable")
check("request survives restart", [r["request_id"] for r in rows] == [durable["request_id"]])
check("expires_at survives restart unchanged", bool(rows) and rows[0]["expires_at"] == durable["expires_at"])
block = vault.request_block(durable["request_id"], "sess-durable")
check("request_block canonical shape", bool(block) and block.get("type") == "vault_request"
      and block.get("request_id") == durable["request_id"]
      and block.get("service") == "Durable" and block.get("domain") == "durable.test"
      and block.get("fields") == ["password"] and block.get("status") == "pending")
check("request_block session isolation", vault.request_block(durable["request_id"], "sess-other") is None)
status, receipt = vault.fulfill_request(
    durable["request_id"], {"decision": "reject"}, key, "sess-durable")
check("fulfill works after restart reload", status == 200 and receipt == {"status": "rejected"})
# TTL is governed by the original absolute expires_at, even across restarts:
stale = vault.create_request("Stale", "stale.test", "Sign in", ["password"], "sess-stale")
stored = json.loads(vault.REQUESTS_PATH.read_text())
stored["requests"][stale["request_id"]]["expires_at"] = time.time() - 5
vault.REQUESTS_PATH.write_text(json.dumps(stored))
vault._requests.clear()
vault._requests_loaded.clear()
check("lapsed TTL expires after restart", vault.list_requests("sess-stale") == []
      and (vault.request_status(stale["request_id"], "sess-stale") or {}).get("status") == "expired")
check("block reports lapsed request as expired",
      (vault.request_block(stale["request_id"], "sess-stale") or {}).get("status") == "expired")

print("== vault_request_pending block shape (2.17.2) ==")
from patches import vault_request_pending as vrp
good = {"type": "vault_request", "request_id": "vreq_abc123", "service": "Demo",
        "domain": "example.test", "reason": "Sign in", "fields": ["password"],
        "status": "pending", "expires_at": 1899999999}
check("validate_block accepts canonical", vrp.validate_block(good) == good)
check("validate_block rejects wrong type", vrp.validate_block({**good, "type": "options"}) is None)
check("validate_block rejects bad id", vrp.validate_block({**good, "request_id": "dlv_abc"}) is None)
check("validate_block rejects empty fields", vrp.validate_block({**good, "fields": []}) is None)
check("validate_block rejects non-dict", vrp.validate_block("vault_request") is None)
check("pending put/list/drop roundtrip",
      vrp.put("sess-p", "run-key", "vreq_abc123", "default")
      and [e["request_id"] for e in vrp.list_pending("sess-p")] == ["vreq_abc123"]
      and vrp.drop("sess-p", vrp.list_pending("sess-p")[0]["card_id"]) is not None
      and vrp.list_pending("sess-p") == [])

print(f"credential_vault_selftest: {len(fails)} failures, {len(skips)} skipped")
raise SystemExit(1 if fails else 0)
