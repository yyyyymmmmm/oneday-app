# 中枢数据四件应用记录（部署包 1.23.0，2026-11-24）

用户 2026-11-24 18:55 亲批「做」。审计正本：`~/workspace/oneday-design-review/hub-rows-audit-20261124.md` 第 1/2/3/6 节。能力号 #34。

## 应用事实

- 应用前内存 4395/7725 ≈ 57%（红线 80% 未触）；近 44 分钟无新会话消息、无在飞 run。
- 回滚基线：`/root/deploypkg-1.23.0-20261124/baseline/`（docker-compose.yml ＋ api_server_runs.py 9cd40e93…／oneday_gateway.py 674b4940…／oneday_ledger_lib.py 5a2254cd…／write_gate_gateway.py 321b66e8…，与改前生产逐一吻合）。
- 包同步：`/root/hermes-deploy-pkg-1.23.0/`（整包 tar，md5 ed2b9aeb… 双边一致；六个变更文件 sha256 与包内钉值全对）。
- DRY_RUN 盘点：补丁 0、模块更新 4、模块新建 2（web_routers_profiles.py／web_routers_ops.py）、compose 挂载变更 1。
- 正式 install 期间 SSH 代理断管一次（exit 255 broken pipe）；复查确认应用已完整落地（部署目录与容器内六文件哈希均为目标值、compose 含新挂载、容器已重启），非回滚态。
- 两个新补丁的上游原件 `.orig` 已放部署目录 patches/（profiles e374c678…／ops e68deb87…，与容器镜像内原件回读一致）。
- install 后健康双验：8642 `/v1/health` ok、9119 应答 302；全量 verify.sh：齐 78／缺 0（第 25 节四探针全齐；首跑两探针因 docker exec 未带 -i 空跑，已修 verify.sh 并复跑全绿，修复版已同步服务器包副本）。

## 四项回读证据

1. **台账摘要结算链**：真实测试 run `run_f0772769759646ebadd4f1931015ddcd`（会话 hub-fields-verify-20261124，提示词要求用搜索工具查西安天气）completed；终态上报**未带** summary，台账条目回读 `"summary": "搜索 西安今天天气"`——服务端从该 run 真实 web_search 事件的 preview 派生（动词模板「搜索」＋对象）后结算入账，列表视图即带出。条目标题「验收测试：西安天气搜索」即测试标注（台账 append-only、无删除惯例，条目为真实 run 记录，保留）。包内自测 hub_fields_selftest.py 24 项全过（含 App 自报优先、回放不丢、纠正覆写）。
2. **审批投影对象字段**：容器内暂存一条 memory batch 待批（3 ops：add／add／remove、target=user），经 `_norm_record` 回读：`op_count=3`、`op_kinds=["add","add","remove"]`、`content_preview="验收测试条目甲"`、`mem_target="user"`；验后 discard、待批计数回 0，未产生裁决、未动记忆。注：decisions.jsonl 中 1.23.0 之前的存量已决行保持旧形状（字段在追加时提取），此后新裁决行才带新字段。
3. **记忆卡日期**：GET /api/memory 回读 `builtin_files_updated_at = {"memory": 1795457797.86692, "user": 1795457797.86592}`，与容器内 MEMORY.md／USER.md 的 st_mtime 逐位一致。
4. **SOUL 回执时间**：GET /api/profiles/default/soul 回读键集含 `updatedAt = 1795455135.079038`，与 SOUL.md st_mtime 逐位一致。

## 回滚法

1. 部署目录 patches/ 四个更新文件覆回基线副本；删除新建的 web_routers_profiles.py／web_routers_ops.py（及 .orig）；docker-compose.yml 覆回基线版（或删两行新挂载）。
2. `docker compose up -d hermes` 重启，复查 8642 健康与 9119 应答。
3. 数据面无迁移：台账 summary 只是事件账新增可选键，旧代码回放自动忽略；decisions 新字段同理向后兼容。

## App 侧待接清单（交主线转 App 线）

| 面 | 字段 | 形状 |
|---|---|---|
| 台账条目（GET /api/oneday-bridge/ledger 的 items[]、详情同） | `summary` | string｜null；终态结算后有值，形如「搜索 西安今天天气」（动词＋对象，对象 ≤30 字、整串 ≤120 字）；未结算/无活动为 null。行型第二行数据源，与胶囊实时短语同源同派生 |
| 上报协议（POST /api/oneday-bridge/ledger/report） | 请求体可加 `summary` | string 可选；终态报告自带则优先落账，缺省由服务端从 run 活动派生兜底 |
| 写闸记录（pending／decisions 两面同形） | `op_count` int、`op_kinds` [string]、`content_preview` string（≤120 字）、`mem_target` "memory"｜"user" | memory batch 行新增（1.23.0 起新产生的记录）；审批行正文可改吃 content_preview，不再回落英文 summary |
| Dashboard GET /api/memory | `builtin_files_updated_at` | `{"memory": epoch 秒 float｜null, "user": 同}`；记忆卡日期数据源 |
| Dashboard GET /api/profiles/{name}/soul | `updatedAt` | epoch 秒 float；文件缺失时 exists=false 且 updatedAt=null；SOUL 卡日期数据源 |
