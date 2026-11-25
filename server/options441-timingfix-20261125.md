# §441 选项卡时序修复应用记录（部署包 2.3.1＋修订一，2026-11-25）

授权：用户 2026-11-25 服务端全批授权链；缺陷登记见 options441-flip-20261125.md（翻闸步发现、本步修复）。

结论：**已应用生产并以真实流量复验落卡关账**——部署包 2.3.0 → **2.3.1**（api_server_runs.py 单文件），应用当日真实复验又抓获第二层断链、同版号**修订一**重应用。最终真实请求（run_e34f9f56）终态助手行 6551 的 display_metadata 实存 options（周六凌晨／周日凌晨两项），§441 自翻闸以来首次在真实流量下成卡。verify 全量缺 0、三读面不变、翻闸状态不回退。

## 根因（两层，均为实证）

**第一层·时序（翻闸记录定位）**：`_attach_options` 挂在 `_finish` 终态发布之前执行，而终态助手文本行由轮次交付提交才落库；attach 执行时库里只有正文为空的 tool-call 助手行，被 `latest_message_row_id` 的 `require_text=True`（上游默认）跳过 → 查无可落之行 → fail-closed 静默无卡。自测 Part A/B 都预置目标行，测不出此形态。

**第二层·绑定（本版首轮真实复验抓获，修订一修）**：新加的 warning 在首轮复验（run_1ec71dec）即实证——模型已调 present_options、handler 已登记（行 6532/6533），卡仍不落，丢卡点在 run_key 守卫：handler 登记的 run_key 是完整会话键 `agent:main:api_server:dm:run_1ec71dec…`，attach 却与裸 run_id 做等值比对，真实流量恒不符。翻闸三轮当时大概率同死于此守卫（旧代码该路径无日志、不可见）；时序层是容器实验＋轮询下的最强解释，两层并存、均须修。此断链自反应 attach 在 1.15.0 已修过一次（结论：工具上下文里没有裸 run_id），§441 attach 未吸取。

## 修法与取舍

- **时序层取方案 B（限时重试），弃方案 A（后移同步点）**：A 把 attach 挪到 `_set_run_status` 之后仍在 `_finish` 同步链内，而 `_set_run_status` 只写运行状态与幂等存储、根本不提交会话行，交付提交时点在 `_finish` 控制之外（工作线程／轮后保存），重排同步点不保证行已在位。B 不依赖提交点位置：首试仍同步（行已在位时行为与旧版逐字一致、终态发布零延迟），首试查无行才起守护线程，0.25s 间隔、5s 截止，等交付行落库补贴；不阻塞终态发布。
- **绑定层照 1.15.0 先例改自验事实绑定**：等值命中，或会话键后缀命中（`agent:…:dm:<run_id>` 形态），或新鲜度命中（条目登记时刻 ≥ 本 run 创建时刻 −1s；同会话 turn 租约串行化，活条目必属本 run）；三路皆不中＝死 run 陈旧残留，丢弃。
- **不许再静默（硬要求落地）**：四种丢卡路径全量 warning 留痕、均带 session/run 标识——run_key 绑定不中、载荷复验不过、目标行在可见谱系外（attach_options 拒绝）、重试耗尽仍无文本行（检索串 `options card NOT attached`／`options card dropped`）。无 pending（常态）不记日志，正常路径不刷屏；成功落卡零告警（复验轮日志实查 0 条）。

## 自测先红后绿（证据）

- 时序用例（新增，DelayedDB 第 3 次查询才出现文本行）：旧代码 **32/33 FAIL**（仅新用例红）→ 修后 **33/33 SELFTEST PASSED**（本地＋容器内各跑一次）。
- 绑定用例（修订一新增两条：会话键新鲜度绑定应落卡、陈旧条目应丢弃）：2.3.1 本体上 **34/35**（绑定用例红、陈旧用例绿）→ 修订一后 **35/35 SELFTEST PASSED**（本地＋容器内各跑一次）。
- Part B（容器真 SessionDB，options_card_container_test.py）：本版与修订一应用后各复跑一次，均 CONTAINER TEST PASSED。

## 入包（2.3.0 → 2.3.1，修订一同版号）

- 改动面仅 api_server_runs.py：sha256 221638a3… →（2.3.1）6bf70010… →（修订一）**bc5a5b36…**；相对上游 diff_lines 765 → 844 → **868**（旧件 diff 实测 +79／+24）。
- install.sh／verify.sh 钉值两处同步换 bc5a5b36…（旧钉全包扫描零残留）；manifest version 升 2.3.1＋修订一注记、runs 条目 sha／diff_lines／summary 同步；CAPABILITIES #37 追加 2.3.1＋修订一状态；DEPLOYMENT-GUIDE 标题升 2.3.1＋注记两段。
- options_card_selftest.py 随包更新（33 → 35 项）。

## 应用

- 内存：应用前 3838/7725 ≈ 50%、修订一后 4117/7725 ≈ 53%（红线 80% 未触）。
- 生产对账：容器内 §441 其余四件与 2.3.0 钉值逐一一致（api_server 18662321… 系 2.3.0 已换件、options_pending 1b354709…、present_options_tool f8400d1c…、sessions d8fb4247…），改动面确认只有 runs 一件。
- 回滚基线先行：**/root/deploypkg-2.3.1-20261125/baseline/**（production/runs 旧件＋package-2.3.0 七件＋hermes-docker-compose.yml＋**已翻闸 config.yaml**，SHA256SUMS 10/10 OK）；修订前件另存 baseline/rev1/api_server_runs.py（6bf70010…）。
- 服务器包目录 /root/hermes-deploy-pkg-2.3.1（以 2.3.0 目录为底，七件逐个覆盖、双边 sha256 全等）。
- 两次真跑前均查 /v1/runs：全终态（completed 42／failed 8＋本件验证 run）、无在飞真实 run；DRY_RUN 两次均恰为「模块更新 1、其余 0、资产待铺 0」才真跑。
- 两次真跑均遇 SSH broken pipe（通道抖动）：未重跑、先查实——install 日志（/root/install-231.log、/root/install-231rev1.log）均达「安装完成：应用 1 个文件、健康检查全过」，容器内件哈希已换新，判定应用完成。

## 验收证据（逐项，修订一后终态）

- 8642 /v1/health → `{status: ok, version: 0.23.0}`；容器内 runs 件回读 = bc5a5b36…。
- **verify.sh 全量：退出 0，汇总 齐 79 / 缺 0 / 规划中 1 / 未验 15**（[齐] 行计 99），存档 verify-output-2.3.1rev1-applied-20261125.txt（本地与服务器各一份）。与 2.3.0 口径（齐 80／未验 14）的差额恰一项：`options-gate-latent` 探针在翻闸后按设计转 `options-gate-state` 未验（不判读），属翻闸后果、非本版回归；options 其余探针（两模块哈希、能力位）全齐。
- 三读面不变：台账 500／目标 41／动态（days=3650）23。
- 翻闸仍在：config.yaml `grep -c options_card` = 2（display.options_card＋工具集 options_card）。
- **真实流量复验（关账门）**：
  - 第 1 轮（run_1ec71dec，会话键 options-timingfix-verify-20261125）：模型调工具、handler 成功——卡未落，warning 实证 run_key 绑定断链 → 触发修订一。
  - 第 2 轮（run_e34f9f56，会话键 options-timingfix-verify2-20261125）：completed，终态助手行 **6551** 的 display_metadata 实存 `{"options": {"v": 1, "options": [{"label": "周六凌晨", "send_text": "周末备份窗口定在周六凌晨。"}, {"label": "周日凌晨", …}]}}`；同轮网关日志 options 告警 0 条。
- 验证会话留痕（登记）：options-timingfix-verify-20261125（行 6531–6535）、options-timingfix-verify2-20261125（行 6548–6552）留在生产 state.db，为真实请求验活留痕，未删。

## 残留与事故

- 传输事故一则：bt3128.sh 末尾写死 `< /dev/null`，经它管道 stdin 传文件全写 0 字节（首轮 7 件中招、当即以服务器 2.3.0 副本恢复包目录、未触生产）；后改直连 ssh（同钥同 ProxyCommand、不经包装）传输，逐件哈希验毕。此坑与 Mac 通道的 stdin 0 字节坑同型，通道纪律追加：**bt3128.sh 只跑命令不传文件，传文件走直连 ssh 管道**。
- 宿主机 python3 过旧（<3.9）跑不了包内自测（模块注解语法），自测改容器内跑，已在上文注明口径。

## 回滚

1. 整版回滚到 2.3.0：基线 production/api_server_runs.py 覆回部署目录 patches/（或包目录换回 hermes-deploy-pkg-2.3.0），跑 2.3.0 版 install.sh，重启后以 2.3.0 版 verify.sh 复验；**config 不动**（翻闸保留——回滚后选项卡退回「守卫＋时序双缺陷」态但闸仍开，等于回到翻闸当日状态；若要连闸一起退，按 options441-flip-20261125.md 的回滚节恢复 pre-flip config）。
2. 只退修订一：baseline/rev1/api_server_runs.py 覆回＋重启，回到 2.3.1 本体（重试已修、绑定未修）态。
3. 回滚不涉及任何数据文件；验证会话留痕不需处理。
