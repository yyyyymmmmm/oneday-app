# ledgerfix 应用记录（部署包 2.1.0，§475，2026-11-25）

授权：用户 2026-11-25 服务端全批授权，服务端线现行指令依次应用本链。正本：`~/workspace/hermes-deploy-ledgerfix/gateway-repin/APPLY.md`＋`REPIN-NOTES.md`。

结论：**已应用生产并验收大部过**——五文件入包升 2.1.0、hermes 重启一次、自测容器复跑 22/22、verify.sh 全量 85 齐/0 缺、健康与读面在位。两项偏离/未决如实登记于文末（样本 1795485581 启动结算未触发的原因与动态读面条数差异），均非本件代码缺陷，回滚不能改变其结果，故未回滚、报主线裁。

## 回滚基线

`/root/deploypkg-2.1.0-20261125/baseline/`（SHA256SUMS 15 件回读全 OK）：`production/`＝生产部署目录五文件现状（应用前），`package-2.0.0/`＝包侧 2.0.0 五文件＋manifest/install.sh/CAPABILITIES（服务器包目录本就无 verify.sh 与 DEPLOYMENT-GUIDE.md 两件，非本次缺失），`hermes-docker-compose.yml`。另部署目录内 install 自带 `.bak-20261125-deploypkg` 五份在位。回滚法：baseline/production 五文件覆回部署目录 patches/（或包退回 2.0.0）＋重启 hermes 一次；事件账为追加式，结算事件不回滚。

## 入包（2.0.0 → 2.1.0，先入包后应用）

- `patches/` 五文件换新（源＝gateway-repin/files/，md5 与 REPIN 改后表逐一全等）：oneday_ledger_lib.py `9f8d65d8…`、oneday_seg_ledger.py `4dfd6923…`、oneday_seg_feed.py `10d48358…`、oneday_seg_ideas_gen.py `8c113981…`、oneday_seg_briefings.py `08c1d138…`。
- 新 sha256 钉值三处同步（install.sh／verify.sh／manifest.yaml 各 5 处，只动钉值行、历史叙事哈希未动）：ledger_lib `32b0310b…`、seg_ledger `768bd29f…`、seg_feed `8d3de658…`、seg_ideas_gen `d8f2cb76…`、seg_briefings `f9fc273c…`。
- 新增包内自测 `ledgerfix_selftest.py`（与 repin 件同字）；manifest 版本行升 2.1.0 并记全本版条目；CAPABILITIES 新增 **#36**（台账 job 状态口径）；DEPLOYMENT-GUIDE 标题升 2.1.0＋2.1.0 注记一行。
- 本地对合并后 patches/ 树复跑自测：**22/22**。存量 Part A 40/40 为 repin 时对字节全等件的实测（本轮未重演，口径如实）。

## 应用（2026-11-25 01:47–01:54 CST，服务器 118.24.41.52）

1. 应用前三查：整机内存 59.2%（红线 80% 未触）；生产五文件 md5（部署目录与容器内双读）与 REPIN 基线表**逐一全等**（ledger_lib 4d8f04e6…／seg_ledger 3f00b686…／feed 86a79da6…／ideas_gen 8b63f6b6…／briefings f611ef3f…）；`/v1/runs` 近 50 条全终态（completed 44／failed 6）、无在飞真实 run。应用前读面基线：台账 200/500 条、动态 200/27 条、目标 200/41 条。
2. 包传服务器 `/root/hermes-deploy-pkg-2.1.0`，包内五文件 sha256 与钉值一致。
3. DRY_RUN：计划恰为「补丁 0、模块更新 5、新建 0、compose 变更 0」，无其他漂移才真跑。
4. 真应用：install 中途 SSH 断线一次（broken pipe，与 2.0.0 同款）——未假设、未重跑，先查实：部署目录五文件已落新哈希、`.bak` 齐全、hermes 已重启（查实时 Up 34 秒）、`/v1/health` ok——判定应用已完成、仅输出被断线截断。

## 验收（回读实证，逐项）

- 8642 `/v1/health` → `{status: ok, version: 0.23.0}`。
- 容器内回读哈希：五文件与包钉值一致（见上 sha256 前缀）。
- **包内自测在容器对部署件复跑：22/22**（/tmp/lf 内以容器 platforms 两件真身＋包内自测执行）。
- verify.sh 全量：**85 齐 / 0 缺**（2.0.0 为 84 齐，齐数不降；未验 16 与规划中 2 均为历版同类项——写型探针默认不跑等）。输出存包内 `verify-output-2.1.0-applied-20261125.txt`（服务器包目录与本地包各一份）。
- 读面：台账 200/500 条（与应用前同，注：该面 500 为回读上限口径）、目标 200/41 条（同）；动态 200/**23 条**（应用前 27，差异见未决一）。
- 启动结算：本次启动结算 **0 件**——日志无 `ledger orphan jobs settled at boot` 行（该行仅 settled＞0 时打印），亦无 reconcile failed 行；原因见偏离二，属设计内行为。
- stale 样本 `job:morning:1795466451` 未动（仍 stale，history 无新增），符合本件范围。
- 应用后整机内存 60.1%。

## 偏离登记

- **偏离一（简报裁定）**：APPLY.md 应用节第 3 条「包内 companion 双生件 ledger.py 同步换新」**作废跳过**——companion 已于 2.0.0 整容器退役、包内 `companion/modules/ledger.py` 不再同步，主线简报明裁。
- **偏离二（APPLY 验收②未达，原因实证）**：APPLY 预期启动结算把 `job:morning:1795485581` 转 failed。实查应用前该条目**已不在 ACTIVE 集**：事件账回放全量 job 状态＝completed 62／failed 28／stale 2／ACTIVE 0，两个 stuck 样本均已 stale。定因：件一诊断（2026-11-24）时该条目尚 running，其后僵尸梯已先行把它标 stale（与 1795466451 同态），而 `settle_orphan_jobs` 按设计只结算 ACTIVE（queued/running/blocked_approval）条目——本次启动无可结算对象、结算 0 件是正确行为。件一机制本体经自测 22/22（含孤儿结算全用例）＋代码在位（seg_ledger:494 启动钩子、lib:888 函数）双证，下次重启遇真 ACTIVE 孤儿即生效。**遗留**：1795485581 与 1795466451 现同为「stale 待人工结算」——APPLY 原只给 6451 留了「另行人工处理」口径，85581 是否一并人工结算请主线裁，本件未动任一样本。

## 未决（报主线）

- **动态读面条数 27（应用前）→ 23（应用后）**：已查实——①本件 seg_feed diff 恰为两处交付调用、读面过滤逻辑（`_list_feed`：30 天窗＋未归档＋未过期）零改动，oneday_gateway.py 本件未动；②store 内 feedPosts 29 帖全在（id 跨 11-10 至 11-24），6 帖不可见均因 archivedAt＝1794421428（2026-11-12 的一次归档扫，非今晚）；③今晚无 feed 轮次（feedGen history 末轮为 11-24 23:10 failed）；④以当前磁盘数据按同一过滤公式在应用前时刻复算亦得 23。即差异源于应用前旧网关的**内存态**与磁盘态分歧（旧网关 01:38 拆桥重启后内存中多出 4 条可见帖，来源未能在本件窗口内坐实），重启后以磁盘为准收敛至 23。回滚重启同样读磁盘、只会同为 23，故回滚无意义。是否另立核查（旧网关内存多出 4 帖的来源）请主线裁。
- 件二「交付齐即完成」的自然轮实证（下一轮动态/点子交付落盘后 job 先于 history 翻 completed、counts 带 produced）须等 2026-11-25 07:30 自然轮，属时间驱动验收，本记录先行登记、待主线晨间回读销账。
