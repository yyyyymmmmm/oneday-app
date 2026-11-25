# OneDay 记忆机制（§439）合并版应用方案

- 对象：部署包 1.11.0（能力 #21；原候选 1.12.0/#22，因自设一期未先合并按顺位定稿、自设顺延 1.12.0/#22）——oneday_memory 模块＋api_server 增量＋通用种子＋机制 cron；以及用户实例专属的移植包（migration-user-instance/）。
- 前置：版本号与能力编号由主线与在途线统一协调后定稿（在途：批二 1.10.0 已入本体并应用；自设一期未先合并，故本包定稿 1.11.0/#21、自设顺延）；api_server.py 以 1.10.0 本体为底叠加本包 +112 行（落点与自设 +29 行不重叠），哈希按合并结果重算并同步 manifest/install/verify 三表。
- 红线：应用须用户批准；执行前查服务器内存（118.24.41.52 ≥80% 立即停）；每步回读验证，不符即停。

## A 段：基础机制应用（任何实例同序）

| 步 | 动作 | 验收/停手 |
|---|---|---|
| 0 | 备份基线：部署目录 patches/ 现行文件＋docker-compose.yml＋data/cron/jobs.json 各一份带日期副本 | 回读清单齐才继续 |
| 1 | DRY_RUN=1 ./install.sh <部署目录> 盘点 | 预期：补丁 1（api_server）＋模块新建 1（oneday_memory）＋compose 挂载 1＋记忆资产待铺 25 项；盘点不符即停、报差异 |
| 2 | ./install.sh <部署目录> 正式应用（补丁原地改写保 inode、模块新建、compose 挂载、3c 铺种子 23 文件＋合并 cron 2 条、重启 hermes） | 脚本内健康检查（8642 health＋容器内回读哈希全对齐）不过即自动回滚 |
| 3 | ./verify.sh 复跑 | 新增第 19 节五探针齐：memory-layers-route（无钥 401）、memory-layers-behavior（带钥回层清单）、memory-capability-flag、memory-seed-tree、memory-cron-jobs；其余能力与应用前对账无新增「缺」 |
| 4 | 行为抽验（只读） | 带钥 GET /v1/memory/search?q=记忆 → 有回（空实例回空命中属正常，结构正确即可）；GET /v1/memory/insights → 空表结构正确；容器内 CLI 跑一次 sweep，INDEX.md 再生且内容与实物对账 |
| 5 | 首跑监督（应用后首个 23:40） | 次日查 journal：日结回执在位（候选数/动作分布）；无回执或回执异常先停 cron 两条再报 |

## B 段：用户实例移植（仅用户实例，A 段验收后另行批准执行）

| 步 | 动作 | 验收/停手 |
|---|---|---|
| 0 | 按 migration-user-instance/baseline/BASELINE.md 第二节做整份快照并回读哈希 | 快照不全即停 |
| 1 | 落位 converted/memories/ → data/memories/（同名文件先 diff：MEMORY.md/USER.md 以转换稿为准替换，替换前原件已在快照内；oneday/ 子树与种子同名文件以转换稿为准） | 落位后文件计数与 CONVERSION-MANIFEST 对账（转换 41＋归档 54） |
| 2 | USER 碎片对账：快照内旧 USER.md 的 565 字现行事实逐条与转换稿比对，仍有效且转换稿没有的，人工补入 USER.md 或对应场景文件 | 对账清单留痕（每条去留一行） |
| 3 | 转写技能落位：converted/skills/ 17 个目录逐个复制到 data/skills/；与存量同名冲突即停该个并报告 | 落位后技能数＝存量＋17（无冲突时）；准入账给 17 个各补一条（verify=移植转写＋本方案指针） |
| 4 | 系统规矩稿与 RULES 落位后，抽一条会话实测：让 agent 复述一条系统层规矩与一条放大红线，答对才算入脑 | 答错先查载入链（文件落位/会话快照），不许将就 |
| 5 | 首个日结在移植内容上跑完后，抽查回执与三条落层条目的尾注溯源 | 异常按 ROLLBACK 一级处理 |

## 回滚

- A 段失败：install.sh 自带回滚（.bak 基线）；资产（种子/cron）留置无害，手动清理步见 migration-user-instance/ROLLBACK.md 二级第 2 条。
- B 段失败：按 migration-user-instance/ROLLBACK.md 分级回滚（一级退移植内容、二级连机制退）。
- 任何回滚后 verify.sh 复跑对账，并把事实记入应用记录。

## 停手条件汇总

内存 ≥80% / DRY_RUN 盘点与预期不符 / 快照回读不全 / 落位计数对不上 / 同名技能冲突未决 / verify 新增「缺」——任一出现，停当前段、保留现场、先报主线。
