# 伴生服务 M1 直接切换报告（2026-11-10 晚）

> 结论：**切换完成，回归门全套通过。** 五桥已由单容器 `oneday-companion`（镜像 `oneday/companion:1.0.0`，最终镜像 ID `c58a296f59b7`）承载；旧五桥容器全部 stopped 未删（M2 待用户点头再删）；**Hermes 容器全程零接触**（其 StartedAt＝2026-11-10 20:55 CST，是切换前设备 MCP 注册那次经批准的重启，M1 期间未动）；聊天零中断，桥功能中断为秒级（见 §4）。切换中出过两处岔子（compose 重复键、nginx 双通道门），均当场修复并全量重验，见 §5——不隐瞒。

## 1. 切换前核查

- 开工内存 3835/7725MB ≈ 50%（红线 80%）；结束 3918/7725 ≈ 51%。
- 服务器侧 `docker build` 成功（基础镜像服务器现成，成品 3.18GB；日志 `/root/m1-20261110/build.log`）。M0 的「本机拉不动」问题在服务器侧不存在。
- **S1 结案**：线上 nginx conf 全文与本地 2026-11-09 快照做了脱敏 diff——差异全部是档案有载的 11-10 增补（`/__bridge_auth` 单钥门、box `/box/` 前缀重写、oneday/device 路由、device-mcp 透传、sessions POST 与 model 精确/正则路由），无意外项，以线上为准施工。
- companion.env 在服务器侧由五桥现行 env＋Hermes compose 的 API_SERVER_KEY 拼装（0600，钥值不出服务器）；新生成 COMPANION_SERVICE_KEY 一把。

## 2. 冒烟（停桥前，备用端口 9643–9647/9650，oneday/overview 禁用避免双写）

- front 登录页 200（9537B 真页）；聚合 /info 形状对规格 §5（五模块态、hermesUp=true）。
- **S2 关键项过**：write-gate 在监督者注入形态（PYTHONPATH/HERMES_HOME）下 `/status` 返回 `supported=true, gate={memory:true, skills:true}`——不是 fail-closed。
- box `/health` mcpSession=up；device `/health` ok；双方式登录在冒烟面先各验一遍（密码/密钥均 ok、cookie 会话可用）。
- 冒烟容器与冒烟 env（含钥副本）验后即删。

## 3. 备份与回滚基线（服务器 `/root/m1-20261110/`）

- `nginx-hermes.conf.bak-20261110-m1`（站点 conf）、`nginx-main.conf.bak-20261110-m1`（主 conf，改 map 时的备份，最终 map 已撤、主 conf 已还原等效）。
- `bridges/`：四套 compose＋五份 env 分开命名存档；`bridges-inspect-20261110-m1.json`、`docker-ps-before-20261110-m1.txt`、build.log。
- 回滚法（未动用）：停 companion → 五桥容器 `docker start`（或各自 compose up）→ nginx 还原站点 conf 备份 → reload → 复验。数据零迁移，回滚无数据风险（已由切换全程同一批宿主机目录实证）。

## 4. 切换与中断时长（实测）

| 段 | 时刻（CST） | 说明 |
|---|---|---|
| 停五桥 | 21:09:23–21:09:34 | 五容器 stop（退出码 137：10 秒宽限后被杀；数据面事后验完整——oneday degraded=false、decisions 账可读，无损坏） |
| companion 占真端口 | 21:10:06 五端口应答 | 首版 compose 有重复 `restart` 键报错一次（见 §5.1），修后起成；**桥中断 ≈43 秒**（自 stop 发起计） |
| front 修复重建 | 21:16:45–21:16:57 | §5.2 的 front 鉴权修复换镜像重建，桥暂停 ≈12 秒 |
| 清临时密码重建 | ≈21:20 | 验完即把门测试用临时面板密码哈希清除、临时密码文件删除，恢复「未设密码」首启状态，桥暂停 ≈10 秒 |
| Hermes | 全程 | 未停未重启，聊天不中断 |

nginx 最终形态：既有全部路由一字未动；只新增两条——`/companion/`（面板页，不挂门，front 自有登录）与 `/api/companion/`（直通 front，front 自验，见 §5.2）。站点 conf 权限仍 600。

## 5. 切换中出的两处岔子（当场修复＋全量重验）

### 5.1 部署 compose 重复 `restart` 键
自备的 companion 专用 compose 模板拼接时 `restart` 写了两次，首次 `up` 被 YAML 拒。此时五桥已停——立即删重复键重起，43 秒内恢复（即上表中断）。教训：切换用 compose 应先 `docker compose config` 干跑再停桥；本次靠回滚基线在手、修复路径单一，未触发回滚。

### 5.2 面板双通道与单钥门的冲突（设计集成缺陷，M1 门抓出）
规格 §2.4 给 `/api/companion/` 定了与五桥同形的 auth_request 换钥。但面板浏览器通道只有 cookie、没有 Bearer：静态门会把登录后的全部面板请求挡在门外（登录端点本身也进不来）；改变量门（`auth_request $var`，set 与 map 两法都试了）——**本机 nginx 1.26.1（宝塔构建）不求值该变量，子请求把变量名当字面路径**（错误日志实证 `subrequest: "$companion_auth_uri"` → 404 → 500）。M0 的 front 自测是直连 front 打的、没有 nginx 在中间，此集成面未被覆盖。
**定版修法（已上线）**：front 的 `_auth` 新增第三通道——直接接受 Hermes 登录钥作 Bearer（front 本就持有登录钥服务端副本供自检，比对为常量时间；信任域不变：持登录钥者＝部署者）。nginx 侧 companion API 路由随之去掉 auth_request 与换钥头、只透传 Authorization 与 Cookie——最终恰好回到任务口径「只新增两条路由」。front 自测 24/24 复跑不回归。规格 §2.4/§4.1 应在 M2 改版指南时同步修订为此口径（偏差登记在此，不回头改 M0 报告）。

## 6. 回归门逐项实录（全过）

| # | 验项 | 结果 |
|---|---|---|
| 1 | F03 钥矩阵·公网（五桥各抽一端点） | write-gate/status、overview/overview、box/status、oneday/health、device/health：登录钥 200／无钥 401／错钥 401，五桥全对 |
| 2 | F03 钥矩阵·直连（服务钥腿） | 8643/8644/8645/8646 各自服务钥 200／错钥 401（device 腿由 #6 的 MCP 门面验，用的就是其服务钥） |
| 3 | 五桥核心端点真数据 | write-gate `supported=true, counts 0/0`；overview `hermesUp=true, activeSessions=29, pendingApprovals=0`；box 厂商真状态（hibernated、box 名 main）；oneday `ok, degraded=false`＋meta/brief 可读；device /health ok |
| 4 | **write-gate 全环**（非 fail-closed） | 经公网 propose 一条测试记忆 → 真暂存（pendingId `2dc4b673`，Hermes 本体暂存区）→ pending 列表可见 → reject 裁决成功（Hermes 原生输出 "Rejected pending memory write"）→ pending 清零、decisions 账留痕可读；不存在 id 裁决回真 404（裁决端点真响应、非 409 不支持） |
| 5 | 面板双方式登录＋会话 | 密码登录 ok（门测试用临时密码，验后已清除）；密钥登录 ok；cookie 会话打 /modules 200；伪造 cookie 被 front 401 |
| 6 | companion info/health | 登录钥 200／匿名 401／错钥 401；聚合 health `ok=true`、五模块全 up、hermesUp=true；/companion/ 面板页 200 |
| 7 | 自检只读档 | 全跑：11 项中 10 ok＋1 warn（warn＝自检对 config 的静态观察「看图模型未指定（会走默认）；box 未登记；github/notion 已登记」，属存量配置状态、非切换引入——box 走 .env 内置集成不在 config mcp_servers 里，与武装库线既有待实测项同源，留窗口期对账） |
| 8 | device MCP 在列＋实调 | `hermes mcp list`：device ✓ enabled（与 notion/github 同列，注册未因切换失效）；经公网 /api/device-mcp 完整握手 tools/list＝10 工具与设计一致；tools/call `device_status` 回 `{"online": false}`——如实报离线（当时 App 设备会话未连），非假数据 |
| 9 | 公网总健康 | `https://hermes.example.com/health` 200 |
| 10 | 资源 | companion 稳态 157.5MiB／1GiB 上限（15%），S9 估值成立；宿主机内存 51% |

## 7. 终态与遗留

- 终态容器面：hermes（Up）＋oneday-companion（Up）＋既存网关三件与其他业务容器（未动）。OneDay 桥面自此为「本体＋伴生」双容器形态。
- 旧五桥容器保持 stopped 未删、四个旧工程目录原样——删除与 DEPLOYMENT-GUIDE 双容器改版同属 M2，待用户点头。
- 面板密码当前**未设置**（首启状态）：部署者首次用密钥登录面板后在页内设密码；服务器侧重置命令为 front 的 `--set-password`（规格 §4.1 口径）。
- 遗留风险：①面板五页未做浏览器逐页实跑（M0 已登记，接口层与登录全链已在 M1 经公网验通，页面渲染待人工点一遍）；②自检 warn 的 box 登记口径待收官窗口与 `GET /api/mcp/servers` 一并对账；③S10 双挂载只读视角在生产已实际生效（overview 的 DECISIONS_PATH/MONITOR_PATH 走 data-ro 挂载且 #3 数据正常），视为已验；④S4 box 长连接在监督者托管下的重连行为待首日观察（总览页重启计数可查）。
