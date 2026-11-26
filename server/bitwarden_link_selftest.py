#!/usr/bin/env python3
"""Bitwarden link (bar 1, queue 195) package selftest.

Run: python3 bitwarden_link_selftest.py        (needs `cryptography`)

Three parts:
  A. Fake-bw unit layer: an injectable bw stand-in walks the
     whitelist refusal, connect/unlock/lock/disconnect state
     machine, the resolve order (Bitwarden wins, ambiguity skips,
     name match), the degrade matrix and the negative cache.
  B. Real chain (only when BW195_REPLICA_URL is set): a throwaway
     Vaultwarden replica + a test account seeded through the real
     Bitwarden crypto (register -> token -> API key -> ciphers),
     then connect -> unlock -> resolve contrast -> ambiguity ->
     lock-degrade -> appdata-loss re-login -> disconnect, all
     against the pinned bw 2026.6.0 binary.
  C. Down phase (BW195_PHASE=down, same BW195_TMP as part B, the
     replica stopped by the operator): unlock still succeeds (bw
     unlock is local crypto), but the resolve leg's sync fails
     unreachable and resolution degrades to the built-in leg with
     the reason recorded and audited.

Sample secrets are assembled at runtime from fragments so the full
strings never appear in any file; the final checks grep the whole
temp tree for them and demand zero hits.
"""

import base64
import hashlib
import hmac as hmac_mod
import json
import os
import shutil
import sys
import tempfile
import types
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

from patches import credential_vault as vault

_gateway = types.ModuleType("gateway")
_platforms = types.ModuleType("gateway.platforms")
_platforms.credential_vault = vault
_gateway.platforms = _platforms
sys.modules.setdefault("gateway", _gateway)
sys.modules["gateway.platforms"] = _platforms

from patches import bitwarden_link as bw

_platforms.bitwarden_link = bw

fails = []


def check(name, cond):
    print(f"  {'ok' if cond else 'FAIL'} {name}")
    if not cond:
        fails.append(name)


KEY = "selftest-bw-api-server-key"
TMPROOT = Path(os.environ.get("BW195_TMP") or tempfile.mkdtemp(prefix="bw-link-selftest-"))
TMPROOT.mkdir(parents=True, exist_ok=True)
vault.STORE_PATH = TMPROOT / "vault" / "entries.json"
vault.AUDIT_PATH = TMPROOT / "vault" / "audit.jsonl"
vault.REQUESTS_PATH = TMPROOT / "vault" / "requests.json"
bw.DATA_DIR = TMPROOT / "bwlink"
bw.LINK_PATH = TMPROOT / "bwlink" / "link.json"
bw.CONFIG_DIR = TMPROOT / "bwlink" / "appdata"

SINK: dict[str, dict] = {}


def _recorder(domain, values):
    SINK[domain] = dict(values)
    return {"status": "completed", "summary": "recorded"}


vault.OPERATIONS[("probe", "fetch")] = _recorder
vault.OPERATIONS[("svcprobe", "fetch")] = _recorder


def _builtin(service, domain, password):
    for entry in vault.list_entries():
        if entry["service"] == service and domain in entry["domains"]:
            return entry["id"]
    status, receipt = vault.write_entry({
        "name": service, "service": service, "domains": [domain],
        "username": "u", "values": {"password": password}}, KEY)
    assert status == 200, receipt
    return receipt["id"]


def _audit_events():
    try:
        return [json.loads(l) for l in vault.AUDIT_PATH.read_text().splitlines() if l.strip()]
    except FileNotFoundError:
        return []


def _grep_root(root: Path, needle: str, exclude: Path | None = None) -> int:
    hits = 0
    if not root.exists():
        return 0
    for path in root.rglob("*"):
        if path.is_file() and path != exclude:
            try:
                if needle in path.read_text(encoding="utf-8", errors="ignore"):
                    hits += 1
            except Exception:
                pass
    return hits


def _grep_tree(needle: str) -> int:
    """Hits in system-written stores only (vault + link dir).

    Test fixtures (the fake bw script, its scenario file, the seed
    receipt) legitimately contain the samples as INPUTS; the zero-hit
    discipline governs what the system itself writes to disk.
    """
    return (_grep_root(TMPROOT / "vault", needle)
            + _grep_root(TMPROOT / "bwlink", needle))


def _reset_bw_state():
    bw._session_key = None
    bw._last_sync_at = None
    bw._degraded_until = 0.0
    bw._last_degraded_reason = None
    bw._last_error = None
    bw._invalidate_status_cache()


PHASE = os.environ.get("BW195_PHASE", "ab")

# ==========================================================================
# Part A -- fake bw

FAKE_MASTER = "".join(["fake-", "master-", "pw-195"])
FAKE_SECRET = "".join(["fake-", "client-", "secret-195"])
BW_PW_A = "".join(["bw-", "pw-", "alpha-195"])
BUILTIN_PW = "".join(["builtin-", "pw-", "alpha-195"])
NAME_PW = "".join(["bw-", "pw-", "nameonly-195"])


def part_a():
    print("== part A: fake bw ==")
    fake_dir = TMPROOT / "fakebw"
    fake_dir.mkdir(parents=True, exist_ok=True)
    scenario_path = fake_dir / "scenario.json"
    log_path = fake_dir / "invocations.log"
    fake_path = fake_dir / "bw"
    # The module runs bw with a clean environment, so the fake's
    # scenario/log paths are baked into the script itself.
    fake_path.write_text(FAKE_BW.replace("__SCENARIO__", str(scenario_path))
                                .replace("__LOG__", str(log_path)), encoding="utf-8")
    fake_path.chmod(0o755)
    os.environ["BITWARDEN_CLI_PATH"] = str(fake_path)

    def scenario(**kw):
        base = {"status": {"status": "locked", "serverUrl": "https://bw.example.com"},
                "master_password": FAKE_MASTER, "items": []}
        base.update(kw)
        scenario_path.write_text(json.dumps(base), encoding="utf-8")
        bw._invalidate_status_cache()

    def log_lines():
        try:
            return log_path.read_text().splitlines()
        except FileNotFoundError:
            return []

    # A0: pure classification signatures
    check("classify version signature", bw._classify(
        {"stderr": "User Decryption Options are required"}) == "version_mismatch")
    check("classify key signature", bw._classify(
        {"stderr": "Invalid client_id"}) == "key_invalid")
    check("classify password signature", bw._classify(
        {"stderr": "Invalid master password."}) == "credential")
    check("classify timeout", bw._classify({"timed_out": True}) == "timeout")
    check("whitelist has no write subcommand", not (
        bw.ALLOWED_SUBCOMMANDS & {"create", "edit", "delete", "restore",
                                   "import", "export", "serve", "send"}))

    # A1: whitelist refusal happens before spawn
    for sub in ("create", "delete", "export", "import", "edit"):
        try:
            bw._run_bw([sub, "item"])
            check(f"whitelist refuses {sub}", False)
        except bw.BwRefused:
            check(f"whitelist refuses {sub}", True)
    check("no write subcommand reached the fake",
          not any(json.loads(l)[0] in ("create", "delete", "export", "import", "edit")
                  for l in log_lines()))
    check("refusals audited", any(e.get("action") == "bitwarden.subcommand_refused"
                                  for e in _audit_events()))

    # A2: failed connect persists nothing (bad key signature)
    scenario(login_fail="Invalid client_id")
    status, payload = bw.connect_link(
        {"server_url": "https://bw.example.com", "client_id": "user.x",
         "client_secret": FAKE_SECRET}, KEY)
    check("connect bad key -> 422 key_invalid",
          status == 422 and payload["error"]["category"] == "key_invalid")
    check("connect failure persists nothing",
          bw._load_link() is None and not vault.list_entries())

    # A3: good connect
    scenario()
    status, payload = bw.connect_link(
        {"server_url": "https://bw.example.com", "client_id": "user.abc",
         "client_secret": FAKE_SECRET}, KEY)
    check("connect ok -> 201", status == 201)
    check("status locked after connect", payload["state"] == "locked")
    check("status hides credential reference", "credential_id" not in json.dumps(payload))
    check("link row stored without the secret",
          FAKE_SECRET not in bw.LINK_PATH.read_text())
    entries = [e for e in vault.list_entries() if e["service"] == "bitwarden_link"]
    check("api key pair in vault under bitwarden_link", len(entries) == 1)

    _builtin("svc", "svc.example.com", BUILTIN_PW)

    # A4: unlock, wrong then right
    status, payload = bw.unlock("wrong-password", KEY)
    check("unlock wrong password -> 401 credential",
          status == 401 and payload["error"]["category"] == "credential")
    check("unlock failure audited", any(
        e.get("action") == "bitwarden.unlock_failed" for e in _audit_events()))
    item_a = {"id": "it-a", "type": 1, "name": "svc-a",
              "login": {"username": "alice", "password": BW_PW_A,
                        "uris": [{"uri": "https://svc.example.com/login", "match": None}]}}
    scenario(items=[item_a])
    status, payload = bw.unlock(FAKE_MASTER, KEY)
    check("unlock ok -> 200 with item count", status == 200 and payload.get("items") == 1)
    check("status unlocked", bw.link_status()["state"] == "unlocked")
    check("session key never hit disk", _grep_tree("FAKE-SESSION-KEY-195") == 0)

    # A5: resolve -- Bitwarden wins the same-domain contrast
    SINK.clear()
    out = bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("resolve source bitwarden", out.get("source") == "bitwarden")
    check("resolve fed the bitwarden value", SINK.get("svc.example.com", {}).get("password") == BW_PW_A)
    check("resolve audited as vault.use source=bitwarden", any(
        e.get("action") == "vault.use" and e.get("source") == "bitwarden"
        for e in _audit_events()))

    # A6: ambiguity -- two same-host items, built-in leg takes over
    item_b = {"id": "it-b", "type": 1, "name": "svc-b",
              "login": {"username": "bob", "password": "other-pw",
                        "uris": [{"uri": "https://svc.example.com", "match": None}]}}
    scenario(items=[item_a, item_b])
    SINK.clear()
    out = bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("ambiguous bitwarden leg skipped to builtin",
          out.get("source") == "builtin" and SINK.get("svc.example.com", {}).get("password") == BUILTIN_PW)
    check("ambiguity audited", any(
        e.get("action") == "vault.resolve.ambiguous" and e.get("source") == "bitwarden"
        for e in _audit_events()))

    # A7: name-only match (tier 1)
    item_c = {"id": "it-c", "type": 1, "name": "svc",
              "login": {"username": "c", "password": NAME_PW,
                        "uris": [{"uri": "https://elsewhere.example.com", "match": None}]}}
    scenario(items=[item_c])
    SINK.clear()
    out = bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("name match wins from bitwarden",
          out.get("source") == "bitwarden" and SINK.get("svc.example.com", {}).get("password") == NAME_PW)

    # A8: lock -> resolve degrades to built-in with a locked trace
    bw.lock()
    check("status locked after lock", bw.link_status()["state"] == "locked")
    SINK.clear()
    out = bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("locked resolve uses builtin", out.get("source") == "builtin")
    check("locked degrade audited", any(
        e.get("action") == "vault.resolve.degraded" and e.get("reason") == "locked"
        for e in _audit_events()))

    # A9: sync failure -> degrade + negative cache (no second bw call)
    scenario(items=[item_a], sync_fail="getaddrinfo EAI_AGAIN temporary failure")
    bw.unlock(FAKE_MASTER, KEY)
    bw._last_sync_at = None  # force a stale sync
    before = len(log_lines())
    SINK.clear()
    out = bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("sync failure degrades to builtin", out.get("source") == "builtin")
    check("unreachable degrade audited", any(
        e.get("action") == "vault.resolve.degraded" and e.get("reason") == "unreachable"
        for e in _audit_events()))
    mid = len(log_lines())
    bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("negative cache blocks an immediate retry", len(log_lines()) == mid and mid > before)

    # A10: missing binary degrades instead of crashing
    bw._degraded_until = 0.0
    bw._bw_version_cache.update({"at": 0.0, "version": None})
    saved_path = os.environ.get("PATH", "")
    os.environ["BITWARDEN_CLI_PATH"] = "/nonexistent/bw"
    os.environ["PATH"] = str(fake_dir / "empty")
    (fake_dir / "empty").mkdir(exist_ok=True)
    check("missing binary reported", bw.link_status()["bw_installed"] is False)
    SINK.clear()
    out = bw.resolve_use("svc", "svc.example.com", "svcprobe", "fetch", api_key=KEY)
    check("missing binary resolve degrades to builtin", out.get("source") == "builtin")
    check("not_installed degrade audited", any(
        e.get("action") == "vault.resolve.degraded" and e.get("reason") == "not_installed"
        for e in _audit_events()))
    os.environ["BITWARDEN_CLI_PATH"] = str(fake_path)
    os.environ["PATH"] = saved_path

    # A11: disconnect wipes everything
    status, _payload = bw.disconnect(KEY)
    check("disconnect ok", status == 200)
    check("status unlinked after disconnect", bw.link_status()["state"] == "unlinked")
    check("link row gone", bw._load_link() is None)
    check("config dir wiped", not bw.CONFIG_DIR.exists())
    check("vault link entry revoked",
          not [e for e in vault.list_entries() if e["service"] == "bitwarden_link"])

    # A12: zero hits for every sample secret in the whole temp tree
    for label, sample in (("master password", FAKE_MASTER),
                          ("client secret", FAKE_SECRET),
                          ("bitwarden value", BW_PW_A),
                          ("session key", "FAKE-SESSION-KEY-195")):
        check(f"zero disk hits: {label}", _grep_tree(sample) == 0)

    # A13: the built-in write path carries no Bitwarden branch
    src = Path(vault.__file__).read_text(encoding="utf-8")
    check("credential_vault has no bitwarden branch", "bitwarden" not in src.lower())


FAKE_BW = r'''#!/usr/bin/env python3
import json, os, sys
with open("__LOG__", "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
scen = json.load(open("__SCENARIO__"))
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "--version":
    print("2026.6.0"); sys.exit(0)
if cmd == "status":
    print(json.dumps(scen.get("status", {"status": "locked"}))); sys.exit(0)
if cmd == "config":
    sys.exit(0)
if cmd == "login":
    if scen.get("login_fail"):
        print(scen["login_fail"], file=sys.stderr); sys.exit(1)
    print("You are logged in!"); sys.exit(0)
if cmd == "unlock":
    if os.environ.get("ONEDAY_BW_MASTER_PW", "") != scen.get("master_password"):
        print("Invalid master password.", file=sys.stderr); sys.exit(1)
    print("FAKE-SESSION-KEY-195"); sys.exit(0)
if cmd == "list":
    print(json.dumps(scen.get("items", []))); sys.exit(0)
if cmd == "sync":
    if scen.get("sync_fail"):
        print(scen["sync_fail"], file=sys.stderr); sys.exit(1)
    print("Syncing complete."); sys.exit(0)
if cmd in ("lock", "logout"):
    print("ok"); sys.exit(0)
print("unknown subcommand", file=sys.stderr); sys.exit(2)
'''

# ==========================================================================
# Part B -- real Vaultwarden replica chain

MASTER = "".join(["repl-", "master-", "pw-195-x"])
BW_CONTRAST = "".join(["bw-", "contrast-", "pw-195"])
BUILTIN_CONTRAST = "".join(["builtin-", "contrast-", "pw-195"])
BW_NAMEONLY = "".join(["bw-", "nameonly-", "pw-195"])
EMAIL = "bw195@test.local"
KDF_ITER = 600000


def _b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode()


def _hkdf_expand(prk: bytes, info: bytes) -> bytes:
    return hmac_mod.new(prk, info + b"\x01", hashlib.sha256).digest()


def _master_materials(password: str):
    master_key = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), EMAIL.lower().encode(), KDF_ITER, 32)
    stretched = _hkdf_expand(master_key, b"enc") + _hkdf_expand(master_key, b"mac")
    pw_hash = _b64(hashlib.pbkdf2_hmac("sha256", master_key, password.encode(), 1, 32))
    return stretched, pw_hash


def _enc_str(key64: bytes, data: bytes) -> str:
    from cryptography.hazmat.primitives import padding
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(data) + padder.finalize()
    enc = Cipher(algorithms.AES(key64[:32]), modes.CBC(iv)).encryptor()
    ct = enc.update(padded) + enc.finalize()
    mac = hmac_mod.new(key64[32:], iv + ct, hashlib.sha256).digest()
    return "2." + _b64(iv) + "|" + _b64(ct) + "|" + _b64(mac)


def _http(method, url, *, json_body=None, form=None, token=None):
    data = None
    headers = {}
    if json_body is not None:
        data = json.dumps(json_body).encode()
        headers["Content-Type"] = "application/json"
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode()
            return resp.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        try:
            return exc.code, json.loads(body)
        except Exception:
            return exc.code, {"raw": body}


def seed_replica(base: str) -> tuple[str, str]:
    """Register a test account and seed ciphers; return (client_id, secret)."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    stretched, pw_hash = _master_materials(MASTER)
    user_key = os.urandom(64)
    rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pub = _b64(rsa_key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo))
    priv = rsa_key.private_bytes(
        serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption())
    # Vaultwarden 1.37: registration lives under /identity and its
    # RegisterData is camelCase (the legacy /api route 404s).
    status, resp = _http("POST", base + "/identity/accounts/register", json_body={
        "email": EMAIL, "name": "BW195 Selftest",
        "masterPasswordHash": pw_hash, "masterPasswordHint": None,
        "key": _enc_str(stretched, user_key),
        "kdf": 0, "kdfIterations": KDF_ITER, "kdfMemory": None, "kdfParallelism": None,
        "keys": {"encryptedPrivateKey": _enc_str(user_key, priv), "publicKey": pub},
        "token": None, "organizationUserId": None})
    assert status in (200, 201), f"register -> {status} {resp}"
    status, tok = _http("POST", base + "/identity/connect/token", form={
        "grant_type": "password", "username": EMAIL, "password": pw_hash,
        "scope": "api offline_access", "client_id": "cli",
        "deviceIdentifier": str(uuid.uuid4()), "deviceName": "bw195-selftest",
        "deviceType": "8"})
    assert status == 200 and tok.get("access_token"), f"token -> {status} {tok}"
    token = tok["access_token"]
    status, profile = _http("GET", base + "/api/accounts/profile", token=token)
    user_id = profile.get("Id") or profile.get("id")
    assert status == 200 and user_id, f"profile -> {status} {list(profile)}"
    status, key_resp = _http("POST", base + "/api/accounts/api-key",
                             json_body={"MasterPasswordHash": pw_hash}, token=token)
    secret = key_resp.get("ApiKey") or key_resp.get("apiKey")
    assert status == 200 and secret, f"api-key -> {status} {key_resp}"
    client_id = "user." + user_id

    def cipher(name, username, password, uri):
        # CipherData is camelCase on Vaultwarden 1.37 as well.
        status, resp = _http("POST", base + "/api/ciphers", token=token, json_body={
            "type": 1, "name": _enc_str(user_key, name.encode()),
            "login": {"username": _enc_str(user_key, username.encode()),
                      "password": _enc_str(user_key, password.encode()),
                      "uris": [{"uri": _enc_str(user_key, uri.encode()), "match": None}],
                      "totp": None},
            "notes": None, "favorite": False, "folderId": None,
            "organizationId": None, "reprompt": 0})
        assert status == 200, f"cipher {name} -> {status} {resp}"

    cipher("contrast-item", "carol", BW_CONTRAST, "https://contrast.example.com")
    cipher("dup-one", "d1", "dup-pw-one", "https://dup.example.com")
    cipher("dup-two", "d2", "dup-pw-two", "https://dup.example.com")
    cipher("nameonly", "nina", BW_NAMEONLY, "https://unrelated.example.com")
    return client_id, secret


def part_b():
    print("== part B: real Vaultwarden replica ==")
    base = os.environ["BW195_REPLICA_URL"].rstrip("/")
    # bw 2026.6.0 refuses plain http even for loopback, so the link
    # under test speaks https (TLS terminator in front of the
    # replica); seeding keeps using the plain loopback channel.
    link_url = os.environ.get("BW195_LINK_URL", base).rstrip("/")
    if os.environ.get("BW195_CA"):
        os.environ["NODE_EXTRA_CA_CERTS"] = os.environ["BW195_CA"]
    real_bw = os.environ.get("BW195_REAL_BW", "/tmp/bw-probe-20261126/bw")
    os.environ["BITWARDEN_CLI_PATH"] = real_bw
    client_id, client_secret = seed_replica(base)
    (TMPROOT / "seed.json").write_text(json.dumps(
        {"client_id": client_id, "client_secret": client_secret}), encoding="utf-8")
    check("seeded replica account + 4 ciphers", True)
    check("pinned bw version seen", bw._bw_version() == "2026.6.0")

    _builtin("contrast", "contrast.example.com", BUILTIN_CONTRAST)
    _builtin("dup", "dup.example.com", "builtin-dup-pw")
    _builtin("nameonly", "nameonly.example.com", "builtin-nameonly-pw")

    status, payload = bw.connect_link(
        {"server_url": link_url, "client_id": client_id, "client_secret": client_secret}, KEY)
    check("real connect -> 201 locked", status == 201 and payload["state"] == "locked")

    status, payload = bw.unlock("not-the-master-password", KEY)
    check("real unlock wrong password -> 401", status == 401)
    status, payload = bw.unlock(MASTER, KEY)
    check("real unlock -> 200, >=4 items", status == 200 and payload.get("items", 0) >= 4)
    check("real status unlocked", bw.link_status()["state"] == "unlocked")

    SINK.clear()
    out = bw.resolve_use("contrast", "contrast.example.com", "probe", "fetch", api_key=KEY)
    check("contrast: bitwarden wins", out.get("source") == "bitwarden")
    check("contrast: executor got the bitwarden password",
          SINK.get("contrast.example.com", {}).get("password") == BW_CONTRAST)

    SINK.clear()
    out = bw.resolve_use("dup", "dup.example.com", "probe", "fetch", api_key=KEY)
    check("dup: ambiguity falls to builtin",
          out.get("source") == "builtin"
          and SINK.get("dup.example.com", {}).get("password") == "builtin-dup-pw")

    SINK.clear()
    out = bw.resolve_use("nameonly", "nameonly.example.com", "probe", "fetch", api_key=KEY)
    check("nameonly: name match from bitwarden",
          out.get("source") == "bitwarden"
          and SINK.get("nameonly.example.com", {}).get("password") == BW_NAMEONLY)

    bw.lock()
    SINK.clear()
    out = bw.resolve_use("contrast", "contrast.example.com", "probe", "fetch", api_key=KEY)
    check("locked: builtin takes over",
          out.get("source") == "builtin"
          and SINK.get("contrast.example.com", {}).get("password") == BUILTIN_CONTRAST)

    # appdata loss: bw forgets the login; unlock must re-login from the
    # stored key pair through the vault executor, then unlock for real.
    shutil.rmtree(bw.CONFIG_DIR, ignore_errors=True)
    _reset_bw_state()
    status, payload = bw.unlock(MASTER, KEY)
    check("appdata loss: re-login via vault executor + unlock -> 200", status == 200)
    SINK.clear()
    out = bw.resolve_use("contrast", "contrast.example.com", "probe", "fetch", api_key=KEY)
    check("after re-login: bitwarden wins again",
          out.get("source") == "bitwarden"
          and SINK.get("contrast.example.com", {}).get("password") == BW_CONTRAST)

    check("zero disk hits: master password", _grep_tree(MASTER) == 0)
    check("zero disk hits: bitwarden contrast value", _grep_tree(BW_CONTRAST) == 0)
    # The client secret's one sanctioned on-disk copy besides the
    # encrypted vault entry is bw's OWN appdata cache (data.json):
    # in API-key mode bw stores no refresh token and re-authenticates
    # with the pair -- stripping it breaks sync (401, login dropped),
    # verified by hand in bar 1. Everywhere else it must be absent,
    # and disconnect (part C) wipes the cache dir entirely.
    appdata_file = bw.CONFIG_DIR / "data.json"
    check("client secret absent from vault store",
          _grep_root(TMPROOT / "vault", client_secret) == 0)
    check("client secret absent from link dir outside bw appdata",
          _grep_root(TMPROOT / "bwlink", client_secret, exclude=appdata_file) == 0)
    check("client secret present only as bw's own appdata cache",
          _grep_root(bw.CONFIG_DIR, client_secret) == 1)
    print(f"part B tmp kept for the down phase: {TMPROOT}")


def part_c():
    print("== part C: replica down ==")
    real_bw = os.environ.get("BW195_REAL_BW", "/tmp/bw-probe-20261126/bw")
    os.environ["BITWARDEN_CLI_PATH"] = real_bw
    _builtin("contrast", "contrast.example.com", BUILTIN_CONTRAST)
    check("link row survived", bw._load_link() is not None)
    # bw unlock is local crypto: it succeeds offline. The degrade must
    # therefore happen at the sync step of the resolve leg.
    status, _payload = bw.unlock(MASTER, KEY)
    check("down: unlock still succeeds (local crypto)", status == 200)
    SINK.clear()
    out = bw.resolve_use("contrast", "contrast.example.com", "probe", "fetch", api_key=KEY)
    check("down: resolve degrades to builtin",
          out.get("source") == "builtin"
          and SINK.get("contrast.example.com", {}).get("password") == BUILTIN_CONTRAST)
    check("down: degrade reason recorded as unreachable",
          bw.link_status()["last_degraded_reason"] == "unreachable")
    check("down: unreachable degrade audited", any(
        e.get("action") == "vault.resolve.degraded" and e.get("reason") == "unreachable"
        for e in _audit_events()))
    # Final: disconnect wipes the bw appdata cache too -- after it,
    # neither the master password nor the client secret may exist
    # anywhere in the system-written stores.
    seed = json.loads((TMPROOT / "seed.json").read_text())
    status, _payload = bw.disconnect(KEY)
    check("down: disconnect ok", status == 200)
    check("after disconnect: zero disk hits master password",
          _grep_tree(MASTER) == 0)
    check("after disconnect: zero disk hits client secret",
          _grep_tree(seed["client_secret"]) == 0)


if PHASE == "down":
    part_c()
else:
    part_a()
    if os.environ.get("BW195_REPLICA_URL"):
        _reset_bw_state()
        part_b()
    else:
        print("  skip part B (BW195_REPLICA_URL not set)")

print(f"\n{'SELFTEST FAILED: ' + ', '.join(fails) if fails else 'SELFTEST PASSED'}")
sys.exit(1 if fails else 0)
