# §441 选择框服务端应用记录（部署包 2.2.0，2026-11-25，只潜伏未翻闸）

授权：用户 2026-11-25 服务端全批授权，服务端线现行指令依次应用本链。正本：`~/workspace/hermes-deploy-options/rebased-1.23.0/REBASE-NOTES.md`（含二轮收尾）。

结论：**已应用生产并验收全过**——§441 选择框机器五文件入包升 2.2.0、hermes 重启一次、包内自测 Part A 合并树 32/32＋容器 Part B 真 SessionDB 通过、verify.sh 全量缺 0、健康与三读面与应用前逐一相同、潜伏判据双证（能力位在位＋实例 config 零 options_card 登记）。**翻闸未做**（display.options_card 未设、platform_toolsets.api_server 未加 options_card 工具集），属另一步。

## 基线对账（应用前实查）

- 整机内存 54%（红线 80% 未触）；应用后 52%。
- 生产三文件（容器内＋部署目录双读）与主包 2.1.0 钉值逐一全等：api_server.py md5 `4fd8cdf0…`、api_server_runs.py `e06499ce…`、web_routers_sessions.py `b69cdf70…`。
- 预制基线假设逐一对账：
  - api_server_runs.py：预制基线（1.23.0 件）与现行生产**逐字同件**（md5 `e06499ce…`）——预制件直采；diff（现行→预制）恰 3 个 hunk、变更行 56（新增 55＋删改 1，删改即 R1 守卫行）。
  - web_routers_sessions.py：现行件与预制基线同件——预制件直采；diff 恰 +45 行纯增、零删改（历史投影 options 平齐 hunk）。
  - api_server.py：**基线已漂移**——预制基线是 1.23.0 件（md5 `9fa4f3b6…`／sha256 `c7435761…`，自 `/root/deploypkg-2.0.0-20261125/baseline/patches-api_server.py` 取回、哈希验明），现行件含 2.0.0 的 device 面增量。按纪律以现行生产件为底三方合并（git merge-file --diff3），冲突恰 1 处＝features 字典同一锚点（2.0.0 加 `device_bridge`、§441 加 `options_card`），按预制并集先例消解：两旗并存、原有条目顺序未动、options_card 殿后。合并件相对现行件恰 4 个 hunk、纯增 56 行、零删改；`_options_from_display_metadata` 与两旗计数与预制件逐一相同；语法校验通过；合并树复跑自测 32/32（见下）。
- 两个新模块在生产不存在（实查），属本件新建。

## 入包（主包 2.1.0 → 2.2.0）

- `patches/` 五文件：api_server.py（合并件，sha256 `186623217a…`）、api_server_runs.py（预制件直采，`221638a36e…`）、web_routers_sessions.py（预制件直采，`d8fb424736…`）、options_pending.py（新模块，`1b354709c9…`，与 options 包原钉值逐字同件）、present_options_tool.py（新模块，`f8400d1cc3…`，同上）。
- 钉值三处同步：install.sh（PATCHES 两件＋MODULES 一件换钉、MODULES 新增两条、compose 探活 grep＋2、挂载 specs＋2、写后校验 grep＋2、MODULES 注释补 §441 潜伏口径）、verify.sh（WANT_SHA 两件＋WANT_SHA_EXTRA 一件换钉、EXTRA/CPATH 各＋2、第 27 节新增四探针：两模块哈希＋options 能力位＋潜伏位）、manifest.yaml（版本行升 2.2.0 记全本版条目、三文件 sha256 换钉、provides 各补 options 项、三文件 summary 各追 2.2.0 段、新增两模块条目）。
- manifest `diff_lines_vs_upstream` 按上游 .orig（自部署目录取回、sha256 与 manifest 登记值逐一全等）以「diff 变更行数」口径重算：api_server 1161→**1441**、runs 281→**765**、sessions 68→**113**。注：前两件的旧值系陈旧未维护（与任何现行口径都对不上），本次一并纠正；增量自洽（api_server 相对 2.1.0 件变更行 +56、sessions 恰 +45；runs 本件实测 +55 行新增／−1 行守卫改写，相对上游净增 +54——被改写的守卫行本身是包侧增量行、不占上游删除计数）。
- CAPABILITIES 新增 **#37**（选择框服务端潜伏）；DEPLOYMENT-GUIDE 标题升 2.2.0＋2.2.0 注记一行（写明翻闸三步属独立一步）。
- 包内自测两件入包：`options_card_selftest.py`（Part A）、`options_card_container_test.py`（Part B），与 options 预制包原文件同字。
- 合并后包内自测在主包树复跑：**32/32 SELFTEST PASSED**；install.sh/verify.sh `bash -n` 通过；manifest YAML 解析通过；旧钉值全包扫描零残留。

## 应用

- 回滚基线先行：**/root/deploypkg-2.2.0-20261125/baseline/**（production/ 三文件＝部署目录应用前件、package-2.1.0/ 八件＝三文件＋install/verify/manifest/CAPABILITIES/GUIDE 的 2.1.0 态、hermes-docker-compose.yml），SHA256SUMS 12 件回读 **12/12 OK**。
- 服务器包目录 `/root/hermes-deploy-pkg-2.2.0`（以 2.1.0 目录为底复制＋12 个变更/新增文件逐个覆盖，落盘后哈希与本地包逐一全等）。
- 应用前 `/v1/runs?limit=50` 两读：completed 42／failed 8、全终态、无在飞真实 run。
- DRY_RUN 计划恰为本件范围才真跑：**补丁 2、模块更新 1、模块新建 2、compose 挂载变更 1、记忆资产待铺 0、语义依赖/模型就绪 1/1**，其余模块全数「已是目标状态，跳过」。记忆资产一项先行专项核查：以包内 seed-memory 与 cron 片段对实例 data 实查，缺失种子 0、未合并 cron 作业 0——批四预制时报的「待铺 26 项」在现行实例上不成立（口径差异/旧时点数），本件真跑不带任何资产铺设。
- 真跑时 SSH 断线一次（broken pipe，与 2.0.0/2.1.0 同款通道抖动）：未重跑、先查实——五文件已落新哈希、.bak 齐全、compose 两挂载行已入、hermes 已重启，判定应用完成；install 自带末验由下方人工验收电池替代。

## 验收证据（逐项）

- 8642 `/v1/health` → `{status: ok, version: 0.23.0}`。
- 容器内五文件回读哈希＝包钉值（`18662321…`／`221638a3…`／`d8fb4247…`／`1b354709…`／`f8400d1c…`）。
- **verify.sh 全量：退出 0，汇总 齐 77 / 缺 0 / 规划中 1 / 未验 15**（[齐] 行计 88）；2.1.0 存档输出同口径为汇总 齐 73 / 缺 0（[齐] 行计 84）——净增恰 4＝第 27 节四探针，未验/规划中不变。输出存包内 `verify-output-2.2.0-applied-20261125.txt`（本地与服务器各一份）。注：2.1.0 交卷口头报「85 齐」，其存档文件实为 84 行/汇总 73——以文件为准，本版两口径均不低于 2.1.0。
- 第 27 节四探针全齐：options_pending／present_options_tool 容器内哈希一致；`features.options_card=true`（补丁在位即声明）；config.yaml 无 options_card 登记＝潜伏态。
- 三读面与应用前逐一相同（同法实测，钥自容器进程环境内取、未出服务器）：台账 200/500 条、目标 200/41 条、动态（days=3650）200/23 条。
- **潜伏验证**（按 REBASE-NOTES 判据：闸门默认关控制生产行为）：①应用前后 config.yaml `options_card` 出现次数均为 **0**——display.options_card 未设（默认关）、platform_toolsets.api_server 未加 options_card 工具集，present_options 工具不注册、模型无从调用；②capabilities 仅多 `options_card: true` 声明位（与 self_reactions 同款广告口径，不产卡）；③attach 侧 pending 恒空（无工具登记路径），_attach_options 恒无-op；④网关启动日志零 Traceback、零 options 相关报错。
- **Part B 容器真码复跑**：以容器内已部署的 options_pending 本体对真 SessionDB（临时库、未触生产数据）跑 `options_card_container_test.py` → **CONTAINER TEST PASSED**（落卡、reactions＋delivery 既有键逐字保全、跨会话行与不存在行拒绝）。
- stale 样本（1795466451／1795485581）未动，不在本件范围。

## 偏离与说明

1. **范围口径（五文件而非三文件）**：简报以「三文件」为纲，但预制件本体含两个新模块——api_server_runs 的 _attach_options 运行时 import options_pending、present_options 工具本体即 present_options_tool；REBASE-NOTES 与 options 包 manifest 均把两模块列为 §441 件内物。若只应用三文件，潜伏代码是死码、日后翻闸还须再发一版，与「只潜伏、翻闸另行一步（只动 config）」的口径冲突。故按五文件合并应用，DRY_RUN 计划（含新建 2）确认在范围内才真跑，特此登记。
2. **install 真跑断线**：见「应用」节；未重跑、查实落盘后以人工电池补末验（容器回读＋verify 全量＋Part B），证据强度不低于 install 自带末验。
3. **上传通道**：两个大文件首传因 base64 命令行超长静默失败（落盘验哈希时发现），改 gzip＋分块传输后逐个验哈希落盘；仅涉包 staging 区，生产零影响。
4. **companion 半边**：预制件无 companion 内容（options 机器全在网关侧），无跳过项；包内 companion/ 目录未动。

## 回滚

基线 `/root/deploypkg-2.2.0-20261125/baseline/`：production 三文件覆回部署目录 patches/（原地改写保 inode）、删除 patches/options_pending.py 与 patches/present_options_tool.py 两新文件、compose 摘两行新挂载（或以基线 hermes-docker-compose.yml 覆回）、包侧件以 package-2.1.0/ 覆回，重启 hermes 后以 2.1.0 版 verify.sh 复验（汇总 齐 73 / 缺 0 为回滚成功口径）。本版未动任何数据文件与 instance config，回滚无数据侧动作。
