# 部署包 1.21.0 应用记录 · 网关生成线缺钥治本（2026-11-24）

- 批准：用户 2026-11-24 14:15 亲点「治本」（此前 14:13 曾裁「先不修」，14:15 改判治本、批准动生产）。
- 定因正本：`~/workspace/oneday-design-review/feed-research-failure-rca-20261124.md`。
- 故障：`HERMES_API_KEY` 只活在旧网关进程环境、从未落进任何配置工件，2026-11-24 11:48 容器重建后丢失；动态/点子/简报三线生成自 11:12 起全停（11:12/12:05/13:05/14:05 四轮 hourly 均 skipped、modelCalls=0）。

## 改动（先入包、再应用）

包内（~/workspace/hermes-deploy/，版本 1.20.0 → 1.21.0）：

1. `patches/oneday_seg_ideas_gen.py` 第 70 行：钥读取照抄 `overview_gateway.py:46-47` 同式兜底——`os.environ.get("API_SERVER_KEY") or os.environ.get("HERMES_API_KEY", "")`（API_SERVER_KEY 优先）。文件 sha256 e4cd7dad…→2cb6a47c…；manifest.yaml、install.sh、verify.sh 三处钉值同步更新；py_compile 通过。
2. `services/hermes-compose.template.yml`：hermes 服务 environment 在 API_SERVER_KEY 行后同位补 `HERMES_API_KEY=${API_SERVER_KEY}`（同值同源、一把钥）。
3. `services/env.template`：compose 段加注记——HERMES_API_KEY 不单独配值、compose 内同源引用。
4. `manifest.yaml`：版本行升 1.21.0 并登记本包变更说明（全文见版本行注释）。

生产（118.24.41.52）：

5. `/www/dk_project/dk_app/hermes/docker-compose.yml`：hermes 服务补 `HERMES_API_KEY` 字面值（源值取自 companion.env 现行 HERMES_API_KEY，与 compose 内 API_SERVER_KEY 哈希比对同值后才写入；值未进任何记录/日志）。`docker compose config -q` 校验通过。
6. `/www/dk_project/dk_app/hermes/patches/oneday_seg_ideas_gen.py`：以包内新版替换（scp 直传，两边 md5 8b63f6b6…／sha256 2cb6a47c…一致）。
7. `docker compose up -d hermes` 重建（14:20 起，API server 14:20:17 起监听）。

## 回滚基线

- `/root/keyfix-1.21.0-baseline-20261124/`：改前 docker-compose.yml 与 oneday_seg_ideas_gen.py 各一份。
- 另：`/www/dk_project/dk_app/hermes/docker-compose.yml.bak-20261124-keyfix`（同目录 .bak 惯例）。
- 回滚法：覆回两文件后 `docker compose up -d hermes`。

## 步 0 前置

- 内存：动手前 4358/7725 ≈ 56%（红线 80%）；重建前复查 4381/7725，在飞 run 为零（/v1/runs 近 50 条：49 completed／1 failed／0 active），未打断任何会话。

## 步 3 回读验证（五项）

1. **容器 env 在位**：docker inspect 容器配置 env 与 docker exec 环境双证——HERMES_API_KEY 在位，且与 API_SERVER_KEY 哈希同值（只报同值结论，未回读明文）。
2. **健康与版本**：/health 200（status ok、version 0.23.0）；/v1/models 带钥 200；网关日志 14:20:17 API server listening、housekeeping started。
3. **生成轮实跑**：15:05 hourly 轮被活跃门正常跳过（活跃分 3＜6，属设计内跳过、非故障），故按任务书「手动触发」口径经引擎同路脚本触发 feed-b 轮：15:09:58 受理、run_f8fd073b… 进场。账本 `/opt/data/oneday/data.json` meta.feedGen.history 新记录落账：
   - `at=2026-11-24 15:09:58，trigger=schedule-b，status=ok，modelCalls=6，produced=1，error=null，edition="20261124-B"，publishTitles=["独立开发者副业成本账本：每月800-900元能跑什么项目"]`
   - materialGates 留痕在位（directions[*].materialGates）：A1 审计注記「agent 取材 run 工具调用数未能回读核验，本路材料未过 A1 审计」多路出现；A2 探活剔除失效链接 agent 路 6/7 条、social 路 5 条（deadUrls 清单在录）；retrieval 实数 agent 4／tavilySearch 2／tavilyExtract 1／social 3／github 2。
   - 附带旁证：14:21 手动 feed-evaluate 的口味整理（taste reconcile）同路调用——14:05 时同动作以 HTTP 401 失败，修复后 14:22 成功 folded。
4. **铃铛无噪音**：基线（修复前）monitors/notifications 为空；B 轮全程（含其全部 completed runs）后回读仍为 0 条——批三「运行完成」来源侧过滤在真实轮上成立，无新增噪音。
5. **内存回读**：重建后 3943/7725 ≈ 51%；verify 时 54%，均在红线内。

包级核账：verify.sh 在部署机全跑——汇总 齐 72／缺 0／规划中 1／未验 14（未验均为默认不跑的写型探针与条件不足项，与本包无关）；容器内 oneday_seg_ideas_gen.py sha256 回读 = 2cb6a47c…，与包内钉值一致。输出存 `verify-output-1.21.0-applied-20261124.txt`。

## 遗留与下一观测点

- 今晚 19:30 引擎自然 B 轮照常触发（与今日手动 B 轮同日两版，属手动轮设计内行为）；盯其 history 记录 status/modelCalls 作常态复核，兼作批三铃铛验证的自然轮复核点。
- 明早 07:30 点子轮、周一 08:00 简报轮共用同一定义点，本次修复一并覆盖，届时随常态观察。
- 包内 `companion/modules/oneday_seg_ideas_gen.py`（companion 镜像源副本）第 70 行仍为旧式单读：companion 进程经 companion.env 持有该钥、不在本次故障路径内，本包未动；如后续 companion 升版可顺手同式对齐（非必须）。
- 丙案（App 任务页呈现 record.error 原文）不在本包范围，归 App 侧后续版本。
