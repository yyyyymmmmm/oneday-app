# 服务端四项落地记录（部署包 1.7.0＋companion 1.0.67，2026-11-23）

> 授权：用户 2026-11-23 19:44 亲批，口径＝部署包补丁（上游镜像本体不改、补丁入
> hermes-deploy 版本化、应用前留回滚基线）。四项：①162 通知分级矩阵服务端缺口
> ②163 Live Activities 服务端缺口（①②合计三缺口 G1/G2/G3，出处 DESIGN §385.1）
> ③131 崩溃上报端点（DESIGN §384.2 上报缺口处置）④G20 rendition API（补登记＋复验）。

## 1. 执行前检查

- 宿主机内存：开工 4472/7725MB ≈ 58%，全程 54–58%（红线 80%，未触）。
- 范围定准依据：总表 131/162/163 条目、DESIGN §384/§385（rel-05103 树实读）、
  App 侧 NotificationTier.swift 分类契约实读（kind 含 fail/error 信号归失败类、
  task_completed 归运行完成类、write_gate_decision 归审批类，其余归系统类）。
- 回滚基线先行：`/root/deploypkg-1.7.0-20261123/baseline/`（现行 patches 四文件＋
  hermes/companion 两份 compose＋companion-build 1.0.66 源码 tar）；install.sh 自带
  `.bak-20261123-deploypkg` 备份同日生成（api_server.py、api_server_runs.py）。

## 2. 入包内容（hermes-deploy 1.6.0 → 1.7.0）

- `patches/api_server_runs.py`（sha bf4f2e15…）：新增 `GET /v1/runs` 终态列表——
  按调用方幂等 scope 隔离（与单 run 状态门同一 scope 派生），从 RunIdempotencyStore
  自有连接在锁内读，只投影生命周期字段（run_id/session_id/status/completed/partial/
  interrupted/model/created_at/updated_at）；**status_json 内的 output 内容绝不经此面
  外泄**（本地自测＋verify 探针 leak=False 双证）。capabilities 的 runs_idempotency
  加 `terminal_list: true`。
- `patches/crash_reports.py`（新模块，sha f74a7424…）：崩溃上报存储——只收 §384
  CrashReportRecord 白名单字段，未知字段丢弃不落盘；服务端二次脱敏（用户路径/
  UUID 形串/十六进制地址三道正则，与 App 门/CI 提取同口径）；落
  `/opt/data/diagnostics/crash_reports.jsonl`，写入时执行 newest-500 留存上限。
- `patches/api_server.py`（sha 4424398a…）：挂 `POST/GET /v1/diagnostics/crash-reports`
  路由＋handler（行为本体在 crash_reports 模块）＋`_handle_list_runs` 委托＋能力表登记。
- `companion/modules/overview_bridge.py`（companion 1.0.66 → 1.0.67）：通知流新增两个
  只读聚合源（沿 B-03 读时聚合、不落副本）——G2 写闸 `GET /pending` → kind=
  approval_pending 条目（生未读、裁决后由 born-read 回执接替；/overview 未读数不计
  待批轴防双计）；G3 `GET /v1/runs` → completed=task_completed、failed=run_failed
  （G1 失败 kind），runs_since 上线基线防历史回灌，cancelled/interrupted 不发条目，
  条目正文只含生命周期事实、无 run 内容。
- 登记同步：manifest.yaml（1.7.0＋新模块＋crash-reports 数据文件＋companion 镜像
  1.0.67）、install.sh（哈希＋crash_reports MODULES/挂载确保）、verify.sh（哈希＋
  5 项新探针）、CAPABILITIES.md（#14 状态修正为在役；新增 #16 通知流三缺口、
  #17 崩溃上报端点、#18 rendition 补登记）、companion Dockerfile/compose 模板升 1.0.67。

## 3. 应用结果与实测证据

- 网关：install.sh 应用补丁 1＋模块更新 1＋新建模块 1＋compose 挂载 1；中途 SSH
  一度断开，现场核查证实安装已完成（部署目录哈希＝目标值、容器已重建）；随后手动
  补齐第 5 步全项：/v1/health ok、9119=302、8643=401、容器内 7 文件回读哈希全对齐。
- 端点行为（回环＋公网 hermes.example.com 双路）：GET /v1/runs 无钥 401、带钥 200
  （5 条终态、零 output 字段）；capabilities terminal_list=true；崩溃 POST 合成
  白名单记录 201 accepted=1、脏记录（deviceName/路径/地址）POST 后 GET 回读断言
  三类脏字节均未落盘；合成记录验后已清除（存储文件仅有 2 行测试行、整文件删除、
  GET 回空列表，零残留）。
- G3 端到端：真跑一轮验收 run（run_b99cf116850a413ca58637845da32486，9 秒
  completed）→ overview /notifications 长出 task_completed 条目（标题「运行完成」、
  正文无内容、未读数 0→1）→ POST 已读标记回执 ok、未读清零（已读路径一并验过）。
- G2 活条目：应用时写闸待批为 0（pendingApprovals=0），无活条目可呈；映射逻辑经
  本地自测全过（stub /pending → approval_pending 条目形态/标题/refId/未读口径逐项
  断言），且与已在役的 /decisions 聚合共用同一 WRITE_GATE_BASE/钥路径（37 条裁决
  条目实流为证）。待下一条真实待批出现即自动生效。
- rendition（G20）：生产在役复验——无钥 401；带 fileproc 钥请求 /opt/data/cloud_pc.jpg
  （1280×800）→ w360=360×225（8713B）、w1080=1080×675（49550B），200 image/jpeg＋
  ETag＋immutable、If-None-Match → 304；越界路径 400、不存在 404。端点本体零改动，
  本轮只补登记（#18）＋探针。
- companion：镜像 oneday/companion:1.0.67（ba1c6a1829b6）构建成功、仅 companion
  容器重建（StartedAt 12:11:06Z）；**hermes StartedAt 全程不变（12:07:42Z）**；
  overview state.json 已落 runs_since 基线；八端口监听＋鉴权如旧。
- verify.sh 全量：**齐 29 / 缺 0 / 规划中 1（APNs）/ 未验 6**（未验均为写型探针
  默认不跑或需桥 key/cookie 的既有口径），输出存 verify-output-1.7.0-applied-20261123.txt。

## 4. 回滚路径（未动用）

- 网关：以 `/root/deploypkg-1.7.0-20261123/baseline/patches/` 还原四文件＋删除
  crash_reports.py＋以 baseline 的 hermes compose 还原后 `docker compose up -d
  --force-recreate hermes`（或 install.sh 的 .bak-20261123-deploypkg 口径）。
- companion：live compose 改回 1.0.66（备份 docker-compose.yml.bak-pre-1.0.67 在位、
  旧镜像保留）后 `docker compose up -d companion`。
- 数据：crash_reports.jsonl 删除即净；overview state.json 的 runs_since 键旧版忽略。

## 5. 边界与存疑

- G1 的「任务失败」侧：kanban/cron 任务失败的条目生产者不在本包表面（任务完成
  条目现由监测/自动化轮次经 oneday 桥监测账本写入，失败记录是否落账取决于生产者），
  本轮 G1 落的是聊天/API run 失败（run_failed）；任务侧如需补齐须另立生产者条目，
  不在本单范围自创。
- 131 的 App 侧自动上送未接线：现行 App（§384）只本地存＋手动分享，本端点先行
  就位，接线另立项；端点已按 App 现行记录结构收发，届时零服务端改动。
- 155 短票端点在 CAPABILITIES 暂编号 #15，本轮新能力顺延 #16–#18，未占用。
