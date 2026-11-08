# OneDay 信息架构（IA）v2 调研定版

2026-11-08。本文只做调研与定版，不含代码。回答用户三问，
每条结论带出处（仓库链接＋仓内文件路径，或官方文档页）；
查不到的写「未查到」，不凭印象补。

## 0 · 结论先行

1. **管理功能进设置页，是竞品主流。** 模型/提供商、密钥、记忆、
   技能、定时、用量——在 LobeChat、Chatbox、Cherry Studio、
   NextChat、LibreChat、Jan、Open WebUI 里全部栖身设置体系。
   v0.1.3 的独立「管理」底栏格是全场唯一的例外形态，应取消，
   六模块并入设置页目录树（定版见 §5.2）。
2. **底栏是少数派，且有底栏的只用 3 格。** 八个开源竞品里只有
   LobeChat 有真移动底栏：聊天／发现（可关）／我，高 48。
   其余（含 ChatGPT、Claude 官方 iOS）皆无底栏，走侧边栏或
   抽屉＋底部账号行。OneDay 定版 3 格：聊天／总览／设置（§5.1）。
3. **总览不该是配置回声，应是状态板。** 竞品里有独立监测页的
   只有 Dify（四指标纪律）；其余把用量/状态收进设置或个人页。
   OneDay 的服务端是常驻网关，性质近 Dify 而非聊天壳——总览
   保留，但按「状态＋今日用量＋待办异常」重做（清单见 §5.3），
   数据全部有现成接口，不编。

## 1 · 方法

逐个进 GitHub 仓库看源码目录、设置页组件、官方截图与自带文档：
导航结论优先取源码实证（组件/枚举/路由文件），截图次之，
第三方文章只作旁证。两个锚对象：ChatGPT/Claude 官方 iOS
引用本仓 docs/DESIGN-V2.md §7.1 的实看记录；Hermes Dashboard
取部署实例（hermes.didichou.site，v0.23.0）2026-11-08 登录
实测的左侧栏条目，接口分组以本仓 docs/API-PATHS.txt 与
docs/hermes-0.23.0-openapi.json 存档互证。

## 2 · 竞品对照表

| 产品 | 底栏 | 侧边栏 | 管理功能落点 | 总览/状态形态 |
|---|---|---|---|---|
| Open WebUI | 无 | 左栏：会话/搜索/文件夹；Workspace 与底栏用户菜单为其他入口 | 用户设置含 Connections、Personalization（记忆）、Usage；实例级在 Admin Panel → Settings（Models/Connections 等 18 节）；Workspace 独立放 Models/Knowledge/Prompts/Tools | 无独立总览；Usage 只在设置内 |
| LobeChat | **有，3 格**：聊天／发现（可关）／我，48pt | 桌面左栏：会话列表＋底部用户入口 | 设置枚举 SettingsTabs 含 Provider、ServiceModel、APIKey、Creds、Memory、Skill、Usage、Stats——全在设置 | 无独立总览；Stats/Usage 在设置与个人页 |
| Chatbox | 无（桌面/移动共用一套 renderer，仓库无底栏组件） | 左栏：会话列表，底部 New Chat＋Settings（官方截图实证） | 设置弹窗分组：Models（Model Provider/Default Models）、Capabilities（Memory/Skills/MCP/知识库）、Chat、App、Account——全在设置 | 无 |
| NextChat | 无 | 左栏：会话＋Masks＋Plugins，底部设置图标 | 设置为单页长列表：Access（访问密码＋各家密钥）、模型配置内嵌、Usage（用量）、Sync、Danger——全在设置 | 无；Usage 是设置内一节 |
| LibreChat | 无 | 左栏：会话；底部用户菜单进设置弹窗 | 设置页签 Data 内含 Memory、API Keys；Account 含 Connections；模型为服务端配置＋对话参数侧栏 | 无 |
| Cherry Studio | 无（纯桌面） | 左图标栏＋列表栏，底部设置齿轮 | 设置页集合含 ProviderSettings、ModelSettings、SkillsSettings、TasksSettings（定时）、UsageSettings——全在设置 | 无；UsageSettings 在设置内 |
| Jan | 无（纯桌面） | 左栏：会话；Hub 管模型；底部设置齿轮 | 设置含模型管理、云端提供商（密钥）、硬件、偏好；API Server、MCP 亦在设置/扩展 | 无 |
| Dify | 无（顶部导航：探索/工作室/知识库/工具） | 应用内左栏：编排/访问/日志/标注/监测 | 工作区设置含模型供应商；应用级配置在「编排」 | **有**：监测页四指标（总消息/活跃用户/平均互动/Token 用量）＋趋势 |
| ChatGPT iOS（锚） | 无 | 抽屉 82%：搜索→新建→历史（时间分组）→底部账号行→设置 | 账号/模型/数据控制等在设置内 | 无 |
| Claude iOS（锚） | 无 | 抽屉：新建→目的地行→Starred/Recents→底部账号 chip | 同上，在设置内 | 无 |
| Hermes Dashboard（锚） | 无 | 左栏平铺 17 项：CHAT/SESSIONS/FILES/MODELS/LOGS/CRON/SKILLS/PLUGINS/MCP/CHANNELS/WEBHOOKS/PAIRING/PROFILES/CONFIG/KEYS/SYSTEM/DOCUMENTATION | **无设置页**：每个管理域都是一级页面（MODELS/CONFIG/KEYS/CRON 并列）；状态只在栏脚（网关状态＋活跃会话数＋重启按钮） | 无；状态在栏脚 |

## 3 · 逐家记录（出处）

### 3.1 Open WebUI（github.com/open-webui/open-webui）

- 布局组件目录 `src/lib/components/layout/` 只有 Sidebar、
  Navbar、Search 与各类 Modal，**无底栏组件**；Workspace 是
  一级路由区（Models/Knowledge/Prompts/Tools/Skills）。
- 用户设置组件目录 `src/lib/components/chat/Settings/`：
  About、Account、Advanced、ArchivedChats、Audio、
  Connections、DataControls、General、Integrations、
  Interface、Notifications、Personalization、Shortcuts、
  Tools、Usage——记忆在 Personalization 子目录，用户级
  Connections 直接管提供商地址与密钥，Usage 独立成节。
- 管理员设置目录 `src/lib/components/admin/Settings/`：
  General、Authentication、Connections、Models、Documents、
  Images、Audio、Interface、WebSearch、CodeExecution、
  Pipelines、Database、Evaluations、Events、
  ExternalKnowledge、Integrations、Apps、Subagents、I18n，
  挂在 Admin Panel 的 Settings 页签下（Admin Panel 另有
  Users/Evaluations/Functions 页签）。

### 3.2 LobeChat（github.com/lobehub/lobehub）

- 移动底栏源码 `src/routes/(mobile)/_layout/NavBar.tsx`：
  items 写死三项——MessageSquare「tab.chat」→ /agent；
  Compass「tab.community」→ /community（showMarket 特性
  开关控制，可整项隐藏）；User「tab.me」→ /me。高度常量
  MOBILE_TABBAR_HEIGHT = 48
  （`packages/const/src/layoutTokens.ts`）。
- 设置页签枚举 `src/store/global/initialState.ts` 的
  SettingsTabs：About、Advanced、APIKey、Appearance、
  Billing、Common、Connector、Credits、Creds、Devices、
  Environments、Hotkey、Integrations、Labels、Labs、LLM、
  **Memory**、Messenger、Notification、OAuthApps、Plans、
  Profile、**Provider**、Proxy、Referral、Security、
  **ServiceModel**、**Skill**、**Stats**、Storage、
  SystemTools、Tools、Trash、TTS、**Usage**。
  提供商、密钥、凭据、记忆、技能、用量、统计全是设置页签。
- 个人页旧枚举 ProfileTabs 同样含 APIKey、Memory、Stats、
  Usage——用量与统计栖身「我/设置」，不设独立总览页。

### 3.3 Chatbox（github.com/chatboxai/chatbox）

- 官方桌面截图 `doc/statics/demo.png`（仓内）：左栏 CHAT
  会话列表，栏底自上而下「+ New Chat」「⚙ Settings」，
  无底栏；移动端与桌面共用 `src/renderer/` 一套代码
  （Sidebar.tsx、pages/SettingDialog/），仓库内无底栏组件。
- 设置导航源码 `src/renderer/components/settings/settingsNav.tsx`
  分组写死如下：Account（Chatbox AI）；**Models**
  （Model Provider、Default Models）；**Capabilities**
  （Web Search、MCP、Knowledge Base、Skills、
  Agent & Memory／Memory、Document Parser）；Chat（Chat、
  Context & Compaction）；App（Appearance、Keyboard
  Shortcuts、Data & Backup、Advanced、About & Updates）。
  模型、密钥（在 Model Provider 内）、记忆、技能全在设置。

### 3.4 NextChat（github.com/ChatGPTNextWeb/NextChat）

- 侧栏源码 `app/components/sidebar.tsx`：会话列表之外，
  Masks、Plugins 是一级入口，底部 Link 直达 Path.Settings。
- 设置页源码 `app/components/settings.tsx` 为单页长列表，
  分组键（Locale.Settings.*）含 Avatar、**Access**（访问
  密码＋各提供商密钥/端点，模型配置组件 model-config.tsx
  内嵌本页）、Theme、Lang、FontSize、FontFamily、Prompt、
  Mask、**Usage**（用量汇总）、Sync（WebDav/UpStash）、
  Danger（Reset/Clear）。无底栏、无总览页。

### 3.5 LibreChat（github.com/LibreChat-AI/LibreChat）

- 设置页签源码 `client/src/components/Nav/Settings/types.ts`
  的 TABS 定义：General（Appearance/Layout/Notifications/
  Accessibility/Admin）、Chat、Speech、Langfuse、**Data**
  （**Memory**、Code Execution、Data、**API Keys**、
  Danger Zone）、Account（Profile、Security、
  **Connections**、Billing、Danger Zone）、About。
- 模型与提供商不在用户设置里：服务端配置文件决定端点，
  单次对话参数走对话右侧参数栏——这是「按会话调」而非
  「全局配」的取舍，与 OneDay 的服务端全局模型不同科，
  只作例外记录（§4）。

### 3.6 Cherry Studio（github.com/CherryHQ/cherry-studio）

- 设置页目录 `src/renderer/pages/settings/` 实查含：
  ProfileSettings、**ProviderSettings**（提供商与密钥）、
  **ModelSettings**、GeneralSettings、AppearanceSettings、
  DataSettings、McpSettings、**SkillsSettings**、
  **TasksSettings**（任务/定时）、**UsageSettings**（用量）、
  WebSearchSettings、ChannelsSettings、ToolSettings、
  PromptSettings、NotificationSettings、VoiceSettings、
  FileProcessingSettings、DeviceConnectionsSettings、
  ArchiveSettings、AboutSettings。纯桌面应用，无底栏；
  模型、技能、定时、用量无一例外全在设置页集合内。

### 3.7 Jan（github.com/janhq/jan）

- 官方文档即仓内 `docs/src/pages/docs/desktop/settings.mdx`：
  设置含 Model Management（导入/删除/启动模型、Hugging
  Face Token）、单模型齿轮设置、Hardware、Preferences
  （Interface & Theme、Spell Check、Jan Data Folder、
  HTTPS Proxy、Factory Reset）；云端提供商密钥见同目录
  `remote-models.mdx`，本地 API Server 见 `api-server.mdx`。
  纯桌面，左栏＋底部设置齿轮，无底栏、无总览页。

### 3.8 Dify（github.com/langgenius/dify）

- 应用详情路由 `web/app/(commonLayout)/app/(appDetailLayout)/[appId]/`
  实查子路由：configuration、workflow（编排）、access-config、
  deploy（访问）、logs（日志）、annotations（标注）、
  **overview（监测）**——监测与日志、编排并列一级。
- 官方文档《Dashboard》（docs.dify.ai/en/self-host/use-dify/monitor/analysis）：
  监测页四指标——Total Messages、Active Users、Average
  User Interactions、Token Usage，配时间选择器看趋势；
  数据分析另含 Total Conversations、Token Output Speed。
- 工作区层为顶部导航（探索/工作室/知识库/工具）；模型
  供应商在工作区 Settings 内（官方文档《模型供应商》页，
  本次未逐行实查其设置目录树，此项以文档页存在为准）。

### 3.9 锚对象（已实查，直接引用）

- ChatGPT / Claude iOS：无底栏、抽屉结构与设置落点见
  本仓 docs/DESIGN-V2.md §7.1（App Store 官方截图逐张
  实看＋OpenAI 官方帮助互证），此处不重复展开。
- Hermes Dashboard v0.23.0：左侧栏平铺 17 项（见 §2 表），
  栏脚为「Logged in as admin via basic」＋网关 Running
  状态＋活跃会话 0＋Restart Gateway 按钮（2026-11-08
  登录部署实例逐项记录）；接口分组与之一一对应
  （/api/config、/api/env＝KEYS、/api/cron/jobs、
  /api/memory、/api/skills、/api/sessions、
  /api/analytics/*、/api/system/stats、/api/logs、
  /api/status、/api/gateway/*，见 docs/API-PATHS.txt）。
  它没有设置页，也没有总览页——IA 是把服务端模块清单
  原样平铺成导航，这是运维控制台的原生形态，不是手机
  客户端可照搬的形态。

## 4 · 问题 1 定版回答：管理功能应不应该进设置页

**是主流，且是压倒性的。** 八个开源竞品逐项对位 Hermes
六模块的落点：

| Hermes 模块 | 竞品对应物 | 落点 |
|---|---|---|
| 模型/提供商 | LobeChat Provider/ServiceModel；Chatbox Models 组；Cherry ProviderSettings/ModelSettings；NextChat 模型配置（设置内嵌）；Jan 模型管理；Open WebUI Admin Settings → Models/Connections；Dify 工作区设置 → 模型供应商 | 设置 |
| 密钥 | LobeChat APIKey/Creds；LibreChat Data → API Keys；NextChat Access；Open WebUI Connections（用户级＋管理员级） | 设置 |
| 记忆 | LobeChat Memory；Chatbox Agent & Memory；LibreChat Data → Memory；Open WebUI Personalization（记忆） | 设置 |
| 技能 | LobeChat Skill；Chatbox Skills（Capabilities 组）；Cherry SkillsSettings；Open WebUI Workspace → Skills | 设置（Open WebUI 放 Workspace，见例外） |
| 会话（数据管理） | NextChat Danger（清空）；LibreChat Data（数据控制）；Chatbox Data & Backup；Open WebUI ArchivedChats/DataControls | 设置 |
| 定时 | Cherry TasksSettings | 设置（其余竞品无此功能，无反对票） |
| 用量 | LobeChat Usage/Stats；Cherry UsageSettings；NextChat Usage 节；Open WebUI Usage 节 | 设置 |

**例外只有两类，逻辑都成立、且都不适用于 OneDay：**

1. **内容库型功能被提为一级入口**：Open WebUI 的 Workspace
   （自建模型预设/知识库/提示词/工具）、NextChat 的 Masks/
   Plugins（侧栏一级）。这些东西是「在聊天里天天要取用的
   内容资产」，提级是为了聊天流内的取用效率；纯配置
   （连接、密钥、参数、数据控制）从无一家提级。OneDay 的
   六模块全是配置与运维，不产出聊天内容资产，不适用此例外。
2. **没有设置页的控制台**：Hermes Dashboard 把 17 个域平铺
   一级（§3.9）。它的用户是坐在桌面前的大屏运维者，平铺
   的代价（找）由屏幕宽度买单；手机上平铺即灾难，且
   OneDay 已有底栏＋抽屉的骨架，设置页是现成的收纳层。
   另 LibreChat 把单次对话参数放对话侧栏，那是「按会话
   调参」与「全局配置」的区别，OneDay 管的是服务端全局
   模型，仍归设置。

**结论**：v0.1.3 的「管理」独立格取消；六模块按 §5.2
目录树并入设置页。设置页由此从「连接＋关于」长成完整的
管理中枢，这也正是 Chatbox/Cherry/LobeChat 设置页的体量。

## 5 · 问题 2 定版回答与 OneDay IA v2 定版

### 5.0 底栏格局（证据小结）

- 有真移动底栏的只有 LobeChat：3 格（聊天／发现／我），
  且发现格可被服务端开关整项隐藏——底栏格数在成熟产品
  里是「能少则少」的。
- 其余七家＋ChatGPT/Claude 两锚共九个对象无底栏，靠
  侧栏（桌面）或抽屉（移动）＋底部账号行完成导航分工：
  抽屉管会话，设置管配置，二者都不占屏幕底边。
- Dify 是另一物种：顶部导航＋应用内左栏，监测靠一级
  位置——它证明「状态/监测」在运维型产品里配得上一级
  入口，但它的形态（Web 控制台）不提供底栏样本。

### 5.1 底栏定版：3 格——聊天／总览／设置

| 格 | 内容 | 依据 |
|---|---|---|
| 聊天（第一格、默认落点） | 对话＋会话抽屉（v0.1.3 已定版，不动） | LobeChat 底栏第一格即聊天；两锚的聊天独占同理 |
| 总览 | 服务器状态板（§5.3） | Dify 监测一级入口的移动等价物；Hermes 栏脚状态在手机上无处安放，提为一格 |
| 设置 | 管理中枢（§5.2 目录树） | LobeChat 第三格「我」即设置入口；Chatbox/Cherry 设置均由固定角落入口到达 |

- 「管理」格取消：其内容按 §4 并入设置。底栏由 4 格收
  到 3 格，与唯一的移动底栏样本（LobeChat 3 格）对齐；
  顺序「聊天第一、设置最后」与 LobeChat（Chat…Me）一致。
- 取舍记录：总览占一格而非塞进设置，是因为 OneDay 的
  服务端是 24 小时常驻网关，「它还活着吗、今天烧了多少」
  的查看频率高于任何配置修改——此判断与 Dify 把监测与
  编排/日志并列一级同构。若日后数据证明总览打开率低，
  可再议降入设置，本版先按运维型产品定版。

### 5.2 设置页目录树（定版）

分组逻辑借 Chatbox 的 settingsNav 分组法（Account /
Models / Capabilities / Chat / App）与 Cherry 的设置页
集合，按 OneDay 的服务端对象改写为五组。条目后标注目标
接口（全部已存档于 docs/API-PATHS.txt / openapi）：

```
设置
├─ 服务器
│  ├─ 当前服务器（名称＋地址＋状态点）→ 连接详情
│  │    服务器地址 / 面板账号 / API 密钥（掩码，可 reveal）
│  │    重测连接（三步探活）/ 切换服务器（多服务器预留位）
│  ├─ 档案 Profile（当前档案名 → /api/profiles 列表与切换，
│  │    切换走 /api/profiles/active）
│  └─ 断开连接（destructive，确认后清凭据回连接页）
├─ 模型与密钥
│  ├─ 对话模型（当前模型名 → 模型管理：默认模型切换与
│  │    提供商清单，读写 /api/config；提供商增删改）
│  ├─ 密钥（/api/env 列表：增 / 改 / 删，POST /api/env/reveal
│  │    查看明文；凭据池 /api/credentials/pool 二期）
│  └─ 用量（摘要行：今日 Token / 今日请求 → 用量页：
│       /api/analytics/usage?days= 与 /api/analytics/models，
│       按日趋势＋按模型分布）
├─ 智能体
│  ├─ 记忆（当前提供方名 → /api/memory：提供方切换、
│  │    各提供方配置、重置）
│  ├─ 技能（/api/skills：已装列表、开关 toggle、内容查看；
│  │    技能商店 /api/skills/hub 搜索安装，二期）
│  ├─ 定时任务（/api/cron/jobs：列表含启用态与下次运行、
│  │    新建/编辑、暂停/恢复/立即触发、运行记录
│  │    /api/cron/jobs/{id}/runs）
│  └─ 会话数据（服务端会话 /api/sessions：列表、删单条、
│       清空空会话；本机会话：清空本机聊天记录）
├─ 网关
│  ├─ 网关状态（运行状态＋版本＋config_version，
│  │    数据 /api/status）
│  ├─ 重启网关（POST /api/gateway/restart，二次确认；
│  │    停止/启动 /api/gateway/stop|start 收进详情页）
│  └─ 日志（/api/logs?level=&component=&lines=：
│       级别/组件筛选、搜索，只读）
└─ 关于
   ├─ App 版本（0.1.x / build）
   ├─ 服务端（Hermes 版本、release_date、服务器时间口径）
   └─ 隐私与许可（数据只存本机 Keychain 的说明、开源许可）
```

- 深度纪律：设置首页只到「组＋条目行（名称＋当前值
  摘要）」一层，实际改动进二级页——与 LobeChat 设置
  页签、Chatbox 设置分组同构，避免 v0.1.2 设置页那种
  「一页摊平三组信息」的浅结构。
- 危险动作（断开连接、删密钥、重置记忆、重启网关）
  一律 destructive 呈现＋二次确认，沿 v0.1.2 已定口径。

### 5.3 总览页重做清单（问题 3）

现状问题：只有版本/网关/模型几行配置回声，下半屏全空。
竞品参照：独立监测页只有 Dify（四指标＋趋势，§3.8）；
Hermes 本体把状态压在栏脚（网关状态＋活跃会话数）。
OneDay 总览按「状态头＋今日四数＋运行面＋异常面＋快捷
动作」五段定版，每段标注数据来源，全部现成接口：

| 段 | 指标 | 来源接口 |
|---|---|---|
| 状态头（保留现签名排版） | 网关状态（运行/停止/异常）、各平台连接态（gateway_platforms 逐项 state）、服务端版本 | GET /api/status |
| 今日四数 | 今日消息数、今日会话数、今日 Token、今日请求/错误数（四数取接口实有字段，无的字段不上） | GET /api/analytics/usage?days=1 |
| 用量趋势 | 近 7 日 Token 走势（简图）、按模型分布 Top 3 | GET /api/analytics/usage?days=7、GET /api/analytics/models?days=7 |
| 运行面 | 活跃会话数、定时任务（总数/启用数/下一次运行时间）、当前记忆提供方、系统资源（CPU/内存/磁盘，接口给什么用什么） | GET /api/sessions（计数）、GET /api/cron/jobs、GET /api/memory、GET /api/system/stats |
| 异常面 | 最近异常 3 条（error 级日志摘要）、任一平台 state≠connected 时置顶警示、出口状态异常提示 | GET /api/logs?level=error&lines=50、GET /api/status、GET /api/egress/status |
| 快捷动作 | 重启网关（二次确认）、去定时任务、看日志——深链到 §5.2 对应设置页 | POST /api/gateway/restart 等 |

- 刷新口径：进页拉取＋下拉刷新；状态头可低频轮询
  （建议 30 秒，仅前台），其余段落跟随手动刷新，
  避免无意义的后台请求。
- 空态纪律：某段接口失败只降级该段（行内错误＋重试），
  不整页报错——沿总览页现有分段报错口径。
- 不上的东西：配置项回声（工具集、providers 键名清单
  等 M1 摘要）退出总览，归设置页模型管理；总览只留
  「活着吗、花了多少、有什么毛病」三类信号，对齐 Dify
  监测页的信息性质。

## 6 · 与 v0.1.3 现状的差异清单（施工时的变更面）

1. 底栏 4 格 → 3 格：删「管理」格；格序改为
   聊天／总览／设置（现序为聊天/总览/管理/设置）。
2. 管理页六个占位入口整体迁入设置页 §5.2 目录树，
   「管理」页本体删除；里程碑 2 的施工对象由「管理页」
   改为「设置页二级页群」。
3. 设置页按 §5.2 五组重排，现三组（服务器/连接/关于）
   中：服务器组并入新「服务器」组，连接组拆入服务器
   （重测）与网关（状态）两组，关于组保留并补服务端行。
4. 总览页按 §5.3 五段重做，配置摘要段（平台/配置两组
   GroupBox 中的配置组）移除，平台连接态并入状态头。
5. 聊天页与会话抽屉不动（DESIGN-V2 §7 定版继续有效）。

## 7 · 出处索引

- Open WebUI：github.com/open-webui/open-webui —
  src/lib/components/layout/、src/lib/components/chat/Settings/、
  src/lib/components/admin/Settings/
- LobeChat：github.com/lobehub/lobehub —
  src/routes/(mobile)/_layout/NavBar.tsx、
  packages/const/src/layoutTokens.ts、
  src/store/global/initialState.ts（SettingsTabs/ProfileTabs）
- Chatbox：github.com/chatboxai/chatbox —
  src/renderer/components/settings/settingsNav.tsx、
  doc/statics/demo.png、src/renderer/Sidebar.tsx
- NextChat：github.com/ChatGPTNextWeb/NextChat —
  app/components/settings.tsx、app/components/sidebar.tsx、
  app/components/model-config.tsx
- LibreChat：github.com/LibreChat-AI/LibreChat —
  client/src/components/Nav/Settings/types.ts
- Cherry Studio：github.com/CherryHQ/cherry-studio —
  src/renderer/pages/settings/
- Jan：github.com/janhq/jan —
  docs/src/pages/docs/desktop/settings.mdx、remote-models.mdx、
  api-server.mdx
- Dify：github.com/langgenius/dify —
  web/app/(commonLayout)/app/(appDetailLayout)/[appId]/ 路由目录；
  docs.dify.ai/en/self-host/use-dify/monitor/analysis
- 锚对象：本仓 docs/DESIGN-V2.md §7.1（ChatGPT/Claude）；
  docs/API-PATHS.txt、docs/hermes-0.23.0-openapi.json、
  docs/M2-DISCOVERY.md（Hermes 接口与面板结构）
