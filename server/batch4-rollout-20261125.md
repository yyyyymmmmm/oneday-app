# 断桥批四应用记录：identity/front 并回网关（部署包 2.3.0，2026-11-25）

预制正本：`hermes-deploy-batch4/PREFAB-NOTES.md`（基线为主包 1.23.0 时代、候选号 1.24.0；合入时现行主包已是 2.2.0，终定 **2.3.0**，能力号顺延 **#38（identity 入关）/#39（front 只读面入关）**）。
施工序按主线简报写死口径执行；全批授权在案。

## 一、应用前基线对账（实测）

| 项 | 应用前 | 口径 |
|---|---|---|
| 服务器内存 | 4276/7725MB ≈ 55%（应用后复测 3939/7725 ≈ 51%） | 红线 80% 未触 |
| 生产 api_server.py | sha256 `186623217a…` ＝ 主包 2.2.0 钉值（容器内回读与部署目录件全等） | 对账通过 |
| 8648/8650 现行状态 | 本地无监听（curl 000）；公网 `/api/identity-bridge/health` 回 401（nginx auth_request 先行、upstream 已死）、`/api/companion/connections` 回 502 | 留证完毕，本件为恢复路径 |
| /v1/runs | 100 条：completed 90／failed 9／cancelled 1，全终态、无在飞（应用前与重启前各查一次） | 可重启 |
| 三读面 | 台账 items=500（total 991、snapshotSeq 10157）／目标 41／动态 23 | 应用后复测不变（见 §五） |
| identity 数据 | 不在旧登记路径，实存宿主 `/www/dk_project/dk_app/identity-bridge/data/`（10M：index.json、name-state.json、av_*.png/jpg、soul-backups/、living-clips/） | 整树复制式平移、源树保留 |
| front 登记 | 实存 `/www/dk_project/dk_app/companion/companion-state/connections.json`（sha `72beccdbef…`） | 复制平移、源保留 |

## 二、合入主包 2.3.0（包内变更）

- **api_server.py 增量按现行 2.2.0 件重落**（不套旧基线）：批四 delta 相对 1.23.0 基线恰 +126/−0（5 hunk：能力端点表 5 行、identity 通配挂载＋保形口五方法＋POST /mcp/identity、front 只读两面、features 两位、_identity_dispatch 等 4 个 handler、connect() 双 start 钩子），以 unified diff 落到 2.2.0 件后恰 +126/−0、py_compile 过。合并件 sha `50cbfc2111…`（修订一后 `6d9a5d67c8…`，见 §六）。
- **新增模块**：identity_gateway.py（sha `015c9251c7…`）、front_gateway.py（sha `857e88becb…`，2026-11-24 原件存续、逐字直采）。
- **钉值三处同步**：install.sh（PATCHES＋MODULES＋compose 盘点/写后校验）、verify.sh（WANT_SHA＋§2 回读名单＋新增 §28）、manifest.yaml（version 2.3.0、api_server sha/diff_lines 1441→1567→修订一 1576/provides +4、两模块条目）。CAPABILITIES 加 #38/#39；DEPLOYMENT-GUIDE 升版＋2.3.0 注记；compose 模板 +2 挂载行＋NEWAPI 三 env 直传行（`${NEWAPI_*:-}`，模板侧登记、不动在役 compose env）；env.template 补 NEWAPI 注释。
- **包内自测全过**：identity_front_gateway_selftest 21/21、options_card_selftest Part A 32/32、device_gateway_selftest 19/19、oneday_gateway_selftest 49/49、hub_fields_selftest ALL PASS（ledgerfix_selftest 需传 ledger.py 路径参数、与本批无关，非回归）。
- 一处钉值事故已自纠：manifest 的 identity 条目初稿抄了预制期的旧 sha（`015c9251a6…`），与文件实值（`015c9251c7…`，与批四工地 AST 对账件逐字同件）不符，落盘前查出并改回真值，三处钉值复核一致。

## 三、identity_gateway 函数级 AST 对账（终验，PASS）

对账双方：桥原件 `hermes-deploy-batch4/baseline/identity_bridge.py-companion-1.0.77`（sha `f141eaf9…`）vs 重建件 `patches/identity_gateway.py`（sha `015c9251c7…`）。桥 33 函数、网关 32 函数；归一登记改名（print→_print、ONEDAY_BRIDGE_KEY→ONEDAY_CLIENT_KEY）后比对，应用当日以 `/tmp/ast_reconcile.py` 复跑、结论与预制登记逐项吻合：

| 类别 | 函数 | 判定 |
|---|---|---|
| 签名＋函数体逐字全等（21） | _get_name、_set_name、_validate_new_name、_parse_soul_name、_soul_target、_find_title_line、_load_name_state 之外的状态/头像全链：_load_index、_save_index、_index_path、_item_view、_get_avatar、_read_avatar_image、_select_avatar、_sniff_image、_record_name_state、_name_state_path、_add_avatar_image、_add_avatar_preset、fn 等 | 业务本体无漂移 |
| BODY-DIFF（4，逐个看过、均为良性） | _load_name_state（仅 docstring 措辞）、_record_trace（登记改名＋flush 差异）、_run_identity_tool／_traced（仅 print→_print；网关 `_print` 默认 flush=True 正好补偿调用点删掉的 flush=True） | 登记在案的适配 |
| SIG-DIFF（3，传输壳） | _send、_send_bytes、_dispatch_mcp：桥版为 handler 方法（写 self.wfile），网关版为返回 (status, raw, headers) 元组的模块函数，逻辑与载荷逐字一致 | 换壳、非业务差异 |
| 桥独有（5，独立服务器壳） | main、log_message、_authed、_body、_dispatch：网关侧由 `dispatch`/`start`/`_parse_body` 接替，_authed 由网关 @_require_auth 单钥接替 | 壳退役、口径单钥化 |
| 网关独有（4） | _parse_body、_print、dispatch、start | 新壳本体 |

## 四、偏离登记

1. **companion 半边整体作废**（主线简报裁定）：预制的 companion 升 1.0.78、摘 8648/8650、front 面板退役一条不做——companion 已于 2.0.0 整容器退役（容器/compose/数据全清），本版只做网关半边。8648/8650 两面经网关挂载＋nginx 改指 8642 恢复。
2. **NEWAPI 管理三件不配**：front_gateway 的 gateway-channels 读进程 env NEWAPI_BASE_URL/NEWAPI_ADMIN_TOKEN/NEWAPI_ADMIN_USER_ID；hermes 容器现 env 无此三件（/opt/data/.env 只有形态不同的 NEWAPI_API_KEY，不擅自挪用）。该面保持**诚实 503**（预制未决项 7 的预期态、verify §28 接受 200 或 503）；env 直传仅写进包内模板，不动在役 compose（避免 DRY_RUN 计划外变更）。后续如需点亮，另行配 env＋重启即可、不用再发版。
3. **/api/companion/ 通配摘除后，未登记路径回 401 而非模板注记的 404**：外层鉴权先行拦截；面已关闭、无数据外泄，与预期（面板 API 无承接面）实质一致，仅状态码差异，登记备查。
4. **/companion/ 面板块未动**：不在批四 nginx 模板范围内，保持现行（upstream 8650 已死、呈 502，系 2.0.0 companion 退役的既有状态），本批不扩范围。

## 五、应用与验收（逐项证据）

- **回滚基线先行**：`/root/deploypkg-2.3.0-20261125/baseline/`（35 文件、SHA256SUMS 回读全 OK）：production/api_server.py（`186623217a…`）、package-2.2.0 侧件（install/verify/manifest/CAPABILITIES/GUIDE/api_server/services 两模板）、hermes-docker-compose.yml、nginx vhost（改前另存 nginx-vhost-pre-batch4.conf）、identity 数据源树快照、front-connections.json。
- **DRY_RUN**：补丁 1、模块更新 0、模块新建 2、compose 挂载变更 1、**记忆资产待铺 0**——恰为本件范围（简报约束 4 满足：无计划外铺设）。
- **真跑**：install 中途 SSH 断线一次，按纪律未重跑、先查实落盘——文件三件哈希已对、compose 挂载已加、容器已重启，install 实际已走完；修订一改以 nohup 后台跑＋日志回读（「安装完成：应用 1 个文件、新建 0 个模块，健康检查全过」）。
- **数据平移**：identity 整树（10M）→ 容器卷 `/opt/data/identity`、front 登记 → `/opt/data/front/connections.json`（sha 与源全等 `72beccdbef…`），chown 10000:10000（hermes），重启后模块载入。
- **网关正口（本地 8642）**：health 200；GET /v1/identity/name 200（soulName「三狗」）；GET /v1/identity/avatar 200（currentId `av_6199b491aa3e`、items 在位）；POST /v1/identity/name 404（改名写口关停 NAME_WRITE_RETIRED_180 符合预制）；GET /v1/front/connections 200（登记投影）；GET /v1/front/gateway-channels 503 诚实未配置；features 两位回读 identity_gateway=true、front_readonly=true。
- **MCP 深水人工冒烟**（verify §28 identity-mcp-deep 的 unk 接替）：POST /mcp/identity initialize 200（serverInfo oneday-identity）；tools/list 6 工具（identity_get_name／identity_set_name／identity_get_avatar／identity_set_avatar_preset／identity_set_avatar_image／identity_select_avatar）；identity_set_name 同值（「三狗」）往返 ok:true、trace 落账（trc_80e1120478f5、sink=oneday），GET name 回读一致。
- **nginx 改指**：在役 vhost `/api/identity-bridge/` 整段改指 8642（摘 auth_request 换钥链、Authorization 直传）；`/api/companion/` 通配摘除、增补 `= /api/companion/connections` 与 `= /api/companion/gateway-channels` 两条精确 location 改指 8642；nginx -t 通过后 reload。（施工小跤：首轮编辑因 heredoc 未加引号致 `$http_authorization` 被远端 shell 展开、nginx -t 拦下，未 reload、已从基线副本恢复重做，不留尾巴。）
- **公网保形口**：/api/identity-bridge/identity/avatar 200、/api/identity-bridge/health 带钥 200、无钥 401；Hermes 注册 URL /api/identity-bridge/mcp initialize 200（注册零改动）；/api/companion/connections 200、/api/companion/gateway-channels 503。
- **verify.sh 全量**：汇总 齐 80／缺 0／规划中 1／未验 14，原始 [齐] 行 100、[缺] 0、[未验] 15、[规划中] 1——不低于 2.2.0 口径（汇总 77／[齐] 行 88／缺 0）；§28 全绿（两模块 patch-hash、batch4-capability-flags、identity-name/avatar-gateway、identity-shape、front-connections-gateway、front-shape、front-gateway-channels）。
- **三读面复测**：台账 items=500／目标 41／动态 23，与应用前逐项相等（snapshotSeq 10157→10163 为窗口内正常活流量，条数口径不变）。
- **启动期旁证**：修订一重启窗口内 oneday MCP 四面曾现 nginx 500，系 MCP 客户端在 API 监听就绪前抢连的开机竞速；就绪后本地/公网 initialize 均 200、面健康，非本批回归。

## 六、2.3.0 修订一（应用当日）：identity 适配器路径重建修复

- **缺陷**：初版 _identity_dispatch 把通配 tail 直拼为模块路径（`/name`），而模块 dispatch 说桥自身 URL 空间（`/identity/name`、`/health`、`/mcp`）——正口与保形口的 name/avatar 面全数落模块 404「路径不存在」。批四自测只验模块 dispatch 本体、未覆盖 api_server 适配器接缝，是本批自测的覆盖缺口（verify §28 的 identity-name-gateway/identity-shape 两探针在全量验收时即对准此缝）。
- **修法**：适配器按 mount 形态重建桥路径——canonical（/v1/identity/<tail>）补 identity 段、保形口（/api/identity-bridge/identity/<tail>、/health、/mcp）原样，单点改 _identity_dispatch。api_server.py 哈希 `50cbfc21…`→`6d9a5d67c8…`、diff_lines 1567→1576，钉值三处同步、自测复跑全过后同版号重应用（DRY_RUN 恰补丁 1），上列 §五验收均在修订一后复测通过。

## 七、回滚口径

回滚基线 `/root/deploypkg-2.3.0-20261125/baseline/`：以 package-2.2.0 侧件覆回部署目录并重跑 2.2.0 install（或直接以 production 件覆回容器挂载源＋compose 摘两挂载行）、nginx vhost 以 nginx-vhost-pre-batch4.conf 覆回后 reload；identity/front 数据目录为新增、回滚可留置不删（2.2.0 无模块读它们）。源数据树（宿主 identity-bridge/data、companion-state）全程未动。
