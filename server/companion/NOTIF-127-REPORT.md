# NOTIF-127-REPORT — 通知中心「已决不提醒」修复（伴生 1.0.27）

用户点名（2026-11-11 21:21 截图）：通知页满屏「技能写入已批准」且条条挂未读点，原话「批准了处理的就不要提醒我」。

## 产生链定因（逐环实证）

1. **源头账本只有已决事件**：write-gate 把每条裁决落进 `/opt/data/write-gate/decisions.jsonl`，`decision` 字段只有 `approved`／`rejected` 两个终局值（write_gate_bridge.py 两处落账点同口径，含规则自动批准 via_rule）——构造上不存在「未决」行。
2. **生成侧无条件未读出生**：overview-bridge 每 5 秒轮询该账本，`_handle_decision` 只收 approved/rejected，`_make_notification` 却把 `read` 硬写 False——每条已决回执一出生就是未读提醒。
3. **App 侧旧口径只消本人裁决**：0.36.5 的 `ApprovalResolution` 只自动消除 refId 命中「本人在 App 内裁决」集合的回执；截图这批是规则自动批准的，不在本人裁决集内，于是永久挂未读，只能逐条手点。旧设计注释明说「another decider's receipt stays unread」——是当时的有意口径，现被用户新口径推翻。
4. 角标＝桥快照 `unreadNotifications`（全部 read==False 计数）＋待审批数，故这批回执同时污染列表未读点与铃铛角标。

## 修法（modules/overview_bridge.py，伴生生成侧收敛）

- **出生即已读**：`_make_notification` 的 `read` 改由条目自带状态字段判定——`entry.decision ∈ {approved, rejected}` 时为 True。判定只认事件的结构性状态字段，不看标题文本；非终局值（现行账本不存在）会落 False，方向保守。
- **存量一次性收敛**：`_load_state` 加载既有状态后调用新函数 `_converge_decided_receipts`：已存条目中 `kind == "write_gate_decision"` 且未读的一律置已读并落盘。迁移口径＝按 kind 判定——该 kind 的每一条都由终局 decision 值生成，是结构事实、非文本猜测；条目本身不删、仍在通知中心可查（与枢纽记录制同哲学：有记录、不打扰）。
- **不误伤需要知晓类**：monitor_change（监测变化）生成与存量一律未动，仍未读出生；待审批提醒走 write-gate /status 的 pendingApprovals 计数与聊天内审批卡，本次零改动——「等用户处理」的照常提醒。
- 文件头契约注释与 refId 注释同步销账：0.36.5 的未读分工口径标注于 2026-11-11 退役。

## App 侧结论：不改

角标数与列表未读点都取自伴生自有状态（快照未读数＋条目 read 字段），伴生部署即全量生效、存量同步收敛，无需 App 发版兜底。App 的 `ApprovalResolution` 对回执变为无操作（回执到达即已读，其守卫条件要求未读）——终态与旧联动一致，聊天回告卡消账不受影响。

## 验收证据

1. **自测**：overview 自测 15 passed（基线 8，只增不减）——新增断言：回执已读出生、监测未读出生、未读数只计监测；二阶段预置旧口径状态（未读回执＋未读监测）重启，验回执收敛已读、监测保持未读、条目全数保留。全套自测其余全绿（p2 34／p3 72／p4 20／p5 23／p6 53／rules 22／anchor 13／spreadsheet 20／ledger 60／delivery＋sentinel OK／device 系 OK）；rendition 在本机仍红——清一色 503 繁忙门（本机内存约 94%），与 1.0.26 报告同因，与本次改动路径无关，生产 rendition 正常。
2. **生产存量收敛（部署前后实数）**：部署前 /overview `unreadNotifications`＝7，状态文件 29 条＝22 已读回执＋7 未读回执（未读全部为已决回执，与截图互证）；部署后未读＝**0**，29 条全数保留且全部 read＝True，条目一条未删。
3. **生产探活**：8643/8644→401（需钥）、8645/8646/8647→200；8646 /health ok、deliverySentinel lastError＝null。
4. 新回执的生产行为未做活体造数验证（不往生产账本写假裁决污染用户列表）；等值证据＝与出厂模块 md5 逐字一致的暂存副本自测一阶段（新裁决行追加→已读出生）已覆盖。

## 部署纪律账

- 版本：伴生 **1.0.27**，镜像 oneday/companion:1.0.27（sha256 b8b7c174b8d3…）；构建目录 /root/build-1.0.27（克隆 build-1.0.26 后替换 modules/overview_bridge.py＋Dockerfile，md5 与本地逐字一致：模块 a8168b9d…、Dockerfile 4bde9020…；运行容器内模块 md5 复核同值）。
- 回滚点：/root/companion-127-deploy-20261111/docker-compose.yml.1.0.26（还原到现行目录 /www/dk_project/dk_app/companion 后 up -d 即回 1.0.26，旧镜像在机）。
- 部署前后：内存 51%→52%；Hermes StartedAt 逐字不变（2026-11-10T14:21:47.024396739Z）；本次只重建 companion 容器。

## 真机待验点

1. 打开通知页：存量「技能写入已批准」等回执不再挂未读点、铃铛角标不再含回执数；条目仍在列表里可查、点开内容不变。
2. 下一次智能体发起需人工裁决的写入（无自动规则命中时）：待审批计数与聊天内审批卡照常出现提醒——本次未动该链。
3. 下一条监测变化通知仍应挂未读点（需要知晓类未动）。
