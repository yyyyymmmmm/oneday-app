# ANCHOR-128 · 伴生审批锚点（write-gate 时序关联）施工报告

日期：2026-11-11。规格唯一依据：`~/workspace/oneday-design-review/approval-anchor-spec-20261111.md`（§128）。版本：伴生 1.0.17 → **1.0.19**（中间版 1.0.18 说明见下「版本与 T3 口径纠正」）。改动面：仅 `modules/write_gate_bridge.py`＋新增自测 `tests/write_gate_anchor_selftest.py`（已注册进 `tests/run_bridge_selftests.sh`）＋Dockerfile/compose 版本位。已按伴生自动部署授权上线。

## 实现（规格 §3 定案机制 B＋E）

- 关联计算在 write-gate 桥（8643）：每次 `/pending`、`/pending/{sub}/{id}`、`/decisions` 响应时，用一个 `_AnchorResolver` 以 `mode=ro` 只读打开 state.db（每请求开一次、目标会话集加载一次），对每条记录算 `anchor`。纯加法：pending 记录与 decision 行新增可选字段 `anchor: {"sessionId","tier"} | null`，恒输出该键；旧字段语义零变化，任何失败（无库/无候选/并列）一律 anchor=null（降级＝现行形态）。
- 目标会话集合：sessions 中 source='api_server' 且 archived=0 且 hidden=0，id 不匹配桥侧常量排除名单 `ANCHOR_EXCLUDE_PATTERNS`＝`oneday-probe-*`、`oneday-verify-*`、`sync-acceptance*`、`audit-*`、`mcp-devicetest-*`（生产实查的探针/验收会话族，与 §122 探针口径同源）；kanban 源永不为目标。
- 分级（按序命中即停）：T0 origin='oneday_app' 恒 null → T1 某目标会话 messages 中有 tool_name ∈ {memory, skill_manage} 且 |timestamp − created_at| ≤ 120s 且唯一（多于一个即弃锚）→ T2 origin='foreground' 且恰一个目标会话活动区间 [started_at, max(last_activity_at, ended_at ?? +∞)] 覆盖 created_at 且其在 ±300s 内有消息 → T3 origin='background_review'（信号口径见下节）。`created_at_approx`（mtime 兜底）记录窗口 ×2 且不给 T1。
- 生产另有第四种 origin `assistant_tool`（旧记录与现行 pending 各见样本）：规格只列三值，本实现按分级通则处理——只可能命中 T1（无暂存工具调用在场即 null），回放样本均 null，如实记录不冒充覆盖。

## 版本与 T3 口径纠正（先讲清）

- **版本号顺延两次**：开工时生产为 1.0.16、本地树已被 §127 期一线占 1.0.17 且其部署正在进行（/root/companion-117-deploy-20261111/ 14:50 建立）。本包等其落地（生产 oneday_bridge 与本地树 md5 逐字一致后）才动，先发 **1.0.18**（基线 /root/companion-118-deploy-20261111/）。
- **T3 信号与规格条文分歧（实证纠正）**：规格 §3 表把 T3 写为 last_activity_at ∈ [created_at−1800s, created_at] 唯一命中。1.0.18 按此字面实现后生产回放：最近 4 条 background_review 只中 1 条。查因（state.db 只读实查）：被审查会话的 last_activity_at 是回合收尾时打戳、普遍比暂存 created_at **晚数秒到数十秒**（如 20977b0a：created 04:25:40Z，其被审查会话 oneday-side-c60d7bfd 的 last_activity_at＝04:25:57Z），字面窗口必然漏掉；而规格 §2 的实证口径本是「±120s 窗口内消息活跃唯一」。**结论：条文形式化与其自身实证不一致，按实证修**——T3 改为消息时间戳口径：目标会话在 [created−1800s, created+120s] 内的最后一条消息取最大者为锚（容差收尾落地），另加 ±120s 并发守卫（两个目标会话在 created±120s 内都有消息＝真并发，弃锚）。离线复算（生产 state.db 只读）最近 4 条 background_review 得 4/4，随即发 **1.0.19**（基线 /root/companion-119-deploy-20261111/，含 1.0.18 的 write_gate_bridge.py.118）。1.0.18 在线时长约 15 分钟、纯加法字段、无行为事故。
- 一处无真值可判的分歧如实记：11-09 三条 background_review，last_activity 口径（1.0.18）指向 api-6e2f193c79997b6e、消息活跃口径（1.0.19）指向 api-e8c923beeaebed9c；无从判定哪条才是当年被审查会话，本包从规格 §2 方法取消息活跃口径。

## 自测（全绿）

- 新增 `write_gate_anchor_selftest` **13 项**：T3 回放命中被审查会话／T3 同刻并列→null／T3 并发守卫→null／探针在场排除后唯一命中／探针独占窗口→null／oneday_app 恒 null／T1 工具调用在场命中／T1 并列→null／T2 覆盖命中／无活动→键在且 null／approx 窗口加倍命中 T3 且不给 T1／decisions 行回溯带锚。
- 全套（run_bridge_selftests.sh）：overview 8／p2 34／p3 46／p4 20／p5 23／p6 53／device OK／write-gate rules 22／**anchor 13**／device_sync OK／model-combos OK／spreadsheet 20／ledger 60——全 RESULT OK（p3/p4 计数为 §127 线 1.0.17 后的现行基线）。

## 部署验收（1.0.19，2026-11-11 15:0x CST）

- 镜像 oneday/companion:1.0.19（sha256:c701afe52c95…），容器 COMPANION_VERSION=1.0.19；五模块探活与部署前同口径（8643/8644→401 在线需钥、8645/8646/8647→200、8650 前端在线）。
- Hermes StartedAt 部署前后逐字不变：2026-11-10T14:21:47.024396739Z。内存全程约 51%（3958–3974 / 7725 MB），未触 80% 红线。
- 构建上下文核对：oneday_bridge.py md5 e2925862…＝生产 1.0.17 原样（§127 在制品未被本包夹带），write_gate_bridge.py md5 d39aff5b…＝本地新版。

## 生产回放（已部署桥 /decisions?limit=50＋/pending 实测，非离线推算）

decisions 共 22 行，background_review 7 行全部命中 T3：

| id | created_at (UTC) | anchor |
|---|---|---|
| 20977b0a | 2026-11-11 04:25:40 | oneday-side-c60d7bfd-e16f-4471-9a68-b2ac36ba4de7 · T3（与规格 §2 点名的被审查会话一致） |
| 801e551f | 2026-11-11 03:35:00 | api-340bdc44179f0a35 · T3 |
| 3258e01d | 2026-11-10 17:08:17 | oneday-main-bfb4e3ed-9e80-4bfe-9203-325d65f6a600 · T3（探针 oneday-probe-03620-hb 同窗在场、排除后唯一，与规格实证一致） |
| 51b07aff | 2026-11-10 16:27:59 | oneday-main-bfb4e3ed-9e80-4bfe-9203-325d65f6a600 · T3 |
| 636968a2 / 8c12706d / 9733fb89 | 2026-11-09 15:27–15:30 | api-e8c923beeaebed9c · T3（信号分歧见上节） |

- 规格口径「最近样本 4/4 可归位」：**4/4 达成**（上表前四行）。
- oneday_app 10 行恒 null（T0）✓；assistant_tool 5 行 null（见实现节说明）；当前 pending 1 行（37f50fbe，assistant_tool）null。
- 与离线复算逐行一致（同一算法先离线验、再上线验，两遍同结果）。

## 回滚

- 回 1.0.18 态：/root/companion-119-deploy-20261111/（compose＋env＋inspect＋write_gate_bridge.py.118）。
- 回 1.0.17 态：/root/companion-118-deploy-20261111/（同套＋write_gate_bridge.py.117）。
- anchor 为纯加法，回滚只需换镜像 tag 重建 companion 容器，App 与数据零影响。
