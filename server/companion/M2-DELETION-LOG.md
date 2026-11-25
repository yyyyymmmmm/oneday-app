# M2 收尾：旧五桥容器删除日志

- 执行时间：2026-11-10 21:22 后（用户亲口批准「删了」）
- 服务器：118.24.41.52
- 开工内存：3907/7725MB ≈ 51%（红线 80% 未触）；删后内存：3916/7725MB ≈ 51%

## 删除前存档

五容器 inspect 摘要（镜像、挂载、env 键名，不含值）已存：
- 服务器：/root/m1-20261110/old-bridges-inspect-20261110.txt
- 本地：本文件附录

回滚基线（M1 备份）在服务器 /root/m1-20261110/，未动。
本次只删容器本体：宿主机数据目录（/www/dk_project/dk_app/...）、桥脚本原件、镜像、匿名卷均未删。

## 删除清单（docker rm，均原为 Exited 状态）

| 容器 | 镜像 | 容器 ID（前 12 位） |
|---|---|---|
| write-gate-bridge | nousresearch/hermes-agent:v0.23.0 | 159d65164238 |
| overview-bridge | nousresearch/hermes-agent:v0.23.0 | 88934f1414a6 |
| box-bridge | nousresearch/hermes-agent:v0.23.0 | 7d5359746523 |
| oneday-bridge | nousresearch/hermes-agent:v0.23.0 | 81e26811831a |
| device-bridge | nousresearch/hermes-agent:v0.23.0 | 315f06d249fa |

## 删后验证（全过）

- docker ps -a：五容器消失；oneday-companion Up、hermes Up，未受影响；其他业务容器一律未碰。
- 公网 https://hermes.example.com/health ＝ 200。
- 五桥公网端点（登录钥 Bearer）：write-gate /api/write-gate/pending＝200；overview-bridge /api/overview-bridge/notifications＝200；box-bridge /api/box-bridge/status＝200；oneday-bridge /api/oneday-bridge/health＝200；device-bridge /api/device-bridge/health＝200。（注：write-gate/overview/box 三模块无 /health 路径，根路径亦 404，故以其真实业务端点验收；鉴权层先行验过——空钥时五路由均 401。）
- hermes mcp list：notion ✓ enabled、github ✓ enabled、device ✓ enabled。
- 宿主机内存 3916/7725MB ≈ 51%。

## 附记

验证中途 SSH 两度报 Host key verification failed：查明系个别 exec 调用 HOME 落到 /root、无 known_hosts 所致；服务器呈现指纹 SHA256:ZleCft4U6vKqvXTekvcDosoGxwO4WR4x4ToFNfbRHDU 与 /home/hatch/.ssh/known_hosts 存档逐字一致，服务器密钥未变，后续命令显式指定 UserKnownHostsFile 后恢复。

## 附录：删除前 inspect 摘要（服务器存档原文）

```
=== write-gate-bridge ===
IMAGE=nousresearch/hermes-agent:v0.23.0 ID=159d65164238728d1967fe69c2d1bde9e7b6785c86356535ba42a0a257bfbe5e CREATED=2026-11-10T07:34:04.439879141Z STATE=exited
MOUNTS:
/www/dk_project/dk_app/hermes/data -> /opt/data (bind)
/www/dk_project/dk_app/hermes/write_gate_bridge.py -> /opt/bridge/write_gate_bridge.py (bind)

ENV_KEYS:
WRITE_GATE_BRIDGE_KEY
WRITE_GATE_PORT
TZ
PYTHONPATH
PATH
PYTHONUNBUFFERED
PYTHONDONTWRITEBYTECODE
PLAYWRIGHT_BROWSERS_PATH
HERMES_RUNTIME_DIR
HERMES_PYTHON
CC
CXX
HERMES_WEB_DIST
HERMES_TUI_DIR
HERMES_HOME
HERMES_WRITE_SAFE_ROOT
XDG_RUNTIME_DIR

=== overview-bridge ===
IMAGE=nousresearch/hermes-agent:v0.23.0 ID=88934f1414a68bd367bd996daa88328a23fb5b118b588ed87a11616ecbdad1eb CREATED=2026-11-10T07:33:35.004928218Z STATE=exited
MOUNTS:
/www/dk_project/dk_app/hermes/overview-data -> /opt/overview-data (bind)
/www/dk_project/dk_app/oneday-bridge/data -> /opt/oneday-data (bind)
/www/dk_project/dk_app/hermes/data -> /opt/data (bind)
/www/dk_project/dk_app/hermes/overview_bridge.py -> /opt/bridge/overview_bridge.py (bind)

ENV_KEYS:
WRITE_GATE_BRIDGE_KEY
OVERVIEW_PORT
MONITOR_PATH
TZ
WRITE_GATE_KEY
HERMES_API_KEY
OVERVIEW_BRIDGE_KEY
PATH
PYTHONUNBUFFERED
PYTHONDONTWRITEBYTECODE
PLAYWRIGHT_BROWSERS_PATH
HERMES_RUNTIME_DIR
HERMES_PYTHON
CC
CXX
HERMES_WEB_DIST
HERMES_TUI_DIR
HERMES_HOME
HERMES_WRITE_SAFE_ROOT
XDG_RUNTIME_DIR

=== box-bridge ===
IMAGE=nousresearch/hermes-agent:v0.23.0 ID=7d53597465238cd7ccd56b248d87975cb5c00c9e04019779918cf812a7b72384 CREATED=2026-11-10T07:35:11.517332514Z STATE=exited
MOUNTS:
/www/dk_project/dk_app/box-bridge/box_bridge.py -> /opt/bridge/box_bridge.py (bind)
/var/lib/docker/volumes/8fb3d6bb62632591fb43742fab12488e180400ba3a8ffddbf7cfed74b2a9b271/_data -> /opt/data (volume)

ENV_KEYS:
BOX_BRIDGE_KEY
BOX_PORT
MCP_BOX_API_KEY
PATH
PYTHONUNBUFFERED
PYTHONDONTWRITEBYTECODE
PLAYWRIGHT_BROWSERS_PATH
HERMES_RUNTIME_DIR
HERMES_PYTHON
CC
CXX
HERMES_WEB_DIST
HERMES_TUI_DIR
HERMES_HOME
HERMES_WRITE_SAFE_ROOT
XDG_RUNTIME_DIR

=== oneday-bridge ===
IMAGE=nousresearch/hermes-agent:v0.23.0 ID=81e26811831aaaf874e76929bd813c9cc61f2cc5a91c234aefaf8f9b734eface CREATED=2026-11-10T07:34:45.881704755Z STATE=exited
MOUNTS:
/www/dk_project/dk_app/oneday-bridge/oneday_bridge.py -> /opt/bridge/oneday_bridge.py (bind)
/var/lib/docker/volumes/596f7a02e98b027b0bbb7c9e3d4020967da37e38a77117d23691db371f3afa75/_data -> /opt/data (volume)

ENV_KEYS:
ONEDAY_PORT
HERMES_DASH_USER
HERMES_DASH_PASSWORD
ONEDAY_BRIDGE_KEY
HERMES_API_KEY
PATH
PYTHONUNBUFFERED
PYTHONDONTWRITEBYTECODE
PLAYWRIGHT_BROWSERS_PATH
HERMES_RUNTIME_DIR
HERMES_PYTHON
CC
CXX
HERMES_WEB_DIST
HERMES_TUI_DIR
HERMES_HOME
HERMES_WRITE_SAFE_ROOT
XDG_RUNTIME_DIR

=== device-bridge ===
IMAGE=nousresearch/hermes-agent:v0.23.0 ID=315f06d249fa8fab97dae0df6e92786714ca388288014f1ab5fc57ab82a1741f CREATED=2026-11-10T07:36:02.84670938Z STATE=exited
MOUNTS:
/www/dk_project/dk_app/device-bridge/device_bridge.py -> /opt/bridge/device_bridge.py (bind)
/www/dk_project/dk_app/device-bridge/data -> /opt/device-data (bind)
/var/lib/docker/volumes/8820d830b48e77b43cc2cec53c8177763f361bb3a259aca975368aad7dd58f0b/_data -> /opt/data (volume)

ENV_KEYS:
DEVICE_BRIDGE_KEY
TZ
DEVICE_PORT
DATA_DIR
PATH
PYTHONUNBUFFERED
PYTHONDONTWRITEBYTECODE
PLAYWRIGHT_BROWSERS_PATH
HERMES_RUNTIME_DIR
HERMES_PYTHON
CC
CXX
HERMES_WEB_DIST
HERMES_TUI_DIR
HERMES_HOME
HERMES_WRITE_SAFE_ROOT
XDG_RUNTIME_DIR
```
