# OneDay ＋ Hermes 自部署完整指南（单容器终局，包 2.5.0）

> 读者：拿到 OneDay 的自部署用户，以及部署者本人重装/迁移时照单执行。
> 口径：本文所有步骤与事实均出自部署包的部署档案与实测记录（出处见文末），按双容器收口后的定版形态编写。档案里查不到的一律写「未记录」，不补想象。标注「窗口回填」的条目是尚未实测的步骤——回填实测结论之前不要把它们当成已验证事实。
> 安全：本文不含任何真实密钥值。所有密钥只写名称、存放位置与持有方。
> **终局注记（包 2.0.0，2026-11-25，断桥批五）**：断桥五批已全部完成——write-gate（批二）、overview/oneday（批三）、fileproc（批一）、device（批五）全部职能入网关模块，**companion 伴生容器已整下线退役，部署终局为 hermes 单容器**。全文已按终局改写：凡写 companion 在役的旧文均已清改，companion 相关章节只保留退役说明与历史出处。连带状态：identity（8648）与 front 伴生面板（8650）随 companion 下线暂停，已于包 2.3.0（断桥批四）入关恢复；fileproc 桥口（8652）职能已在网关（批一）。应用与回滚见 bridge-teardown-rollout-20261125.md。
> **2.1.0 注记（2026-11-25）**：台账 job 状态口径修复（§475）——网关启动结算孤儿 job 条目、三类轮次（动态/点子/简报）完成口径改「交付齐即完成」；仅换 oneday_ledger_lib／oneday_seg_ledger／oneday_seg_feed／oneday_seg_ideas_gen／oneday_seg_briefings 五文件，架构与路由零变化。应用与回滚见 ledgerfix-rollout-20261125.md。
> **2.3.1 注记（2026-11-25）**：§441 选项卡时序修复——翻闸后真实流量下选项卡不落（终态行由交付提交才落库、attach 首查无行静默丢卡），api_server_runs.py 单文件改首试同步＋守护线程限时重试补贴、丢卡路径全量 warning 留痕；翻闸状态（display.options_card＋工具集 options_card）不回退。应用与回滚见 options441-timingfix-20261125.md。2.3.1 修订一（应用当日）：真实复验又抓获 run_key 绑定断链（handler 登记完整会话键、attach 等值比对裸 run_id 恒不符，1.15.0 自反应同款），改自验事实绑定，同版号重应用。
> **2.4.0 注记（2026-11-25）**：G1 任务侧失败覆盖——overview_gateway.py 增 cron_failed／kanban_failed 两读时聚合源（cron 按 cron_incidents 开放事故一条、kanban 按任务最新终态 run 一条；born unread 计入未读；error 一行去敏；cron_since/kanban_since 基线防回灌）。应用与回滚见 g1-rollout-20261125.md。
> **2.5.0 注记（2026-11-25）**：服务端三件＋点子 409——①§435 二期服务端半边：新增 settings_admin／settings_admin_tool 两模块与 settings-admin-config-patch.py（工具集登记＋总闸 settings.agent_admin 应用即翻 true，非潜伏），api_server 增设置写/审计/撤销三路由；②点子摘要轮幂等键改轮次 epoch；③C-3 终局：instance compose 摘 HERMES_DASH_USER／HERMES_DASH_PASSWORD（内部通道只剩会话令牌服务凭据）＋全机明文真钥 scrub；唯一真钥轮换经安全门拦截未执行（原因见应用记录）。应用与回滚见 batch3plus-rollout-20261125.md。
> **2.3.0 注记（2026-11-25）**：断桥批四·identity/front 入关——identity 桥（8648）与 front 桥（8650）拆壳为网关模块 identity_gateway／front_gateway，8648/8650 两面经 nginx 改指 8642 恢复；identity 数据家 data/identity/、front 登记 data/front/；改名写口保持关停（仅 MCP identity_set_name 进程内直调）；NEWAPI 管理三件未配时 gateway-channels 回诚实 503。预制的 companion 半边（升版/摘面/面板退役）因 companion 已于 2.0.0 整容器退役而整体作废，本版只做网关半边。应用与回滚见 batch4-rollout-20261125.md。2.3.0 修订一（应用当日）：identity 适配器路径重建修复（正口/保形口 name/avatar 面初版落 404），同版号重应用。
> **2.2.0 注记（2026-11-25）**：§441 选择框服务端潜伏（总表 203）——选择框机器全量入关：api_server 投影＋能力位、api_server_runs 终态 attach、历史投影平齐，及 options_pending／present_options_tool 两新模块；但 display.options_card 闸默认关、options_card 工具集未启用，行为与 2.1.0 逐字一致。翻闸（设 display.options_card=true＋platform_toolsets.api_server 增 options_card＋重启）是独立一步，届时才真正产卡。应用与回滚见 options441-rollout-20261125.md。
> **凭据单源（终局已达成）**：全栈只剩一把钥——Hermes 本体的 `API_SERVER_KEY`：网关全部端点（含 device 面）都验这把钥，包内任何新面不另设钥；`verify.sh`/`install.sh` 亦从 hermes 容器环境回读同一把钥。各桥钥（WRITE_GATE/OVERVIEW/BOX/ONEDAY/DEVICE_BRIDGE_KEY）与 companion.env 已随各批作废。第三方服务钥（搜索/模型等）与 Dashboard 登录口令属外部/上游面，不在此列。
---

## 1. 架构总览

部署面只有一个容器：**Hermes 本体**。原先五个独立桥先收编为伴生（companion）容器内的模块、再经断桥五批逐个拆壳入网关成为网关进程内模块（批一 fileproc、批二 write-gate、批三 oneday/overview、批四 identity/front、批五 device），companion 已于包 2.0.0 整容器退役。模型网关是可选件，不用网关的部署就是纯单容器。

```
┌─────────────┐   HTTPS，只带一把「Hermes 登录密钥」
│ OneDay App  │ ───────────────────────────────┐
└─────────────┘                                ▼
                                        ┌────────────┐
                                        │   nginx    │  443 入口，按路径分流
                                        └─────┬──────┘
              ┌───────────────────────────────┴───────────────────────────────┐
              ▼                                                               ▼
     ┌─────────────────┐         ┌──────────────────────┐
     │ Hermes 网关 8642 │         │ Dashboard 9119        │
     │ /v1、/api、runs  │         │ /api/files、/api/config│
     │ ＋全部入关模块    │         └──────────────────────┘
     │ （write-gate/    │
     │ oneday/overview/ │
     │ fileproc/device） │
     └────────┬────────┘
              │  model.provider=custom，base_url 指向网关
              ▼
     ┌─────────────────┐        ┌──────────────────┐
     │ New API 网关     │ ─────► │ 上游渠道（渠道＝一家服务商）│
     │ 172.18.0.1:3000 │        │ 现行：渠道 14＝DeepSeek 官方│     （网关为可选件）
     └─────────────────┘        └──────────────────┘
```

各业务面入网关后，nginx 一律**透传** App 带来的单钥（`Authorization $http_authorization`）、不再挂 `auth_request`、不再换钥：鉴权由网关与各模块自验 `API_SERVER_KEY`（凭据单源，见文首注记）。桥时代的 auth_request＋换钥机制已随各批退役，线上 conf 不再含任何模块钥字面值。

要点：

- Hermes 本体只跟 New API 网关说话；「服务商」在这一层是网关里的**渠道**，不是 Hermes 的配置项（详见 §6、§8）。
- 所有后端端口只绑 `127.0.0.1`，公网只有 nginx 的 443。任何端口直接暴露公网都算部署错误。
- 全部业务面都是网关进程内模块：模块故障只降级对应端点（api_server 回 503），不拖垮网关本体；模块清单与能力位见 CAPABILITIES.md。

## 2. 前置条件

| 项 | 要求 | 缺了的症状 |
|---|---|---|
| 服务器 | Linux＋Docker＋docker compose。本机实测：内存总量约 7.7 GB 跑全栈（Hermes 2 GB 上限）常态占用约 50%（companion 退役后口径） | 内存吃紧时容器被杀、模块随机 502 |
| 内存红线 | **任何施工/部署动作前先查内存，使用率超 80% 立即停手**（本机 2026-10-12 有过构建＋浏览器把负载打爆、SSH 中断的事故） | 边施工边把生产打挂 |
| 域名＋HTTPS | 一个域名解析到服务器、443 证书有效（本机为宝塔签发/自动续期）。App 的全部公网流量走 HTTPS | App 连不上、iOS ATS 直接拒绝明文请求 |
| Hermes 版本 | **钉版 v0.23.0**，镜像 `nousresearch/hermes-agent:v0.23.0`。本文涉及的内部接口（会话 API、模型锁、MCP 形态）均按此版实测；升级前必须回归 §10 验收清单 | 版本漂移后 Dashboard 内部接口形状可能变，App 某些面静默失效 |
| 时间/时区 | 容器统一 `TZ=Asia/Shanghai`（本机口径；异地自部署可自选，但全栈须一致） | 定时作业（点子生成、晨报、周简报）触发时刻错位 |

## 3. 服务端组件清单

成套 compose 模板在部署包 `services/hermes-compose.template.yml`（只有 hermes 一条服务；全量模块挂载由 install.sh 幂等补齐）。全新部署的目录组只有 `data`（Hermes 数据，内含各入关模块的数据子目录：oneday/、overview/、device/、write-gate/、identity/、front/ 等）。companion 时代的 `companion.env`、`companion-state` 与各桥 data 目录均已退役（device 数据已迁入 `data/device/`，属主须为容器内 hermes 用户 uid 10000——以 root 拷贝后必须 chown，否则模块导入即失败，批五实证）。

构建与启动：

```
bash install.sh <部署目录>                   # 补丁/模块/挂载幂等应用＋服务级重启＋健康检查
docker compose up -d hermes                  # 只许服务级 up（compose 内 legacy 桥服务定义勿整表拉起）
```

| 组件 | 作用 | 端口（回环） | 部署形态 | 健康检查 | 缺失症状 |
|---|---|---|---|---|---|
| hermes（网关＋Dashboard） | 对话、会话、模型锁、文件面、配置面、MCP 客户端宿主 | 8642（API）＋9119（Dashboard） | compose 服务，镜像 v0.23.0，`gateway run`，mem 2 GB | `GET /health`（公开）→200；带登录密钥 `GET /v1/models`→200 | 全部功能不可用 |
| oneday-companion（伴生容器） | **已于包 2.0.0（2026-11-25，断桥批五）整容器退役**：容器已删、compose 换墓碑空定义、companion.env 作废；末代镜像保留标签 `oneday/companion:pre-2.0.0-baseline` 供回滚 | — | — | `docker ps` 无此容器即为终局形态 | 若它又出现＝有人误拉起旧定义，按 bridge-teardown-rollout-20261125.md 处置 |
| — 模块·write-gate（审批） | 记忆/技能写入的待审批队列与裁决账本（decisions.jsonl）；**已入关**（批二，网关模块 write_gate_gateway） | 网关 8642 的 /v1/write-gate 与保形口 /api/write-gate | 网关进程内模块 | `GET /api/write-gate/status`（带单钥）→`{supported:true, counts:{...}}` | App 待审批角标与审批面失效；智能体写记忆/技能无闸门 |
| — 模块·overview（总览通知） | 聚合 Hermes 在线状态、待审批数、通知流；**已入关**（批三，网关模块 overview_gateway） | 网关 8642 的 /api/overview-bridge/* 与 /overview-mcp | 网关进程内模块 | `GET /api/overview-bridge/overview`（带单钥）→200 | 枢纽总览数与通知流空白/陈旧 |
| — 模块·box（云电脑） | 把 Simular Box 云电脑能力转成 App 可消费的接口；companion 侧 box 模块早已不在末代伴生注册表内（1.0.77 注册表仅 device/identity/front/fileproc 四模块），App 电脑面以 Hermes 侧 Box MCP 注册为准（§7） | —（Hermes MCP 直连厂商） | Hermes MCP 注册 | `hermes mcp test box` | App「电脑」面不可用时先查 Hermes 侧注册与厂商连通性 |
| — 模块·oneday（目标点子） | 目标/点子/监测/动态流（/feed）＋简报（brief）＋调度（点子每日 07:30、晨报 08:30、简报周一 08:00）；**已入关**（批三，网关模块 oneday_gateway＋16 分段） | 网关 8642 的 /api/oneday-bridge/*（66 路由）与三 MCP 门面 | 网关进程内模块，数据为单文件 data/oneday/data.json | `GET /api/oneday-bridge/health`（带单钥）→`{ok:true}`，且 `degraded:false` | 动态/点子/目标三页空白；定时产出停摆 |
| — 模块·device（手机设备） | 智能体与手机之间的工具调用中转：会话注册/心跳/长轮询＋MCP 门面（**53 个工具**，2026-11-25 对在役桥注册表逐名对账）；**已入关**（批五，网关模块 device_gateway＋device_sync）；同步副本存五数据集（sync.db），审计只存元数据、**不存设备数据本体** | 网关 8642 的 /api/device-bridge/* 与 /api/device-mcp；数据目录 data/device/（DEVICE_DATA_DIR） | 网关进程内模块 | `GET /api/device-bridge/health`（免鉴权）→`{ok:true}`；设备会话全环冒烟（见 §10） | 智能体调不了手机日历/提醒/通讯录；目录里设备组显示离线 |
| New API 网关（可选） | 模型流量网关：渠道调度、计费统计、令牌管理 | 内网地址（按部署填写） | 独立容器，管理面为独立子域名站点 | 管理面可登录；用网关令牌 `GET /v1/models` 应列出渠道提供的模型 | Hermes 能连但每轮对话报错/无模型可用 |

规划中、尚未上线的组件（不要按已部署对待）：

- **工作台账**：已上线形态为网关 oneday 模块的台账面（JSONL 事件账，见能力 #31/#34），本条旧规划注记作废。
- **oneday 模块的 MCP 门面**：已随批三入关注册（goals/feed/library 三门面，见能力 #31）。

## 4. nginx 路由全表

站点：`hermes.example.com`（443）。下表为现行全量路由；每条改动前必须备份站点 conf（命名 `hermes.example.com.conf.bak-<日期>-<事项>`，0600），`nginx -t` 通过才 reload。

| 路由 | 转发到 | 为什么需要 | 缺了 App 哪项坏 |
|---|---|---|---|
| `/v1/` | 8642 | 对话主通道（runs 任务制发送、模型清单验钥） | 聊天发不出、登录验不过 |
| `= /health` 与 `/health/` | 8642 | App 与监控的存活探针 | 连接状态恒显异常 |
| `/`（其余全部） | 9119 Dashboard | 文件面 /api/files、配置面 /api/config、会话管理等 Dashboard 接口 | 文件页、设置里的管理面全坏 |
| `= /api/sessions`（精确匹配，仅 POST） | 8642 | **建会话只存在于网关面**；Dashboard 面只有 GET，App 打过去必 405 且曾被静默吞掉（2026-11-10 串话事故根因） | 旁聊建不出真会话、多条对话串进同一条——这是全表最不能缺的一条 |
| `/api/sessions/{id}/model`（2026-11-10 新增，用户批准） | 8642 | 会话内切换模型的模型锁端点只在网关面，公网原本无路由 | 在对话里换模型无反应/失败；验收方法见 §10 |
| `/api/write-gate/` | 8642 网关保形口（透传单钥，批二入关） | 审批模块入口 | 待审批面失效 |
| `/api/overview-bridge/` | 8642 网关保形口（透传单钥，批三入关） | 总览模块入口 | 总览与通知失效 |
| `/api/box-bridge/` | **已退役**（companion box 模块不在末代注册表内；App 电脑面走 Hermes 侧 Box MCP，见 §7） | — | — |
| `/api/oneday-bridge/` | 8642 网关保形口（透传单钥，批三入关） | 目标点子模块入口 | 动态/点子/目标失效 |
| `/api/device-bridge/` | 8642 网关保形口（透传单钥、摘 auth_request；read_timeout 120 s、关 buffering；批五入关，模板 services/nginx-batch5-device-shape.conf） | 设备模块 App 通道（长轮询一轮最长 25 s，超时必须大于它） | 设备会话连不上、智能体调用到不了手机 |
| `= /api/device-mcp` | 8642/api/device-mcp（批五改指） | 设备 MCP 门面的公网入口（Hermes 侧现行走 127.0.0.1:8642 回环直连，见 §7；本公网面供 App/外部） | 智能体调不了设备工具（App 侧目录会如实标注） |
| `/companion/` | **已退役**（包 2.0.0：front 随 companion 下线，待批四入关后另定形态） | — | — |
| `/api/companion/` | **已退役**（同上；App 的伴生探测在此期间无应答属预期，见 §9） | — | — |

桥时代的 auth_request＋换钥机制已全部退役（批一至批五）：现行所有业务路由都是透传单钥、模块自验，线上 conf 不再含任何钥字面值；conf 文件权限仍保持 600（历史纪律，其他段落可能含敏感配置）。

companion 两条路由已随批五退役，本节旧注记（M1 不挂门定版）只作历史，见包内版本注记。

> 历史形态备忘：四桥曾有「旧桥钥直通」的过渡双模，2026-11-10 用户批准撤销、回归严格单钥。新部署不要复刻双模。

## 5. 凭据与密钥清单（只有名目，没有值）

**总原则：用户永远只持有一把密钥——Hermes 登录密钥。在 App 里登录一次即可，其余凭据全是服务器内部的事，用户不见、不输、不保管。**（面板密码是部署者自设的第二种登录方式，不改变这条总原则，见 §12。）

| 凭据 | 存放位置 | 谁持有 | 轮换方法 |
|---|---|---|---|
| Hermes 登录密钥（API_SERVER_KEY） | 服务器 `/opt/data/.env`（0600）；App 侧 Keychain（键名 api.key） | 用户（经 App）＋服务器 | 改 .env 后重启 Hermes 容器，用户在 App 重新登录一次；旧钥立即失效 |
| Dashboard 基础认证（用户名/密码/secret） | Hermes 容器环境（compose 的 data.env） | 部署者（网页管理 Dashboard 时用） | 改环境后 `docker compose up -d` 重建 hermes 服务 |
| 五把模块服务钥（WRITE_GATE_BRIDGE_KEY / OVERVIEW_BRIDGE_KEY / BOX_BRIDGE_KEY / ONEDAY_BRIDGE_KEY / DEVICE_BRIDGE_KEY） | **全部作废**（断桥各批逐个退役、批五收官）：companion.env 已删、nginx 注入副本已摘，全栈只剩 API_SERVER_KEY 一把钥 | — | 不再轮换；回滚场景按各批 rollout 记录从基线恢复 |
| COMPANION_SERVICE_KEY（伴生内部服务钥） | **已作废**（包 2.0.0，front 随 companion 退役） | — | — |
| 登录密钥的服务端副本（HERMES_API_KEY） | hermes 服务 compose 环境（与 API_SERVER_KEY 同值同源，包 1.21.0 定版）；网关内各模块直读，无 companion 副本（旧 companion.env [global] 副本已随批五作废） | 仅服务器 | 随登录密钥轮换时同步更新 compose 两处同值 |
| 面板密码哈希（scrypt） | **随 front 退役冻结**（状态卷 companion-state 留盘未删，批四入关时再定去留） | — | — |
| MCP_BOX_API_KEY（Simular Box 个人密钥） | `/opt/data/.env`（Hermes 侧 MCP 注册用；旧 companion.env [box] 副本已作废） | 仅服务器 | 在 Box 平台换钥后替换 .env、重启 Hermes 装载 |
| GITHUB_MCP_TOKEN（GitHub 细粒度 PAT 的插值变量） | `/opt/data/.env`（0600），config 只写 `${GITHUB_MCP_TOKEN}` 占位 | 仅服务器；令牌本体由用户在保险库交付 | github.com 令牌页吊销旧令牌→新令牌经保险库交付→改 .env 一行→`hermes mcp test github` 验活 |
| Notion OAuth 令牌组 | `/opt/data/mcp-tokens/`（0600 文件组） | 仅服务器（Hermes 本体托管刷新） | `hermes mcp reauth notion` 重新授权；全清删该目录下 notion* 文件 |
| New API 网关令牌「hermes」 | 网关令牌表（id 67）；Hermes config 的 model.api_key 引用它 | 仅服务器/网关 | 网关管理面重置令牌→同步改 config→验活一轮对话 |
| New API 管理员凭据 | 部署者的密码保险库 | 部署者 | 只在网关管理面操作，**永不进 App、永不下发客户端** |
| 部署凭据账本 credentials.txt | 部署者本机 `~/workspace/hermes-deploy/credentials.txt`（0600） | 部署者 | 历史迁移母本（companion.env 已退役，仅回滚场景用）；不进 git、不经聊天传输 |

companion.env **不在部署档案里留填好值的副本**：模板只有 `companion.env.example`（值全空/占位）；迁移时按账本在服务器内逐项重新生成。

## 6. config.yaml 必备段

文件：`/opt/data/config.yaml`（改前整份备份，如 `config.yaml.bak-<日期>-<事项>`）。两个形状先分清：**磁盘上是嵌套式 YAML**（`model: {default, provider, base_url, api_key}`），**Dashboard 给 App 的是规范化扁平视图**（model 字符串＋顶层 providers/fallback_providers）——给 App 看的永远是后者，写磁盘永远是前者，混用必错。

必备与口径：

- **model 段（唯一模型端点）**：`default: deepseek-flash`、`provider: custom`、`base_url: http://172.18.0.1:3000/v1`（自建 New API 网关）、`api_key:` 填网关令牌。Hermes 只认这一个端点，「提供商」由网关渠道吸收（§8）。
- **providers 顶层键默认不存在，这是正常现象、不是故障**：App 读到空 providers 显示「暂无提供商」属如实呈现。v0.23.0 支持具名 provider 条目（`base_url`＋`key_env`/`api_key`＋`extra_headers` 等，走 Hermes 直连上游、绕过网关），只在明确要直连时才加。
- **auxiliary.vision 钉死 flash**：`auxiliary.vision` 的 provider/model 钉为 deepseek-flash（2026-11-09 落，备份 config.yaml.bak-20261109-auxvision）。看图必须走原生多模态的 flash；其余 auxiliary 槽位（共 20 格）保持 auto（跟随主模型），不要逐个乱钉。
- **默认模型口径**：上游规范名只有两个——`deepseek-flash`、`deepseek-v4-pro`。
- **别名禁令（三条，都是实测教训）**：
  1. `hermes-agent` 是网关别名（`/v1/models` 只回这一个），**严禁进入 App 的模型候选清单**；
  2. `deepseek-chat`、`deepseek-reasoner` 是映射到 flash 的别名，不是规范名，配置与清单里只写规范名；
  3. **严禁在 API 会话里发送「/model xxx」文本切模型**——API 路径不分发斜杠命令，智能体会把这行字当任务去执行（2026-11-09 曾引发一轮 72 次调用的失控 turn）。切模型只走 §4 的模型锁端点或逐请求 `{"model": 名, "provider": "custom"}`。
- **裸 model 字段无效**：`/v1/chat/completions` 只带 model 不带 provider 会被忽略、走全局默认（`direct_model_requests` 默认关）；Hermes 原生会话端点则以会话模型锁为准，优先级：确认锁 ＞ 会话持久化模型 ＞ 逐请求值 ＞ 全局默认。
- **fallback_providers 现状为空列表**（未启用模型级故障转移）；要启用就在 config 里按顺序填备用 provider/model，顺序即转移顺序。
- **gateway.multiplex_profiles**：本机已开（每个 profile 一套独立 config/记忆，按 `/p/<profile>/` 前缀路由，各 profile 须自配 API_SERVER_KEY）。单用户部署用不上，保持默认即可。
- **mcp_servers 段**：见 §7。

## 7. MCP 与外部服务注册

配置形态（v0.23.0 实测）：`config.yaml` 顶层 `mcp_servers.<名>`。HTTP 型＝`url`＋`headers`；OAuth 型加 `auth: oauth`；`url`/`headers` 支持 `${VAR}` 占位、从 `HERMES_HOME/.env` 插值，变量缺失时该条目明确报错、不拖垮整体加载。改完配置后，**运行中的网关在启动时才装载 mcp_servers，须重启一次 Hermes 才进会话**；验活第一点是 CLI 独立进程 `hermes mcp test <名>`（不依赖重启），最终验收是重启后 `GET /api/mcp/servers` 列全。

| 服务 | 形态 | 状态（2026-11-10） |
|---|---|---|
| Simular Box | Hermes 侧 `mcp_servers` 注册厂商端点 `https://mcp.box.simular.ai/mcp`，个人密钥以 `MCP_BOX_API_KEY` 存 `/opt/data/.env`（Hermes 环境变量） | **已注册、在服役**（网关日志有 reconciled added=['box']）。另有伴生的 box 模块以同一密钥直连厂商供 App 电脑面用（§3） |
| GitHub | 配置已写：`url: https://api.githubcopilot.com/mcp/`＋`headers.Authorization: "Bearer ${GITHUB_MCP_TOKEN}"`。**OAuth 路已判死**（GitHub 无动态注册、仅预注册客户端可用），官方正道就是 PAT。PAT 用细粒度令牌、只授权需要的仓库、权限从仓库读写起步 | 配置在位、**只差令牌交付**：用户生成 PAT 存保险库→部署方写入 .env→`hermes mcp test github` 验活（现测报错正是「变量未设置」，形态已被正确识别）——令牌到位与实测结论：**窗口回填** |
| Notion | 配置已写：`url: https://mcp.notion.com/mcp`＋`auth: oauth`。Hermes 本体承载完整 OAuth（发现→动态注册→PKCE→刷新），回调走本机 127.0.0.1 临时端口＋**粘贴回退**（授权后浏览器跳到打不开的 localhost 地址，把地址栏完整 URL 粘回终端即完成），不需要公网回调面。授权范围＝该账号可见的全部页面与数据库（官方无细粒度/只读模式），访问令牌约 8 小时、自动刷新 | 配置在位、`hermes mcp test notion` 已验到「只差授权」（端点可达、OAuth 发现正常）——实际授权与工具清单：**窗口回填** |
| oneday 模块 9B 门面 | 给伴生的 oneday 模块加 `/mcp` 门面（goals_create 等，独立 scope 钥），注册进 `mcp_servers` 后智能体可在对话里直接建目标（goal.source=chat 的模块侧契约已备） | **未注册**——注册步骤与实测：**窗口回填** |
| device（设备模块门面） | `mcp_servers.device`：url 型指向**网关回环** `http://127.0.0.1:8642/api/device-mcp`，Authorization 为单钥 `API_SERVER_KEY`（包 2.0.0 起，改法＝包内 device-mcp-config-patch.py，只动这一条）；门面本体是网关 device_gateway 模块 | **已注册、在服役**：tools/list **53 个工具**（2026-11-25 与退役前在役桥注册表逐名对账一致）；`device_status` 离线如实回离线（在线读真数以 App 设备会话在连为前提，见 §11）；网关启动瞬间 MCP 客户端可能因 8642 未就绪把本条 park、按需重连——与既有各 MCP 同一口径 |

窗口收官的固定顺序（device 已提前办完，余项照旧）：GitHub 令牌到位并 test 验活 → Notion 授权并 test 验活 → 注册 9B 一条 → **重启 Hermes 一次** → `GET /api/mcp/servers` 复验 box/notion/github/device（及新增 9B）同列 → 逐项实调验收。回滚：整份还原 `config.yaml.bak-20261110-mcp1` 并重启，或 `hermes mcp remove <名>` 单条摘除。

## 8. 网关与渠道（New API，可选件）

概念对齐：**渠道＝一家上游服务商的接入点**（一组 base_url＋Key＋可用模型清单）；Hermes 眼里只有一个 custom 端点（网关本身），渠道才是「提供商」。

建立顺序（照此序，乱序必出「连得上但没模型」的假故障）：

1. 在网关管理面**建渠道**：填上游 base_url、上游 Key、在渠道的模型清单里列出要供的模型（名字必须与上游规范名逐字一致，如 deepseek-flash / deepseek-v4-pro）。
2. **测渠道**通过后再建/选**令牌**：本机令牌名为「hermes」，专供 Hermes 使用，不要与他用令牌混用。
3. 把令牌值写进 Hermes config 的 `model.api_key`（§6），base_url 指向网关。
4. 验活：带登录密钥向 Hermes 发一轮最短对话，并到网关日志按 channel_id 对账，确认流量落在预期渠道。

现行状态：启用渠道只有 **14＝DeepSeek 官方**（含 flash 与 v4-pro）；渠道 13（Modal 上的 Qwen）已于 2026-11-10 禁用、该线终结，历史记录里的 Qwen 内容不要再当现行能力部署。渠道优先级/权重在网关管理面调整（管理员操作）。

渠道管理面口径：**管理凭据永不进 App**。App 侧对渠道只做只读展示（模型包规划中、未上线）；启停/优先级/加渠道等写操作，一律经服务端管理面（部署方持网关凭据操作，伴生可代办、App 不持有）。

## 9. App 侧要求

- **服务器地址**：App 内置默认地址为部署域名（本机 `https://hermes.example.com`，构建期写死为默认值，连接屏预填）。自部署分发时这是**必改项**：换成自己的域名并重新打包，不要让别人的 App 连到本机。
- **登录**：欢迎/连接屏用户只填**一把 access key＝Hermes 登录密钥**（§5），不存在「桥钥匙」输入项（那是已被废弃的旧形态，App 内相关设置已整套删除）；凭据存 iOS Keychain。
- **伴生探测**：companion 已退役（包 2.0.0），`/api/companion/info` 无应答属当前预期；依赖 front/identity 的 App 面待批四入关后按新契约恢复，此期间 App 应如实呈现不可用、不许静默坏死。
- **权限用途文案清单**（Info.plist，缺一条对应功能在真机上直接被系统拒）：
  - `NSCalendarsFullAccessUsageDescription`（日历全量访问）
  - `NSRemindersFullAccessUsageDescription`（提醒事项全量访问）
  - `NSContactsUsageDescription`（通讯录查询）
  - `NSPhotoLibraryAddUsageDescription`（图片查看器「下载」存相册，只增不读）
  - 麦克风/语音识别两项文案随语音输入版本加入（该功能未上线，现行包内无此二项——属已知缺项，不是漏配）
  - HealthKit/HomeKit 不靠文案、靠签名权益（见 §11）
- **构建基线**：默认守上架合规——不用私有 API、权限文案齐全、账号删除入口具备（OneDay 终局是 App Store 上架，非侧载终态）。

## 10. 上线验收清单（M1 回归门口径，逐项打勾，含缺失症状）

本清单源自 2026-11-10 双容器切换的回归门。**包 2.0.0 终局口径**：第 1 组钥矩阵与第 2 组端点改走网关保形口＋单钥（路由见 §4 现行表）；第 4 组（面板与伴生本体）整组退役；程序化验收以包内 `verify.sh` 为准（2.0.0 应用时 84 项齐、0 缺，含第 26 节 device 八探针）。以下各组保留历史判据供回滚场景对照。

**第 1 组 · 钥矩阵**（F03 口径：登录钥放行、自钥放行、他钥与无钥必拒）

- [ ] 公网五端点各抽一：write-gate `/api/write-gate/status`、overview `/api/overview-bridge/overview`、box `/api/box-bridge/status`、oneday `/api/oneday-bridge/health`、device `/api/device-bridge/health`——带登录密钥均 200、无钥 401、错钥 401。缺：先查 nginx auth_request 与注入值，再查 companion.env 对应段。
- [ ] 直连服务钥腿：宿主机回环 8643/8644/8645/8646 各带本模块服务钥→200、错钥→401（device 腿由第 5 组的 MCP 门面验，用的就是其服务钥）。缺：监督者分段注入错位，查 companion.env 段名与模块映射。

**第 2 组 · 五端点真数据**（活着≠正常，必须读到真值）

- [ ] write-gate `/status` → `supported=true`、counts 与 App 待审批角标一致。supported=false：模块所处环境不对（Hermes 代码/数据路径没对齐），它只会如实报不支持、不会绕过。
- [ ] overview `/overview` → `hermesUp=true`、activeSessions 为真实会话数、pendingApprovals 与第 1 组的上行一致。对不上：查 companion.env 里登录密钥服务端副本与跨段借钥。
- [ ] box `/status` → 厂商真状态（如休眠/在线）与 Box 名对得上、mcpSession 正常。mcpSession 非 up：查 [box] 段 MCP_BOX_API_KEY 与厂商连通性。
- [ ] oneday `/health` → ok 且 `degraded:false`；meta/brief 可读。为 true：数据文件损坏被隔离降级，先处理 data.json.corrupt-* 再谈功能。
- [ ] device `/health` → ok；App 注册设备会话全环冒烟（session 201 → poll 空回 → heartbeat ok → disconnect 后在线状态转 false）。

**第 3 组 · write-gate 全环**（不许只看 fail-closed，必须真走一遍裁决）

- [ ] 经公网 propose 一条测试记忆 → 返回 pendingId 且真暂存 → pending 列表可见 → 裁决（reject）成功且回 Hermes 原生输出 → pending 清零、decisions 账留痕可读。
- [ ] 对不存在的 pendingId 裁决 → 回真 404（证明裁决端点真响应，不是「不支持」的假成功）。

**第 4 组 · 面板与伴生本体**

- [ ] `/companion/` 登录页 200；**密码登录与密钥登录各走一遍**均能进面板（首次部署先密钥登录设密码，见 §12）。
- [ ] cookie 会话打 `/api/companion/modules`（或任一面板 API）→200；伪造 cookie→401；匿名/错钥打 `/api/companion/info`→401、登录密钥→200。
- [ ] `/api/companion/health` → `ok=true`、五模块全 up、hermesUp=true。ok=false 时 info 明细里看哪个模块 degraded/down，不许拿「容器在跑」交差。
- [ ] 面板自检**只读档全跑**：结果应为全 ok 或仅含已知存量 warn（如「box 未在 config 登记」——Box 走 .env 内置集成、与 mcp_servers 登记是两回事，属存量口径）；出现红项先处理再宣布上线。

**第 5 组 · MCP 在列与实调**

- [ ] `hermes mcp list`：device ✓ enabled（与 box/notion/github 同列；notion/github 的实调状态见 §7 窗口回填）。
- [ ] 经公网 `/api/device-mcp` 完整握手 → tools/list 应为 **53 个工具**（包 2.0.0 口径，与退役前在役桥注册表逐名一致）。
- [ ] 实调 `device_status`：App 设备会话在线时回真状态；不在线时如实回 `{"online": false}`——**回离线是正确行为**，拿旧数据或编数字才算失败。

**第 6 组 · 聊天与会话**（Hermes 面，经公网域名、带登录密钥）

- [ ] `GET /health` → 200。缺：App 显未连接，先查 nginx 与 hermes 容器。
- [ ] `GET /v1/models` → 200（回 hermes-agent 属正常，它只是网关别名）。
- [ ] `POST /api/sessions` 建会话 → **201**。若 405：`/api/sessions` 精确路由丢了（请求落到 Dashboard 面），旁聊会串话——立即按 §4 补路由。
- [ ] 新会话发一轮消息 → 响应 `runtime.model_lock="confirmed"`、模型为所选模型。缺：建会话时没带 `require_model_lock:true` 或模型锁端点异常。
- [ ] 两个不同会话各发一条 → 各自历史互不可见（以服务端 state.db 为准）。若串话：查是否有人绕过会话 API 用无头 completions 拼历史。
- [ ] `POST /api/sessions/{id}/model` 换模型 → 200，下一轮 `runtime.model` 已变。若 404/405：该路由未加或被 Dashboard 兜底吞了。
- [ ] `GET /api/mcp/servers`（重启后）列出 box 与 device；notion/github 及 9B 在窗口办理后应同列——**窗口回填**。

**第 7 组 · 文件面与网关对账**

- [ ] `GET /api/files?path=` 能列 /opt/data 目录（根被锁在 /opt/data，越根应被拒）。
- [ ] App 文件页能聚合出交付物（产出根目录有新文件时列表出现）。缺：先分清是 Dashboard 登录态问题还是产出根本就没文件。
- [ ] 切到 v4-pro 发一轮 → 网关日志该条 channel_id=14、model_name=deepseek-v4-pro（不用网关的部署跳过此项）。对不上：查渠道模型清单与 config 的 model 段。

## 11. 已知边界（不是故障，不要当 bug 修）

- **侧载无可靠推送**：智能体「随时调用」手机设备以 App 在线（设备会话活着）为限；App 被杀/久置后台，工具如实报设备离线，不拿旧数据冒充。在线边界在付费开发者账号＋正规 APNs 到位后重估。
- **HealthKit / HomeKit / 正规 APNs 需付费开发者账号**（$99/年）：健康、家庭两件的签名权益与后台唤醒都卡在这一个账号上；到位前目录里如实标注「待签名权益」，不硬做。同一账号也解开礼记等其他 App 的小组件问题。
- **Google 官方 MCP 处于 Workspace Developer Preview 准入制**：且须自建 Cloud OAuth 客户端、把 Hermes 钉死的 localhost 回调逐字登记——只能由账号本人办，我方只能陪跑清单。另注意官方 Gmail MCP 无发信工具（只能建草稿/打标签）。
- **Spotify 无官方 MCP、Instagram 无官方路径**：维持排除，不要用社区方案冒充官方接入。
- **蓝牙不做（已决）**：iOS 不给第三方 App 系统已配对设备名单，真数据太少。
- **工作台账**：已在网关 oneday 模块上线（见 §3），本条旧注记作废。
- **上次打开排序只有本机记录**：Hermes 文件面没有 atime 字段，App 的「上次打开」是本机记录表，换机清零——与 Muse 的账户级真源有差距，属已知取舍。
- **系统文件边界就是 /opt/data**：App 的服务器文件浏览器根锁 Hermes 数据目录；auth.json、.env 等凭据类文件应禁预览/禁下载/禁删除（文件页 v2 规格已定，施工随该版本）。
- **单容器爆炸半径（终局口径）**：全部业务面同在网关进程内，网关挂＝全停（桥时代 companion 独立存活的隔离性已不存在，换来的是单钥与零桥运维）；模块级故障只降级本面（api_server 回 503），数据都在 data 卷内、与进程解耦。
- **front/identity 待批四**：伴生面板与身份面随 companion 退役暂停（包 2.0.0 的已知后果，用户令下接受），恢复形态以批四规格为准；在此之前不要把这两面的 502/无应答当新故障报。

## 12. 伴生面板使用说明（已退役，历史留档）

> 本节所述 front 伴生面板已随 companion 于包 2.0.0（2026-11-25）下线，以下内容只作历史与回滚参考；批四入关后按新形态另行成文。

- **入口**：`https://<部署域名>/companion/`，只有这一个入口；8650 不对公网裸露。
- **登录（双方式，登录页分段选择、默认密码）**：①密码登录——部署者自设密码，只存 scrypt 哈希；②密钥登录——填 Hermes 登录密钥，front 在服务端验真。任一方式通过后发 `HttpOnly; Secure; SameSite=Strict` 会话 cookie（服务端会话落盘、12 小时滑动过期、容器重启不踢人），写操作另带会话下发的 CSRF 令牌头。两路登录都有限速（连错 5 次锁 5 分钟）；登录失败只回通用提示，细节只进容器日志；密钥不进浏览器存储、不进页面 JS、不进日志。
- **首次部署设密码流程**：初始状态没有密码（哈希为空）→ 先用**密钥登录**进面板 → 在页内设置密码（哈希写入状态卷 `companion-state/password.json`，0600，此后以它为准）→ 退出后用密码登录复验一遍。够不到面板时（或密码遗忘）用服务器侧重置：在伴生工程内跑 `python3 front/front.py --set-password '<新密码>'`（与面板改密同源逻辑、写同一文件）；只想生成哈希填进 companion.env 的部署者用 `--hash-password`。测试/临时密码用完必须清除回未设状态，不许留弱口令在生产（M1 即按此纪律收尾）。
- **五页导览**：**状态总览**（伴生版本＋聚合健康一句话、Hermes 连通、五模块状态点/运行时长/重启计数/内存、资源行、最近自检摘要）；**配置自检**（只读档默认全跑＝§10 第 4 组的程序化版；探针档手动勾选、会真建会话再删并留痕；人工档只给指引不代跑）；**连接管理**（外部连接的凭据自助：清单/创建/验活/断开，与 App 凭据自助共用同一套 `/api/companion/connections` 接口；写凭据走备份→只改目标一行→验活→不过自动回滚）；**模块开关**（经监督者控制通道真开关模块，期望状态落盘、重启不丢；关「审批」模块须二次确认并写明后果——关停期间智能体写记忆/技能无闸门）；**版本对齐**（只两行：Hermes 本体与伴生服务；App 兼容只作伴生行下一句注记。Hermes 实际版本取不到时如实显示「未能自动检测」，不假报）。
- **升级与回滚**：换镜像标签→`docker compose up -d companion`（数据目录与 companion.env 不动，Hermes 不受影响，桥功能在重建的数十秒内暂停）；升级前把旧标签记入 companion-state（last-known-good），回滚改回旧标签再 up。迁移级回滚（如整套退回五容器形态）不在面板内：按部署档案的 M1 备份基线还原（compose/env 归档＋nginx conf 备份→起旧桥→reload→复验，M1 报告 §3 有全录；本机该基线在服务器 `/root/m1-20261110/`）。

---

## 附：本文证据出处

本文内容源自部署包的部署档案与实测记录；实例侧原始档案（部署日记、验收报告与盘点记录）不随分发副本提供。