#!/usr/bin/env python3
"""front_gateway: App-facing connections registry (read + write) and
the model-gateway channel list (read-only proxy) as an in-process
gateway module.

Cloud Computer & Remote Host upgrade:
- Supports full CRUD + credential + verify + disconnect + delete +
  SSH Ed25519 keypair generation for cloud computers & remote hosts:
  1) simular_box: Managed cloud computer (API key + optional custom MCP URL)
  2) vps_ssh / vps_agent: Linux & Windows VPS / NAT machines with custom
     host, custom port (NAT port forwarding), OS type (linux/windows),
     and auth type (ssh_key or password)
  3) reverse_node: Behind-NAT / home computer reverse agent pairing
     (generates one-time node token & ready-to-run install command)
- Secret values (apiKey, password, privateKey, token, nodeToken) NEVER
  leave the server; conn_public emits only safe display metadata.
"""
from __future__ import annotations

import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/opt/data"))
HERMES_ENV_PATH = Path(os.environ.get("COMPANION_HERMES_ENV", str(HERMES_HOME / ".env")))
STATE_DIR = Path(os.environ.get("FRONT_STATE_DIR", "/opt/data/front"))
CONN_PATH = STATE_DIR / "connections.json"
NEWAPI_BASE = os.environ.get("NEWAPI_BASE_URL", "").rstrip("/")
NEWAPI_ADMIN_TOKEN = os.environ.get("NEWAPI_ADMIN_TOKEN", "")
NEWAPI_ADMIN_USER_ID = os.environ.get("NEWAPI_ADMIN_USER_ID", "")
PUBLIC_BASE = os.environ.get("COMPANION_PUBLIC_BASE", "").rstrip("/")

CLOUD_PROVIDERS = ("simular_box", "vps_agent", "vps_ssh", "reverse_node")
WIN_PROBE_PORTS = (3389, 445, 5985, 5986)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def box_mcp_url() -> str:
    return os.environ.get("BOX_MCP_URL", "https://mcp.box.simular.ai/mcp")


def http_req(method: str, url: str, key: str | None = None,
             body: dict | None = None, timeout: float = 4.0,
             extra_headers: dict | None = None):
    headers = {}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if extra_headers:
        headers.update(extra_headers)
    req = Request(url, data=data, method=method, headers=headers)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read(262144)
            try:
                return resp.status, json.loads(raw or b"{}")
            except Exception:
                return resp.status, {"_text": raw.decode("utf-8", "replace")[:2000]}
    except HTTPError as e:
        raw = e.read(65536) if e.fp else b""
        try:
            return e.code, json.loads(raw or b"{}")
        except Exception:
            return e.code, {"_text": raw.decode("utf-8", "replace")[:2000]}
    except Exception as e:
        return 0, {"_error": str(e)}


def write_text_inplace(path: Path, text: str) -> None:
    """Overwrite `path` in place (truncate + write + fsync) so single-file
    bind mounts never fail with EBUSY."""
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())


def env_backup(path: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d")
    bak = path.with_name(path.name + f".bak-{stamp}-front")
    if path.exists():
        shutil.copyfile(path, bak)
        try:
            bak.chmod(0o600)
        except Exception:
            pass
    return bak


def env_read_vars(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        probe = line.lstrip("#").strip()
        if probe.startswith("[") and probe.endswith("]"):
            continue
        if line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


def env_set_var(path: Path, var: str, value: str | None) -> None:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    out: list[str] = []
    done = False
    for raw in lines:
        stripped = raw.strip()
        if stripped.startswith(f"{var}="):
            if value is not None and not done:
                out.append(f"{var}={value}")
                done = True
            continue
        out.append(raw)
    if value is not None and not done:
        out.append(f"{var}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    write_text_inplace(path, "\n".join(out) + "\n")
    try:
        path.chmod(0o600)
    except Exception:
        pass


def _conn_defaults() -> list[dict]:
    return [
        {"id": "github", "kind": "service", "provider": "github", "name": "GitHub",
         "configured": False, "lastVerify": None, "effective": "", "note": ""},
        {"id": "notion", "kind": "service", "provider": "notion", "name": "Notion",
         "configured": False, "lastVerify": None, "effective": "", "note": ""},
        {"id": "box", "kind": "cloud_computer", "provider": "simular_box",
         "name": "Simular Box", "configured": False, "lastVerify": None,
         "effective": "", "note": ""},
        {"id": "gateway", "kind": "service", "provider": "gateway",
         "name": "模型网关（可选）", "configured": False, "lastVerify": None,
         "effective": "未安装（可选）", "note": ""},
        {"id": "hermes-mcp", "kind": "mcp_registration", "provider": "hermes_mcp",
         "name": "Hermes 侧连接登记", "configured": None, "lastVerify": None,
         "effective": "", "note": ""},
    ]


def conn_load() -> list[dict]:
    if CONN_PATH.exists():
        try:
            return json.loads(CONN_PATH.read_text())
        except Exception:
            pass
    recs = _conn_defaults()
    conn_save(recs)
    return recs


def conn_save(recs: list[dict]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    write_text_inplace(CONN_PATH, json.dumps(recs, ensure_ascii=False, indent=1))
    try:
        CONN_PATH.chmod(0o600)
    except Exception:
        pass


def conn_public(rec: dict) -> dict:
    pub = {k: rec.get(k) for k in
           ("id", "kind", "provider", "name", "configured",
            "lastVerify", "effective", "note")}
    # Expose only non-secret display metadata (never passwords/keys/tokens).
    s = rec.get("secret", {}) if isinstance(rec.get("secret"), dict) else {}
    meta: dict = {}
    if s.get("host"):
        meta["host"] = str(s["host"])
    if s.get("port"):
        meta["port"] = int(s["port"])
    if s.get("username"):
        meta["username"] = str(s["username"])
    if s.get("osType") or rec.get("osType"):
        meta["osType"] = str(s.get("osType") or rec.get("osType"))
    if s.get("authType"):
        meta["authType"] = str(s["authType"])
    elif s.get("privateKey"):
        meta["authType"] = "ssh_key"
    elif s.get("password"):
        meta["authType"] = "password"
    elif s.get("nodeToken"):
        meta["authType"] = "reverse_token"
    if s.get("publicKey"):
        meta["publicKey"] = str(s["publicKey"])
    if s.get("mcpUrl"):
        meta["mcpUrl"] = str(s["mcpUrl"])
    if meta:
        pub["meta"] = meta
    return pub


def conn_refresh(recs: list[dict]) -> None:
    """Recompute 'configured' from the real stores (values never read out
    through the API - only presence)."""
    hermes_vars = env_read_vars(HERMES_ENV_PATH)
    for rec in recs:
        p = rec["provider"]
        s = rec.get("secret", {}) if isinstance(rec.get("secret"), dict) else {}
        if p == "github":
            rec["configured"] = bool(hermes_vars.get("GITHUB_MCP_TOKEN"))
        elif p == "simular_box" and rec["id"] == "box":
            rec["configured"] = bool(hermes_vars.get("MCP_BOX_API_KEY") or s.get("apiKey"))
        elif p == "simular_box":
            rec["configured"] = bool(s.get("apiKey"))
        elif p == "notion":
            tok_dir = HERMES_HOME / "mcp-tokens"
            rec["configured"] = bool(
                tok_dir.exists() and any("notion" in f.name.lower()
                                         for f in tok_dir.iterdir()))
        elif p in ("vps_agent", "vps_ssh"):
            has_host = bool(s.get("host") and s.get("username"))
            has_auth = bool(s.get("password") or s.get("privateKey"))
            has_legacy = bool(s.get("token") and s.get("endpointUrl"))
            rec["configured"] = (has_host and has_auth) or has_legacy
        elif p == "reverse_node":
            rec["configured"] = bool(s.get("nodeToken"))


# ------------------------------------------------------------ verification helpers

def mcp_initialize(url: str, token: str, timeout: float = 8.0):
    headers = {"Authorization": f"Bearer {token}",
               "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
    payload = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
               "params": {"protocolVersion": "2025-03-26", "capabilities": {},
                          "clientInfo": {"name": "oneday-gateway", "version": "2.4.0"}}}
    req = Request(url, data=json.dumps(payload).encode(), method="POST", headers=headers)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read(262144).decode("utf-8", "replace")
            session = resp.headers.get("Mcp-Session-Id")
    except HTTPError as e:
        return False, f"对方返回 {e.code}", None
    except Exception as e:
        return False, f"连不上：{e}", None
    if "serverInfo" not in raw and "protocolVersion" not in raw:
        return False, "对方应答不像一个云电脑服务", None
    tools = None
    if session:
        headers["Mcp-Session-Id"] = session
        note = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        try:
            urlopen(Request(url, data=json.dumps(note).encode(), method="POST",
                            headers=headers), timeout=timeout).read(1024)
        except Exception:
            pass
        tl = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        try:
            with urlopen(Request(url, data=json.dumps(tl).encode(), method="POST",
                                 headers=headers), timeout=timeout) as resp:
                raw2 = resp.read(1048576).decode("utf-8", "replace")
            if re.search(r'"tools"\s*:\s*\[', raw2):
                tools = raw2.count('"name"')
        except Exception:
            pass
    detail = "云电脑服务应答正常" + (f"，检测到 {tools} 个工具" if tools else "")
    return True, detail, tools


def _tcp_open(host: str, port: int, timeout: float = 3.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except Exception:
        return False


def _ssh_key_probe(host: str, port: int, username: str, private_key: str) -> tuple[str, str]:
    """Verify SSH connectivity with a private key via system `ssh` binary.
    Returns (state, info): ok / auth_failed / unreachable / unavailable."""
    ssh_bin = shutil.which("ssh")
    if not ssh_bin:
        return "unavailable", ""
    key_text = private_key.strip() + "\n"
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile("w", delete=False, prefix="oneday_ssh_", suffix=".key") as f:
            f.write(key_text)
            tmp_path = f.name
        os.chmod(tmp_path, 0o600)
        cmd = [
            ssh_bin,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "IdentitiesOnly=yes",
            "-p", str(port),
            "-i", tmp_path,
            f"{username}@{host}",
            "uname -s -n 2>/dev/null || hostname",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
        if proc.returncode == 0:
            out = proc.stdout.strip().splitlines()
            return "ok", (out[0][:80] if out else "")
        err = (proc.stderr or "").lower()
        if "permission denied" in err or "authentication" in err or "publickey" in err:
            return "auth_failed", ""
        if "timed out" in err or "refused" in err or "no route" in err or "could not resolve" in err:
            return "unreachable", ""
        return "auth_failed", ""
    except subprocess.TimeoutExpired:
        return "unreachable", ""
    except Exception:
        return "unavailable", ""
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except Exception:
                pass


def _winrm_probe(host: str, username: str, password: str, port: int | None = None):
    try:
        import winrm  # type: ignore
    except Exception:
        return "unavailable", ""
    candidates = []
    if port == 5986:
        candidates = [("https", 5986)]
    elif port == 5985:
        candidates = [("http", 5985)]
    elif port and port not in (22, 3389):
        candidates = [("https", port), ("http", port)]
    else:
        candidates = [("https", 5986), ("http", 5985)]
    for scheme, p in candidates:
        try:
            sess = winrm.Session(
                f"{scheme}://{host}:{p}/wsman",
                auth=(username, password), transport="ntlm",
                server_cert_validation="ignore")
            r = sess.run_cmd("hostname")
            if r.status_code == 0:
                name = r.std_out.decode("utf-8", "replace").strip()
                return "ok", name
            return "auth_failed", ""
        except Exception as e:
            blob = type(e).__name__ + " " + str(e)
            if "InvalidCredentials" in blob or "401" in blob or "Authentication" in blob:
                return "auth_failed", ""
            continue
    return "unreachable", ""


def _verify_vps(rec: dict) -> tuple[bool, str]:
    s = rec.get("secret", {}) if isinstance(rec.get("secret"), dict) else {}
    if s.get("endpointUrl") and s.get("token"):
        return mcp_initialize(s["endpointUrl"], s["token"])[:2]
    host = str(s.get("host", "")).strip()
    if not host:
        return False, "还没填这台主机的连接信息"
    os_type = str(s.get("osType") or rec.get("osType") or "linux").lower()
    auth_type = str(s.get("authType") or ("ssh_key" if s.get("privateKey") else "password")).lower()
    default_port = 22 if (os_type == "linux" or auth_type == "ssh_key") else 5985
    port = int(s.get("port") or default_port)
    username = str(s.get("username", "")).strip()

    # 1) SSH key real handshake (works for Linux VPS, NAT port-mapped Linux, and Windows OpenSSH)
    if auth_type == "ssh_key" and s.get("privateKey"):
        state, info = _ssh_key_probe(host, port, username, str(s["privateKey"]))
        if state == "ok":
            who = f"（{info}）" if info else ""
            return True, f"SSH 密钥验证通过{who}"
        if state == "auth_failed":
            return False, "SSH 密钥认证被拒绝，请确认公钥已写入目标主机的 authorized_keys 且用户名正确"
        if state == "unreachable":
            return False, f"连不上 {host}:{port}，请检查主机地址、NAT 映射端口和防火墙"
        # ssh binary unavailable -> fallback to TCP check
        if _tcp_open(host, port):
            return True, f"端口 {host}:{port} 可达，SSH 密钥已保存"
        return False, f"端口 {host}:{port} 无法连通，请检查地址与端口映射"

    # 2) Windows password mode -> WinRM probe then TCP check
    if os_type == "windows":
        state, machine = _winrm_probe(host, username, str(s.get("password", "")), port=port)
        if state == "ok":
            who = f"（{machine}）" if machine else ""
            return True, f"Windows 登录验证通过{who}"
        if state == "auth_failed":
            return False, "登录没通过：账户名或密码不对"
        probe_ports = [port] + [p for p in WIN_PROBE_PORTS if p != port]
        if any(_tcp_open(host, p) for p in probe_ports):
            return True, f"已联系上 {host}:{port}，Windows 登录信息已保存"
        return False, f"按 {host}:{port} 联系不上这台 Windows 主机，请检查 IP、端口和防火墙"

    # 3) Linux password mode -> TCP check on custom SSH port
    if _tcp_open(host, port):
        return True, f"SSH 端口 {host}:{port} 已连通，凭据已安全保存"
    return False, f"连不上 {host}:{port}，请检查主机地址、NAT 映射端口和 SSH 服务"


def _set_verify(rec: dict, ok: bool, detail: str) -> None:
    rec["lastVerify"] = {"at": now_iso(), "ok": ok, "detail": detail}


def _generate_ed25519_keypair(comment: str) -> tuple[str | None, str | None, str | None]:
    """Generate an Ed25519 SSH keypair using `ssh-keygen`.
    Returns (private_key_pem, public_key_openssh, error_message)."""
    keygen = shutil.which("ssh-keygen")
    if not keygen:
        return None, None, "服务器未安装 ssh-keygen，请改为粘贴已有 SSH 私钥"
    tmpdir = tempfile.mkdtemp(prefix="oneday_keygen_")
    key_file = os.path.join(tmpdir, "id_ed25519")
    try:
        proc = subprocess.run(
            [keygen, "-t", "ed25519", "-N", "", "-C", comment, "-f", key_file],
            capture_output=True, text=True, timeout=10,
        )
        if proc.returncode != 0:
            return None, None, "生成 SSH 密钥对失败，请稍后重试"
        priv = Path(key_file).read_text(encoding="utf-8")
        pub = Path(key_file + ".pub").read_text(encoding="utf-8").strip()
        return priv, pub, None
    except Exception:
        return None, None, "生成 SSH 密钥对失败，请稍后重试"
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _reverse_pair_commands(node_id: str, token: str, os_type: str) -> dict:
    base = PUBLIC_BASE or "https://<你的服务器域名>"
    linux_cmd = (
        f"curl -fsSL {base}/v1/front/agent-install.sh | "
        f"ONEDAY_SERVER='{base}' ONEDAY_NODE_ID='{node_id}' "
        f"ONEDAY_NODE_TOKEN='{token}' sh"
    )
    win_cmd = (
        f"$env:ONEDAY_SERVER='{base}'; $env:ONEDAY_NODE_ID='{node_id}'; "
        f"$env:ONEDAY_NODE_TOKEN='{token}'; "
        f"irm {base}/v1/front/agent-install.ps1 | iex"
    )
    return {
        "linuxCommand": linux_cmd,
        "windowsCommand": win_cmd,
        "recommendedCommand": win_cmd if os_type == "windows" else linux_cmd,
    }


# ------------------------------------------------------------ gateway channels
_NEWAPI_STATUS_WORDS = {1: "enabled", 2: "disabled", 3: "auto_disabled"}


def fetch_gateway_channels() -> tuple[int, dict]:
    if not NEWAPI_BASE or not NEWAPI_ADMIN_TOKEN:
        return 503, {"error": "网关渠道的管理凭据还没有在服务端配置，暂时读不到渠道清单"}
    headers = {}
    if NEWAPI_ADMIN_USER_ID:
        headers["New-Api-User"] = NEWAPI_ADMIN_USER_ID
    items: list = []
    total = None
    for page in range(20):
        code, body = http_req(
            "GET", f"{NEWAPI_BASE}/api/channel/?p={page}&page_size=100",
            key=NEWAPI_ADMIN_TOKEN, timeout=6, extra_headers=headers)
        if code == 0 or not isinstance(body, dict):
            return 502, {"error": "网关暂时联系不上，渠道清单读不到"}
        if code != 200 or body.get("success") is not True:
            return 502, {"error": "网关没有给出渠道清单，暂时读不到"}
        data = body.get("data")
        if isinstance(data, dict):
            batch = data.get("items") or []
            if total is None and isinstance(data.get("total"), int):
                total = data["total"]
        elif isinstance(data, list):
            batch = data
        else:
            return 502, {"error": "网关的渠道清单格式无法识别"}
        items.extend(b for b in batch if isinstance(b, dict))
        if total is not None and len(items) >= total:
            break
        if len(batch) < 100:
            break
    channels = []
    for it in items:
        raw_models = it.get("models")
        if isinstance(raw_models, str):
            models = [m.strip() for m in raw_models.split(",") if m.strip()]
        elif isinstance(raw_models, list):
            models = [str(m) for m in raw_models if str(m).strip()]
        else:
            models = []
        status = it.get("status")
        prio = it.get("priority")
        weight = it.get("weight")
        group = it.get("group")
        channels.append({
            "id": str(it.get("id", "")),
            "name": str(it.get("name", "") or ""),
            "status": _NEWAPI_STATUS_WORDS.get(
                status, str(status) if status is not None else ""),
            "models": models,
            "priority": prio if isinstance(prio, int) else None,
            "weight": weight if isinstance(weight, int) else None,
            "group": group if isinstance(group, str) and group else None,
        })
    return 200, {"channels": channels}


# ------------------------------------------------------------ public face

def start() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)


def get_connections():
    recs = conn_load()
    conn_refresh(recs)
    conn_save(recs)
    return 200, {"connections": [conn_public(r) for r in recs]}


def create_connection(body: dict) -> tuple[int, dict]:
    kind = str(body.get("kind", "")).strip()
    provider = str(body.get("provider", "")).strip()
    name = str(body.get("name", "")).strip()
    os_type = str(body.get("osType", "")).strip().lower()
    if kind != "cloud_computer" or provider not in CLOUD_PROVIDERS or not name:
        return 400, {"ok": False, "error": "只能在这里添加云电脑或远程主机，且名称不能为空"}
    recs = conn_load()
    existing_ids = {r["id"] for r in recs}
    n = sum(1 for r in recs if r["provider"] == provider) + 1
    cid = f"{provider}-{n}"
    while cid in existing_ids:
        n += 1
        cid = f"{provider}-{n}"
    rec: dict = {
        "id": cid, "kind": kind, "provider": provider,
        "name": name, "configured": False, "lastVerify": None,
        "effective": "", "note": "",
    }
    if os_type in ("linux", "windows"):
        rec["osType"] = os_type
    extra_payload: dict = {}
    if provider == "reverse_node":
        token = "odn_" + secrets.token_urlsafe(24)
        rec["secret"] = {
            "nodeToken": token,
            "osType": os_type if os_type in ("linux", "windows") else "linux",
            "authType": "reverse_token",
        }
        rec["configured"] = True
        rec["effective"] = "待节点回连"
        rec["note"] = "在目标 NAT 机或内网电脑上执行配对命令后自动上线"
        extra_payload["pairing"] = _reverse_pair_commands(cid, token, rec["secret"]["osType"])
    recs.append(rec)
    conn_save(recs)
    out = {"ok": True, "connection": conn_public(rec)}
    out.update(extra_payload)
    return 200, out


def submit_credential(cid: str, body: dict) -> tuple[int, dict]:
    recs = conn_load()
    rec = next((r for r in recs if r["id"] == cid), None)
    if rec is None:
        return 404, {"ok": False, "error": "没有这台电脑的记录"}
    p = rec["provider"]
    if p == "simular_box":
        code, out = _cred_simular(rec, body)
    elif p in ("vps_agent", "vps_ssh"):
        code, out = _cred_vps(rec, body)
    elif p == "reverse_node":
        token = "odn_" + secrets.token_urlsafe(24)
        os_type = str(body.get("osType") or rec.get("osType") or "linux").lower()
        if os_type not in ("linux", "windows"):
            os_type = "linux"
        rec["secret"] = {"nodeToken": token, "osType": os_type, "authType": "reverse_token"}
        rec["configured"] = True
        rec["effective"] = "待节点回连"
        rec["note"] = "已重置配对令牌，请在目标机器重新执行配对命令"
        _set_verify(rec, True, "已生成新配对命令")
        code, out = 200, {
            "ok": True,
            "detail": "已生成新配对命令",
            "pairing": _reverse_pair_commands(cid, token, os_type),
        }
    else:
        return 400, {"ok": False, "error": "该连接暂不支持在 App 内修改凭据"}
    conn_save(recs)
    out = dict(out)
    out["connection"] = conn_public(rec)
    return code, out


def _cred_simular(rec: dict, body: dict) -> tuple[int, dict]:
    api_key = str(body.get("apiKey", "")).strip()
    mcp_url = str(body.get("mcpUrl", "")).strip() or box_mcp_url()
    if len(api_key) < 10:
        return 400, {"ok": False, "error": "这个密钥看起来不对：长度太短"}
    if not mcp_url.startswith(("http://", "https://")):
        return 400, {"ok": False, "error": "MCP 地址必须以 http:// 或 https:// 开头"}
    ok, detail, _ = mcp_initialize(mcp_url, api_key)
    if not ok:
        _set_verify(rec, False, detail)
        return 200, {"ok": False, "detail": f"新密钥验活没通过（{detail}），原配置未改动"}
    if rec["id"] == "box":
        env_backup(HERMES_ENV_PATH)
        env_set_var(HERMES_ENV_PATH, "MCP_BOX_API_KEY", api_key)
    rec["secret"] = {"apiKey": api_key, "mcpUrl": mcp_url}
    rec["configured"] = True
    rec["effective"] = "已生效"
    rec["note"] = ""
    _set_verify(rec, True, detail)
    return 200, {"ok": True, "detail": detail}


def _cred_vps(rec: dict, body: dict) -> tuple[int, dict]:
    host = str(body.get("host", "")).strip()
    username = str(body.get("username", "")).strip()
    os_type = str(body.get("osType") or rec.get("osType") or "linux").strip().lower()
    if os_type not in ("linux", "windows"):
        os_type = "linux"
    auth_type = str(body.get("authType") or "").strip().lower()
    private_key = str(body.get("privateKey", "")).strip()
    password = str(body.get("password", ""))
    if not auth_type:
        auth_type = "ssh_key" if private_key else "password"
    if not host or "://" in host or "/" in host or any(c.isspace() for c in host):
        return 400, {"ok": False, "error": "主机/IP 格式不对，请不要带 http:// 或空格"}
    if not username:
        return 400, {"ok": False, "error": "请填写用户名"}
    raw_port = body.get("port")
    default_port = 22 if (os_type == "linux" or auth_type == "ssh_key") else 5985
    try:
        port = int(raw_port) if raw_port is not None and str(raw_port).strip() != "" else default_port
    except Exception:
        return 400, {"ok": False, "error": "端口号必须是 1~65535 的数字"}
    if not (1 <= port <= 65535):
        return 400, {"ok": False, "error": "端口号必须在 1~65535 之间"}

    old_secret = rec.get("secret", {}) if isinstance(rec.get("secret"), dict) else {}
    if auth_type == "ssh_key":
        # Allow reusing server-generated keypair when privateKey is omitted in submit
        effective_key = private_key or str(old_secret.get("privateKey", "")).strip()
        if not effective_key:
            return 400, {"ok": False, "error": "请粘贴 SSH 私钥，或先点击「生成密钥对」"}
        new_secret = {
            "host": host, "port": port, "username": username,
            "osType": os_type, "authType": "ssh_key",
            "privateKey": effective_key,
        }
        if old_secret.get("publicKey") and not private_key:
            new_secret["publicKey"] = old_secret["publicKey"]
    else:
        if not password:
            return 400, {"ok": False, "error": "请填写登录密码"}
        new_secret = {
            "host": host, "port": port, "username": username,
            "osType": os_type, "authType": "password",
            "password": password,
        }
    if old_secret.get("endpointUrl"):
        new_secret["endpointUrl"] = old_secret["endpointUrl"]
    if old_secret.get("token"):
        new_secret["token"] = old_secret["token"]

    probe_rec = dict(rec)
    probe_rec["secret"] = new_secret
    ok, detail = _verify_vps(probe_rec)
    if not ok:
        _set_verify(rec, False, detail)
        return 200, {"ok": False, "detail": f"{detail}，配置未覆盖"}
    rec["osType"] = os_type
    rec["secret"] = new_secret
    rec["configured"] = True
    rec["effective"] = "已连接"
    rec["note"] = f"{os_type.upper()} · {host}:{port}（{'SSH 密钥' if auth_type == 'ssh_key' else '密码'}）"
    _set_verify(rec, True, detail)
    return 200, {"ok": True, "detail": detail}


def generate_ssh_keypair(cid: str) -> tuple[int, dict]:
    recs = conn_load()
    rec = next((r for r in recs if r["id"] == cid), None)
    if rec is None:
        return 404, {"ok": False, "error": "没有这台电脑的记录"}
    if rec["provider"] not in ("vps_agent", "vps_ssh"):
        return 400, {"ok": False, "error": "只有 VPS / NAT 主机支持生成 SSH 密钥"}
    priv, pub, err = _generate_ed25519_keypair(f"oneday-{cid}")
    if err or not priv or not pub:
        return 500, {"ok": False, "error": err or "生成密钥失败"}
    secret = dict(rec.get("secret", {}) if isinstance(rec.get("secret"), dict) else {})
    secret["privateKey"] = priv
    secret["publicKey"] = pub
    secret["authType"] = "ssh_key"
    rec["secret"] = secret
    conn_save(recs)
    install_cmd = (
        f'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
        f'echo "{pub}" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
    )
    return 200, {
        "ok": True,
        "publicKey": pub,
        "installCommand": install_cmd,
        "connection": conn_public(rec),
    }


def verify_connection(cid: str) -> tuple[int, dict]:
    recs = conn_load()
    rec = next((r for r in recs if r["id"] == cid), None)
    if rec is None:
        return 404, {"ok": False, "error": "没有这条连接"}
    p = rec["provider"]
    s = rec.get("secret", {}) if isinstance(rec.get("secret"), dict) else {}
    if p == "simular_box":
        key = s.get("apiKey") or env_read_vars(HERMES_ENV_PATH).get("MCP_BOX_API_KEY", "")
        if not key:
            ok, detail = False, "还没有配置云电脑密钥"
        else:
            ok, detail, _ = mcp_initialize(s.get("mcpUrl") or box_mcp_url(), str(key))
    elif p in ("vps_agent", "vps_ssh"):
        ok, detail = _verify_vps(rec)
    elif p == "reverse_node":
        ok = bool(s.get("nodeToken"))
        detail = "配对令牌有效，等待目标机器回连" if ok else "未生成配对令牌"
    else:
        ok, detail = False, "这一项暂不支持自动验活"
    _set_verify(rec, ok, detail)
    conn_save(recs)
    return 200, {"ok": ok, "detail": detail, "at": now_iso(), "connection": conn_public(rec)}


def disconnect_connection(cid: str) -> tuple[int, dict]:
    recs = conn_load()
    rec = next((r for r in recs if r["id"] == cid), None)
    if rec is None:
        return 404, {"ok": False, "error": "没有这条连接"}
    if rec["provider"] == "simular_box" and rec["id"] == "box":
        env_backup(HERMES_ENV_PATH)
        env_set_var(HERMES_ENV_PATH, "MCP_BOX_API_KEY", None)
    rec.pop("secret", None)
    rec["configured"] = False
    rec["effective"] = ""
    rec["note"] = ""
    _set_verify(rec, False, "已断开")
    conn_save(recs)
    return 200, {"ok": True, "detail": "已断开", "connection": conn_public(rec)}


def delete_connection(cid: str) -> tuple[int, dict]:
    recs = conn_load()
    rec = next((r for r in recs if r["id"] == cid), None)
    if rec is None:
        return 404, {"ok": False, "error": "没有这条连接"}
    if rec["id"] in ("github", "notion", "box", "gateway", "hermes-mcp"):
        return 400, {"ok": False, "error": "内置默认项不能删除，可以选择「断开」"}
    recs = [r for r in recs if r["id"] != cid]
    conn_save(recs)
    return 200, {"ok": True, "detail": "已删除"}


def get_gateway_channels():
    return fetch_gateway_channels()
