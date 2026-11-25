# 服务端后序施工准备报告（只读清点，2026-11-25 01:0x）

纪律声明：本报告全部为只读清点——未应用任何变更、未重启容器、未改生产数据、未碰凭据明文。部署包密钥 scrub 是待裁项，不在本报告范围。

## 现场基线（2026-11-25 实查）

- 服务器 118.24.41.52 内存：4326/7725 MB ≈ **56%**，未触 80% 红线；load 0.34/0.17/0.11；已开机 43 天。
- 部署包现行 **1.23.0**（manifest.yaml 实读；中枢数据四件，2026-11-24 应用，回滚基线 /root/deploypkg-1.23.0-20261124/baseline/）。
- 生产容器：hermes（nousresearch/hermes-agent:v0.23.0，Up 5h）、oneday-companion **1.0.77**（Up 14h）。另见一个名为 `agitated_tesla` 的容器同跑 companion 1.0.77 镜像（用途未查实，本次未碰）。
- 断桥进度：批一（1.8.0/1.9.0）、批二（1.10.0）、批三（1.19.0，oneday＋overview 入网关、companion 升 1.0.77 摘两模块）均已应用。版本注记：断桥施工图（bridge-retirement-spec-20261124.md）里批四拟号 1.13.0 已被设置注册表占用、批三拟号段亦被顺延占用——**图内版本号全部过期**，实际版本号与能力号（现行 CAPABILITIES 已到 #34）须在合并时由主线重新分配，下文不再引用图内拟号。

---

## 1. §441 选择框服务端半边（需求第 203 条）

- **状态：已预制未合并未应用。** 预制副本在 `~/workspace/hermes-deploy-options/`（整包快照，占位版本 1.12.0／能力 #22，均已过期）；施工图正本 `oneday-design-review/options-card-spec-20261124.md`（DESIGN §441）。App 半边已随 0.50.106 发货潜伏（服务端未翻闸不渲染）。
- **范围／拟改动**（据副本 manifest 实读）：①网关补丁 api_server.py——capabilities 增 `features.options_card=true`、消息投影增 options 字段（读 display_metadata 的 options 键、形状校验后投影）；②api_server_runs.py——终态 `_finish` 在自反应 attach 之后同步调 `_attach_options`（无工具轮过滤，干完活再拍板是主场景）；③新增模块 present_options_tool.py＋options_pending.py（/opt/hermes/tools/）；④instance config 闸 `display.options_card` 默认关＝潜伏，翻闸才产卡。副本自测：本地桩 32/32＋容器真码全过（副本自述，未复跑）。
- **差什么**：副本基线停在 1.10.0 时代的 api_server.py／api_server_runs.py，现行包已到 1.23.0（其间叠了自设一期、语义检索、批三挂载、回执运行时化、1.23.0 四件）——**两份补丁必须按增量三方重基到 1.23.0 本体**，不能整文件覆盖；能力号 #22 已被占用（现行至 #34），须顺延新号；manifest／install.sh／verify.sh 钉值同步重算。
- **回滚基线做法**：按包惯例——动手前把生产 api_server.py／api_server_runs.py 现行件＋compose 快照存 /root/deploypkg-<新版>-<日期>/baseline/；新增模块回滚＝删文件＋摘 compose 挂载；数据面无迁移（options 只是 display_metadata 新增可选键，旧代码忽略）。
- **前置条件**：重基完成＋包内自测对合并树复跑全绿；应用与翻闸分两步（先应用潜伏、后单独翻闸，翻闸后须用户真机 verdict 才关账）。
- **预计停机／影响**：hermes 容器重启一次（分钟级）；潜伏期对用户零行为变化；翻闸后 AI 才可能产选择卡。

## 2. ledgerfix（§475 台账 job 条目状态口径，排 companion 槽位）

- **状态：预制完成、自测全过、未应用。** 正本 `~/workspace/hermes-deploy-ledgerfix/APPLY.md`；两件同包：件一＝孤儿 job 启动结算（进程死亡丢回写链的根治），件二＝「交付齐即完成」（用户 2026-11-24 10:41 亲点）。
- **范围／拟改动**：companion 五文件——ledger.py（新增 settle_orphan_jobs／settle_job_delivered／共用映射常量）、oneday_seg_ledger.py（启动对账钩子＋交付钩子＋finish 交付守卫）、oneday_seg_feed.py／oneday_seg_ideas_gen.py／oneday_seg_briefings.py（各挂一处交付判据点调用）。自测：ledgerfix_selftest 22/22＋存量 ledger_selftest 回归 40/40（预制自述，未复跑）。
- **基线核验（本次实查，最重要的一项）**：生产 oneday-companion 容器内五文件 md5 与 APPLY.md 钉的 1.0.76 基线**逐一全等、零漂移**（ledger.py 41b8d59b…、oneday_seg_ledger.py d7ca9573…、feed e9194da0…、ideas_gen b48f758d…、briefings f7217eeb…）。companion 虽已升 1.0.77，这五文件未被批三动过。
- **未查实（应用前必须先定）**：hermes 网关容器内另有一套 oneday_seg_feed／ideas_gen／briefings 副本（批三入关件，哈希与 companion 侧不同）。APPLY.md 的定因证据（2026-11-24 10:15 companion 重建杀死轮次线程）表明当日轮次执行宿主是 companion，但批三之后的分工未逐行复核——**应用前须先确认动态/点子/简报三类轮次的实际执行宿主**：若轮次已改在网关副本跑，只改 companion 五文件将不生效，须按 1.23.0「双生同步」先例两边同改或改判落点。本次日志侧探（26h 窗口 grep）无命中，不足以定案。
- **回滚基线做法**：APPLY.md 已写明——应用前五文件备份至 /root/ledgerfix-apply-baseline-<日期>/，回滚＝覆回＋companion 重建一次；台账事件账为追加式，结算事件不回滚（终态纠正走台账自有 corrected 机制）。
- **前置条件**：①上条宿主确认；②占一个 companion 槽位（只重建 companion 一次）；③重建前查 /v1/runs 无在飞真实用户 run。已知在案状态：样本条目 job:morning:1795485581 仍挂 running、1795466451 挂 stale（件一不动 stale，其结算另行人工处理），非新故障。
- **预计停机／影响**：companion 重建一次（分钟级）；启动即结算存量孤儿（预期日志 `ledger orphan jobs settled at boot: N`，N≥2）；此后 job 条目状态口径变更（交付齐即 completed）。

## 3. 批四·身份与 front（断桥第四批）

- **状态：未预制完成。** 自研清点表（self-built-inventory-server-20261124.md）记 identity 桥与 front 面板为「断桥已覆盖（批四，预制在制）」；覆盖审计（hermes-coverage-audit-20261124.md）记「批四/批五未预制」。以审计为准：**无可直接应用的预制件，须先施工入包**。
- **范围／拟改动**（据 bridge-retirement-spec 第七节分期表）：①identity 头像＋MCP 入网关（#13，identity 桥 8648 退役）；②front /info 探针→capabilities，App 侧 CompanionProbe 双读过渡（先读 capabilities、失败回落 /info，两版后删回落）——**这是全图仅有的两处必须随批同改 App 之一，须与 App 版协同排期**；③connections 按 C-2 裁决执行（#17）；④front 面板（8650）退役、supervisor 下线准备（#18/#19 的 App 面部分）；凭据托管面按用户 2026-11-24 00:28 裁决降级为「服务器侧配置录入＋App 只读」。
- **未查实**：C-1／C-2 裁决的正文（批五中继组去留＝C-1、connections 处置＝C-2）未在本轮读到原文，只查到批一记录里用户已裁「device 整搬（后续批）、front 凭据托管降级只读」；施工前须回读裁决正本。
- **回滚基线做法**：按分期共同纪律——identity-data 快照、connections.json 导出封存、nginx conf＋compose 快照；观察窗内 identity/front 桥模块保持在役待命（nginx 切走、进程不摘），回滚＝nginx 指回桥端口＋网关模块开关停挂，分钟级、不动数据。
- **前置条件**：预制入包（新网关模块＋探针登记）＋App 双读版先行或同批；§441 已按定序排在其前（覆盖审计：§441 归批三之后的合并定序；总表 D1 定序 §441→批四→批五）。
- **预计停机／影响**：hermes 重启＋（如摘桥）companion 重建各一次；探针读面语义变化期靠 App 双读兜底；front 面板退役后运维入口改走新面，须知会使用习惯。

## 4. 批五·device 收官（部署包终局 2.0.0）

- **状态：未预制。** 终局版，批四之后才许动。
- **范围／拟改动**：①device 同步组入网关（#14）；②中继组按 C-1 裁决整搬或留微伴生（#15）——用户 2026-11-24 00:28 已裁 device 整搬，后续批执行，C-1 正文仍待回读确认；③companion 容器下线、nginx 桥 location 全摘、companion.env 作废、单钥终局验收；④DEPLOYMENT-GUIDE.md 终局改写（现正文仍按 companion 在役形态，靠批一/批二/批三头部注记过渡）；⑤部署包新增三件托管物（nginx vhost 模板、config.yaml 托管段补丁器、companion.env 整体作废）。
- **回滚基线做法**：device-data 全量快照；companion 镜像上一版 tag 保留至本批验收后才删；compose 保留 companion 定义至验收关账。
- **前置条件**：批四关账；批五开工前按施工图风险节做一次**网关内存实测**（终局后 oneday data.json 全量内存库＋device 会话＋rendition 生成同进程，hermes 容器现限 2GB）；App 侧零改动（路径保形），第二段 App 原生路径清理另排小包群。
- **预计停机／影响**：全批最大——companion 下线不可逆性最高（验收后删镜像 tag 才算真终局）；网关爆炸半径变大是终局架构固有价（施工图风险 1，交卷时须向用户明示）。

## 5. G1 失败覆盖（通知流任务侧失败生产者，另立包）

- **定
...[truncated 2085 chars]

---

## 附一：ledgerfix 宿主定案（2026-11-25 只读查证）

**结论：动态（feed）／点子（ideas_gen）／简报（briefings）三类轮次的实际执行宿主＝hermes 网关容器（进程内 oneday_gateway 模块），不在 companion。ledgerfix 若按 APPLY.md 只改 companion 五文件将不生效，落点须改判网关侧（见末段）。**

证据链（2026-11-25 实查，服务器内存 4285/7725MB ≈ 55%，未触红线；全程只读）：

1. **网关侧加载点**：hermes 容器 `/opt/hermes/gateway/platforms/oneday_gateway.py` 第 572–582 行以 `_load_segment()` 依次装载 `oneday_seg_ideas_gen.py`、`oneday_seg_briefings.py`、`oneday_seg_feed.py`、`oneday_seg_ledger.py`；其模块 docstring 明载启动序「start() mirrors the bridge main() sequence (load, reconcile loop, cron ensure, ledger collector, delivery sentinel, automation watcher)」。api_server.py 第 3463 行 `from gateway.platforms import oneday_gateway` 为挂载点。
2. **网关侧哈希（＝部署包 1.23.0 现行件，本地包与容器逐一全等）**：feed `86a79da65be400bfec18175acd6ec524`、ideas_gen `8b63f6b6c503b91ac53f032c2dab2ad5`、briefings `f611ef3f04b445fd04e64e4be4517cd6`、seg_ledger `3f00b686a66291d21343d4a2f58f5cc2`、ledger 库（oneday_ledger_lib.py）`4d8f04e6ae42b089e4f00272fe53e9c6`。
3. **调用点（定时轮次）**：Hermes 原生 cron（/opt/data/cron/jobs.json）在册「动态调研 A 版／B 版、动态小时评估、点子日轮、点子到期清理、简报轮」等系统轮，脚本为 /opt/data/scripts/oneday-round-*.py（no_agent 回调脚本），内容为 POST `http://127.0.0.1:8642/api/oneday-bridge/internal/cron/rounds/<类>`——8642 即网关面，由 oneday_gateway 的 `_dispatch_cron_callback` 接入 seg 代码；非定时部分由 oneday_gateway 进程内 reconcile 循环驱动。
4. **companion 侧排除**：生产 oneday-companion 容器 supervisor 注册表（/opt/companion/supervisor/modules.json）仅剩 device／identity／front／fileproc 四模块，无 oneday 条目；进程表只有 supervisor＋device_bridge＋identity_bridge＋front＋fileproc_bridge，无 oneday_bridge 进程；supervisor.py 第 126 行注释明载「write-gate/overview/oneday 已随断桥批二/批三退役入网关」。其 /opt/companion/modules/ 下的 seg 副本为镜像内陈迹，无人装载，哈希仍停在 1.0.76 基线（feed `e9194da0…`、ideas_gen `b48f758d…`、briefings `f7217eeb…`、seg_ledger `d7ca9573…`、ledger.py `41b8d59b…`，与 APPLY.md 钉值全等——即清点报告所见「零漂移」的另一面：它们根本没在跑）。另一同镜像容器 agitated_tesla 经查为一次性诊断残留（仅 device＋front 进程），同样排除。
5. **对 ledgerfix 的落点修正**：件一（孤儿 job 启动结算）与件二（交付齐即完成）的五处改动须落到网关侧对应文件——`oneday_seg_feed.py`／`oneday_seg_ideas_gen.py`／`oneday_seg_briefings.py`（交付判据点）、`oneday_seg_ledger.py`（启动对账＋交付钩子）、`oneday_ledger_lib.py`（结算函数本体，部署包内与 companion/modules/ledger.py 为双生件、包内哈希同为 4d8f04e6…，但生产 companion 镜像未随 1.23.0 重建、其在役 ledger.py 仍是 41b8d59b… 的旧件且无人执行）。按 1.23.0「双生同步」先例，包内两处同改、实际生效者为网关侧；应用形态随之由「排 companion 槽位、重建 companion」改为「入部署包、重启 hermes 一次」，APPLY.md 的基线哈希与应用步骤须按网关侧五文件（上列哈希）重钉后再排期。本节只定案，未改任何文件。

## 附二：§441 重基结果（2026-11-25，本地预备，未应用）

**一句话：api_server.py 重基完成（4/4 hunk，其中 1 处文本冲突按并集消解待复核）；api_server_runs.py 移植 1/3 hunk、2 处冲突留痕待裁（锚点被 1.20.0 回执运行时化替换），按建议落点在临时副本验证自测 32/32 全过。**

- 产物与完整说明：`~/workspace/hermes-deploy-options/rebased-1.23.0/`（api_server.py＋api_server_runs.py＋REBASE-NOTES.md）；原 patches/ 快照未动。
- 新基线＝1.23.0 两文件（与生产容器 md5 全等）；旧基线验明：api_server 取 /root/deploypkg-1.11.0-20261124/baseline 件（diff 恰 4 个 options hunk），runs 取 /root/deploypkg-1.15.0-20261124/baseline 件（diff 恰 3 个 options hunk，与 selfsettings-p1 工地件逐字同）。
- 冲突清单：①api_server capabilities 特征位双边同锚追加——无语义交叠，已并集消解并在 REBASE-NOTES 标注可单独回退；②runs R1 事件抑制守卫放宽与 1.20/1.23 新增的回执／活动登记链的衔接；③runs R2 _finish 调用点锚点（_attach_self_reaction 调用）已被回执状态机整段替换，建议落在 completed 分支 _maybe_social_judge 之后、终态发布之前。②③未强行套用，产物文件内保留 diff3 冲突标记。
- 验证：包内自测 Part A 在「重基后 api_server 原样＋runs 按建议落点的临时脚手架」下 32/32 全过；install.sh DRY_RUN 未跑（钉值待合并时重算，此时跑无增益，理由见 REBASE-NOTES）。
- 合并时待办（主线）：R1／R2 裁定后复跑自测、能力号顺延、manifest／install／verify 钉值重算；另提示第三份文件 web_routers_sessions.py 的历史投影 options hunk 不在本次两份范围、现行 1.23.0 同名文件无 options 内容，合并时须一并处置或明文豁免。
