"""Bitwarden link: the user's own Bitwarden as read-only first source.

Bar 1 (queue 195, vault two-step proposal, approved 2026-11-26):
the server-side link module only -- link store, bw subprocess
wrapper with a hard subcommand whitelist, in-memory session unlock,
the six-state status surface, and the Bitwarden leg of credential
resolution. The client settings face is bar 2; shipping the pinned
bw binary inside the deployment package is bar 3.

Resolution order (proposal, written in stone): Bitwarden first,
built-in vault second, password-card request flow last (unchanged,
owned by credential_vault). ``resolve_use`` below is the single
resolution entry: it feeds the winning side's values into the SAME
executor registry ``credential_vault.vault_use`` uses, so a value
from either source exists only inside an executor frame on this
server; callers see {status, summary, source} and nothing else.

Master-password discipline (royal ruling 2026-11-26 19:21): the
master password is NEVER persisted, logged, audited or stored as a
link credential. It crosses memory exactly once per unlock, fed to
``bw unlock --passwordenv`` through a one-shot environment variable;
the session key it buys lives only in this process's memory and
dies with the process (a gateway restart is an automatic lock).
The only credential the link persists is the personal API key pair,
encrypted inside the built-in vault under service ``bitwarden_link``
-- the same AES-GCM store, the same 0600 discipline, no new storage.

Read-only discipline: the bw wrapper refuses every subcommand
outside the whitelist BEFORE spawning, so no code path here can
create / edit / delete / import / export on the Bitwarden side;
new credentials keep landing in the built-in vault because
``credential_vault.write_entry`` has no Bitwarden branch.

Degrade discipline: any Bitwarden-side anomaly (locked, missing
binary, unreachable, timeout, version mismatch, bad key) degrades
the whole lookup to the built-in leg with an audit trace; failures
additionally arm a short negative cache so a dead link cannot stall
every lookup.

Known footprint (verified experimentally in bar 1, do not
rediscover): the official bw CLI persists the API key pair in its
own appdata state file (``data.json``, keys ending
``_token_apiKeyClientId`` / ``_token_apiKeyClientSecret``). In
API-key mode bw stores NO refresh token -- the pair IS its
re-authentication mechanism, and sync re-authenticates with it:
deleting those keys makes sync fail 401 and drops the login state,
so the cache is load-bearing and this module does not strip it.
The exposure is bounded by the isolated config dir (0700, file
0600, same /opt/data trust domain as the vault store), and
``disconnect`` wipes the whole dir, after which no trace of the
pair remains anywhere. The pair's encrypted copy of record stays
the built-in vault entry; the appdata cache is the tool's own
session persistence, flagged for the bar-3 acceptance ruling
against the proposal's config-dir zero-hit line.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

DATA_DIR = Path(os.environ.get("BITWARDEN_LINK_DIR", "/opt/data/bitwarden-link"))
LINK_PATH = Path(os.environ.get("BITWARDEN_LINK_PATH", str(DATA_DIR / "link.json")))
CONFIG_DIR = Path(os.environ.get("BITWARDEN_CLI_APPDATA_DIR", str(DATA_DIR / "appdata")))

VAULT_SERVICE = "bitwarden_link"
LINK_NAME = "Bitwarden 链接"
PINNED_BW_VERSION = "2026.6.0"
PINNED_BW_ZIP_SHA256 = "392549496c712ab86bfbd6c27302df9fd2c431cfc7a47e26941ac3e3893f4d27"

ALLOWED_SUBCOMMANDS = frozenset({
    "config", "login", "logout", "lock", "unlock",
    "sync", "status", "list", "get",
})

RESOLVE_BUDGET_SECONDS = 10.0
SYNC_FRESH_SECONDS = 300
DEGRADE_COOLDOWN_SECONDS = 60
STATUS_CACHE_SECONDS = 30
UNLOCK_ENV_VAR = "ONEDAY_BW_MASTER_PW"

CATEGORY_HUMAN = {
    "validation": "参数不完整或格式不对",
    "credential": "主密码被拒，请核对后重试",
    "key_invalid": "API 密钥被拒（可能已在 Bitwarden 侧轮换），请更新钥匙",
    "unreachable": "服务器连不上，查找暂走内置库",
    "timeout": "服务器响应超时，查找暂走内置库",
    "version_mismatch": "本机组件与服务器版本不合，升级部署包或服务器后重试",
    "not_installed": "本机组件（bw）未就位，链接暂不可用",
    "insecure_url": "服务器地址须用 https（bw 拒绝明文 http，本机 localhost 亦然）",
    "error": "未知错误",
}

_lock = threading.RLock()
_job = threading.local()
_session_key: str | None = None
_last_sync_at: float | None = None
_degraded_until: float = 0.0
_last_degraded_reason: str | None = None
_last_error: dict[str, Any] | None = None
_status_cache: dict[str, Any] = {"at": 0.0, "probe": None}
_bw_version_cache: dict[str, Any] = {"at": 0.0, "version": None}


class BwRefused(Exception):
    """A subcommand outside the whitelist was attempted."""


class BwUnavailable(Exception):
    """The bw binary cannot be run at all (missing / spawn failure)."""


# --------------------------------------------------------------------------
# vault access (same lazy import shape as mail_gateway)

def _vault():
    from gateway.platforms import credential_vault
    return credential_vault


def _audit(event: dict[str, Any]) -> None:
    """Metadata-only audit into the vault audit stream (never values)."""
    try:
        _vault()._audit({"at": int(time.time()), **event})
    except Exception:
        pass


# --------------------------------------------------------------------------
# link store (metadata only; the API key pair lives in the vault)

def _load_link() -> dict[str, Any] | None:
    try:
        data = json.loads(LINK_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) and data.get("credential_id") else None
    except Exception:
        return None


def _save_link(row: dict[str, Any]) -> None:
    LINK_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = LINK_PATH.with_name(LINK_PATH.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(row, f, ensure_ascii=False, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, LINK_PATH)


def _drop_link() -> None:
    try:
        LINK_PATH.unlink()
    except FileNotFoundError:
        pass


def _link_meta() -> dict[str, Any] | None:
    """Public link shape: metadata only, never the credential reference."""
    row = _load_link()
    if row is None:
        return None
    return {"server_url": row["server_url"], "server_host": row["server_host"],
            "credential_configured": True,
            "created_at": row["created_at"], "updated_at": row["updated_at"]}


# --------------------------------------------------------------------------
# bw subprocess wrapper (whitelist enforced before spawn)

def _bw_path() -> str | None:
    for candidate in (os.environ.get("BITWARDEN_CLI_PATH"),
                      os.environ.get("ONEDAY_BW_PATH")):
        if candidate and Path(candidate).is_file():
            return candidate
    return shutil.which("bw")


def _scrub(text: str, secrets: tuple[str, ...] = ()) -> str:
    out = text or ""
    for secret in secrets:
        if secret and secret in out:
            out = out.replace(secret, "***")
    return out.strip()[:200]


def _run_bw(args: list[str], *, env_extra: dict[str, str] | None = None,
            timeout: float = 15.0, with_session: bool = False,
            secrets: tuple[str, ...] = ()) -> dict[str, Any]:
    """Run one whitelisted bw subcommand; return {rc, stdout, stderr}.

    The subcommand check happens before any spawn: a write-class
    subcommand (create/edit/delete/import/export/...) raises
    BwRefused and no process is ever started for it. Secret values
    travel only through the child environment, never argv.
    """
    if not args or args[0] not in ALLOWED_SUBCOMMANDS:
        _audit({"action": "bitwarden.subcommand_refused",
                "subcommand": (args[0] if args else "")[:32]})
        raise BwRefused(args[0] if args else "")
    exe = _bw_path()
    if exe is None:
        raise BwUnavailable("not_installed")
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(CONFIG_DIR, 0o700)
    except Exception:
        pass
    env = {"PATH": os.environ.get("PATH", ""),
           "BITWARDENCLI_APPDATA_DIR": str(CONFIG_DIR)}
    # TLS trust passthrough: a self-hosted Vaultwarden behind an
    # internal CA is a legitimate deployment shape; the operator's
    # CA pointers must reach bw or every call fails TLS.
    for var in ("NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE"):
        if os.environ.get(var):
            env[var] = os.environ[var]
    if with_session and _session_key:
        env["BW_SESSION"] = _session_key
    if env_extra:
        env.update(env_extra)
    try:
        proc = subprocess.run([exe, *args], env=env, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"rc": -1, "stdout": "", "stderr": "", "timed_out": True}
    except OSError as exc:
        raise BwUnavailable(str(exc)[:120])
    return {"rc": proc.returncode,
            "stdout": proc.stdout or "",
            "stderr": _scrub(proc.stderr or "", secrets)}


def _bw_version() -> str | None:
    now = time.time()
    if now - _bw_version_cache["at"] < 3600 and _bw_version_cache["version"]:
        return _bw_version_cache["version"]
    exe = _bw_path()
    if exe is None:
        return None
    try:
        proc = subprocess.run([exe, "--version"], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=10)
        version = (proc.stdout or "").strip() or None
    except Exception:
        version = None
    _bw_version_cache.update({"at": now, "version": version})
    return version


def _classify(res: dict[str, Any]) -> str:
    """Map a bw failure onto the human categories (signature first)."""
    if res.get("timed_out"):
        return "timeout"
    text = (res.get("stderr") or "") + "\n" + (res.get("stdout") or "")
    if "User Decryption Options are required" in text:
        return "version_mismatch"
    if "Insecure URL not allowed" in text:
        return "insecure_url"
    if "Invalid master password" in text:
        return "credential"
    low = text.lower()
    if ("Invalid client_id" in text or "Invalid client_secret" in text
            or "invalid_client" in text or "401" in text
            or "unauthorized" in low):
        return "key_invalid"
    if any(k in low for k in ("getaddrinfo", "econnrefused", "econnreset",
                              "etimedout", "network error", "failed to fetch",
                              "fetcherror", "fetch failed",
                              "connection refused", "connection reset",
                              "socket hang up", "cannot connect",
                              "could not connect", "enotfound")):
        return "unreachable"
    return "error"


def _probe_status() -> dict[str, Any] | None:
    """bw status JSON (serverUrl/status only), cached 30 s."""
    now = time.time()
    if now - _status_cache["at"] < STATUS_CACHE_SECONDS and _status_cache["probe"]:
        return _status_cache["probe"]
    try:
        res = _run_bw(["status"], timeout=10)
        probe = json.loads(res["stdout"]) if res["rc"] == 0 else None
        if not isinstance(probe, dict):
            probe = None
    except (BwUnavailable, BwRefused):
        probe = None
    _status_cache.update({"at": now, "probe": probe})
    return probe


def _invalidate_status_cache() -> None:
    _status_cache.update({"at": 0.0, "probe": None})


def _record_error(category: str, res: dict[str, Any] | None = None) -> None:
    global _last_error
    summary = ""
    if res is not None:
        summary = _scrub(res.get("stderr") or res.get("stdout") or "")
    _last_error = {"kind": category, "summary": summary, "at": int(time.time())}


def _degrade(reason: str) -> None:
    """Arm the negative cache after a real failure (not for 'locked')."""
    global _degraded_until, _last_degraded_reason
    _degraded_until = time.time() + DEGRADE_COOLDOWN_SECONDS
    _last_degraded_reason = reason


# --------------------------------------------------------------------------
# status surface (six states, derived server-side; clients never guess)

def link_status() -> dict[str, Any]:
    version = _bw_version()
    base = {
        "bw_installed": version is not None,
        "bw_version": version,
        "bw_version_pinned": version == PINNED_BW_VERSION,
        "last_sync_at": int(_last_sync_at) if _last_sync_at else None,
        "last_degraded_reason": _last_degraded_reason,
    }
    meta = _link_meta()
    if meta is None:
        return {"linked": False, "state": "unlinked", **base}
    base.update({"linked": True, **meta})
    if _session_key:
        base["state"] = "unlocked"
    elif _last_error and _last_error["kind"] in ("unreachable", "key_invalid",
                                                 "version_mismatch"):
        base["state"] = _last_error["kind"]
        base["error_summary"] = _last_error["summary"]
    else:
        probe = _probe_status()
        if probe is not None and probe.get("status") == "unauthenticated":
            # The login itself is gone (appdata wiped / token revoked):
            # unlocking cannot fix this, the key must be re-presented.
            base["state"] = "key_invalid"
        else:
            base["state"] = "locked"
    return base


# --------------------------------------------------------------------------
# connect / unlock / lock / disconnect

def _valid_server_url(raw: Any) -> tuple[str, str] | None:
    """(normalized_url, host) or None.

    https is effectively required: bw 2026.6.0 refuses plain http
    at login time even for localhost (verified in bar 1), so http
    is only accepted for loopback test rigs and will surface bw's
    own insecure_url verdict there if the build refuses it.
    """
    if not isinstance(raw, str) or not raw.strip() or len(raw) > 512:
        return None
    url = raw.strip().rstrip("/")
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if not host or parsed.scheme not in ("https", "http"):
        return None
    if parsed.scheme == "http" and host not in ("127.0.0.1", "localhost", "::1"):
        return None
    if parsed.username or parsed.password:
        return None
    return url, host


def _fail(category: str) -> dict[str, Any]:
    return {"ok": False, "category": category, "detail": CATEGORY_HUMAN[category]}


def connect_link(body: Any, api_key: str) -> tuple[int, dict[str, Any]]:
    """Save-and-test-login: only a passing login persists anything.

    Order mirrors mail_gateway.create_account: live test with the
    caller-supplied key pair first, vault write + link row only on
    a full pass, so a rejected key leaves nothing behind.
    """
    global _session_key
    if not isinstance(body, dict):
        return 400, {"status": "rejected", "error": _fail("validation")}
    parsed = _valid_server_url(body.get("server_url"))
    client_id = body.get("client_id")
    client_secret = body.get("client_secret")
    if (parsed is None or not isinstance(client_id, str) or not client_id
            or len(client_id) > 256 or not isinstance(client_secret, str)
            or not client_secret or len(client_secret) > 512):
        return 400, {"status": "rejected", "error": _fail("validation")}
    server_url, host = parsed
    if _bw_path() is None:
        return 503, {"status": "unavailable", "error": _fail("not_installed")}
    with _lock:
        try:
            _run_bw(["logout"], timeout=10)  # clear any prior login, best effort
        except (BwUnavailable, BwRefused):
            pass
        _session_key = None
        _invalidate_status_cache()
        try:
            res = _run_bw(["config", "server", server_url], timeout=10)
            if res["rc"] == 0:
                res = _run_bw(["login", "--apikey"],
                              env_extra={"BW_CLIENTID": client_id,
                                         "BW_CLIENTSECRET": client_secret},
                              timeout=30, secrets=(client_secret,))
        except BwUnavailable:
            return 503, {"status": "unavailable", "error": _fail("not_installed")}
        if res["rc"] != 0:
            category = _classify(res)
            _record_error(category, res)
            _audit({"action": "bitwarden.connect_failed", "category": category,
                    "server_host": host})
            return 422, {"status": "test_failed", "error": _fail(category)}
        vault = _vault()
        existing = _load_link()
        entry_id = existing["credential_id"] if existing else None
        status, receipt = vault.write_entry({
            "name": LINK_NAME, "service": VAULT_SERVICE, "domains": [host],
            "username": None,
            "values": {"api_key": client_id, "secret": client_secret},
        }, api_key, entry_id=entry_id)
        if status != 200:
            return 503, {"status": "vault_unavailable"}
        now = int(time.time())
        _save_link({"server_url": server_url, "server_host": host,
                    "credential_id": receipt["id"],
                    "created_at": (existing or {}).get("created_at", now),
                    "updated_at": now})
        global _last_error
        _last_error = None
        _invalidate_status_cache()
        _audit({"action": "bitwarden.connected", "server_host": host})
    return 201, link_status()


def _exec_login(domain: str, values: dict[str, str]) -> dict[str, Any]:
    """vault_use executor for ("bitwarden_link", "login").

    Runs inside the vault call: the stored API key pair exists only
    in this frame and is fed to bw through the child environment.
    Used to re-login from the stored keys when the bw-side login
    state is gone but the link row is intact.
    """
    job = getattr(_job, "ctx", None)
    if not isinstance(job, dict):
        return {"status": "failed", "summary": "operation failed"}
    try:
        _run_bw(["config", "server", job["server_url"]], timeout=10)
        res = _run_bw(["login", "--apikey"],
                      env_extra={"BW_CLIENTID": values.get("api_key", ""),
                                 "BW_CLIENTSECRET": values.get("secret", "")},
                      timeout=30, secrets=(values.get("secret", ""),))
        if res["rc"] != 0 and "already logged in" in (
                res["stderr"] + res["stdout"]).lower():
            res = {**res, "rc": 0}  # a live login is the goal state
        job["result"]["rc"] = res["rc"]
        job["result"]["category"] = _classify(res) if res["rc"] != 0 else None
        if res["rc"] != 0:
            job["result"]["res"] = res
            return {"status": "failed", "summary": "bitwarden login failed"}
    except BwUnavailable:
        job["result"]["category"] = "not_installed"
        return {"status": "failed", "summary": "bitwarden login failed"}
    return {"status": "completed", "summary": "bitwarden login completed"}


def _register_operations() -> None:
    try:
        _vault().OPERATIONS[(VAULT_SERVICE, "login")] = _exec_login
    except Exception:
        pass


_register_operations()


def ensure_login(api_key: str) -> bool:
    """Re-login from the stored key pair when bw forgot the login."""
    row = _load_link()
    if row is None:
        return False
    _invalidate_status_cache()
    probe = _probe_status()
    if probe is not None and probe.get("status") in ("locked", "unlocked"):
        return True
    _register_operations()
    job = {"server_url": row["server_url"], "result": {}}
    _job.ctx = job
    try:
        outcome = _vault().vault_use(row["credential_id"], row["server_host"],
                                     VAULT_SERVICE, "login", api_key=api_key)
    finally:
        _job.ctx = None
    _invalidate_status_cache()
    if outcome.get("status") != "completed":
        category = job["result"].get("category") or "error"
        _record_error(category, job["result"].get("res"))
        return False
    return True


def unlock(master_password: Any, api_key: str) -> tuple[int, dict[str, Any]]:
    """One transient master-password pass -> in-memory session key.

    The password is fed to bw through a one-shot environment
    variable and is never written anywhere; only the fact of the
    attempt (and the probe's item count) is audited.
    """
    global _session_key, _last_error
    if not isinstance(master_password, str) or not master_password \
            or len(master_password) > 1024:
        return 400, {"status": "rejected", "error": _fail("validation")}
    if _load_link() is None:
        return 409, {"status": "unlinked"}
    if _bw_path() is None:
        return 503, {"status": "unavailable", "error": _fail("not_installed")}
    with _lock:
        if _session_key:
            return 200, link_status()
        if not ensure_login(api_key):
            category = (_last_error or {}).get("kind", "error")
            return 422, {"status": "login_failed", "error": _fail(category)}
        try:
            res = _run_bw(["unlock", "--passwordenv", UNLOCK_ENV_VAR, "--raw"],
                          env_extra={UNLOCK_ENV_VAR: master_password},
                          timeout=30, secrets=(master_password,))
        except BwUnavailable:
            return 503, {"status": "unavailable", "error": _fail("not_installed")}
        session = res["stdout"].strip()
        if 'BW_SESSION="' in session:  # non-raw output shape fallback
            session = session.split('BW_SESSION="', 1)[1].split('"', 1)[0]
        if res["rc"] != 0 or not session:
            category = _classify(res)
            _audit({"action": "bitwarden.unlock_failed", "category": category})
            return 401, {"status": "unlock_failed", "error": _fail(category)}
        _session_key = session
        _last_error = None
        _invalidate_status_cache()
        items = _list_items(timeout=10)
        count = len(items) if items is not None else -1
        items = None
        _audit({"action": "bitwarden.unlocked", "items": count})
    return 200, {**link_status(), "items": count}


def lock() -> tuple[int, dict[str, Any]]:
    """Drop the in-memory session key and lock the bw side too."""
    global _session_key
    with _lock:
        try:
            _run_bw(["lock"], timeout=10, with_session=True)
        except (BwUnavailable, BwRefused):
            pass
        _session_key = None
        _invalidate_status_cache()
        _audit({"action": "bitwarden.locked"})
    return 200, link_status()


def disconnect(api_key: str) -> tuple[int, dict[str, Any]]:
    """Logout, wipe the isolated config dir, revoke the vault entry."""
    global _session_key, _last_sync_at, _last_error
    row = _load_link()
    if row is None:
        return 404, {"status": "not_found"}
    with _lock:
        try:
            _run_bw(["logout"], timeout=10, with_session=True)
        except (BwUnavailable, BwRefused):
            pass
        _session_key = None
        _last_sync_at = None
        _last_error = None
        _invalidate_status_cache()
        try:
            import shutil as _shutil
            _shutil.rmtree(CONFIG_DIR, ignore_errors=True)
        except Exception:
            pass
        status, _payload = _vault().delete_entry(row["credential_id"])
        if status not in (200, 404):
            return 503, {"status": "vault_unavailable"}
        _drop_link()
        _audit({"action": "bitwarden.disconnected",
                "server_host": row["server_host"]})
    return 200, {"status": "disconnected", **link_status()}


# --------------------------------------------------------------------------
# Bitwarden leg internals

def _list_items(timeout: float) -> list[dict[str, Any]] | None:
    """All vault items as parsed JSON; values stay in this frame."""
    res = _run_bw(["list", "items"], timeout=timeout, with_session=True)
    if res["rc"] != 0:
        return None
    try:
        items = json.loads(res["stdout"])
    except Exception:
        return None
    return items if isinstance(items, list) else None


def _uri_host(uri: str) -> str | None:
    if not isinstance(uri, str) or not uri:
        return None
    parsed = urlparse(uri if "://" in uri else "//" + uri)
    return (parsed.hostname or "").lower() or None


def _match(items: list[dict[str, Any]], service: str,
           domain: str) -> tuple[dict[str, Any] | None, int]:
    """(unique top match, ambiguous count). URI-host exact beats name."""
    tiered: list[tuple[int, dict[str, Any]]] = []
    for item in items:
        if not isinstance(item, dict) or item.get("type") != 1:
            continue
        login = item.get("login") or {}
        if not login.get("password"):
            continue
        hosts = {_uri_host(u.get("uri") or "")
                 for u in (login.get("uris") or []) if isinstance(u, dict)}
        if domain in hosts:
            tiered.append((0, item))
        elif (item.get("name") or "").lower() == service.lower():
            tiered.append((1, item))
    if not tiered:
        return None, 0
    best = min(t for t, _ in tiered)
    tops = [it for t, it in tiered if t == best]
    if len(tops) != 1:
        return None, len(tops)
    return tops[0], 0


def _bitwarden_leg(service: str, domain: str, purpose: str,
                   operation: str) -> dict[str, Any] | None:
    """Try the Bitwarden side; None means 'fall through to built-in'."""
    row = _load_link()
    if row is None:
        return None
    if time.time() < _degraded_until:
        return None
    if _bw_path() is None:
        _audit({"action": "vault.resolve.degraded", "reason": "not_installed",
                "domain": domain})
        return None
    if not _session_key:
        _audit({"action": "vault.resolve.degraded", "reason": "locked",
                "domain": domain})
        return None
    vault = _vault()
    executor = vault.OPERATIONS.get((purpose, operation))
    if executor is None:
        _audit({"action": "vault.use.denied", "source": "bitwarden",
                "domain": domain, "purpose": purpose, "operation": operation,
                "reason": "operation_not_allowed"})
        return {"status": "denied", "summary": "operation not allowlisted",
                "source": "bitwarden"}
    deadline = time.time() + RESOLVE_BUDGET_SECONDS
    with _lock:
        global _last_sync_at
        if _last_sync_at is None or time.time() - _last_sync_at > SYNC_FRESH_SECONDS:
            try:
                res = _run_bw(["sync"], timeout=max(1.0, deadline - time.time()),
                              with_session=True)
            except BwUnavailable:
                _degrade("not_installed")
                _audit({"action": "vault.resolve.degraded",
                        "reason": "not_installed", "domain": domain})
                return None
            if res["rc"] != 0:
                category = _classify(res)
                _record_error(category, res)
                _degrade(category)
                _audit({"action": "vault.resolve.degraded", "reason": category,
                        "domain": domain})
                return None
            _last_sync_at = time.time()
        try:
            items = _list_items(timeout=max(1.0, deadline - time.time()))
        except BwUnavailable:
            items = None
        if items is None:
            _degrade("unreachable")
            _audit({"action": "vault.resolve.degraded", "reason": "unreachable",
                    "domain": domain})
            return None
        match, ambiguous = _match(items, service, domain)
        if ambiguous:
            _audit({"action": "vault.resolve.ambiguous", "source": "bitwarden",
                    "domain": domain, "count": ambiguous})
            items = None
            return None
        if match is None:
            items = None
            return None
        login = match.get("login") or {}
        values = {"username": login.get("username") or "",
                  "password": login.get("password") or ""}
        item_id = str(match.get("id") or "")
        items = None
    try:
        outcome = executor(domain=domain, values=values)
        if not isinstance(outcome, dict):
            outcome = {"status": "failed", "summary": "operation failed"}
        safe = {"status": str(outcome.get("status", "completed"))[:32],
                "summary": str(outcome.get("summary", "completed"))[:240]}
    except Exception:
        safe = {"status": "failed", "summary": "operation failed"}
    finally:
        values = None
    _audit({"action": "vault.use", "source": "bitwarden", "item": item_id,
            "domain": domain, "purpose": purpose, "operation": operation,
            "status": safe["status"]})
    return {**safe, "source": "bitwarden"}


# --------------------------------------------------------------------------
# resolution entry: Bitwarden leg, then built-in leg, then caller falls
# back to the unchanged password-card request flow.

def resolve_use(service: str, domain: str, purpose: str, operation: str,
                *, api_key: str, scope: str = "default") -> dict[str, Any]:
    domain = (domain or "").strip().lower().rstrip(".")
    outcome = _bitwarden_leg(service, domain, purpose, operation)
    if outcome is not None:
        return outcome
    vault = _vault()
    candidates = [e for e in vault.list_entries(scope)
                  if e.get("service") == service
                  and domain in (e.get("domains") or [])
                  and e.get("service") != VAULT_SERVICE]
    if len(candidates) > 1:
        _audit({"action": "vault.resolve.ambiguous", "source": "builtin",
                "domain": domain, "count": len(candidates)})
        return {"status": "unavailable",
                "summary": f"内置库有 {len(candidates)} 条同域凭据，未自动选用",
                "source": "builtin"}
    if len(candidates) == 1:
        result = vault.vault_use(candidates[0]["id"], domain, purpose,
                                 operation, api_key=api_key, scope=scope)
        return {**result, "source": "builtin"}
    return {"status": "unavailable", "summary": "credential unavailable",
            "source": None}
