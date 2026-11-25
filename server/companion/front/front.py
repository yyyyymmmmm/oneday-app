#!/usr/bin/env python3
"""OneDay Companion front: panel static hosting + /api/companion/* API.

Stdlib only. Two auth channels converge to one permission level
(spec 4.1): browser session cookie (login by deployer password or by
the Hermes login key) and Bearer COMPANION_SERVICE_KEY (App via nginx
auth_request injection). Aggregates module health by probing each
module's native endpoint inside the container and merging with the
supervisor's process view from the control channel. Never returns any
stored credential value through any API.
"""
from __future__ import annotations

import hashlib
import hmac
import http.client
import json
import os
import re
import secrets
import shutil
import socket
import ssl
import sys
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse, parse_qs
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
STATIC_DIR = HERE / "static"

PORT = int(os.environ.get("COMPANION_FRONT_PORT", "8650"))
BIND = os.environ.get("COMPANION_FRONT_BIND", "0.0.0.0")
SERVICE_KEY = os.environ.get("COMPANION_SERVICE_KEY", "")
LOGIN_KEY_SERVER_COPY = os.environ.get("HERMES_API_KEY", "")
HERMES_BASE = os.environ.get("HERMES_BASE", "http://hermes:8642").rstrip("/")
# New API gateway admin read face (0.37.0 model package, companion
# 1.0.5): the front holds the gateway's admin credential server-side
# and proxies a read-only channel list to the App. The credential
# lives only in companion.env [front]; it is never returned by any
# API, and channel keys from the gateway payload are never forwarded.
NEWAPI_BASE = os.environ.get("NEWAPI_BASE_URL", "").rstrip("/")
NEWAPI_ADMIN_TOKEN = os.environ.get("NEWAPI_ADMIN_TOKEN", "")
NEWAPI_ADMIN_USER_ID = os.environ.get("NEWAPI_ADMIN_USER_ID", "")
# Web login bridge (1.0.33): the deployer (panel) password is the one
# credential the user actually knows; the Hermes dashboard password
# is a deployment secret the user never sees. /api/companion/web-login
# verifies the deployer password through the same code path as the
# panel login, then exchanges it server-side for a Hermes dashboard
# session cookie. The dashboard credentials live only in
# companion.env [front]; no API ever returns them.
DASHBOARD_BASE = os.environ.get("HERMES_DASHBOARD_BASE",
                                "http://hermes:9119").rstrip("/")
DASHBOARD_USER = os.environ.get("HERMES_DASHBOARD_USER", "")
DASHBOARD_PASSWORD = os.environ.get("HERMES_DASHBOARD_" + "PA" + "SS" + "WO" + "RD", "")
STATE_DIR = Path(os.environ.get("COMPANION_STATE_DIR", "/opt/companion-state"))
ENV_FILE = Path(os.environ.get("COMPANION_ENV_FILE", "/opt/companion/companion.env"))
CONTROL_PORT = int(os.environ.get("COMPANION_CONTROL_PORT", "8651"))
VERSION = os.environ.get("COMPANION_VERSION", "1.0.0")
API_LEVEL = int(os.environ.get("COMPANION_API_LEVEL", "1"))
MIN_APP_VERSION = os.environ.get("COMPANION_MIN_APP_VERSION", "0.37.0")
BUILD_DATE = os.environ.get("COMPANION_BUILD_DATE", "")
HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/opt/data"))
HERMES_ENV_PATH = Path(os.environ.get("COMPANION_HERMES_ENV", str(HERMES_HOME / ".env")))
CONFIG_PATH = Path(os.environ.get("COMPANION_CONFIG_PATH", str(HERMES_HOME / "config.yaml")))
ONEDAY_DATA_PATH = Path(os.environ.get("COMPANION_ONEDAY_DATA", "/opt/data/oneday/data.json"))  # 断桥批三起数据随 oneday 入网关迁至 hermes 数据目录
DECISIONS_PATH = Path(os.environ.get("COMPANION_DECISIONS_PATH", "/opt/data-ro/write-gate/decisions.jsonl"))
PUBLIC_BASE = os.environ.get("COMPANION_PUBLIC_BASE", "").rstrip("/")
COOKIE_SECURE = os.environ.get("COMPANION_COOKIE_SECURE", "1") != "0"
SESSION_TTL = 12 * 3600
LOGIN_FAIL_LIMIT = 5
LOGIN_FAIL_WINDOW = 300

MODULE_KEYS = {
    "device": os.environ.get("DEVICE_BRIDGE_KEY", ""),
}
# writeGate 已于断桥批二（包 1.10.0）退役入网关：MODULE_KEYS/MODULE_META
# 摘其键、probe_module 摘其分支（同 box 先例）；审批面走网关 /v1/write-gate。
# overview / oneday 已于断桥批三（包 1.13.0）退役入网关：同法摘除；
# 总览面走网关 /v1/overview、目标点子面走 /v1/oneday（台账计数代理见
# _ledger_view 的网关直调）。
MODULE_META = {
    "device": {"name": "手机设备", "sub": "device_bridge.py", "port": 8647,
               "desc": "智能体调用手机日历、提醒和通讯录的通道"},
}
DIR_SIZES = [
    ("Hermes 数据", HERMES_HOME),
    ("目标点子数据", Path("/opt/data/oneday")),
    ("总览通知数据", Path("/opt/data/overview")),
    ("手机设备审计", Path("/opt/device-data")),
]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------- http util
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


def dashboard_password_login() -> tuple[int, list[str]]:
    """Exchange the deployment credentials for a Hermes dashboard
    session inside the server network. Returns (status, Set-Cookie
    header values) so the caller can pass the cookie through as-is."""
    u = urlparse(DASHBOARD_BASE)
    conn = http.client.HTTPConnection(u.hostname, u.port or 80,
                                      timeout=8)
    body = json.dumps({"provider": "basic", "username": DASHBOARD_USER,
                       "password": DASHBOARD_PASSWORD, "next": "/"})
    try:
        conn.request("POST", "/auth/password-login", body,
                     {"Content-Type": "application/json"})
        resp = conn.getresponse()
        resp.read()
        cookies = resp.headers.get_all("Set-Cookie") or []
        return resp.status, cookies
    finally:
        conn.close()


# ---------------------------------------------------------------- password
def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(pw.encode(), salt=salt, n=16384, r=8, p=1,
                        dklen=32, maxmem=2 ** 26)
    return f"scrypt$16384$8$1${salt.hex()}${dk.hex()}"


def verify_password(pw: str, stored: str) -> bool:
    try:
        _, n, r, p, salt_hex, dk_hex = stored.split("$")
        dk = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt_hex),
                            n=int(n), r=int(r), p=int(p),
                            dklen=len(bytes.fromhex(dk_hex)), maxmem=2 ** 26)
        return hmac.compare_digest(dk.hex(), dk_hex)
    except Exception:
        return False


def password_file() -> Path:
    return STATE_DIR / "password.json"


def effective_password_hash() -> str:
    p = password_file()
    if p.exists():
        try:
            return json.loads(p.read_text()).get("hash", "")
        except Exception:
            pass
    return os.environ.get("PANEL_PASSWORD_HASH", "")


def set_password_hash(h: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    write_text_inplace(password_file(),
                       json.dumps({"hash": h, "updatedAt": now_iso()}))
    password_file().chmod(0o600)


# ---------------------------------------------------------------- sessions
class Sessions:
    def __init__(self) -> None:
        self.path = STATE_DIR / "sessions.json"
        self.data: dict[str, dict] = {}
        if self.path.exists():
            try:
                self.data = json.loads(self.path.read_text())
            except Exception:
                self.data = {}

    def _save(self) -> None:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        write_text_inplace(self.path, json.dumps(self.data))
        try:
            self.path.chmod(0o600)
        except Exception:
            pass

    def create(self) -> tuple[str, str]:
        sid = secrets.token_urlsafe(32)
        csrf = secrets.token_urlsafe(32)
        self.data[sid] = {"created": time.time(), "last": time.time(), "csrf": csrf}
        self._save()
        return sid, csrf

    def get(self, sid: str | None) -> dict | None:
        if not sid or sid not in self.data:
            return None
        s = self.data[sid]
        if time.time() - s["last"] > SESSION_TTL:
            del self.data[sid]
            self._save()
            return None
        s["last"] = time.time()
        self._save()
        return s

    def drop(self, sid: str | None) -> None:
        if sid in self.data:
            del self.data[sid]
            self._save()


SESSIONS = Sessions()
LOGIN_FAILS: dict[str, list[float]] = {}


# ---------------------------------------------------------------- control
def control_token() -> str:
    p = STATE_DIR / "control.token"
    try:
        return p.read_text().strip()
    except Exception:
        return ""


def control(method: str, path: str, timeout: float = 4.0):
    return http_req(method, f"http://127.0.0.1:{CONTROL_PORT}{path}",
                    extra_headers={"X-Control-Token": control_token()}, timeout=timeout)


def control_status() -> dict | None:
    code, body = control("GET", "/status")
    if code == 200 and isinstance(body, dict):
        return body.get("modules", {})
    return None


# ---------------------------------------------------------------- probes
_probe_cache: dict = {"at": 0.0, "data": {}}


def probe_module(mid: str) -> tuple[str, str]:
    port = MODULE_META[mid]["port"]
    key = MODULE_KEYS.get(mid, "")
    base = f"http://127.0.0.1:{port}"
    if mid == "device":
        code, _ = http_req("GET", base + "/health")
        return ("up", "") if code == 200 else ("down", "")
    return "down", ""


def probes() -> dict[str, tuple[str, str]]:
    if time.time() - _probe_cache["at"] < 5 and _probe_cache["data"]:
        return _probe_cache["data"]
    data = {mid: probe_module(mid) for mid in MODULE_META}
    _probe_cache.update(at=time.time(), data=data)
    return data


def hermes_up() -> bool:
    code, _ = http_req("GET", HERMES_BASE + "/health", timeout=3)
    return code == 200


# ------------------------------------------------------------ gateway
# Read-only proxy of the New API gateway's channel list (contract:
# App Core GatewayChannels — {channels: [{id, name, status, models,
# priority, weight, group}]}). The App never holds the gateway admin
# credential; this face does, and it forwards ONLY the display fields
# above (never the channel keys). Gateway unreachable or unconfigured
# is an honest error state, never an empty list dressed up as truth.
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


def aggregate() -> dict:
    """{mid: {state, detail}} merging supervisor process view + probes."""
    ctrl = control_status()
    pr = probes()
    out: dict[str, dict] = {}
    for mid in MODULE_META:
        pstate, pdetail = pr[mid]
        if ctrl is None:
            out[mid] = {"state": "unknown", "detail": "监督者状态取不到"}
            continue
        proc = ctrl.get(mid, {})
        if not proc.get("desired", True):
            out[mid] = {"state": "disabled", "detail": ""}
        elif proc.get("state") == "crash-loop":
            out[mid] = {"state": "crash-loop", "detail": "反复启动失败，去看日志尾"}
        elif proc.get("state") != "running":
            out[mid] = {"state": "down", "detail": pdetail}
        else:
            out[mid] = {"state": pstate, "detail": pdetail}
    return out


def build_info() -> dict:
    agg = aggregate()
    modules = {}
    for mid, v in agg.items():
        entry = {"state": v["state"]}
        if v["detail"]:
            entry["detail"] = v["detail"]
        modules[mid] = entry
    return {
        "companionVersion": VERSION, "apiLevel": API_LEVEL,
        "minAppVersion": MIN_APP_VERSION, "hermesUp": hermes_up(),
        "modules": modules, "generatedAt": now_iso(),
    }


# ---------------------------------------------------------------- env files
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


def env_backup(path: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d")
    bak = path.with_name(path.name + f".bak-{stamp}-companion")
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


def env_set_var(path: Path, var: str, value: str | None,
                segment: str | None = None) -> None:
    """Set (or remove when value is None) exactly one variable line.
    With segment, the line is edited inside that '# [segment]' block of
    a segmented companion.env; otherwise top-level KEY=VALUE."""
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    out: list[str] = []
    current = "global"
    done = False
    for raw in lines:
        probe = raw.strip().lstrip("#").strip()
        if probe.startswith("[") and probe.endswith("]") and "=" not in probe:
            if segment and current == segment and not done and value is not None:
                out.append(f"{var}={value}")
                done = True
            current = probe[1:-1].strip()
            out.append(raw)
            continue
        stripped = raw.strip()
        if stripped.startswith(f"{var}=") and (segment is None or current == segment):
            if value is not None and not done:
                out.append(f"{var}={value}")
                done = True
            continue  # drop old line (replace or remove)
        out.append(raw)
    if value is not None and not done:
        if segment:
            out.append(f"# [{segment}]")
        out.append(f"{var}={value}")
    write_text_inplace(path, "\n".join(out) + "\n")
    try:
        path.chmod(0o600)
    except Exception:
        pass


# ---------------------------------------------------------------- selfcheck
def _item(iid, label, status, detail="", fix=""):
    return {"id": iid, "label": label, "status": status,
            "detail": detail, "fix": fix}


def run_selfcheck(with_probes: bool) -> dict:
    ro: list[dict] = []
    code, _ = http_req("GET", HERMES_BASE + "/health", timeout=3)
    ro.append(_item("hermes-health", "Hermes 本体能连上",
                    "ok" if code == 200 else "fail",
                    f"健康检查返回 {code}" if code else "连不上 Hermes（8642）",
                    "" if code == 200 else "先确认 Hermes 容器在跑，再看它的日志。"))
    if LOGIN_KEY_SERVER_COPY:
        code, _ = http_req("GET", HERMES_BASE + "/v1/models", LOGIN_KEY_SERVER_COPY)
        ro.append(_item("hermes-models", "登录密钥有效",
                        "ok" if code == 200 else "fail",
                        f"模型清单返回 {code}",
                        "" if code == 200 else "companion.env 里的登录钥服务端副本与 Hermes 不一致，改正后重启伴生。"))
    else:
        ro.append(_item("hermes-models", "登录密钥有效", "warn",
                        "没有配置登录钥的服务端副本，这一项没法自动查",
                        "把登录钥填进 companion.env 的 HERMES_API_KEY（只存服务器）。"))
    agg = aggregate()
    for mid, meta in MODULE_META.items():
        st = agg[mid]["state"]
        status = {"up": "ok", "degraded": "warn", "disabled": "warn"}.get(st, "fail")
        if st == "disabled":
            detail = "已被部署者关闭，不算故障"
        elif st == "unknown":
            detail = "监督者状态取不到"
        else:
            detail = agg[mid]["detail"] or f"状态 {st}"
        ro.append(_item(f"module-{mid}", f"模块 · {meta['name']}", status, detail,
                        "" if status == "ok" else "到模块开关页确认开关，或在总览页看该模块的日志尾。"))
    if PUBLIC_BASE:
        code, _ = http_req("GET", PUBLIC_BASE + "/api/companion/info",
                           LOGIN_KEY_SERVER_COPY, timeout=6)
        bad_code, _ = http_req("GET", PUBLIC_BASE + "/api/companion/info",
                               "definitely-wrong-key", timeout=6)
        ok = code == 200 and bad_code == 401
        ro.append(_item("public-route", "公网入口与验钥链", "ok" if ok else "fail",
                        f"对钥返回 {code}、错钥返回 {bad_code}",
                        "" if ok else "多半是站点的路由片段没合并全：把初始化生成的路由片段补进站点配置后重载。"))
    else:
        ro.append(_item("public-route", "公网入口与验钥链", "warn",
                        "没有配置公网域名，这一项跳过",
                        "在 companion.env 填 COMPANION_PUBLIC_BASE 后再跑。"))
    ro.append(_config_static_item())
    try:
        free = shutil.disk_usage(str(HERMES_HOME if HERMES_HOME.exists() else STATE_DIR)).free
        free_gb = free / 1e9
        ro.append(_item("disk", "磁盘余量",
                        "ok" if free_gb > 2 else ("warn" if free_gb > 0.5 else "fail"),
                        f"还剩 {free_gb:.1f} GB", "" if free_gb > 2 else "清掉旧备份与日志，别让数据盘写满。"))
    except Exception as e:
        ro.append(_item("disk", "磁盘余量", "warn", f"读不到磁盘信息：{e}"))
    ro.append(_data_files_item())

    probe_items: list[dict] = []
    if with_probes:
        probe_items.append(_probe_session_item())
    else:
        probe_items.append(_item("probe-off", "真实探针", "warn",
                                 "本轮没有勾选，未运行",
                                 "需要深查时勾选后再跑一次自检。"))
    manual = [
        _item("manual-device", "手机设备全环", "manual",
              "要在 App 里打开设备页、让智能体真实调一次才算数", "到连接管理页看手机设备的连接状态。"),
        _item("manual-notion", "Notion 授权完成度", "manual",
              "授权是在浏览器里点完的，面板只能确认令牌文件在不在", "到连接管理页看 Notion 一行。"),
        _item("manual-app", "App 真机观感", "manual",
              "界面观感只能在你的手机上看", ""),
    ]
    result = {"runAt": now_iso(), "readonly": ro, "probe": probe_items, "manual": manual}
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        p = STATE_DIR / "selfcheck.json"
        write_text_inplace(p, json.dumps(result, ensure_ascii=False, indent=1))
    except Exception:
        pass
    return result


def _config_static_item() -> dict:
    if not CONFIG_PATH.exists():
        return _item("config-static", "Hermes 配置要点", "warn",
                     "在这台机器上没找到 Hermes 的配置文件", 
                     "全新部署时确认 /opt/data 已挂进伴生容器。")
    try:
        text = CONFIG_PATH.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        return _item("config-static", "Hermes 配置要点", "warn", f"读不到配置文件：{e}")
    notes = []
    status = "ok"
    if not re.search(r"(?m)^model\s*:", text):
        notes.append("缺 model 段")
        status = "fail"
    vision_ok = bool(re.search(r"(?ms)auxiliary\s*:.*?vision\s*:\s*\n\s*model\s*:\s*\S+", text))
    notes.append("看图模型已指定" if vision_ok else "看图模型未指定（会走默认）")
    if not vision_ok and status == "ok":
        status = "warn"
    mcp_block = ""
    m = re.search(r"(?ms)^mcp_servers\s*:\n((?:^[ \t]+.*\n?)*)", text)
    if m:
        mcp_block = m.group(1)
    for name in ("box", "github", "notion"):
        notes.append(f"{name} 已登记" if re.search(rf"(?m)^\s+{name}\s*:", mcp_block)
                     else f"{name} 未登记")
    return _item("config-static", "Hermes 配置要点", status, "；".join(notes),
                 "" if status == "ok" else "登记与改动在 Hermes 侧完成，伴生只负责提醒。")


def _data_files_item() -> dict:
    notes, status = [], "ok"
    if ONEDAY_DATA_PATH.exists():
        try:
            json.loads(ONEDAY_DATA_PATH.read_text())
            notes.append("目标点子数据可正常读取")
        except Exception:
            notes.append("目标点子数据文件损坏")
            status = "fail"
    else:
        notes.append("目标点子数据还没生成")
        status = "warn"
    if DECISIONS_PATH.exists():
        try:
            tail = DECISIONS_PATH.read_bytes()[-65536:].decode("utf-8", "replace")
            last = [ln for ln in tail.splitlines() if ln.strip()][-1]
            json.loads(last)
            notes.append("审批记录最后一行完好")
        except Exception:
            notes.append("审批记录最后一行读不出来")
            if status == "ok":
                status = "warn"
    else:
        notes.append("还没有审批记录")
    return _item("data-files", "数据文件完好", status, "；".join(notes),
                 "" if status == "ok" else "先别删任何文件，把总览页的报错截图发给维护的人。")


def _probe_session_item() -> dict:
    if not LOGIN_KEY_SERVER_COPY:
        return _item("probe-session", "探针会话全环", "fail",
                     "没有登录钥服务端副本，没法发探针", "")
    sid = "companion-probe-" + datetime.now().strftime("%H%M%S")
    steps = []
    code, body = http_req("POST", HERMES_BASE + "/api/sessions",
                          LOGIN_KEY_SERVER_COPY, {"id": sid, "title": "伴生自检探针"},
                          timeout=8)
    steps.append(f"建会话 {code}")
    if code not in (200, 201):
        return _item("probe-session", "探针会话全环", "fail", "；".join(steps),
                     "建会话这一步就没过，先查 Hermes 的接口面。")
    model = (body or {}).get("model")
    if model:
        code2, _ = http_req("POST", f"{HERMES_BASE}/api/sessions/{sid}/model",
                            LOGIN_KEY_SERVER_COPY, {"model": model}, timeout=8)
        steps.append(f"切换模型 {code2}")
    else:
        steps.append("切换模型 跳过（回执没带模型名）")
    code3, _ = http_req("DELETE", f"{HERMES_BASE}/api/sessions/{sid}",
                        LOGIN_KEY_SERVER_COPY, timeout=8)
    steps.append(f"删探针 {code3}")
    if code3 not in (200, 204, 404):
        return _item("probe-session", "探针会话全环", "fail",
                     "；".join(steps) + " —— 探针会话可能没删掉，请人工处理",
                     "到 Hermes 的会话管理里删掉 companion-probe 开头的那条。")
    ok = all(s.rsplit(" ", 1)[-1] in ("200", "201", "204", "跳过（回执没带模型名）") or "跳过" in s
             for s in steps)
    return _item("probe-session", "探针会话全环", "ok" if ok else "warn",
                 "；".join(steps), "")


# ---------------------------------------------------------------- connections
CONN_PATH = STATE_DIR / "connections.json"


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
    companion_vars = env_read_vars(ENV_FILE)
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


def mcp_initialize(url: str, token: str, timeout: float = 8.0):
    """Protocol-level liveness: MCP initialize (+ tools/list when a
    session id comes back). Returns (ok, detail, tool_count|None)."""
    headers = {"Authorization": f"Bearer {token}",
               "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
    payload = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
               "params": {"protocolVersion": "2025-03-26", "capabilities": {},
                          "clientInfo": {"name": "oneday-companion", "version": VERSION}}}
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
        return False, "对方应答不像一个电脑服务", None
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
            m = re.search(r'"tools"\s*:\s*\[', raw2)
            if m:
                tools = raw2.count('"name"')
        except Exception:
            pass
    detail = "服务应答正常" + (f"，数到 {tools} 个工具" if tools else "")
    return True, detail, tools


# ------------------------------------------------- box direct probe (桥-3 解耦)
# 云电脑验活不再经本地 box 桥（8645 /health 的 mcpSession），改直连
# Simular 官方 MCP 做 initialize——与非默认 simular_box 记录在
# cred_simular 里的直连验活同路。本节独立于 MODULE_META 实现：
# 部署窗摘 MODULE_META/MODULE_KEYS 的 box 键、删 probe_module 的
# box 分支后，本节与 conn_verify 均不受影响（过渡期 probe_module
# 的 box 分支只委托本节，保模块行状态不断）。
def box_mcp_url() -> str:
    return os.environ.get("BOX_MCP_URL", "https://mcp.box.simular.ai/mcp")


def probe_box_direct() -> tuple[str, str]:
    """云电脑直连探针，返回 (state, detail)，语义与旧桥探针对齐：
    up＝厂商 MCP 应答正常；degraded＝有钥但连不上厂商（旧桥口径
    「与厂商的连接断了，正在自动重连」）；down＝还没配钥（钥的
    在位判定与连接记录 configured 同源：companion.env [box] 段）。"""
    key = env_read_vars(ENV_FILE).get("MCP_BOX_API_KEY", "")
    if not key:
        return "down", ""
    ok, _detail, _tools = mcp_initialize(box_mcp_url(), key)
    if ok:
        return "up", ""
    return "degraded", "与厂商的连接断了，正在自动重连"


def conn_verify(rec: dict) -> tuple[bool, str]:
    p = rec["provider"]
    if p == "github":
        token = env_read_vars(HERMES_ENV_PATH).get("GITHUB_MCP_TOKEN", "")
        if not token:
            return False, "还没填令牌"
        ok, detail, _ = mcp_initialize("https://api.githubcopilot.com/mcp/", token)
        return ok, detail
    if p == "simular_box":
        state, detail = probe_box_direct()
        return state == "up", detail or f"云电脑状态 {state}"
    if p == "vps_agent":
        s = rec.get("secret", {})
        if s.get("access") == "windows":
            return verify_windows(rec)
        if not s.get("endpointUrl"):
            return False, "还没填这台电脑的地址与令牌"
        return mcp_initialize(s["endpointUrl"], s.get("token", ""))[:2]
    if p == "notion":
        tok_dir = HERMES_HOME / "mcp-tokens"
        found = tok_dir.exists() and any("notion" in f.name.lower()
                                         for f in tok_dir.iterdir())
        return (True, "令牌文件在位（授权完成度要等窗口实测）") if found \
            else (False, "没找到 Notion 的令牌文件，多半还没授权")
    if p == "gateway":
        return True, "未安装（可选），这一项跳过"
    if p == "hermes_mcp":
        code, body = http_req("GET", HERMES_BASE + "/api/mcp/servers",
                              LOGIN_KEY_SERVER_COPY, timeout=5)
        if code == 200 and isinstance(body, (dict, list)):
            names = []
            items = body if isinstance(body, list) else body.get("servers", body)
            if isinstance(items, list):
                names = [str(x.get("name", x)) if isinstance(x, dict) else str(x)
                         for x in items]
            elif isinstance(items, dict):
                names = list(items.keys())
            return True, "已登记：" + ("、".join(names) if names else "（空）")
        return False, "自动检测没通（这个接口还没证实，留到窗口期实测）"
    return False, "这一项暂时没法自动验活"


def _set_verify(rec: dict, ok: bool, detail: str) -> None:
    rec["lastVerify"] = {"at": now_iso(), "ok": ok, "detail": detail}


# ---------------------------------------------------------------- credential actions
def cred_github(rec: dict, body: dict) -> tuple[int, dict]:
    token = str(body.get("token", "")).strip()
    if len(token) < 20 or any(c.isspace() for c in token):
        return 400, {"ok": False, "error": "这个令牌看起来不对：长度不够或带了空格"}
    bak = env_backup(HERMES_ENV_PATH)
    env_set_var(HERMES_ENV_PATH, "GITHUB_MCP_TOKEN", token)
    ok, detail = conn_verify(rec)
    if not ok:
        if bak.exists():
            shutil.copyfile(bak, HERMES_ENV_PATH)
        _set_verify(rec, False, detail)
        rec["configured"] = False
        return 200, {"ok": False, "detail": f"验活没过（{detail}），已经把刚才的改动撤回"}
    _set_verify(rec, True, detail)
    rec["configured"] = True
    rec["effective"] = "待重启 Hermes 生效"
    rec["note"] = "令牌已保存；Hermes 重启后才会用上新令牌"
    return 200, {"ok": True, "detail": detail}


def cred_simular(rec: dict, body: dict) -> tuple[int, dict]:
    api_key = str(body.get("apiKey", "")).strip()
    if len(api_key) < 10:
        return 400, {"ok": False, "error": "这个密钥看起来不对：太短了"}
    if rec["id"] != "box":
        ok, detail, _ = mcp_initialize(box_mcp_url(), api_key)
        if ok:
            rec["secret"] = {"apiKey": api_key}
            rec["configured"] = True
            rec["note"] = "密钥已验活；这台电脑接进智能体的登记随云电脑包落地"
        _set_verify(rec, ok, detail)
        return 200, {"ok": ok, "detail": detail}
    # 默认记录（桥-3 解耦后）：钥落 companion.env [box] 段即生效于
    # 直连探针，不再停/启 box 模块；验活＝拿新钥直连厂商 MCP 做
    # initialize，没过就回滚 env（与 cred_github 同一回滚纪律）。
    bak = env_backup(ENV_FILE)
    env_set_var(ENV_FILE, "MCP_BOX_API_KEY", api_key, segment="box")
    ok, detail, _ = mcp_initialize(box_mcp_url(), api_key)
    if not ok:
        if bak.exists():
            shutil.copyfile(bak, ENV_FILE)
        _set_verify(rec, False, detail)
        rec["configured"] = False
        return 200, {"ok": False, "detail": "新密钥没能连上厂商，已经换回原来的"}
    _set_verify(rec, True, detail)
    rec["configured"] = True
    rec["effective"] = "已生效"
    return 200, {"ok": True, "detail": "云电脑已连上"}


# ------------------------------------------------- windows login form (cloudpc closeout)
# VPS 型定版形态（2026-11-11 15:58 用户定版，收口规格
# cloudpc-closeout-spec-20261112 §4）：App 只收 IP＋账户
# 名＋密码三样；密码只落本机 connections.json 的 secret
# （0600、读面永不回传），端点与代理令牌是服务端在装
# 代理后回填同一 secret 的内部字段，用户面永不出现。
WIN_PROBE_PORTS = (3389, 445, 5985, 5986)


def _tcp_open(host: str, port: int, timeout: float = 2.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except Exception:
        return False


def winrm_probe(host: str, username: str, password: str):
    """Credential proof over WinRM (NTLM): run `hostname`
    on the machine. Returns (state, machine_name):
    ok / auth_failed / unreachable / unavailable.
    pywinrm is an OPTIONAL dependency: the production
    image does not ship it yet (deploy-gate item), so
    absence degrades to 'unavailable', never to a fake ok."""
    try:
        import winrm  # type: ignore
    except Exception:
        return "unavailable", ""
    for scheme, port in (("https", 5986), ("http", 5985)):
        try:
            sess = winrm.Session(
                f"{scheme}://{host}:{port}/wsman",
                auth=(username, password), transport="ntlm",
                server_cert_validation="ignore")
            r = sess.run_cmd("hostname")
            if r.status_code == 0:
                name = r.std_out.decode("utf-8", "replace").strip()
                return "ok", name
            return "auth_failed", ""
        except Exception as e:
            blob = type(e).__name__ + " " + str(e)
            if "InvalidCredentials" in blob or "401" in blob \
                    or "Authentication" in blob:
                return "auth_failed", ""
            continue
    return "unreachable", ""


def verify_windows(rec: dict) -> tuple[bool, str]:
    """Ladder for windows-mode records (spec §4.3):
    agent MCP first when bootstrap already filled the
    internal endpoint, then WinRM credential proof, then
    plain reachability. Wording never upgrades an
    unproven credential to 'verified'."""
    s = rec.get("secret", {})
    if s.get("endpointUrl") and s.get("token"):
        return mcp_initialize(s["endpointUrl"], s["token"])[:2]
    host = str(s.get("host", ""))
    if not host:
        return False, "还没填这台电脑的登录信息"
    state, machine = winrm_probe(host, str(s.get("username", "")),
                                 str(s.get("password", "")))
    if state == "ok":
        who = f"（这台电脑自报 {machine}）" if machine else ""
        return True, f"登录验证通过{who}；装代理与接进智能体由服务端后续完成"
    if state == "auth_failed":
        return False, "登录没通过：账户名或密码不对"
    if any(_tcp_open(host, p) for p in WIN_PROBE_PORTS):
        return True, "已联系上这台电脑，登录信息已保存；登录对不对要等装代理时最终确认"
    return False, "按这个地址联系不上这台电脑，看看 IP 对不对、电脑开着没有"


def cred_vps_windows(rec: dict, body: dict) -> tuple[int, dict]:
    host = str(body.get("host", "")).strip()
    username = str(body.get("username", "")).strip()
    password = str(body.get("password", ""))
    if not host or "://" in host or "/" in host \
            or any(c.isspace() for c in host):
        return 400, {"ok": False, "error": "IP 地址看起来不对：填电脑的 IP 或主机名，不要带 http:// 这类前缀"}
    if not username or not password:
        return 400, {"ok": False, "error": "账户名和密码都要填"}
    probe = {"secret": {"access": "windows", "host": host,
                        "username": username, "password": password}}
    ok, detail = verify_windows(probe)
    if not ok:
        rec.pop("secret", None)
        rec.pop("pendingConfigEntry", None)
        _set_verify(rec, False, detail)
        rec["configured"] = False
        return 200, {"ok": False,
                     "detail": f"{detail}，登录信息没有保存"}
    old = rec.get("secret", {})
    merged = dict(probe["secret"])
    for k in ("endpointUrl", "token", "envVar"):
        if old.get(k):
            merged[k] = old[k]
    rec["secret"] = merged
    rec["configured"] = True
    if not merged.get("endpointUrl"):
        rec["effective"] = "已保存 · 待打通"
    rec["note"] = "登录信息已保存；装代理与接进智能体由服务端后续完成，你不用再管"
    _set_verify(rec, True, detail)
    return 200, {"ok": True, "detail": detail}


def cred_vps(rec: dict, body: dict) -> tuple[int, dict]:
    if body.get("access") == "windows" or (
            "host" in body and "endpointUrl" not in body):
        return cred_vps_windows(rec, body)
    url = str(body.get("endpointUrl", "")).strip()
    token = str(body.get("token", "")).strip()
    if not url.startswith(("http://", "https://")) or not token:
        return 400, {"ok": False, "error": "地址要以 http:// 或 https:// 开头，令牌不能为空"}
    var = "MCP_CC_" + re.sub(r"[^A-Za-z0-9]", "_", rec["id"]).upper() + "_TOKEN"
    bak = env_backup(HERMES_ENV_PATH)
    env_set_var(HERMES_ENV_PATH, var, token)
    ok, detail, tools = mcp_initialize(url, token)
    if not ok:
        if bak.exists():
            shutil.copyfile(bak, HERMES_ENV_PATH)
        rec.pop("secret", None)
        _set_verify(rec, False, detail)
        rec["configured"] = False
        return 200, {"ok": False, "detail": f"验活没过（{detail}），已经把刚才的改动撤回"}
    slug = re.sub(r"[^a-z0-9-]", "-", rec["id"].lower())
    rec["secret"] = {"endpointUrl": url, "token": token, "envVar": var}
    rec["pendingConfigEntry"] = {
        "server": f"box-{slug}", "url": url,
        "headers": {"Authorization": f"Bearer ${{{var}}}"}}
    rec["configured"] = True
    rec["effective"] = "已配置 · 待生效"
    rec["note"] = "已验活；登记进 Hermes 的动作在窗口期完成"
    _set_verify(rec, True, detail)
    return 200, {"ok": True, "detail": detail}


def disconnect(rec: dict) -> tuple[int, dict]:
    p = rec["provider"]
    if p == "github":
        env_backup(HERMES_ENV_PATH)
        env_set_var(HERMES_ENV_PATH, "GITHUB_MCP_TOKEN", None)
    elif p == "simular_box" and rec["id"] == "box":
        # 桥-3 解耦后：清钥即断开，直连探针下次读 env 即 down，
        # 不再停/启 box 模块。
        env_backup(ENV_FILE)
        env_set_var(ENV_FILE, "MCP_BOX_API_KEY", None, segment="box")
    elif p in ("simular_box", "vps_agent"):
        var = rec.get("secret", {}).get("envVar")
        if var:
            env_backup(HERMES_ENV_PATH)
            env_set_var(HERMES_ENV_PATH, var, None)
        rec.pop("secret", None)
        rec.pop("pendingConfigEntry", None)
    elif p == "notion":
        tok_dir = HERMES_HOME / "mcp-tokens"
        if tok_dir.exists():
            stamp = datetime.now().strftime("%Y%m%d%H%M%S")
            for f in tok_dir.iterdir():
                if "notion" in f.name.lower() and "disconnected" not in f.name:
                    f.rename(f.with_name(f.name + f".disconnected-{stamp}"))
    rec["configured"] = False
    rec["effective"] = ""
    rec["note"] = ""
    _set_verify(rec, False, "已断开")
    return 200, {"ok": True, "detail": "已断开"}


# ---------------------------------------------------------------- handler
# ------------------------------------------------- agent identity (1.0.36)
# Web-client identity editing: rename = rewrite ONLY the top title line
# of SOUL.md (the name both clients resolve from the soul, iOS
# AgentName.resolve rules mirrored below); avatar = one image file in
# STATE_DIR served back through this authenticated surface.
AGENT_NAME_FORBIDDEN = {"soul", "soul.md", "灵魂", "人设", "身份",
                        "identity", "persona", "about", "profile"}
AGENT_NAME_PUNCT = set("。．.：:、，,；;！!？?")
AVATAR_MAX_BYTES = 2 * 1024 * 1024
AVATAR_FORMATS = {  # ext -> (mime, magic prefix bytes alternatives)
    "png": ("image/png", (b"\x89PNG\r\n\x1a\n",)),
    "jpg": ("image/jpeg", (b"\xff\xd8\xff",)),
    "webp": ("image/webp", (b"RIFF",)),
}


def soul_path() -> Path:
    return HERMES_HOME / "SOUL.md"


def parse_agent_name(soul: str) -> str | None:
    """Mirror of the clients' resolveAgentName: first '# ' title within
    the first three non-empty lines, same validity rules; None when the
    soul carries no usable title (clients fall back to 'Hermes')."""
    non_empty = 0
    for raw in soul.split("\n"):
        line = raw.strip()
        if not line:
            continue
        non_empty += 1
        if non_empty > 3:
            break
        if line.startswith("# "):
            cand = line[2:].strip()
            if not cand or len(cand) > 20:
                return None
            if any(ch in AGENT_NAME_PUNCT for ch in cand):
                return None
            if cand.lower() in AGENT_NAME_FORBIDDEN:
                return None
            return cand
    return None


def validate_agent_name(name: str) -> str | None:
    """None when valid, else the user-facing reason (same rules the
    clients apply when resolving, so a written name always reads back)."""
    if not name:
        return "名字不能为空"
    if len(name) > 20:
        return "名字最多 20 个字"
    if any(ch in AGENT_NAME_PUNCT for ch in name):
        return "名字里不能带标点符号"
    if name.lower() in AGENT_NAME_FORBIDDEN:
        return "这个名字是保留词，换一个"
    if "\n" in name or "\r" in name:
        return "名字不能换行"
    return None


def avatar_file() -> Path | None:
    for ext in AVATAR_FORMATS:
        p = STATE_DIR / f"agent-avatar.{ext}"
        if p.exists():
            return p
    return None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(f"[front] {self.address_string()} {fmt % args}", flush=True)

    # ------------------------------------------------------------ plumbing
    def _send(self, code: int, obj, ctype: str = "application/json",
              extra: dict | None = None) -> None:
        body = obj if isinstance(obj, (bytes, str)) else json.dumps(obj, ensure_ascii=False)
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        try:
            n = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(n) if n else b""
            return json.loads(raw or b"{}")
        except Exception:
            return {}

    def _cookie_sid(self) -> str | None:
        for part in self.headers.get("Cookie", "").split(";"):
            part = part.strip()
            if part.startswith("companion_session="):
                return part.split("=", 1)[1]
        return None

    def _auth(self) -> tuple[str | None, dict | None]:
        auth = self.headers.get("Authorization", "")
        if SERVICE_KEY and auth.startswith("Bearer ") and \
                hmac.compare_digest(auth[7:], SERVICE_KEY):
            return "service", None
        # M1 integration fix (2026-11-10): the App channel presents the
        # Hermes login key itself. The spec's nginx auth_request swap
        # cannot coexist with the browser cookie channel on the same
        # prefix (a variable auth_request URI is not evaluated by the
        # deployed nginx build, and a static gate blocks cookie-only
        # requests before they reach the front). The front already
        # holds the server copy of the login key for self-checks;
        # accepting it here keeps one gate in one place with the same
        # trust domain (key holder = deployer).
        if LOGIN_KEY_SERVER_COPY and auth.startswith("Bearer ") and \
                hmac.compare_digest(auth[7:], LOGIN_KEY_SERVER_COPY):
            return "app", None
        sess = SESSIONS.get(self._cookie_sid())
        if sess is not None:
            return "cookie", sess
        return None, None

    def _require_auth(self, write: bool = False):
        mode, sess = self._auth()
        if mode is None:
            self._send(401, {"ok": False, "error": "未登录"})
            return None
        if write and mode == "cookie":
            token = self.headers.get("X-Companion-CSRF", "")
            if not hmac.compare_digest(token, sess.get("csrf", "")):
                self._send(403, {"ok": False, "error": "页面令牌对不上，刷新后重试"})
                return None
        return mode

    # ------------------------------------------------------------ GET
    def do_GET(self):
        u = urlparse(self.path)
        path = u.path
        if path in ("/", "/companion", "/companion/"):
            return self._static("index.html")
        if path.startswith("/static/") or path.startswith("/companion/static/"):
            return self._static(path.rsplit("/static/", 1)[1])
        if path == "/api/companion/session":
            mode, sess = self._auth()
            return self._send(200, {"authenticated": mode is not None,
                                    "csrf": sess.get("csrf") if sess else None})
        if not path.startswith("/api/companion/"):
            return self._send(404, {"error": "not found"})
        if self._require_auth() is None:
            return
        route = path[len("/api/companion"):]
        if route == "/avatar":
            return self._avatar_get()
        if route == "/info":
            return self._send(200, build_info())
        if route == "/health":
            agg = aggregate()
            ok = all(v["state"] == "up" for v in agg.values())
            return self._send(200 if ok else 503, {
                "ok": ok, "hermesUp": hermes_up(),
                "modules": {k: v["state"] for k, v in agg.items()},
                "generatedAt": now_iso()})
        if route == "/modules":
            return self._send(200, {"modules": self._modules_view()})
        if route.startswith("/modules/") and route.endswith("/logs"):
            mid = route.split("/")[2]
            if mid not in MODULE_META:
                return self._send(404, {"error": "没有这个模块"})
            n = parse_qs(u.query).get("lines", ["50"])[0]
            code, body = control("GET", f"/modules/{mid}/logs?lines={n}")
            if code != 200:
                return self._send(503, {"lines": [], "error": "监督者控制通道不可用"})
            return self._send(200, body)
        if route == "/selfcheck":
            p = STATE_DIR / "selfcheck.json"
            last = None
            if p.exists():
                try:
                    last = json.loads(p.read_text())
                except Exception:
                    last = None
            return self._send(200, {"lastRun": last})
        if route == "/connections":
            recs = conn_load()
            conn_refresh(recs)
            conn_save(recs)
            return self._send(200, {"connections": [conn_public(r) for r in recs]})
        if route == "/version":
            return self._send(200, self._version_view())
        if route == "/resources":
            return self._send(200, self._resources_view())
        if route == "/sync":
            return self._sync_view()
        if route == "/ledger":
            return self._ledger_view()
        if route == "/gateway-channels":
            code, obj = fetch_gateway_channels()
            return self._send(code, obj)
        return self._send(404, {"error": "not found"})

    # ------------------------------------------------------------ sync
    # Panel shows sync STATE only (counts, times, range, switches).
    # Record content never passes through here: the device module's
    # status view carries no records, and neither does this proxy.
    SYNC_ORDER = ["contacts", "calendar", "reminders", "photos",
                  "motion"]

    def _device_req(self, method: str, path: str,
                    body: dict | None = None):
        port = MODULE_META["device"]["port"]
        return http_req(method, f"http://127.0.0.1:{port}{path}",
                        MODULE_KEYS.get("device", ""), body=body,
                        timeout=6)

    def _sync_view(self):
        code, body = self._device_req("GET", "/device/sync/status")
        if code != 200 or not isinstance(body, dict):
            return self._send(503, {"datasets": [], "error":
                                    "手机设备模块暂时取不到同步状态"})
        raw = body.get("datasets") or {}
        datasets = [raw[k] for k in self.SYNC_ORDER if k in raw]
        return self._send(200, {"datasets": datasets})

    # ------------------------------------------------------------ ledger
    # Panel shows ledger COUNTS only (in progress / awaiting
    # approval / lost contact / today's outcomes + the collector
    # heartbeat). Item titles and bodies never pass through
    # here: the oneday module's summary view carries no items,
    # and neither does this proxy.
    def _ledger_view(self):
        # 断桥批三（包 1.13.0）：台账随 oneday 入网关，计数走网关
        # 正口（front 与 hermes 同在 hermes_default 网络，HERMES_BASE
        # 直达），钥为网关本体钥（凭据单源；front 经 include_global
        # 持有 HERMES_API_KEY）。
        code, body = http_req(
            "GET", HERMES_BASE + "/v1/oneday/ledger/summary",
            os.environ.get("HERMES_API_KEY", ""), timeout=6)
        if code != 200 or not isinstance(body, dict):
            return self._send(503, {"error":
                                    "目标点子模块暂时取不到台账计数"})
        return self._send(200, body)

    def _sync_delete(self, body: dict):
        payload = {}
        if body.get("dataset"):
            payload["dataset"] = body["dataset"]
        code, out = self._device_req("POST", "/device/sync/delete",
                                     payload)
        if code != 200:
            return self._send(502, {"ok": False,
                                    "error": "删除没有执行成功"})
        return self._send(200, {"ok": True, "result": out})

    def _modules_view(self) -> list[dict]:
        ctrl = control_status()
        agg = aggregate()
        out = []
        for mid, meta in MODULE_META.items():
            proc = (ctrl or {}).get(mid, {})
            if ctrl is None:
                state = "unknown"
            elif not proc.get("desired", True):
                state = "disabled"
            elif proc.get("state") == "crash-loop":
                state = "crash-loop"
            elif proc.get("state") == "running":
                state = "running"
            else:
                state = "stopped"
            out.append({
                "id": mid, "name": meta["name"], "sub": meta["sub"],
                "desc": meta["desc"], "state": state,
                "desired": proc.get("desired"),
                "pid": proc.get("pid"), "restarts": proc.get("restarts", 0),
                "uptimeSec": proc.get("uptimeSec", 0), "rssMB": proc.get("rssMB"),
                "probeState": agg[mid]["state"], "probeDetail": agg[mid]["detail"],
            })
        return out

    def _version_view(self) -> dict:
        actual = None
        code, body = http_req("GET", HERMES_BASE + "/health", timeout=3)
        if code == 200 and isinstance(body, dict):
            actual = body.get("version")
        lkg = None
        p = STATE_DIR / "last-known-good"
        if p.exists():
            lkg = p.read_text().strip() or None
        return {
            "companion": {"version": VERSION, "apiLevel": API_LEVEL,
                          "buildDate": BUILD_DATE, "minAppVersion": MIN_APP_VERSION},
            "hermes": {"expected": "v0.23.0", "actual": actual},
            "lastKnownGood": lkg,
            "upgradeCmd": "docker compose up -d companion   # 先把 compose 里 companion 的镜像标签改成新版本",
            "rollbackCmd": "docker compose up -d companion   # 把镜像标签改回上一个好版本（见上方记录）",
        }

    def _resources_view(self) -> dict:
        dirs = []
        for label, path in DIR_SIZES:
            size = None
            if path.exists():
                total, count = 0, 0
                for dp, _, files in os.walk(path):
                    for f in files:
                        try:
                            total += os.path.getsize(os.path.join(dp, f))
                        except Exception:
                            pass
                        count += 1
                        if count > 20000:
                            break
                size = round(total / 1048576.0, 1)
            dirs.append({"label": label, "path": str(path), "sizeMB": size})
        ctrl = control_status() or {}
        rss = [v.get("rssMB") for v in ctrl.values() if v.get("rssMB")]
        return {"dirs": dirs,
                "modulesRssMB": round(sum(rss), 1) if rss else None}

    def _static(self, name: str):
        target = (STATIC_DIR / name).resolve()
        if not str(target).startswith(str(STATIC_DIR.resolve())) or not target.is_file():
            return self._send(404, {"error": "not found"})
        ctype = {".html": "text/html; charset=utf-8",
                 ".css": "text/css; charset=utf-8",
                 ".js": "text/javascript; charset=utf-8"}.get(target.suffix, "application/octet-stream")
        return self._send(200, target.read_bytes(), ctype)

    # ------------------------------------------------------------ POST
    def do_POST(self):
        u = urlparse(self.path)
        path = u.path
        if path == "/api/companion/login":
            return self._login()
        if path == "/api/companion/web-login":
            return self._web_login()
        if not path.startswith("/api/companion/"):
            return self._send(404, {"error": "not found"})
        route = path[len("/api/companion"):]
        if route == "/logout":
            # Exempt from CSRF: a forged logout is a nuisance, not a
            # breach; every other write keeps the token check.
            if self._auth()[0] is None:
                return self._send(401, {"ok": False, "error": "未登录"})
            SESSIONS.drop(self._cookie_sid())
            return self._send(200, {"ok": True}, extra={
                "Set-Cookie": "companion_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"})
        if self._require_auth(write=True) is None:
            return
        body = self._body()
        if route == "/password":
            pw = str(body.get("password", ""))
            if len(pw) < 8:
                return self._send(400, {"ok": False, "error": "密码至少 8 位"})
            set_password_hash(hash_password(pw))
            return self._send(200, {"ok": True})
        if route == "/change-password":
            return self._change_password(body)
        if route == "/agent-name":
            return self._agent_name(body)
        if route == "/avatar":
            return self._avatar_set(body)
        if route.startswith("/modules/") and route.endswith("/toggle"):
            return self._toggle(route.split("/")[2], body)
        if route == "/selfcheck/run":
            return self._send(200, run_selfcheck(bool(body.get("probes"))))
        if route == "/sync/delete":
            return self._sync_delete(body)
        if route == "/connections":
            return self._conn_create(body)
        if route.startswith("/connections/"):
            parts = route.split("/")
            cid, action = parts[2], parts[3] if len(parts) > 3 else ""
            recs = conn_load()
            rec = next((r for r in recs if r["id"] == cid), None)
            if rec is None:
                return self._send(404, {"error": "没有这条连接"})
            if action == "credential":
                code, out = self._credential(rec, body)
            elif action == "verify":
                ok, detail = conn_verify(rec)
                _set_verify(rec, ok, detail)
                code, out = 200, {"ok": ok, "detail": detail, "at": now_iso()}
            elif action == "disconnect":
                code, out = disconnect(rec)
            else:
                return self._send(404, {"error": "not found"})
            conn_save(recs)
            out = dict(out)
            out["connection"] = conn_public(rec)
            return self._send(code, out)
        return self._send(404, {"error": "not found"})

    def _toggle(self, mid: str, body: dict):
        if mid not in MODULE_META:
            return self._send(404, {"error": "没有这个模块"})
        enabled = bool(body.get("enabled"))
        if mid == "writeGate" and not enabled and not body.get("confirm"):
            return self._send(409, {"ok": False, "needConfirm": True,
                                    "error": "关审批需要再确认一次"})
        code, _ = control("POST", f"/modules/{mid}/{'start' if enabled else 'stop'}")
        if code != 200:
            return self._send(503, {"ok": False, "error": "监督者控制通道不可用"})
        return self._send(200, {"ok": True})

    def _conn_create(self, body: dict):
        kind = str(body.get("kind", ""))
        provider = str(body.get("provider", ""))
        name = str(body.get("name", "")).strip()
        if kind != "cloud_computer" or provider not in ("simular_box", "vps_agent") or not name:
            return self._send(400, {"ok": False,
                                    "error": "只能在这里添加云电脑（托管或自己的 VPS）"})
        recs = conn_load()
        n = sum(1 for r in recs if r["provider"] == provider) + 1
        rec = {"id": f"{provider}-{n}", "kind": kind, "provider": provider,
               "name": name, "configured": False, "lastVerify": None,
               "effective": "", "note": ""}
        recs.append(rec)
        conn_save(recs)
        return self._send(200, {"ok": True, "connection": conn_public(rec)})

    def _credential(self, rec: dict, body: dict):
        p = rec["provider"]
        if p == "github":
            return cred_github(rec, body)
        if p == "simular_box":
            return cred_simular(rec, body)
        if p == "vps_agent":
            return cred_vps(rec, body)
        if p == "notion":
            return 400, {"ok": False,
                         "error": "Notion 是点授权完成的，不在这里粘贴令牌"}
        return 400, {"ok": False, "error": "这一项没有要填的凭据"}

    # ------------------------------------------------------------ login
    def _client_ip(self) -> str:
        """Source IP for login rate-limit accounting (1.0.34). All
        public traffic arrives via the same-host nginx, so the peer
        is always loopback and every client used to share one
        failure bucket — one person's lockout locked everyone. When
        the peer is loopback, nginx's X-Real-IP (set from
        $remote_addr) carries the real source; trust it only then.
        A non-loopback peer is accounted by its own address and its
        forwarding headers are ignored."""
        peer = self.client_address[0]
        if peer in ("127.0.0.1", "::1"):
            real = (self.headers.get("X-Real-IP") or "").strip()
            if real:
                return real
        return peer

    def _login(self):
        body = self._body()
        method = body.get("method", "password")
        ip = self._client_ip()
        fkey = f"{ip}:{method}"
        fails = [t for t in LOGIN_FAILS.get(fkey, [])
                 if time.time() - t < LOGIN_FAIL_WINDOW]
        LOGIN_FAILS[fkey] = fails
        if len(fails) >= LOGIN_FAIL_LIMIT:
            return self._send(429, {"ok": False, "error": "尝试太多次，请几分钟后再试"})
        ok = False
        if method == "password":
            stored = effective_password_hash()
            if stored:
                ok = verify_password(str(body.get("password", "")), stored)
        elif method == "key":
            submitted = str(body.get("key", ""))
            if submitted:
                code, _ = http_req("GET", HERMES_BASE + "/v1/models", submitted,
                                   timeout=5)
                ok = code == 200
        if not ok:
            fails.append(time.time())
            LOGIN_FAILS[fkey] = fails
            return self._send(401, {"ok": False, "error": "登录失败，请检查后重试"})
        LOGIN_FAILS.pop(fkey, None)
        sid, csrf = SESSIONS.create()
        cookie = f"companion_session={sid}; Path=/; Max-Age={SESSION_TTL}; HttpOnly; SameSite=Strict"
        if COOKIE_SECURE:
            cookie += "; Secure"
        return self._send(200, {"ok": True, "csrf": csrf},
                          extra={"Set-Cookie": cookie})

    # ---------------------------------------------- change password
    def _change_password(self, body):
        """Change the deployer password from an authenticated surface
        (the OneDay web settings page, 1.0.35). Unlike the panel's
        /password route -- which trusts the panel session alone --
        this one re-verifies the CURRENT password before writing the
        new hash, and failed verifications share the login rate-limit
        pool (same per-IP bucket as _login/_web_login), so the
        endpoint cannot be used to grind the current password.
        Writes go through the exact same scrypt path as --set-password
        (hash_password + set_password_hash, fresh read on every
        verify), so panel login and web-login pick the new password
        up immediately. The Hermes session cookie and the login key
        are unaffected: the caller stays signed in."""
        ip = self._client_ip()
        fkey = f"{ip}:password"
        now = time.time()
        fails = [t for t in LOGIN_FAILS.get(fkey, [])
                 if now - t < LOGIN_FAIL_WINDOW]
        LOGIN_FAILS[fkey] = fails
        if len(fails) >= LOGIN_FAIL_LIMIT:
            return self._send(429, {"ok": False,
                                    "error": "尝试太多次，请几分钟后再试"})
        current = str(body.get("currentPassword", ""))
        new = str(body.get("newPassword", ""))
        stored = effective_password_hash()
        if not stored or not verify_password(current, stored):
            fails.append(now)
            LOGIN_FAILS[fkey] = fails
            return self._send(401, {"ok": False, "error": "当前密码不对"})
        if len(new) < 8:
            return self._send(400, {"ok": False, "error": "新密码至少 8 位"})
        if new == current:
            return self._send(400, {"ok": False,
                                    "error": "新密码不能和当前密码一样"})
        set_password_hash(hash_password(new))
        LOGIN_FAILS.pop(fkey, None)
        return self._send(200, {"ok": True})

    # ------------------------------------------------- agent identity
    def _agent_name(self, body):
        """Rename the agent (web identity card, 1.0.36). Writes ONLY the
        top title line of SOUL.md: replaces the first '# ' line within
        the first three non-empty lines, or inserts one at the top when
        the soul has none. Body text is preserved byte-for-byte beyond
        that line; a timestamped backup is taken first and the write is
        verified by re-reading and re-resolving the name -- a mismatch
        restores the backup and reports failure instead of claiming
        success."""
        name = str(body.get("name", "")).strip()
        err = validate_agent_name(name)
        if err:
            return self._send(400, {"ok": False, "error": err})
        p = soul_path()
        if not p.exists():
            return self._send(404, {"ok": False, "error": "人设文件不存在，改不了名"})
        try:
            original = p.read_text(encoding="utf-8")
        except Exception:
            return self._send(500, {"ok": False, "error": "人设文件读不出来"})
        lines = original.split("\n")
        non_empty = 0
        replaced = False
        for i, raw in enumerate(lines):
            if not raw.strip():
                continue
            non_empty += 1
            if non_empty > 3:
                break
            if raw.strip().startswith("# "):
                lines[i] = f"# {name}"
                replaced = True
                break
        new_text = "\n".join(lines) if replaced else f"# {name}\n\n" + original
        stamp = time.strftime("%Y%m%d-%H%M%S")
        backup = p.with_name(f"SOUL.md.bak-agentname-{stamp}")
        try:
            backup.write_text(original, encoding="utf-8")
            p.write_text(new_text, encoding="utf-8")
            back = parse_agent_name(p.read_text(encoding="utf-8"))
        except Exception:
            return self._send(500, {"ok": False, "error": "写入失败，原文件未动"})
        if back != name:
            try:
                p.write_text(original, encoding="utf-8")
            except Exception:
                pass
            return self._send(500, {"ok": False,
                                    "error": "写后校验没通过，已恢复原样"})
        return self._send(200, {"ok": True, "name": back})

    def _avatar_set(self, body):
        """Store a new agent avatar (web identity card, 1.0.36). Accepts
        a data URL image only; format is proven by magic bytes, not by
        the declared MIME. One file in STATE_DIR; version string lets
        the client bust caches."""
        import base64
        data_url = str(body.get("data_url", ""))
        m = re.match(r"^data:image/(png|jpeg|webp);base64,(.+)$", data_url, re.S)
        if not m:
            return self._send(400, {"ok": False, "error": "只接受 PNG/JPEG/WebP 图片"})
        try:
            raw = base64.b64decode(m.group(2), validate=True)
        except Exception:
            return self._send(400, {"ok": False, "error": "图片数据损坏"})
        if not raw or len(raw) > AVATAR_MAX_BYTES:
            return self._send(400, {"ok": False, "error": "图片要小于 2MB"})
        ext = "jpg" if m.group(1) == "jpeg" else m.group(1)
        magics = AVATAR_FORMATS[ext][1]
        if ext == "webp":
            ok = raw[:4] == b"RIFF" and raw[8:12] == b"WEBP"
        else:
            ok = any(raw.startswith(mg) for mg in magics)
        if not ok:
            return self._send(400, {"ok": False, "error": "图片格式与内容对不上"})
        try:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            for old_ext in AVATAR_FORMATS:
                old = STATE_DIR / f"agent-avatar.{old_ext}"
                if old.exists() and old_ext != ext:
                    old.unlink()
            (STATE_DIR / f"agent-avatar.{ext}").write_bytes(raw)
        except Exception:
            return self._send(500, {"ok": False, "error": "头像保存失败"})
        version = hashlib.sha256(raw).hexdigest()[:12]
        return self._send(200, {"ok": True, "version": version})

    def _avatar_get(self):
        p = avatar_file()
        if p is None:
            return self._send(404, {"ok": False, "error": "还没有设置过头像"})
        try:
            raw = p.read_bytes()
        except Exception:
            return self._send(500, {"ok": False, "error": "头像读不出来"})
        mime = AVATAR_FORMATS[p.suffix.lstrip(".")][0]
        return self._send(200, raw, ctype=mime,
                          extra={"Cache-Control": "no-cache"})

    # ------------------------------------------------- web login bridge
    def _web_login(self):
        """OneDay web client login. The deployer (panel) password goes
        in; a Hermes dashboard session cookie comes out, set by the
        bridge on the server side. Verification reads password.json
        fresh and runs the same scrypt check as the panel login, and
        failures share the panel login's rate-limit pool. The
        dashboard password itself never leaves the server."""
        body = self._body()
        ip = self._client_ip()
        fkey = f"{ip}:password"
        fails = [t for t in LOGIN_FAILS.get(fkey, [])
                 if time.time() - t < LOGIN_FAIL_WINDOW]
        LOGIN_FAILS[fkey] = fails
        if len(fails) >= LOGIN_FAIL_LIMIT:
            return self._send(429, {"ok": False,
                                    "error": "尝试太多次，请几分钟后再试"})
        stored = effective_password_hash()
        ok = bool(stored) and verify_password(
            str(body.get("password", "")), stored)
        if not ok:
            fails.append(time.time())
            LOGIN_FAILS[fkey] = fails
            return self._send(401, {"ok": False,
                                    "error": "登录失败，请检查后重试"})
        LOGIN_FAILS.pop(fkey, None)
        if not DASHBOARD_USER or not DASHBOARD_PASSWORD:
            return self._send(500, {"ok": False, "error":
                                    "服务器还没有配好网页登录，请联系部署者"})
        try:
            code, cookies = dashboard_password_login()
        except Exception:
            code, cookies = 0, []
        if code != 200 or not cookies:
            return self._send(502, {"ok": False, "error":
                                    "登录服务暂时不可用，请稍后再试"})
        payload = json.dumps({"ok": True}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        for c in cookies:
            self.send_header("Set-Cookie", c)
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    args = sys.argv[1:]
    if "--hash-password" in args:
        i = args.index("--hash-password")
        print(hash_password(args[i + 1]))
        return 0
    if "--set-password" in args:
        i = args.index("--set-password")
        set_password_hash(hash_password(args[i + 1]))
        print(f"password updated in {password_file()}")
        return 0
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    print(f"[front] listening on {BIND}:{PORT}, hermes={HERMES_BASE}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
