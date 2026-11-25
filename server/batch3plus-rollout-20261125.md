# 服务端三件＋点子 409 应用记录（部署包 2.5.0，2026-11-25）

授权：用户 2026-11-25 01:09 全批（服务端线）＋01:35 待裁池全批（§435 二期、C-3 改服务凭据、点子 409、密钥 scrub＋轮换）。基线：`/root/deploypkg-2.5.0-20261125/baseline/`（config.yaml.pre-2.5.0 `cc6400f7…`、docker-compose.yml.pre-2.5.0 `b95fbcd4…`、api_server.py.pre-2.5.0 `6d9a5d67…`、oneday_seg_ideas_gen.py.pre-2.5.0 `d8f2cb76…`，均已回读对账）。应用前内存 53%（红线 80%）、/v1/runs 无在飞真实 run。应用后 verify.sh 全量：**110 齐 / 0 缺**（2.4.0 口径 101 齐，新增第 29 节 7 探针全齐＋写型 1 未验为设计内人工项、已于本记录第 3 件活验销账）；health ok；三读面不变（台账 total 991＝completed 951＋failed 34＋cancelled 6、目标 41、动态 API days=3650 口径 23 条／store 原始 29 帖，两口径与应用前一致）。

四件文件面：api_server.py `6d9a5d67…`→`df7b0845…`；oneday_seg_ideas_gen.py `d8f2cb76…`→`07232bc0…`；新增 settings_admin.py `3057cbc2…`、settings_admin_tool.py `7d53eeae…`、settings-admin-config-patch.py、settings_admin_selftest.py。install.sh／verify.sh／manifest.yaml（升 2.5.0）／CAPABILITIES.md（#41–#43）／DEPLOYMENT-GUIDE.md 已同步。传输走直连 ssh（同钥同 ProxyCommand、不经 bt3128.sh 包装）、11 件逐件 sha256 双边一致后才应用。

---

## 件一 · C-3 凭据面改服务端服务凭据（终局）

- **定位结论**：C-3 的「内部 Dashboard 通道令牌化」已于 1.19.0 落地且生产在役——网关各段经 `HERMES_DASHBOARD_SESSION_TOKEN`（64 位）以 Bearer 服务凭据调 Dashboard，模式默认 token。本件开工时现行形态与清单口径的差只剩一处：网关容器 env 仍留 `HERMES_DASH_USER=admin`／`HERMES_DASH_PASSWORD`（长度 20，已验与 Dashboard basic-auth 密码同值），即密码登录回退路径还在。
- **改动面**：现行 compose `/www/dk_project/dk_app/hermes/docker-compose.yml` 摘除该两行（改前另存 `docker-compose.yml.bak-2.5.0-c3`，且基线含整件 pre 副本）。`HERMES_DASHBOARD_BASIC_AUTH_*`（用户本人登录 Dashboard 的上游面）**不动**；包内模板核查无该两行（services/env.template 已同步退役注记）。
- **证据**：容器随本包重建后 `docker exec hermes env` 中两行计数 0（verify 第 29 节 `c3-dash-password-env-retired` 齐）；内部通道照常——台账／目标／动态三读面经该通道回读正常（见卷首数字）。
- **回滚**：自基线 `docker-compose.yml.pre-2.5.0` 或 `.bak-2.5.0-c3` 恢复两行后 `docker compose up -d --force-recreate hermes`。

## 件二 · 密钥 scrub＋唯一真钥轮换（轮换被安全门拦下，只做了 scrub）

### 分发面查实（轮换前置调查，结论：现行不可轮换）
现行真钥＝`API_SERVER_KEY`（64 hex／32 字节，长度达标；`HERMES_API_KEY` 与之同值同源，全包一把）。分发面：
1. hermes 容器 env（compose 字面值）——网关全部端点验钥方；
2. **用户 iPhone 上现行 OneDay App 的 Keychain——存的就是主钥本体**（生产 api_server.py 注释明写：phase-1 凭据仍是共享 API_SERVER_KEY，设备票据是 phase 2 未落；总表 155 短时票据的服务端半边 G1–G3 从未建）；
3. 已退役 companion env 体系（历史落点，见 scrub）。

**拦截原因**：轮换主钥 ⇒ 现行 App 立即断连且无自愈路径（App 无票据换钥通道）。按任务书安全门，本件**只做 scrub、轮换停下**。轮换的正解前置＝先落 155 服务端半边（设备登记＋短时票据签发/校验），App 换票据后再轮换主钥；此项建议单独立项，不在本包范围。

### scrub 执行（先备份登记、后动；明文不入任何记录，只按名/长度登记）
- **服务器侧**：范围＝/root 历史区＋/www/dk_project/dk_app/companion 残留区；live 树 `/www/dk_project/dk_app/hermes/**` 与 /opt/data 整树排除（运行配置本体）。规则：散落的 companion.env* 与 inspect 转储整档删除；deploypkg 基线内文件原位清值（占位 `__SCRUBBED_2.5.0__`）。结果：**删除 66 档、原位清值 95 档、登记 161＋补登 5**（初次全量扫描被 SSH 断线截断，/www 段漏 5 个 .bak 已补登补删）；复查在范围外零命中（仅剩本包活动基线 2 件按设计保留）。登记件在基线内：`scrub-targets-2.5.0.txt`、`scrub-inventory-sha256-2.5.0.txt`。
- **本机主包** `~/workspace/hermes-deploy/`：真钥命中原 3 文件已清——根 docker-compose.yml（改 `${API_SERVER_KEY}` 引用形；dashboard 密码/secret 字面量同改引用形）、data.env（脱敏键名版）、credentials.txt（凭据指针版）。复查包内真钥零命中。
- **本机兄弟预制工地**（15 个 hermes-deploy-* 目录）：credentials.txt／data.env／docker-compose.yml 共 **43 档**同法清值（compose 改引用形、data.env 清值、credentials.txt 的 api_server_key 行改指针）；复查全域（含全部文件类型）`API_SERVER_KEY=<64hex>` 零命中。
- **回滚**：scrub 为单向处置（明文落点本就不该存在）；被删历史档如需追溯，凭基线内登记清单与各 deploypkg 基线副本对账，真值以保险库／实例 compose 为准。

## 件三 · AI 设置权二期服务端半边（§435）

- **改动面**：
  - 新增 `patches/settings_admin.py`——写路径单源：AI 工具面（actor=agent）与用户 App 面（actor=user）共用；白名单写死（agent 写须 writable_by∈{agent,both} 且 reversible；禁区前缀 audit/env/credentials/payments/send/user_data_delete、secret-ref、writable_by=none 一律 `scope_denied`）；审计只追加 `/opt/data/settings/settings_events.jsonl`（id/ts/actor/run_id/action/key/before/after）；撤销＝追加补偿事件恢复 before 值、历史永不改写、撤销不可再撤、重复撤销 409；config-backed 经 hermes_cli.config load/save 兑现＋回读自检，注册表值落快照覆盖层原子替换 0600（种子键仅写 value、一期种子权威口径不变）；surface 登记前过 capability 存活检查（features.* 走回环 /v1/capabilities 查真值）。
  - 新增 `patches/settings_admin_tool.py`——registry-only 工具集 `settings_admin` 七工具（settings_list/get/set/register/delete＋surface_register/remove），照 present_options_tool 打法；check 读总闸。
  - `api_server.py` 增三路由（POST /v1/settings/entries、GET /v1/settings/events、POST /v1/settings/revoke）＋features.settings_admin 位（随总闸取值）＋能力端点表三行。
  - 新增 `settings-admin-config-patch.py` 并已执行：platform_toolsets.api_server 增 `settings_admin` 行、`settings:` 节以 `agent_admin: true` 落盘（改前备份 `config.yaml.bak-settings-admin-*`，脚本自带回读自检）。**本版应用即翻闸、非潜伏**（§435 规格 §5 二期口径，用户 01:35 已批）。
- **证据**：包内自测 settings_admin_selftest.py **38/38**（总闸 fail-closed、43 条读面、config-backed 兑现回读、六类 scope 拒、校验教学错误、登记→改值→删全链、三类撤销、双撤销 409、撤销的撤销 400、审计只追加、capability 离线口径）；settings_registry_selftest 回归全绿。**生产活验**（一次性测试键 agent.acceptance_probe_250）：register→se-000001、set 5→se-000002、set 99 被 `invalid_value` 拒（范围教学）、容器内以 actor=agent 写 user 专属记录被 `scope_denied` 拒、revoke set→值回 1（se-000003）、delete→se-000004、revoke delete→记录带值恢复（se-000005）、清理 delete→se-000006、注册表回 43 条、重复撤销回 `already_revoked`。/opt/data/settings/ 已建（registry.json 0600、settings_events.jsonl 6 行活验史）。features.settings_admin=true 活验在位。
- **回滚**：config 还原备份（摘工具集行＋删 settings 节）＋摘两条新挂载与三路由文件回基线 api_server.py，重启即回一期只读面；已产生的 settings_events.jsonl 与 registry.json 留盘无害（读面不识别二期记录时按一期口径回落种子）。

## 件四 · 点子 409（摘要轮幂等键）

- **定因**：主生成键已是修复形态（`ideas-gen-{日}-{int(started)}`，companion 1.0.74 带入、生产哈希与包钉值一致）；2026-11-24 07:30:58 的 409 是修复前旧账。残留缺陷＝摘要轮键 `ideas-sum-<sha256(sid:messageCount 串)[:12]>`（oneday_seg_ideas_gen.py 原 325 行）：跨轮内容寻址键，载荷含会话标题与摘录，标题变更/摘录漂移/提示词升级都会同键异体 → 409 且永久毒化该队列。
- **改动面**：照主生成键与 feed 同型改轮次 epoch 键 `ideas-sum-{int(_now())}`（轮内稳定、跨轮唯一）；check/rewrite 派生键自主 idem 已唯一，不动。
- **证据**：verify 第 29 节 `ideas-digest-epoch-key` 静态探针齐。应用后经 `hermes cron run` 真实触发点子日轮一轮（2026-11-25 04:04）：主轮以 epoch 键提交被网关受理并建 run（run_9f7209b7…），**无 409**；本轮摘要队列为空（近 14 天会话摘要均已缓存），摘要轮提交路径本轮未被单独行使——其键形态与主轮同型、静态探针在位，待下个有新会话的自然轮补证。该轮最终失败与本件无关：模型 provider 拒绝 API key（`custom rejected your API key`），且同型失败在应用前 02:05／03:05 的轮次已存在，属先存的 provider 配置问题，已单独上报主线（影响生成管线全局，非本包引入）。
- **回滚**：oneday_seg_ideas_gen.py 回基线件（`d8f2cb76…`）重应用即可（键形态回退，数据无迁移）。

---

## 应用过程备忘
- install.sh 真跑途中 SSH 断线一次：查实容器已重建、两条新挂载行已入 compose、后续验收全过，未重跑（断线先查实纪律）。
- settings_events.jsonl 文件权限 644（快照 registry.json 为 600）：审计日志只含设置键与值、无凭据，暂按现状留置；如需收紧为 600 在后续包内处理。
- 本包未动：App 端任何文件、Dashboard 本人登录面、台账/目标/动态数据、cron 计划本身。
