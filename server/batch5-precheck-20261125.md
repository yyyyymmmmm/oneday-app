# 批五（device 收官 → 部署包 2.0.0）前置核查（只读实测，2026-11-25 01:1x）

纪律声明：全程只读——未应用任何变更、未重启容器、未改任何文件、未读凭据明文（companion.env 只读了键名清单）。正本：server-next-prep-20261125.md 第 4 节；施工图 bridge-retirement-spec-20261124.md §4 C-1 与分期表。

## 一、网关内存实测（前置条件①）

实测时刻整机内存：4291/7725 MB ≈ **55.5%**（available 3124 MB），未触 80% 红线。

| 对象 | 实测 | 口径 |
|---|---|---|
| hermes 容器总占用 | **947.3 MiB / 2 GiB 上限 = 46.25%** | docker stats --no-stream；上限经 inspect 核实 = 2147483648 B |
| ├ 网关进程（8642）RSS | ≈533 MiB（545,812 KB） | 容器内 ps --sort=-rss 第一位 |
| └ Dashboard（9119）RSS | ≈347 MiB（354,924 KB） | 同上第二位；与网关同容器、共享 2 GiB 上限 |
| oneday-companion 容器 | 97.0 MiB / 1 GiB | 批五下线后整机净释放约 97 MiB |
| oneday data.json | **710,674 B ≈ 0.68 MB**（oneday 目录总 4.7 MB） | 宿主机 /www/dk_project/dk_app/hermes/data/oneday/data.json |
| device 数据 | sync.db 1,208,320 B ≈ 1.15 MB；device-bridge 全目录 1.5 MB；audit.jsonl 189 KB / 1247 行；write-keys.json 1.7 KB | /www/dk_project/dk_app/device-bridge/data/ |
| rendition 缓存 | fileproc-cache 2.4 MB（小图变体） | hermes/data/fileproc-cache |

**关键事实修正**：施工图风险节假设终局要把「data.json 全量内存库＋rendition」新并入网关——实查这两件**早已在网关进程内**：oneday 模块组随批三（1.19.0）入关、fileproc_gateway.py 随批一入关（服务器 patches 目录实见该文件、缓存目录已在 hermes/data 下在役）。批五真正新增进网关的只有 device 三件：

- 同步组：对 1.15 MB SQLite 的 CRUD，无常驻大内存结构，常驻增量可忽略；
- 中继组：纯内存会话表——每会话为一条长轮询（25 秒/轮）＋少量状态，并发会话量级＝用户在用设备数（个位数；audit.jsonl 全量历史 1247 行事件佐证低频小量），按每会话高估 1 MB 也不到 10 MB；
- MCP 门面：aiohttp 路由挂载，常驻增量可忽略。

**余量判断**：批五常驻增量高估 **<10 MB**，并入后网关容器约 957 MiB / 2 GiB ≈ **47%**，限内余量仍有约 **1.09 GiB**；整机侧还净释放 companion 的约 97 MiB。**结论：内存不是批五的约束项，前置条件①按本基线通过。** 注意两点：①网关 RSS 的真实驱动是会话负载与缓存，与批五无关，开工当天仍应按前置条件原意复测一次再动；②Dashboard 与网关同容器共享 2 GiB，终局后若要再压风险，拆限额是可选优化、非批五必需。

附带发现：`agitated_tesla` 容器（companion 1.0.77 镜像，Up 14h，48 MiB）实查其 Cmd 为一次性诊断命令（读镜像内 modules.json、grep identity_bridge.py），匿名卷、非常驻服务；批五清点时可顺手确认去留，本次未碰。

## 二、C-1 裁决正文回读（前置条件②）

**已确认。** 裁决原文出处两处互证：

- bridge-batch1-rollout-20261124.md 第 4 行：「用户已裁（2026-11-24 00:28）：**device 整搬（后续批）**、front 凭据托管降级只读（批四）、自反应做（已入 1.8.0）」。
- bridge-retirement-spec-20261124.md §4 C-1 正本：整搬法＝①device_gateway.py 内建会话表（asyncio.Event 替代条件变量）；②write-keys.json、permission-parks.json、audit.jsonl 平移 /opt/data/device/（0600 纪律不变）；③切换窗内先停新注册（/device/session 回 503 短窗）→改 config＋nginx→放行，全程分钟级；④验收＝设备全环冒烟（session→poll→实调一工具→respond→disconnect）＋MCP tools/list 10 工具对账。降级法「留 device-only 微伴生」**未被选用**。

即批五 #15 按**整搬**执行，微伴生方案销账。未查实一点：C-1 所列 permission-parks.json 在宿主机 device-bridge/data 与 companion-state 两处均未查见（可能按需生成或在容器内路径），搬迁施工时须先定位该文件实际落点。

## 三、终局托管物三件现状（前置条件③）

### 1. nginx vhost 模板——现为宿主机手工文件，包内副本已过期

- 在役文件：/www/server/panel/vhost/nginx/hermes.example.com.conf（宝塔 vhost 目录），共 **27 条 location**；proxy_pass 去向实查：8642 网关 ×10、9119 Dashboard ×2、8650 front ×2（批四摘）、8648 identity 桥 ×1（批四摘）、**8647 device 桥 ×2（批五摘）**。同目录留有各批 .bak 备份 16 份（逐批改指的历史痕迹）。
- 部署包内有一份 hermes.example.com.conf，但 md5（8504867b…）与在役文件（44e79c2b…）**不一致**——包内副本不是在役正本，尚不存在「包托管模板」事实。批五交付动作：以在役文件为基线收编成包托管模板（摘完 8647 两条后即终局形态），后续改 vhost 只走包。

### 2. config.yaml 托管段补丁器——现无托管机制，文件全手工维护

- 在役文件：/www/dk_project/dk_app/hermes/data/config.yaml，139,651 B。部署包 install.sh 对 config.yaml **无任何处理**（实查 grep 零命中）——现行 config 全靠服务器侧手工维护，批五的「托管段补丁器」是净新建，不是改造现成机制。
- 与批五直接相关的托管段＝mcp_servers（第 1701 行起）：notion、github 为外部服务；**device 的 url 现为 https://hermes.example.com/api/device-mcp**（批五须改指 8642 保形口）；oneday 四条 url 仍走 /api/oneday-bridge/* 保形口（批三已入关、nginx 改指承接，路径保形不动）；identity 一条 /api/identity-bridge/mcp（批四处理）。补丁器最小范围：只管 mcp_servers 段内 device 一条的 url 改指＋校验，不碰其余手工段。

### 3. companion.env 整体作废——消费方仅 companion 自家

- 在役文件：/www/dk_project/dk_app/companion/companion.env，0600、1973 B、57 行；键名构成：模块开关 7 个（MODULE_*_ENABLED）、各桥钥（DEVICE_BRIDGE_KEY 等）、NEWAPI_ADMIN_TOKEN、PANEL_PASSWORD_HASH、HERMES_DASHBOARD_USER/PASSWORD 等（只读键名，未读值）。
- **消费方实查**：宿主机上只有 companion 自家 docker-compose.yml 与 docker-compose.smoke.yml 引用该文件；hermes 的 docker-compose.yml 零引用；agitated_tesla 未挂载它。companion 容器以文件挂载方式读 /opt/companion/companion.env，监督者按段把凭据注入各模块进程。
- 作废连带：部署包侧 install.sh、manifest.yaml、DEPLOYMENT-GUIDE.md（§5 凭据清单与 companion.env.example 模板）都引用 companion.env——批五作废时须同步清包内模板与指南（终局改写的一部分）。注意：env 内的 NEWAPI_ADMIN_TOKEN、Dashboard 凭据等是**凭据本身另有正主**（New API／Dashboard 各自的账），作废的只是 companion 这份副本文件，不涉及轮换。

## 四、前置条件总账

| 前置 | 结论 |
|---|---|
| ① 网关内存实测 | ✅ 通过（基线：容器 46.25%、批五增量高估 <10 MB、限内余量约 1.09 GiB）；开工当天复测一次 |
| ② C-1 裁决回读 | ✅ 已确认＝device 整搬（2026-11-24 00:28 用户裁，原文在案）；permission-parks.json 落点未查实，施工时先定位 |
| ③ 托管物三件 | 现状已清：nginx 在役文件 27 location（批五摘 8647×2）、包内副本过期须收编；config.yaml 无托管机制、补丁器净新建（最小范围＝mcp_servers 的 device url）；companion.env 消费方仅 companion 自家 compose，作废须同步清包内模板与指南 |

未查实清单：permission-parks.json 实际落点；agitated_tesla 的确切来历（Cmd 形态为一次性诊断，去留待批五清点时定）。
