# 部署包 1.22.0 应用记录 · 设置目标树落码·服务端侧（种子 v4，2026-11-24）

- 批准：用户 2026-11-24 15:49 拍板「照这棵树落码」。
- 方案正本：`~/workspace/oneday-design-review/settings-ia-restructure-20261124.md` §4.3（本包只做其中服务端半边；App 侧合并引擎加门＋断开连接迁当前服务器页属 App 版本另行）。

## 改动（先入包、再应用）

包内（~/workspace/hermes-deploy/，版本 1.21.0 → 1.22.0）：

1. `patches/settings_registry.py`：SEED_VERSION 3→4；三条 config-backed 记录（platform_toolsets.api_server／memory.write_approval／skills.write_approval）的 surface 自 `agent` 改离为 `machine`（机器消费面），不再被 App 合并引擎混排进设置根页浏览组；模块 docstring 补 SEED V4 段。文件 sha256 23920f14…→0478458b…；manifest.yaml／install.sh／verify.sh 三处钉值同步。
2. `settings_registry_contract_selftest.py`：版本断言 3→4、EXPECTED agent 10→7、字段守恒加 SURFACE_OFF 豁免（基线 settings.agent → machine）与三条逐条 surface／不可浏览断言。
3. `settings_registry_selftest.py`：陈旧断言对齐（seed-version 2→4、§470 三条 browse 旗标 usage／mainSession／status 改 False——此四项自 1.19.0 起即与种子漂移、本次顺手关账），三条 key 加 surface==machine 断言。改后两套自检全绿（此前包自测 4 项陈旧红、契约自检绿）。

生产（118.24.41.52）：

4. `/www/dk_project/dk_app/hermes/patches/settings_registry.py`：scp 直传新文件（两边 sha256 0478458b…一致）替换；`docker compose restart hermes` 生效（注：先行的 `docker compose up -d` 因 compose 配置未变未重建容器、旧进程续跑，已用显式 restart 纠正）。

## 步 0 前置

- 内存：动手前 4348/7725 ≈ 56%、应用前复查 55%（红线 80%）。
- 在飞 run 为零（/v1/runs 近 50 条全 completed、0 active），重启未打断会话。

## 回滚基线

- `/root/deploypkg-1.22.0-20261124/baseline/settings_registry.py`（改前生产件，sha 23920f14…）。
- 另：`/www/dk_project/dk_app/hermes/patches/settings_registry.py.bak-20261124-deploypkg`（同目录 .bak 惯例）。
- 回滚法：覆回基线文件（保持 0644）后 `docker compose restart hermes`。

## 应用后回读（五项）

1. **三条 surface 已改离＋总数不变** ✓：带钥回读 GET /v1/settings/registry——version=4、records=43（与改前同数）；三条 key surface 均为 `machine`；surface 分布 top 1／agent 7／serverAndWorkspace 14／preferences 6／support 6／chat 1／hub 5／machine 3——agent 面只剩 7 条真目录行，与契约自检 EXPECTED 逐组一致（改前 agent=10，差额恰为本三条）。
2. **网关健康／版本** ✓：/health 200（status ok、platform hermes-agent、version 0.23.0）；容器内挂载文件 sha256 回读 = 0478458b…，与包钉值一致。
3. **审批 key 直查在位** ✓：注册表回读中 memory.write_approval／skills.write_approval 两条按 key 在位（surface=machine、value 已解析、default=true）；写闸活证 GET /v1/write-gate/status 回 gate.memory=true／gate.skills=true，审批执行链未受影响（写闸走上游 config、与注册表 surface 无关，源码先行核实＋活证双证）。
4. **内存** ✓：重启后 50%、收尾复查 53%，红线内。
5. **铃铛无异常** ✓：/opt/data/oneday/data.json 中 notification 键出现数改前 8、改后 8，无新增；verify 全跑无通知类红项。

包级核账：verify.sh 在部署机全跑——汇总 齐 72／缺 0／规划中 1／未验 14（未验均为默认不跑的写型探针，与本包无关；与 1.21.0 同口径）；settings-registry-seed 项 seed_ok records=43 extra=0。输出存 `verify-output-1.22.0-applied-20261124.txt`。

## 应用中一跤（已当场关账，留痕防复发）

- scp 落地的新文件权限为 0640（VM 侧源文件模式），而网关进程以 uid 10000 运行、原文件为 0644——重启后注册表端点一度 503（settings_registry_unavailable，模块读不了文件导入失败；以 root 在容器内复现导入却成功，差点误导定因）。`chmod 644` 后端点即恢复（handler 逐请求导入、无需二次重启），五项回读随后全过。教训：经 scp 替换部署文件后必须核对 mode 与原文件一致（0644），或传后立即 chmod 对齐。
- 另：`docker compose up -d` 对「仅 bind mount 文件内容变化」不重建容器，换件后必须显式 restart 并以容器启动时长＋容器内哈希双证生效，不许只看宿主机文件。

## 遗留与边界

- App 侧两件（合并引擎加门：值记录默认不进浏览组；断开连接迁当前服务器页）不在本包，随 App 后续版本；在本服务端改动之后、App 加门之前，根页三行已不再出现（服务端 surface 改离即时生效于现行 App 合并判据）。
- companion 侧无涉（注册表只在网关面）。
