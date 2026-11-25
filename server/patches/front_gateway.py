#!/usr/bin/env python3
"""front_gateway: the companion front's App-facing READ faces as an
in-process gateway module -- connections registry (read-only) and
the model-gateway channel list (read-only proxy).

Batch 4 of the bridge retirement (bridge-retirement-spec-20261124
section 3, rows 16-18 + section 4 C-2; user ruling 2026-11-24
00:28): the companion front (port 8650) carried three kinds of
surface, and they do NOT share one fate:

- the App probe face (/api/companion/info, /health) is replaced by
  the gateway's own GET /v1/capabilities + /health (no module here;
  api_server advertises the front_readonly / identity_gateway
  feature flags so the App can tell the new world from the old);
- the credential-hosting faces are KEPT but downgraded (user
  ruling): credentials are entered in server-side configuration
  only, and the App gets read-only views. That is this module:
  GET connections (presence recomputed from the real stores at
  read time; stored secret values are never emitted -- conn_public
  filters them, exactly as the front did) and GET gateway-channels
  (the New API admin credential stays server-side in the Hermes
  deployment env; only display fields are forwarded, channel keys
  never leave the server). The front's credential WRITE actions
  (create / credential / verify / disconnect) are NOT carried:
  they retire with the panel, replaced by server-side config
  entry, per the same ruling;
- the deployer panel itself (static pages, password login,
  web-login bridge, module toggles, selfcheck, logs, sync/ledger
  views, the panel-side avatar copy) retires without migration:
  the Hermes Dashboard (9119, upstream) is the deployer face at
  end state, and the panel-side avatar copy merges into the
  identity gateway's avatar store (the canonical one).

Business functions below are carried verbatim from front.py
(AST-extracted); the registered differences are: state dir moves
to /opt/data/front (connections.json carried over in place at
rollout), the box key's presence check reads its operative home
(the Hermes .env -- production-verified to hold MCP_BOX_API_KEY),
and the New API credential envs are read from the Hermes
deployment env instead of companion.env [front].
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/opt/data"))
HERMES_ENV_PATH = Path(os.environ.get("COMPANION_HERMES_ENV", str(HERMES_HOME / ".env")))
STATE_DIR = Path(os.environ.get("FRONT_STATE_DIR", "/opt/data/front"))
CONN_PATH = STATE_DIR / "connections.json"
# Server-side service credential for the read-only channel list:
# entered in the Hermes deployment env by the deployer (config-side
# entry, per the downgrade ruling); never returned by any API, and
# channel keys from the gateway payload are never forwarded.
NEWAPI_BASE = os.environ.get("NEWAPI_BASE_URL", "").rstrip("/")
NEWAPI_ADMIN_TOKEN = os.environ.get("NEWAPI_ADMIN_TOKEN", "")
NEWAPI_ADMIN_USER_ID = os.environ.get("NEWAPI_ADMIN_USER_ID", "")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


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
    """Overwrite `path` in place (truncate + write + fsync); never write a
    tmp file and rename it over the target. companion.env is a single-file
    bind mount — renaming over a mount point fails with EBUSY, which broke
    every panel env write in production. In-place writes preserve the
    inode, so they work on single-file bind mounts and directory mounts
    alike; all small env/state writes in front go through here."""
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())


def env_read_vars(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    in_global = True
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        probe = line.lstrip("#").strip()
        if probe.startswith("[") and probe.endswith("]"):
            in_global = probe == "[global]"
            continue
        if line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


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
    return {k: rec.get(k) for k in
            ("id", "kind", "provider", "name", "configured",
             "lastVerify", "effective", "note")}


def conn_refresh(recs: list[dict]) -> None:
    """Recompute 'configured' from the real stores (values never read out
    through the API - only presence)."""
    hermes_vars = env_read_vars(HERMES_ENV_PATH)
    companion_vars = env_read_vars(HERMES_ENV_PATH)  # batch 4: box key presence reads its operative home (Hermes .env)
    for rec in recs:
        p = rec["provider"]
        if p == "github":
            rec["configured"] = bool(hermes_vars.get("GITHUB_MCP_TOKEN"))
        elif p == "simular_box" and rec["id"] == "box":
            rec["configured"] = bool(companion_vars.get("MCP_BOX_API_KEY"))
        elif p == "notion":
            tok_dir = HERMES_HOME / "mcp-tokens"
            rec["configured"] = bool(
                tok_dir.exists() and any("notion" in f.name.lower()
                                         for f in tok_dir.iterdir()))
        elif p == "vps_agent":
            s = rec.get("secret", {})
            if s.get("access") == "windows":
                rec["configured"] = bool(s.get("host") and s.get("username")
                                         and s.get("password"))
            else:
                rec["configured"] = bool(s.get("token")
                                         and s.get("endpointUrl"))


_NEWAPI_STATUS_WORDS = {1: "enabled", 2: "disabled", 3: "auto_disabled"}


def fetch_gateway_channels() -> tuple[int, dict]:
    if not NEWAPI_BASE or not NEWAPI_ADMIN_TOKEN:
        return 503, {"error": "网关渠道的管理凭据还没有在服务端配置，"
                              "暂时读不到渠道清单"}
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
    """Idempotent boot: make sure the state dir exists (the
    connections registry file itself is carried over at rollout;
    a missing file simply yields the default registry, exactly as
    the front behaved on first run)."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)


def get_connections():
    """GET connections (canonical /v1/front/connections + shape
    /api/companion/connections): presence recomputed from the real
    stores at read time and the normalized registry saved back,
    exactly the front's read path. Secret values never leave:
    conn_public emits only the public field set."""
    recs = conn_load()
    conn_refresh(recs)
    conn_save(recs)
    return 200, {"connections": [conn_public(r) for r in recs]}


def get_gateway_channels():
    """GET gateway channels (canonical /v1/front/gateway-channels
    + shape /api/companion/gateway-channels): the front's
    read-only proxy, verbatim."""
    return fetch_gateway_channels()
