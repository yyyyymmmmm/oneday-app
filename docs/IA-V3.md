# OneDay 信息架构（IA）v3 调研修订

2026-11-08。本文是 IA-V2.md 的纠正版：上一版竞品集选错了
类别——查的是传统聊天客户端（ChatGPT 类），用户明确指出
OneDay 的竞品是 **Muse 这一类个人智能体产品**。本版按
智能体产品/智能体管理客户端重查，逐条复核 v2 的三条定版，
只出调研与修订建议，不含代码。查不到的写「未查到」。

## 0 · 结论先行

1. **v2 的「管理并入设置」只对了一半，必须拆分。** 智能体
   竞品全员把两类东西分开放：**配置类**（模型/提供商、密钥、
   连接、凭据、权限）进设置——Muse、OpenClaw、Manus 一致；
   **运维/工作类**（定时、会话、记忆、技能、用量、活动）
   全员不进设置——Muse 放状态屏（Activity/Approvals/
   Upcoming），OpenClaw 明文写「管理面是工作区目的地、
   不是设置」并做成一级目的地，Manus 的 Skills/Automations
   是侧边栏一级，Letta ADE 的记忆与配置和聊天同屏并列。
   v2 把六模块整包塞进设置，在新竞品集下不成立。
2. **v2 的「底栏三格」数字不成立，但方向部分成立。**
   智能体产品在手机上普遍用底栏/标签栏：Muse iOS 是五格
   （Chat/Feed/Ideas/Goals/Library），OpenClaw 安卓是四个
   主标签（Overview/Chat/Sessions/Settings）且默认落点是
   Overview。修订为 **4 格：聊天／总览／智能体／设置**，
   新增的「智能体」格收纳运维四模块（记忆/技能/定时/
   服务端会话）。
3. **v2 的「总览做状态板」方向成立，证据加强、配方修订。**
   同类产品 OpenClaw（自托管网关的手机客户端）的默认落点
   就是专职 Overview，配方是状态头＋计数指标卡＋最近会话，
   不是分析图表。v2 五段按此重排：趋势图退出总览、最近
   会话与待办面进入总览（详见 §4 复核 3、§5.4）。

## 1 · 方法与竞品集

- **Muse 本体（标杆）**：依据本机 ~/docs/ 产品文档逐份
  记录（client-surfaces.md、muse.md、feed.md、goals.md、
  files-and-library.md、scheduling-and-watching.md），
  出处标注文件名。
- **OpenClaw（开源个人智能体网关）**：GitHub 仓库
  openclaw/openclaw 源码实查——Web 控制台导航定义
  ui/src/app-navigation.ts，安卓 App 的 ui 包
  （ShellScreen.kt、ShellNavigation.kt、SettingsRoute.kt、
  SidebarContent.kt）。
- **Letta（原 MemGPT）ADE**：官方文档集（docs.letta.com
  的 guides/ade/* 系列页，文档源 fern/pages/ade-guide/
  *.mdx）与官方教程、官方博客。版本注记：letta-ai/letta
  主仓 README（2026-11-08 实查）称 V1 API 服务器已归档、
  现行源码迁至 letta-ai/letta-code；ADE 是 V1 平台的管理
  环境，本版按 ADE 文档集记录其结构，不外推现行版界面。
- **Manus**：官方文档站 manus.im/docs（quickstart、
  features/overview、features/projects、features/skills）
  与官方博客（Scheduled Tasks 2.0）；移动端形态引官方
  账号（Threads @manus_jp/@manus_kr）演示视频说明。
- **Simular（Sai）**：官方站 simular.ai（/sai 产品页、
  llms.txt 索引）与官方开发者文档 docs.simular.ai。
- **Hermes Dashboard**：服务端原生 IA 锚，承 IA-V2 §3.9
  简要带过（§3.6）。

## 2 · 新对照表

| 产品 | 一级导航构成 | 智能体管理面落点 | 状态/总览面 | 与传统 chat 的结构差异 |
|---|---|---|---|---|
| Muse（标杆） | iOS 五格底栏：Chat/Feed/Ideas/Goals/Library；Web 左图标栏（＋Search），窄窗折叠为底栏五格＋More；设置走齿轮/菜单，不占格 | 配置类在设置（Connectors/Devices/Wallet/凭据库/Permissions）；定时在状态屏 Upcoming；记忆无行式管理页（Web 状态屏 Identity 里编辑 MEMORY 等文件；设置 Data controls 里 Import memory）；无 Skills 标签（「connected skills live under Settings > Connectors」）；无模型选择器（模型由套餐定） | **状态屏（点头像）**：Activity（动作日志）/Approvals（待批）/Upcoming（定时＋运行历史）；另有 Feed（智能体定时撰写的帖子）与 Goals（长期目标）两个「智能体在忙什么」的一级面 | 标签装的是智能体的产出与职责（动态/目标/资料库），不是功能页；监督（活动/审批/预告）独立成面；聊天只是五格之一 |
| OpenClaw | Web：Chat（内含 Sessions 视图）＋侧栏工作区目的地＋profile 菜单里的 Settings/Docs；安卓：标签式主导航 Overview/Chat/Sessions/Settings（＋详情标签），**默认落点 Overview**，侧栏可深链一级目的地 | **明文分界**：providers/secrets/memory 设置/channels 进设置分组（Connections/Agents/Security/System）；sessions/cron/usage/activity/dashboards 是侧栏一级「工作区目的地」，源码注释写明「not settings」；安卓侧栏把 Skills/Agents/Automations/Usage/Dreaming 与标签并列为一级目的地 | 安卓专职 Overview（默认落点）：网关状态头＋智能体主面板（连接态/待运行/会话数/定时数）＋指标卡深链＋最近会话；Web 有 dashboards/usage/activity/systems 目的地 | 三层 IA（聊天／工作区／设置）＋成文的分界纪律；手机默认落点是总览不是聊天；运维面一级化、只有配置进设置 |
| Letta ADE | Web 管理环境：智能体列表（可按标签筛选）/Templates 为一级；单个智能体是三栏工作台，无底栏 | 全部在工作台内与聊天并列：左栏 Agent Configuration（LLM 选择/System Instructions/Tools/Data Sources/Advanced）；记忆在右栏；没有「设置页收纳管理」的结构（智能体设置即左栏内容） | 无全局总览；右栏 Agent State Visualization＝单智能体的状态面：Context Window Viewer＋Core Memory Blocks＋Archival Memory | 以「智能体」而非「会话」为中心对象；聊天只是中间的 Simulator（测试台）；记忆是可见可编辑的状态面，和聊天同屏 |
| Manus | Web：侧边栏——任务列表（筛选含 Scheduled）、Projects 区、Skills（左侧主菜单标签页）、Connectors、Web development 等，功能总览页明言「grouped in the same way as the sidebar」；移动 App 有 Tasks 屏与 Projects 标签（完整标签构成未查到） | Skills 一级（左侧主菜单，管理页可装/搜/加，聊天内 / 唤起）；Automations 一级（侧面板＋schedule/calendar 视图看运行）；Projects 一级（主指令＋知识库文件即上下文配置）；模式（模型档位）选在任务顶部；Flex＝自带 API key 在 Reference 组 | 无全局状态总览（未查到）；任务级状态靠任务列表筛选与 Automations 的运行视图（Updates/Manage） | 以任务与项目（持久工作区）组织而非会话列表；技能/自动化是与项目并列的一级工作面；上下文靠项目的主指令＋文件承载，无独立记忆面（未查到） |
| Simular（Sai) | 官方公开文档未给出 App 内导航构成——**未查到**（docs.simular.ai 为开发者文档，不含消费端界面结构） | skills 支持（官网问答）；其余管理面落点未查到 | 中心对象是「电脑」：官网主打 Watch your Sai computers work（实时看电脑干活）、Sai World（每台电脑一个角色）；审批经 iMessage/Telegram 推送到 App 外处理 | 电脑（而非会话）是持久对象；监督＝看电脑实况＋消息应用里的审批；记忆＝虚拟机环境本身（登录/偏好跨会话保留） |
| Hermes Dashboard（锚） | 左栏平铺 17 项一级页面，无底栏 | 无设置页：MODELS/CONFIG/KEYS/CRON/SKILLS 等每个管理域都是一级页面 | 无总览页；状态压在栏脚（网关状态＋活跃会话数＋重启按钮） | 桌面运维控制台形态：平铺即「运维面全一级」的极端版，与智能体集方向同向，但手机不可照搬（承 v2） |

## 3 · 逐家记录（出处）

### 3.1 Muse 本体（~/docs/）

产品定义：每位用户有一个常驻智能体，跑在自己的专属
电脑上，在对话之间持续存在（muse.md）。

- **一级入口**（client-surfaces.md）：iOS 标签页为
  Chat、Feed、Ideas、Goals、Library 五格；Web 为左侧
  图标栏 Chat、Search、Feed、Ideas、Goals、Library，
  窄窗时折叠为底栏（五格＋More sheet）。其中 Feed 是
  智能体按一份 brief 定时撰写的短帖（feed.md）；Goals
  是智能体维护的长期目标（进度记录、后台简报，goals.md）；
  Library 收纳智能体产出的 artifacts、文档、媒体与文件
  （files-and-library.md）。Ideas 是智能体给用户的建议
  卡。**五个标签没有一个是管理页。**
- **状态屏**（client-surfaces.md「Status screen」节，
  点头像打开）：Activity＝智能体的近期动作日志（Web
  端运行中条目带 Stop）；Approvals＝待批权限请求；
  Upcoming＝定时任务（列表＋运行历史；编辑方式是起草
  一条聊天消息让用户发送，删除在详情页内，另见
  scheduling-and-watching.md）；Identity＝头像与名字
  （Web 端在此打开并编辑 MEMORY、SOUL、IDENTITY 文件
  ——原文：「Memory is that editable file, not a list
  of rows」）。
- **设置**（client-surfaces.md「Muse iOS app only >
  Settings」）：齿轮进入，不占标签格。订阅卡置顶，其后
  依次为 Connectors、Devices、Wallet、Secure credentials
  store、Permissions、Messaging channels、Encryption、
  Notifications、Appearance、Data controls（AI 训练
  退出、Import memory、下载智能体数据、Reset）、
  Report an issue、Help & support、Legal info、
  Accounts Center、Log out。装的全是能力管道（连接、
  凭据、权限、设备、钱包）与账号事项。
- **技能与记忆的落点**（同文件，原文）：「There is no
  Skills tab anywhere; connected skills live under
  Settings > Connectors.」记忆没有管理页：文件形态存于
  智能体电脑，编辑走 Identity（Web），导入走 Settings
  > Data controls > Import memory（memory.md）。
- **模型**：没有模型选择器，模型由套餐决定（muse.md
  Models 节：「there's no model setting to point the
  user to」）——Muse 的设置里根本不存在 Hermes 式
  「当前模型」行，这一项无从对位，只能记差异。
- **会话**：主聊天＋侧边聊天（side chats）在聊天侧栏
  组织，全量聊天搜索跨主/侧聊天（client-surfaces.md
  「Side chats」「Chat search」）。

### 3.2 OpenClaw（github.com/openclaw/openclaw）

Web 控制台导航定义 `ui/src/app-navigation.ts`：

- 文件头注释（原文要旨）：Chat 含 Sessions 视图；
  Settings/Docs 在 profile 菜单里；Skills 与 Skill
  Workshop 从 Plugins 工作区进入、不是侧栏条目；
  Worktrees 是 Sessions 中枢的一个页签。
- 侧栏工作区目的地 `SIDEBAR_NAV_ROUTES`：templates、
  dashboards、usage、cron、sessions、systems、
  activity、meetings、plugins、apps、portals。
- 设置分组 `SETTINGS_NAVIGATION_GROUPS`：无标题组
  （custodian/profile/appearance/notifications）、
  Device（device/device-permissions）、Connections
  （connection/channels/communications/talk/devices/
  cloud-workers）、Agents（agents/model-providers/
  search/plugin-settings/skill-settings/mcp/memory/
  automation）、Security（security/secrets/approvals）、
  System（infrastructure/labs/advanced/debug/logs/
  updates/about）。
- 同文件成文纪律（原文）：「Management surfaces
  (sessions, worktrees, activity, memory import) are
  workspace destinations, not settings; model setup
  is a subpage of Models.」——哪些是管理面、哪些进
  设置，作者写死在导航源码里。

安卓 App（`apps/android/app/src/main/java/ai/openclaw/app/ui/`）：

- `ShellScreen.kt` 的 Tab 枚举：Overview、Chat、
  Sessions、Settings 为主标签，另有 ProvidersModels、
  Files、Dashboard 三个详情型标签（从别处跨标签打开）。
  `ShellNavigation.kt`：默认标签＝**Overview**；注释
  原文「Tab-bar-style switch: Back from the selected
  tab returns to Overview」——总览是回退的原点。
- Overview 屏（`ShellScreen.kt` 的 OverviewScreen）：
  网关状态头；主面板＝当前智能体（名/徽标/头像）＋
  网关连接状态＋待运行数＋会话数＋定时任务数，按钮
  深链 Agents 与 Gateway 设置；指标卡一组（连接与
  注意事项、节点与设备摘要、待审批数、会话数），逐卡
  点击深链到对应设置路由或标签；其下是最近会话列表
  （头部入口跳 Sessions 标签，行点击切会话进 Chat）。
- `SettingsRoute.kt` 的设置分类：Personal（Profile/
  Appearance）、This phone（Voice/Notifications/
  Phone Capabilities）、Connections（Nodes & Devices/
  Channels/Gateway）、Configuration（Providers &
  Models/Approvals）、**Workspace（Agents/Automations
  （即 CronJobs)/Usage/Skills/Dreaming（记忆）/
  Terminal/Desktop）**、System（Health/About/
  Licenses），另有无分类的 OpenClaw（系统智能体）行。
- `SidebarContent.kt` 的 SidebarDestination 把
  Settings、Work（Overview)、Home（Chat)、**Skills、
  Threads（Sessions)、Agents、Automations、Usage、
  Dreaming、Terminal、Desktop** 并列为一级侧栏目的
  地——Workspace 类设置路由在侧栏与标签同级露出。

小结：OpenClaw 的 IA 是「聊天／工作区目的地／分组
设置」三层；配置（providers、secrets、memory 的
设置项、channels）进设置，运维（cron、sessions、
usage、activity、dashboards）是一级目的地。安卓端
虽把路由挂在 SettingsRoute 枚举下，但用 Workspace
分类把它们与 Configuration 分开，并给侧栏一级入口
——容器叫设置，结构待遇不是设置。

### 3.3 Letta ADE（docs.letta.com/guides/ade/*；文档源 fern/pages/ade-guide/）

- **定位与一级入口**（ade-guide/overview.mdx）：
  ADE 是为有状态智能体做创建、测试、监控的可视化
  环境，位于 app.letta.com，可连本地/自托管服务器。
  一级是智能体列表——可按标签筛选（ade-guide/
  settings.mdx：在 agents list 里按 tags 过滤）——与
  Templates（官方教程 customer-specific-agents.mdx：
  从 Letta dashboard 点 Templates → New template）。
- **单个智能体＝三栏工作台**（overview.mdx「Core
  Components of the ADE」）：
  - 中栏 Agent Simulator：与智能体聊天测试，消息按
    类型着色（用户/智能体/系统/工具），工具调用可
    展开看参数、结果与报错，带 token 用量监测
    （ade-guide/simulator.mdx）。
  - 左栏 Agent Configuration：LLM (Model) Selection、
    System Instructions、Tools Management、Data
    Sources、Advanced Settings（上下文窗口、温度等）；
    智能体设置含身份（名/ID/描述/标签）、模型选择与
    Advanced Settings 页签（Agent/LLM Config/
    Embedding Config 三类）（ade-guide/settings.mdx）。
    工具从左栏进 Tool Manager（官方教程）。
  - 右栏 Agent State Visualization：Context Window
    Viewer（看智能体当下在处理什么）、Core Memory
    Blocks（查看与编辑）、Archival Memory（监控与
    搜索）。Core Memory 区列出全部记忆块、内容与
    字数上限（ade-guide/core_memory.mdx）；默认块为
    human（关于用户）与 persona（智能体自我）。
- **定时**：ADE 界面内未查到定时任务管理面（ade-guide
  与 agent-development-environment 两组文档页均无）。
- **总览**：没有全局总览页；「状态」以单智能体右栏
  状态可视化的形态存在——与聊天同屏、常驻可见。
- 结构要点：ADE 里没有「设置页」这个收纳层。配置是
  左栏、记忆是右栏、聊天是中栏，三者是同一个工作台
  的并列面板；管理面离聊天一步不离。

### 3.4 Manus（manus.im/docs、manus.im/blog）

- **形态**：任务制——给目标，Manus 在自己的虚拟
  电脑里规划执行、交付成果；入口有 Web、桌面 Studio、
  移动 App、邮件（docs/introduction/quickstart）。
- **侧边栏即信息架构**（docs/features/overview 原文：
  「Manus features are grouped in the same way as
  the sidebar」）：Workflows 组含 Projects、Manus
  Skills、Automations、Parallel Tasks、Branch、
  Manus Collab、Mail Manus；Capabilities 组为任务内
  能力；另有 Web development（原文：open Web
  development in the sidebar）与 Reference 组
  （内置模型、Manus Flex＝用自己的 API key 运行）。
- **任务列表**（docs/features/projects）：任务列表
  带筛选——All tasks / Non-project tasks /
  Favorites / **Scheduled**；Projects 区在侧边栏
  （「Projects」旁 + 新建，可置顶、拖拽排序）。
  Projects 是持久工作区：主指令＋知识库文件自动
  套用到项目内每个新任务。
- **技能**（docs/features/skills 原文）：「Navigate
  to the Skills tab in the main menu on the
  left-hand side」——左侧主菜单一级标签页；管理页
  可查看已装、搜索新技能，添加方式含 Build with
  Manus（从成功任务生成）、上传、官方库、GitHub
  导入；聊天内打 / 唤起。
- **定时**（官方博客 manus.im/blog/manus-schedules
  《Introducing Scheduled Tasks 2.0》）：定时工作
  在侧面板（side panel）展示并关联其运行，另有
  schedule view 与 calendar view；每次运行可选
  续接同一任务或另起新任务；创建无专门流程——在
  任务/Project/网站里直接告诉 Manus 即可。
- **模型**：模式（Manus 2.0 Max/2.0/Lite/Flex）在
  任务顶部菜单选（quickstart），不是设置项。
- **移动 App**：官方账号演示视频（Threads
  @manus_jp、@manus_kr，2026-05）显示 Tasks 屏
  （带筛选 chips）与 Projects 标签，项目详情含
  Instructions/Files/Skills 三页签；移动端完整
  标签构成未查到。
- **记忆**：官方文档未见独立记忆管理面——未查到；
  持久上下文由 Projects 的主指令＋知识库文件承载。
- **总览**：无全局状态总览面——未查到；状态查看靠
  任务列表筛选与 Automations 的运行视图。

### 3.5 Simular / Sai（simular.ai）

- **形态**（simular.ai/llms.txt、simular.ai/sai）：
  Sai 是「robosecretary」式电脑智能体：在 Simular
  提供的云电脑或用户自己的 Mac/Windows 上像人一样
  看屏幕、点击、输入完成任务；敏感步骤先经人审批。
- **可证的功能面**（/sai 产品页原文）：Watch your
  Sai computers work（实时看电脑干活，全透明）；
  Teach it once, and Sai reruns on a schedule
  （教会一次即按计划重跑）；审批与求助经 iMessage、
  Telegram 推送（close the laptop 也继续跑）；Sai
  World——每台 Sai 电脑一个角色形象，代表一台真在
  干活的电脑；持久记忆＝虚拟机环境本身（「Your
  setup, logins, preferences, and context persist
  between sessions」）；支持 skills（官网问答）。
- **App 内导航构成**（底栏/侧边栏/设置目录）：官方
  公开文档未给出——**未查到**。docs.simular.ai 是
  开发者文档（Simulang、Agent S、Sai API 与集成），
  不含消费端 App 的界面结构。本行只记可证的产品
  形态，不补界面细节。
- 结构要点（可证部分）：中心对象是「电脑」而非
  会话；监督方式是看电脑实况＋在消息应用里审批，
  管理不在 App 内做成设置页——但其 App 导航未查到，
  此点只作形态旁证、不作结构证据。

### 3.6 Hermes Dashboard（锚，简要）

承 IA-V2 §3.9：左栏平铺 17 项（CHAT/SESSIONS/
FILES/MODELS/LOGS/CRON/SKILLS/…/CONFIG/KEYS/
SYSTEM），无设置页，状态在栏脚（网关状态＋活跃
会话数＋重启按钮），接口分组见 docs/API-PATHS.txt。
v3 视角补一句：它的平铺是「运维面全一级」的极端
形态，与智能体竞品集的方向并不矛盾——矛盾的只是
桌面平铺的呈现方式不可搬到手机（v2 此判维持）。

## 4 · 对 IA-V2 三条定版的逐条复核

### 复核 1：底栏三格（聊天／总览／设置）

- v2 依据：传统 chat 样本里底栏是少数派（八家里
  只有 LobeChat 有，且 3 格），其余靠侧栏/抽屉。
- 新证据：该样本以桌面应用为主，系统性低估了手机
  底栏。智能体集里 Muse iOS 是五格底栏、OpenClaw
  安卓是四主标签的标签式主导航——**底栏在智能体
  产品的手机端是常态，格数是 4–5 而非 3**。同时
  两家都证明：格里装的优先是工作面（Muse 的
  Feed/Goals/Library、OpenClaw 的 Sessions），
  设置在 Muse 走齿轮不占格、在 OpenClaw 占一格。
- **判定：修订。**「三格」这个数字不成立（证据
  基础错误）；「聊天居首、总览占一格」成立且总览
  的证据加强（见复核 3）。格数随复核 2 的拆分
  结果定为 4 格（§5.1）。

### 复核 2：管理并入设置

- v2 依据：八家 chat 客户端里，模型/密钥/记忆/
  技能/定时/用量六项全部栖身设置体系。
- 新证据：智能体集给出一条清晰的分界线，且四家
  独立同向：
  - **配置类进设置**：Muse 设置装 Connectors、
    凭据库、Permissions、Devices、Wallet；OpenClaw
    设置分组装 model-providers、secrets、memory
    设置项、channels；Manus 的连接器有独立入口、
    自带 key 走 Flex（Reference 组）。此半 v2 成立。
  - **运维/工作类不进设置**：Muse 的定时在状态屏
    Upcoming、活动在状态屏 Activity，都不在设置；
    OpenClaw 源码注释明文「管理面是工作区目的地，
    不是设置」，cron/sessions/usage/activity/
    dashboards 全部一级，安卓再给 Workspace 类
    路由侧栏一级目的地；Manus 的 Skills 与
    Automations 是侧边栏一级工作面；Letta ADE 的
    记忆（右栏）与工具（左栏）与聊天同屏，根本
    没有设置收纳层。此半 v2 不成立。
  - 附带纠正 v2 §4 的「例外论」：v2 把技能被提为
    一级解释为「内容库例外」。在智能体集里这不是
    例外——技能是智能体的工作资产（Manus 在聊天
    里 / 唤起、OpenClaw 从 Plugins 工作区进入、
    Sai 支持技能扩展），一级化是常态。
- **判定：拆分修订。** Hermes 六模块按类分流：
  模型与密钥（配置类）留在设置，v2 定版维持；
  记忆、技能、定时、会话数据（运维类）退出设置，
  改入一级「智能体」面（§5.2）；用量按 OpenClaw
  口径处理——总览只放计数、详情页独立成页（挂
  设置·模型与密钥下，见 §5.3/§5.4）。

### 复核 3：总览状态板五段（状态头/今日四数/趋势/运行面/异常面）

- v2 依据：竞品里只有 Dify 有独立监测页（四指标
  ＋趋势），Hermes 把状态压在栏脚，故总览按状态
  板重做、配方借 Dify。
- 新证据：Dify 是 LLM 应用开发平台，与 OneDay
  不同类；智能体集里有**同类直接样本**——OpenClaw
  安卓（自托管网关的手机客户端）的 Overview 是
  专职页且为默认落点，配方是：状态头＋智能体主
  面板（连接态、待运行数、会话数、定时任务数）
  ＋指标卡（逐卡深链）＋最近会话列表，没有趋势
  图。Muse 的状态屏（Activity/Approvals/
  Upcoming）则证明智能体状态的核心是「做过
  什么、什么待批、接下来跑什么」——v2 五段里
  「活动」完全缺位、「下次运行」埋在运行面里。
- **判定：方向成立、配方修订。** 状态板保留且
  依据升级为同类样本（OpenClaw Overview 为主
  依据，Dify 降为旁证）；五段重排为 §5.4：状态头
  ／指标行／待办面／最近会话／快捷动作。7 日趋势
  与模型分布退出总览，降入用量详情页。

## 5 · 修订后的 OneDay IA 定版（v3）

### 5.1 底栏：4 格——聊天／总览／智能体／设置

| 格 | 内容 | 依据 |
|---|---|---|
| 聊天（第一格、默认落点） | 对话＋会话抽屉（v0.1.3 定版，不动） | 全员聊天一级；Muse 聊天居首格。默认落点取聊天不取总览：OneDay 是对话优先的个人客户端，OpenClaw 取 Overview 默认是其运维定位（二者都占格，只差落点，此取舍明记于此） |
| 总览 | 状态板（§5.4），只看不动（除快捷动作） | OpenClaw 安卓 Overview 的手机等价物；Muse 状态屏的「监督」职能 |
| 智能体 | 运维四模块目录（§5.2） | OpenClaw 侧栏工作区目的地、Manus 侧边栏 Workflows 组的手机压缩形态 |
| 设置 | 配置中枢（§5.3） | 配置类全员入设置（Muse 设置全目录、OpenClaw 设置分组） |

与 v2 的关键差别只在第三格：v2 是「管理并入设置」
所以底栏只有 3 格；v3 按复核 2 的分界线把运维类
提为一格，底栏回到 4 格——注意这不是回到 v0.1.3
的「管理」格：那一格当时装的是含模型/密钥在内的
整包管理，v3 的「智能体」格只装运维四模块，配置
类已按证据留在设置。

### 5.2 智能体页目录（新增，运维四模块）

首页形态沿设置页的深度纪律：只到「条目行（名称
＋当前值摘要）」一层，点入二级页操作。

```
智能体
├─ 记忆（当前提供方名 → /api/memory：提供方切换、
│    各提供方配置、记忆内容查看、重置）
├─ 技能（已装 N 个 → /api/skills：列表、开关
│    toggle、内容查看；技能商店 /api/skills/hub
│    搜索安装，二期）
├─ 定时任务（启用 N 个 · 下次运行 HH:MM →
│    /api/cron/jobs：新建/编辑、暂停/恢复/立即
│    触发、运行记录 /api/cron/jobs/{id}/runs）
└─ 服务端会话（共 N 条 → /api/sessions：列表、
     删单条、清空空会话；本机会话仍归聊天抽屉，
     不在此重复）
```

落点依据逐项：记忆——Letta 右栏状态面与 OpenClaw
Dreaming 一级目的地的手机形态（可看可改的状态，
不是设置行）；技能——Manus 左侧主菜单 Skills 与
OpenClaw Plugins 工作区（一级工作资产）；定时——
Muse 状态屏 Upcoming 与 OpenClaw cron 一级目的地
（要看下次运行与历史，是日常监督对象）；会话
数据——OpenClaw Sessions 一级目的地（服务端会话
是工作面，本机会话在抽屉里，两处分工不同不合并）。

### 5.3 设置页目录树（v3，四组）

v2 §5.2 的五组删去「智能体」组，其余四组逐条
不变，重列于此使 v3 自足：

```
设置
├─ 服务器
│  ├─ 当前服务器（名称＋地址＋状态点）→ 连接详情
│  │    服务器地址 / 面板账号 / API 密钥（掩码，可 reveal）
│  │    重测连接（三步探活）/ 切换服务器（多服务器预留位）
│  ├─ 档案 Profile（当前档案名 → /api/profiles 列表
│  │    与切换，切换走 /api/profiles/active）
│  └─ 断开连接（destructive，确认后清凭据回连接页）
├─ 模型与密钥
│  ├─ 对话模型（当前模型名 → 模型管理：默认模型
│  │    切换与提供商清单，读写 /api/config；
│  │    提供商增删改）
│  ├─ 密钥（/api/env 列表：增 / 改 / 删，
│  │    POST /api/env/reveal 查看明文；凭据池
│  │    /api/credentials/pool 二期）
│  └─ 用量（摘要行：今日 Token / 今日请求 → 用量
│       详情页：/api/analytics/usage?days= 按日
│       趋势＋/api/analytics/models 按模型分布
│       ——v2 放在总览的趋势与分布移到这里）
├─ 网关
│  ├─ 网关状态（运行状态＋版本＋config_version，
│  │    数据 /api/status）
│  ├─ 重启网关（POST /api/gateway/restart，二次
│  │    确认；停止/启动 /api/gateway/stop|start
│  │    收进详情页）
│  └─ 日志（/api/logs?level=&component=&lines=：
│       级别/组件筛选、搜索，只读）
└─ 关于
   ├─ App 版本（0.1.x / build）
   ├─ 服务端（Hermes 版本、release_date、服务器
   │    时间口径）
   └─ 隐私与许可（数据只存本机 Keychain 的说明、
        开源许可）
```

危险动作口径沿 v2：断开连接、删密钥、重置记忆、
重启网关一律 destructive 呈现＋二次确认（重置
记忆的入口随记忆页迁至智能体格，口径不变）。

### 5.4 总览（v3 五段）

主依据换为 OpenClaw 安卓 Overview 的配方（状态头
＋计数指标＋最近会话）与 Muse 状态屏的监督三件
（活动/待批/预告），段落与数据来源如下：

| 段 | 指标 | 来源接口 |
|---|---|---|
| 状态头（保留现签名排版） | 网关状态（运行/停止/异常）、各平台连接态（gateway_platforms 逐项 state）、服务端版本 | GET /api/status |
| 指标行（逐项可点、深链对应页） | 活跃会话数 → 聊天抽屉/会话；定时任务（启用数 · 下一次运行时间）→ 智能体·定时任务；今日 Token → 设置·用量详情 | GET /api/sessions（计数）、GET /api/cron/jobs、GET /api/analytics/usage?days=1 |
| 待办面 | 最近异常 3 条（error 级日志摘要）、任一平台 state≠connected 时置顶警示、出口状态异常提示；Hermes 侧若开放待处理配对/审批数据，同列于此（对应 Muse Approvals/OpenClaw 待审批指标卡的位置） | GET /api/logs?level=error&lines=50、GET /api/status、GET /api/egress/status |
| 最近会话 | 服务端最近会话 3–5 条（标题＋时间＋所属档案），点击回聊天续接；无服务端会话时回退本机最近会话 | GET /api/sessions |
| 快捷动作 | 重启网关（二次确认）、新建定时任务、看日志——深链到 §5.2/§5.3 对应页 | POST /api/gateway/restart 等 |

- 相对 v2 §5.3 的进出：**进**——指标行（计数＋
  下次运行，对应 OpenClaw 主面板的计数位）、最近
  会话（OpenClaw Overview 的主体段）；**并**——
  v2 的异常面与运行面中的警示项合并为待办面；
  **出**——7 日趋势、按模型分布（降入 §5.3 用量
  详情页）；今日四数收为指标行中的今日 Token
  一项（消息数/会话数与指标行重复，不再单列）。
- 刷新与空态口径沿 v2：进页拉取＋下拉刷新，状态
  头可 30 秒前台轮询；某段失败只降级该段。

### 5.5 与 v2 的差异清单（汇总）

1. 底栏 3 格 → 4 格：新增「智能体」格，序为
   聊天／总览／智能体／设置（v2 序：聊天/总览/
   设置）。
2. 设置目录树五组 → 四组：删「智能体」组；
   记忆/技能/定时/会话数据迁往智能体格；服务器、
   模型与密钥、网关、关于四组逐条不变。
3. 里程碑 2 的施工对象按类分流：配置类二级页
   （模型管理、密钥、用量详情）归设置；运维类
   二级页（记忆、技能、定时、服务端会话）归
   智能体格。
4. 总览配方换方：主依据由 Dify 监测页换为
   OpenClaw 安卓 Overview＋Muse 状态屏；趋势与
   分布退出总览，指标行与最近会话进入总览。
5. **维持不变的 v2 结论**（新证据支持原案，不为
   改而改）：聊天第一格＋会话抽屉不动；总览保留
   独立格且只承载状态信号、配置回声退出总览；
   模型与密钥在设置页；设置页「首页只到条目行」
   的深度纪律；危险动作 destructive＋二次确认。

## 6 · 出处索引

- Muse：本机 ~/docs/client-surfaces.md（Tabs、
  Status screen、iOS/Android/Web Settings 各节）、
  ~/docs/muse.md（产品定义、Models 节）、
  ~/docs/feed.md、~/docs/goals.md、
  ~/docs/files-and-library.md、
  ~/docs/scheduling-and-watching.md、
  ~/docs/memory.md（Import memory 路径）
- OpenClaw：github.com/openclaw/openclaw —
  ui/src/app-navigation.ts（SIDEBAR_NAV_ROUTES、
  SETTINGS_NAVIGATION_GROUPS 及文件内注释）；
  apps/android/app/src/main/java/ai/openclaw/app/ui/
  ShellScreen.kt（Tab 枚举、OverviewScreen）、
  ShellNavigation.kt（默认标签与回退语义）、
  SettingsRoute.kt（分类与路由）、SidebarContent.kt
  （SidebarDestination）
- Letta：docs.letta.com/guides/ade/*（文档源
  letta-ai/letta 文档集 fern/pages/ade-guide/
  overview.mdx、settings.mdx、core_memory.mdx、
  simulator.mdx，及 fern/pages/tutorials/
  customer-specific-agents.mdx）；官方博客
  《Introducing the Agent Development
  Environment》；letta-ai/letta README（V1 归档
  注记，2026-11-08 实查）
- Manus：manus.im/docs/introduction/quickstart、
  manus.im/docs/features/overview、
  manus.im/docs/features/projects、
  manus.im/docs/features/skills、
  manus.im/blog/manus-schedules（Scheduled Tasks
  2.0）；官方账号 Threads @manus_jp/@manus_kr
  演示视频说明（移动端 Projects，2026-05）
- Simular：simular.ai/llms.txt、simular.ai/sai
  （产品页与问答）；docs.simular.ai（开发者文档，
  经查不含消费端 App 导航，故该项记未查到）
- Hermes（锚）：本仓 docs/API-PATHS.txt、
  docs/hermes-0.23.0-openapi.json、
  docs/M2-DISCOVERY.md，及 IA-V2.md §3.9 的
  2026-11-08 登录实测记录
