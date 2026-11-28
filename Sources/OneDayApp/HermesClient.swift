import Foundation
import OneDayCore
#if canImport(EventSource)
import EventSource
#endif

/// Hermes 服务端对接协议：连接页三步探活、总览与聊天走对话面，
/// 智能体/设置的总览外全部功能走 Dashboard 管理面（/api/*，
/// 会话 cookie 鉴权，401 由 AppState 自动重登兜底）。
/// 接口路径与请求体口径全部对 docs/hermes-0.23.0-openapi.json
/// 与 2026-11-08 GET 实测结构（见 docs/API-SURFACE.md）。
///
/// 【C-13 冻结·改本协议前必读】Demo 侧接口面已冻结
/// （overcomplexity-audit-20261114 C-13＋demo-surface-
/// freeze-20261111）：给本协议新增方法时，DemoHermes-
/// Client 只许加一行 `throw HermesError.demoLimitReached`
/// 桩（流式口许返回即时空流），不许再写种子实现——种子
/// 面以 2026-11-11 冻结清单为限，扩大须施工单点名；
/// 新增桥 Client 一律不建 Demo 对应物。
protocol HermesClientProtocol: Sendable {
    /// 探活一：GET /health（免鉴权）
    func health(config: ServerConfig) async throws -> HealthResponse
    /// 探活二：POST /api/companion/web-login 验面板密码
    /// 拿会话 cookie（§244 一把密码统一：走伴生登录桥，
    /// 与网页端/伴生面板同一把用户密码；cookie 由
    /// URLSession 共享存储持有，本方法只判成败）
    func login(config: ServerConfig, username: String, password: String) async throws
    /// GET /api/status（免登录）
    func status(config: ServerConfig) async throws -> ServerStatus
    /// GET /api/hermes/update/check（需会话）：自更新
    /// 感知只读切片（DESIGN §360，台账 36 案 A）；本
    /// 部署恒走 managed-runtime 分支，执行腿不做
    func updateCheck(config: ServerConfig) async throws -> UpdateCheckResponse
    /// GET /api/hermes/update/receipt（需会话）：无更
    /// 新运行记录时服务端回 404 → 抛
    /// UpdateReceiptError.absent（专属空态，不走通用
    /// 失败面，DESIGN §360）
    func updateReceipt(config: ServerConfig) async throws -> UpdateReceiptResponse
    /// GET /api/config（需会话；401 由调用方走重登重试）
    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary
    /// 探活三：GET /v1/models（Bearer API 密钥），返回模型 id 列表
    func models(config: ServerConfig, apiKey: String) async throws -> [String]
    /// GET /v1/capabilities（Bearer）：能力发现正源
    /// ——静态旗标＋端点表（部署包补丁能力不在广告
    /// 内，靠下方探针补齐；DESIGN §357 连接自检）
    func capabilities(
        config: ServerConfig, apiKey: String
    ) async throws -> CapabilitiesResponse
    /// GET /v1/settings/registry（Bearer）：设置注册
    /// 表下发（AI 自主设置权一期，DESIGN §437）——
    /// 只读端点、无写面；能力位 features.settings_
    /// registry 亮时才调，拉不到由调用方回落内置目录
    func settingsRegistry(
        config: ServerConfig, apiKey: String
    ) async throws -> SettingsRegistryResponse
    /// GET /health/detailed（Bearer）：深度健康——
    /// readiness 逐项检查＋网关/平台/今日指标
    func healthDetailed(
        config: ServerConfig, apiKey: String
    ) async throws -> HealthDetailedResponse
    /// POST /v1/chat/completions 流式：逐段产出通道事件
    /// （正文增量／思考增量分开，0.5.1 §32）
    /// sessionID（0.21.0）：非 nil 时带 X-Hermes-Session-Id
    /// 头走会话模式（服务端持上下文、只发本轮新消息）。
    /// 0.27.0：ChatView 发送恒带会话头（未链接先链接、
    /// 失败整轮不发）；nil 只剩升级前旧待恢复账的兜底
    /// 路径，且恢复链已改判为带头重发或不发，不再产生
    /// 新的无头发送
    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage],
        sessionID: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>

    // MARK: 任务制生成（/v1/runs，0.31.0）

    /// POST /v1/runs：提交一轮生成、立即返回 run_id
    /// （生成与连接分家——提交成功后生成在服务端独
    /// 立跑完，断线不取消）。sessionID 绑定既有服务
    /// 端会话（历史以 state.db 为准）；idempotencyKey
    /// 为本轮提交的幂等键（同 key＋同体重复提交＝重
    /// 演原 run，不双跑）
    func submitRun(
        config: ServerConfig, apiKey: String, sessionID: String,
        input: RunInput, model: String, provider: String?,
        idempotencyKey: String
    ) async throws -> RunSubmitResponse
    /// GET /v1/runs/{id}：run 状态轮询（终态带 out-
    /// put 全文）；404（记录过期/不存在）返回 nil，
    /// 由调用方转 transcript 定性
    func runStatus(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws -> RunStatusResponse?
    /// GET /v1/runs/{id}/events：结构化事件流（可按
    /// lastSeq 重挂回放）。流自然结束/断开只 finish
    /// 不抛错——「没看到终态」与「轮次失败」是两回
    /// 事，定性归状态机＋status/transcript 对账
    func runEvents(
        config: ServerConfig, apiKey: String, runID: String,
        lastSeq: Int
    ) -> AsyncStream<RunEventEnvelope>
    /// POST /v1/runs/{id}/stop：真取消（服务端对本
    /// run 的 agent 发 hard interrupt，终态 cance-
    /// lled；与旧 chat 通道「断流假取消」本质不同）
    func stopRun(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws
    /// POST /v1/runs/{id}/steer：向运行中的轮次注入纠偏指令
    func steerRun(
        config: ServerConfig, apiKey: String, runID: String, input: String
    ) async throws -> RunSteerReceipt
    /// POST /v1/runs/{id}/approval：响应运行中等待审批的工具请求（once/session/always/deny）
    func respondRunApproval(
        config: ServerConfig, apiKey: String, runID: String,
        requestID: String?, choice: String, executionGeneration: Int?
    ) async throws
    /// POST /v1/runs/{id}/clarify：回答运行中等待澄清的问题
    func respondRunClarify(
        config: ServerConfig, apiKey: String, runID: String,
        requestID: String, answer: String, executionGeneration: Int?
    ) async throws
    /// POST /api/sessions/{id}/fork：在服务端无损克隆分支会话
    func forkServerSession(
        config: ServerConfig, apiKey: String, id: String, title: String?
    ) async throws -> ServerSession
    /// POST /v1/diagnostics/crash-reports：批量上报本地崩溃诊断
    func uploadCrashReports(
        config: ServerConfig, apiKey: String, reports: [CrashReportRecord]
    ) async throws -> CrashReportsUploadReceipt
    /// GET /v1/diagnostics/crash-reports：回读服务端已上报崩溃列表
    func listServerCrashReports(
        config: ServerConfig, apiKey: String, limit: Int
    ) async throws -> [ServerCrashReportItem]
    /// GET /v1/memory/layers：获取四层记忆清单
    func memoryLayers(
        config: ServerConfig, apiKey: String
    ) async throws -> [MemoryLayerSummary]
    /// GET /v1/memory/search：跨层混合/语义检索记忆
    func searchLayeredMemory(
        config: ServerConfig, apiKey: String, query: String,
        limit: Int, mode: String
    ) async throws -> [MemorySearchHit]
    /// GET /v1/memory/insights：获取 ExpeL 洞察台账
    func memoryInsights(
        config: ServerConfig, apiKey: String
    ) async throws -> [MemoryInsightItem]
    /// 清除某服务器的全部会话 cookie（断开连接时调用）
    func clearCookies(config: ServerConfig)

    // MARK: 管理面（里程碑 2，IA v3）

    /// GET /api/memory
    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus
    /// PUT /api/memory/provider {provider}
    func setMemoryProvider(config: ServerConfig, name: String) async throws
    /// GET /api/memory/providers/{name}/config
    func memoryProviderConfig(config: ServerConfig, name: String) async throws -> MemoryProviderConfig
    /// PUT /api/memory/providers/{name}/config {values}
    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws
    /// POST /api/memory/reset {target}
    func resetMemory(config: ServerConfig, target: String) async throws

    /// GET /api/learning/graph（台账 164）：学到的
    /// 技能＋记忆块图谱（记忆真源在服务端，本面只
    /// 读呈现、写走 node 三口，不建本地第二真源）
    func learningGraph(config: ServerConfig) async throws -> LearningGraph
    /// GET /api/learning/node?id=（台账 164）：节点
    /// 全文（编辑预填）；形态未钉死、宽容提取
    func learningNode(
        config: ServerConfig, id: String
    ) async throws -> LearningNodeContent
    /// PUT /api/learning/node {id, content}（台账
    /// 164）：改写节点全文（技能＝SKILL.md、记忆＝
    /// 记忆块）
    func updateLearningNode(
        config: ServerConfig, id: String, content: String
    ) async throws
    /// DELETE /api/learning/node {id}（台账 164）：
    /// 技能归档（可恢复）、记忆删除（不可恢复）——
    /// 服务端语义，呈现层确认文案据 kind 分流
    func deleteLearningNode(config: ServerConfig, id: String) async throws

    /// GET /api/skills（裸数组）
    func skills(config: ServerConfig) async throws -> [SkillItem]
    /// GET /api/skills/content?name=
    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent
    /// PUT /api/skills/content {name, content}
    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws
    /// PUT /api/skills/toggle {name, enabled}
    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws
    /// PUT /api/skills/lock {name, locked}
    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws

    /// GET /api/skills/hub/sources（P10）——本部署实测
    /// 服务端抓注册表超时，调用方须容忍长耗时与失败
    func skillHubSources(config: ServerConfig) async throws -> [HubSource]
    /// GET /api/skills/hub/search?q=&source=&limit=
    func skillHubSearch(
        config: ServerConfig, query: String, source: String?
    ) async throws -> [HubSkill]
    /// GET /api/skills/hub/preview?identifier=
    func skillHubPreview(
        config: ServerConfig, identifier: String
    ) async throws -> HubPreview
    /// POST /api/skills/hub/install {identifier}（服务端
    /// 后台执行，落定靠回读技能列表对账，不认回执即成功）
    func skillHubInstall(config: ServerConfig, identifier: String) async throws
    /// POST /api/skills/hub/uninstall {name}
    func skillHubUninstall(config: ServerConfig, name: String) async throws

    /// GET /api/cron/jobs（裸数组）
    func cronJobs(config: ServerConfig) async throws -> [CronJob]
    /// POST /api/cron/jobs（schedule 传字符串表达式）
    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob
    /// PUT /api/cron/jobs/{id} {updates}
    func updateCronJob(config: ServerConfig, id: String, updates: [String: JSONValue]) async throws
    /// DELETE /api/cron/jobs/{id}
    func deleteCronJob(config: ServerConfig, id: String) async throws
    /// POST /api/cron/jobs/{id}/pause
    func pauseCronJob(config: ServerConfig, id: String) async throws
    /// POST /api/cron/jobs/{id}/resume
    func resumeCronJob(config: ServerConfig, id: String) async throws
    /// POST /api/cron/jobs/{id}/trigger（服务端同步等任务跑完，
    /// 官方桌面端为此单独放宽到 24h；App 侧放宽到 10 分钟）
    func triggerCronJob(config: ServerConfig, id: String) async throws
    /// GET /api/cron/jobs/{id}/runs?limit=（{"runs": [会话同构行]}）
    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession]
    /// GET /api/cron/blueprints（§388 H6；服务端单源目录，
    /// 内置＋插件蓝图，条目即表单模式）
    func cronBlueprints(config: ServerConfig) async throws -> [CronBlueprint]
    /// POST /api/cron/blueprints/instantiate {blueprint, values}
    /// （填空建任务；422 为字段级校验错，原文透传给表单）
    func instantiateBlueprint(
        config: ServerConfig, blueprint: String, values: [String: JSONValue]
    ) async throws
    /// GET /api/cron/delivery-targets（§388 H6；local 打头＋
    /// 已接网关平台，未设主频道者如实带 home_target_set=false）
    func cronDeliveryTargets(config: ServerConfig) async throws -> [CronDeliveryTarget]

    /// GET /api/sessions?limit=
    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage
    /// GET /api/sessions/{id}
    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession
    /// 建会话（0.7.0 主线钦定）：id/title 由 App 指定，
    /// 服务端回执的 id 为准（服务端改派时以回执改存）。
    /// 0.27.0 送达改路：POST /api/sessions 只存在于
    /// 网关面（8642），nginx 已为该方法该路径加精确
    /// 路由——请求必须带 App 既有的 /v1 Bearer 密钥
    /// （网关面鉴权），不再走 Dashboard cookie 通道
    /// （旧通道必 405 且曾被静默吞，见串话诊断档）
    func createServerSession(config: ServerConfig, apiKey: String, id: String?, title: String?) async throws -> ServerSession
    /// 建旁聊真会话（0.21.0）：POST /api/sessions 带
    /// model＋require_model_lock（模型锁＝建时胶囊所
    /// 选、锁后不许回退）；**不带 title**——服务端两
    /// 段式标题（derived→llm）须由首轮内容自生，App
    /// 指定标题会占住标题位、AI 标题回不了流。
    /// 0.27.0：送达改路同 createServerSession（Bearer）
    func createLinkedServerSession(config: ServerConfig, apiKey: String, id: String, model: String) async throws -> ServerSession
    /// 种子导入（0.27.0）：POST /api/sessions/import
    /// （Dashboard 面 cookie 通道）一次落会话行＋全
    /// 量历史消息——带会话头的发送历史以服务端为
    /// 准、重放灌不进历史，有历史线程的链接只能走
    /// 导入落种。围栏：request_id §331 改稳定派生
    /// （SideChatLink.seedRequestID：同一一种子重试
    /// 恒同 id，收据重放＋导入前回读双层幂等；旧
    /// 「每发新铸」作废）、expectedRevision 取锚点
    /// 当前 runtime_revision（新锚 0、已存在锚先
    /// GET 读值），冲突 409 由调用方如实上抛。
    /// sessionBody 由 Core SideChatLink 组装
    func importServerSession(
        config: ServerConfig, requestID: String,
        expectedRevision: Int, sessionBody: [String: JSONValue]
    ) async throws
    /// 会话内切换模型（0.21.0）：POST /api/sessions/
    /// {id}/model——服务端自动按确认锁持久化；已链
    /// 接线程胶囊改选时推一次（口径见 SideChatLink
    /// .needsModelRelock）
    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws
    /// GET /api/sessions/{id}/messages
    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage]
    /// §237（P6）：GET /api/sessions/{id}/messages
    /// ?limit=&offset=&order=latest——§331 订正：
    /// 服务端两面（网关 8642/面板 9119）的 order 只
    /// 认 oldest/latest，旧注「OpenAPI 冻结三参数、
    /// desc 倒序」是错误假设，desc 已被新版服务端
    /// 以 400 invalid_pagination 拒（2026-11-18 重
    /// 装三连之三实锤）。latest＝从最新一页取起、
    /// 页内时序返回，调用方按消息 id 升序重排落
    /// 盘，先最新首屏、再向前补全
    func sessionMessagesPage(
        config: ServerConfig, id: String, limit: Int, offset: Int,
        afterRowID: Int?
    ) async throws -> [SessionMessage]
    /// GET /api/sessions/search?q=&limit=（P10；生产实样
    /// {"results":[…]}，2026-11-09 只读联调验过）
    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit]
    /// GET /api/sessions/{id}/timeline?limit=&after_
    /// row_id=（台账 161）：prompt 元数据时间线，条
    /// 目 row_id 是 messages/around 的寻址坐标；响
    /// 应形态未被冻结件钉死，走 JSONValue 宽容提取
    func sessionTimeline(
        config: ServerConfig, id: String,
        afterRowID: Int64?, limit: Int
    ) async throws -> SessionTimelinePage
    /// GET /api/sessions/{id}/messages/around?row_
    /// id=&limit=（台账 161）：自某 prompt 起的有界
    /// 展示页（与 /messages 同投影）；row_id 不存在
    /// 时服务端 404（Prompt not found）
    func sessionMessagesAround(
        config: ServerConfig, id: String,
        rowID: Int64, limit: Int
    ) async throws -> SessionAroundPage
    /// GET /api/sessions/{id}/mutation-snapshot：围栏
    /// 身份的官方指定来源（删除 409 热修，报告 §1.2）
    func sessionMutationSnapshot(
        config: ServerConfig, id: String
    ) async throws -> SessionMutationSnapshot
    /// DELETE /api/sessions/{id}：围栏三参数走 query
    /// （官方契约，身份读 mutation-snapshot）；收口按
    /// 错误码分流，身份读不到不许裸发（报告 §1.4）
    func deleteServerSession(config: ServerConfig, id: String) async throws
    /// POST /api/sessions/{id}/rewind（D3/D2，DESIGN
    /// §352；部署包 1.1.0 批 0 实测契约）：把服务端
    /// transcript 截断到 target 行之前（target 及其后
    /// 全部移除）。身份走 mutation-snapshot 现读、
    /// request_id 每试新铸；409 先对账防回执丢失的二
    /// 次截断。predecessorRowID＝target 的前一行服务
    /// 端行 id（无前行传 nil＝截断后尾应为空），只供
    /// 对账比对。定性失败抛 RewindError，其余抛
    /// HermesError
    func rewindSession(
        config: ServerConfig, id: String,
        targetMessageID: Int, predecessorRowID: Int?
    ) async throws -> RewindReceipt
    /// GET /api/sessions/empty/count
    func emptySessionCount(config: ServerConfig) async throws -> Int
    // §241：DELETE /api/sessions/empty（无围栏裸删）与
    // POST /api/sessions/bulk-delete（无调用方残留）的
    // 客户端方法已摘除——删会话只许走围栏单删一条路，
    // 空会话清理走 EmptyCleanupSheet 安全处置（dry-run
    // ＋对账＋逐条围栏删＋审计＋核验）
    /// GET /api/sessions?limit=&offset=&archived=（0.18.0
    /// 「全部对话」管理面分页拉全；archived 取
    /// exclude/only/include，nil 不带参数走服务端默认）
    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage
    /// PATCH /api/sessions/{id}（SessionRename 子集，
    /// 只带要改的字段）。0.27.0 口径修订：服务端现
    /// 行版本对无围栏 PATCH 必回 409 client_upgrade_
    /// required（本包生产实证，旧「不带守卫」口径就
    /// 此作废）——实现内先 GET 取 runtime_revision、
    /// 带 request_id＋expected_revision 发，409 冲突
    /// 重读修订号重试一次；落定仍靠调用方 GET 回读
    /// 对账（立项档 O-4），2xx 只算服务端受理。
    /// 删除 409 热修后：修订号改读 mutation-snapshot
    /// （官方身份源），读不到如实上抛、不再裸发回退
    func updateServerSession(
        config: ServerConfig, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws
    /// POST /api/sessions/prune（0.18.0 清理区）：
    /// dryRun 先行给数、用户确认才真跑；回执条数多
    /// 键宽容提取（SessionPruneReceipt），取不到返
    /// 回 nil、界面如实显「条数未回」
    func pruneSessions(
        config: ServerConfig, olderThanDays: Double, dryRun: Bool
    ) async throws -> Int?

    /// GET /api/profiles
    func profiles(config: ServerConfig) async throws -> [ProfileItem]
    /// GET /api/profiles/active
    func activeProfileName(config: ServerConfig) async throws -> String?
    /// GET /api/profiles/active 全形（active 与 current
    /// 分开）：H1-d 身份对账要认 current（本进程实际
    /// 所辖档案），activeProfileName 的合并口径
    /// （active ?? current）不够用
    func activeProfile(
        config: ServerConfig
    ) async throws -> ActiveProfileResponse
    /// POST /api/profiles/active {name}
    func setActiveProfile(config: ServerConfig, name: String) async throws
    /// GET /api/profiles/{name}/soul（回执 schema 未冻结，
    /// ProfileSoulDocument 宽容解码；三期枢纽页身份段）
    func profileSoul(config: ServerConfig, name: String) async throws -> ProfileSoulDocument
    /// PUT /api/profiles/{name}/soul {content}（编辑由
    /// ProfilesView 承载，枢纽页只读不调）
    func updateProfileSoul(config: ServerConfig, name: String, content: String) async throws
    /// POST /api/profiles {name, clone_from?}（P10）
    func createProfile(
        config: ServerConfig, name: String, cloneFrom: String?
    ) async throws
    /// DELETE /api/profiles/{name}（P10）
    func deleteProfile(config: ServerConfig, name: String) async throws
    /// POST /api/profiles/{name}/export（P10；档案包生成
    /// 在服务器上，回执多形收引用，见 ProfileExportResult）
    func exportProfile(
        config: ServerConfig, name: String
    ) async throws -> ProfileExportResult
    /// POST /api/profiles/import {archive, name?}（P10；
    /// archive 是服务器上的档案包路径——导出产物同机
    /// 恢复的正道，本机文件无上传通道、不假装能传）
    func importProfile(
        config: ServerConfig, archive: String, name: String?
    ) async throws
    /// PATCH /api/profiles/{name} {new_name}（重命名分身，default 分身改写 display_name）
    func renameProfile(
        config: ServerConfig, name: String, newName: String
    ) async throws
    /// PUT /api/profiles/{name}/description {description}（编辑分身职责简介）
    func updateProfileDescription(
        config: ServerConfig, name: String, description: String
    ) async throws
    /// POST /api/profiles/{name}/describe-auto {overwrite}（辅助模型一键生成分身简介）
    func autoDescribeProfile(
        config: ServerConfig, name: String, overwrite: Bool
    ) async throws -> ProfileAutoDescribeResult
    /// PUT /api/profiles/{name}/model {provider, model}（为单个分身绑定专属模型）
    func updateProfileModel(
        config: ServerConfig, name: String, provider: String, model: String
    ) async throws

    /// GET /api/tools/computer-use/status（回执 schema
    /// 未冻结，ComputerUseStatus 宽容提取；浏览器段留口）
    func computerUseStatus(config: ServerConfig) async throws -> ComputerUseStatus

    /// GET /api/mcp/servers（P10；生产实样 {"servers":[…]}，
    /// 2026-11-09 只读联调验过，含 box 插件预置行）
    func mcpServers(config: ServerConfig) async throws -> [MCPServerItem]
    /// PUT /api/mcp/servers/{name}/enabled {enabled}
    func setMCPServerEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws
    /// POST /api/mcp/servers/{name}/test（回执多键宽容，
    /// 无显式信号不判成功，见 MCPTestResult）
    func testMCPServer(
        config: ServerConfig, name: String
    ) async throws -> MCPTestResult
    /// GET /api/mcp/catalog（§388 H7；Nous 批准目录＋本
    /// profile 的 installed/enabled 标注与诊断行）
    func mcpCatalog(config: ServerConfig) async throws -> MCPCatalogResponse
    /// POST /api/mcp/catalog/install {name, env, enable}
    /// （回执只当受理信号，落定靠回读目录对账）
    func installMCPCatalogEntry(
        config: ServerConfig, name: String, env: [String: String], enable: Bool
    ) async throws -> MCPInstallReceipt
    /// POST /api/mcp/servers（Hermes v0.23.0 添加自定义 Remote HTTP/SSE 或 stdio MCP 服务）
    func addMCPServer(
        config: ServerConfig, name: String, url: String?,
        command: String?, args: [String], env: [String: String],
        auth: String?, bearerToken: String?
    ) async throws
    /// DELETE /api/mcp/servers/{name}（移除自定义 MCP 服务）
    func deleteMCPServer(config: ServerConfig, name: String) async throws
    /// POST /api/mcp/servers/{name}/auth（发起 MCP OAuth 2.1 授权流，返回 authorization_url）
    func startMCPOAuthFlow(config: ServerConfig, name: String) async throws -> MCPOAuthFlowSnapshot
    /// GET /api/mcp/oauth/flows/{flow_id}（轮询 MCP OAuth 授权状态与工具发现）
    func pollMCPOAuthFlow(config: ServerConfig, flowID: String) async throws -> MCPOAuthFlowSnapshot
    /// DELETE /api/mcp/oauth/flows/{flow_id}（取消进行中的 MCP OAuth 授权流）
    func cancelMCPOAuthFlow(config: ServerConfig, flowID: String) async throws

    /// GET /api/config 全量（动态 JSON，原样保留未知字段）
    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue]
    /// PUT /api/config {config}（全量写回，调用方负责先读后改）
    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws

    /// GET /api/env（顶层字典，解码层已排序）
    func envVars(config: ServerConfig) async throws -> [EnvVarEntry]
    /// PUT /api/env {key, value}
    func setEnvVar(config: ServerConfig, key: String, value: String) async throws
    /// DELETE /api/env {key}（带 body 的 DELETE）
    func deleteEnvVar(config: ServerConfig, key: String) async throws
    /// POST /api/env/reveal {key} → 明文（响应形态宽容提取）
    func revealEnvVar(config: ServerConfig, key: String) async throws -> String

    /// GET /api/analytics/usage?days=
    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics
    /// GET /api/analytics/models?days=
    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics
    /// GET /api/model/options：上游提供商＋精选模型列表（官方
    /// ModelPickerDialog 同源端点）；回执未定型，经
    /// ModelCatalog.extractModelIDs 宽容提取为 id 列表
    func modelOptions(config: ServerConfig) async throws -> [String]
    /// GET /api/model/options 的原始回执整树（§153）：
    /// 顶栏全量分组（ChatModelGroups）与默认回读共用
    /// 一次取数——结构已于 2026-11-11 生产定型（顶层
    /// {provider, model, providers:[{slug, is_current,
    /// models}]}），不再只宽容提取 id 把分组扔掉
    func modelOptionsRaw(config: ServerConfig) async throws -> JSONValue
    /// POST /api/model/set {scope:"main", provider, model}：
    /// 全局默认指派的官方写面（§141）。具名服务商靠它落盘
    /// provider: custom:<名>；拍平的 config PUT 改不了
    /// provider，不许拿那条路冒充
    func setMainModel(
        config: ServerConfig, provider: String, model: String
    ) async throws
    /// GET /api/model/options 的结构化回读（§141）：当前
    /// 默认的归属（哪家服务商＋哪个模型），Core
    /// MainModelAssignment 解析、回读为准
    func mainModelAssignment(
        config: ServerConfig, providerNames: [String]
    ) async throws -> MainModelAssignment
    /// GET /api/logs?level=&search=&lines=
    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse
    /// GET /api/egress/status
    func egressStatus(config: ServerConfig) async throws -> EgressStatus

    /// GET /api/messaging/platforms（频道直连，API 直连 B 包）：
    /// Dashboard 原生频道状态全量载荷，映射口径在 OneDayCore
    /// MessagingStatusMapping；走 performAdmin（登录失效自动续登）
    func messagingPlatforms(config: ServerConfig) async throws -> MessagingPlatformsResponse
    /// PUT /api/messaging/platforms/{id}（频道凭据编排直连）：
    /// 只写 env 编排结果与启用位；服务端按平台目录校验 env 键，
    /// 非法键 400（detail 原文经 HermesError 上抛）。写后生效
    /// 由调用方再调 gatewayRestart 触发（桥时代同一时序）
    func updateMessagingPlatform(
        config: ServerConfig, platform: String, enabled: Bool,
        env: [String: String], clearEnv: [String]
    ) async throws

    /// POST /api/gateway/restart
    func gatewayRestart(config: ServerConfig) async throws
    /// POST /api/gateway/start
    func gatewayStart(config: ServerConfig) async throws
    /// POST /api/gateway/stop
    func gatewayStop(config: ServerConfig) async throws

    // MARK: 运维体检（H1-a，台账 158；契约据 H1-0 探活冻结）

    /// POST /api/ops/doctor：只触发后台自检动作、立即
    /// 回执 {ok,pid,name}——检查结果不在本响应里，走
    /// opsActionStatus 轮询日志解析（两段式）
    func opsDoctor(config: ServerConfig) async throws -> OpsSpawnResponse
    /// POST /api/ops/security-audit：同上两段式
    func opsSecurityAudit(config: ServerConfig) async throws -> OpsSpawnResponse
    /// GET /api/actions/{name}/status?lines=：动作状态
    /// ＋追加式共享日志尾（消费前须按 started 标记切
    /// 本轮，见 OneDayCore.OpsActionLog）
    func opsActionStatus(
        config: ServerConfig, name: String, lines: Int
    ) async throws -> OpsActionStatus
    /// POST /api/ops/backup：同上两段式，回执额外带
    /// archive 产物路径；服务端要 JSON body（Backup-
    /// Request{output?}），output 不填、服务端定名
    func opsBackup(config: ServerConfig) async throws -> OpsSpawnResponse
    /// GET /api/ops/checkpoints：同步结构化（现役实例
    /// 恒空，如实呈现）；prune 删除行为未知，不接
    func opsCheckpoints(
        config: ServerConfig
    ) async throws -> CheckpointsResponse

    // MARK: 服务端语音（H2-a，台账 159；契约据 H2-0
    // 探活＋开通复探冻结，见 OneDayCore.VoiceSpeech）

    /// GET /api/audio/voice-config：语音配置读面（可
    /// 用性总闸的数据源；判定口径在 Core VoiceAvai-
    /// lability，不许只读 mode/reason 判可用）
    func voiceConfig(config: ServerConfig) async throws -> VoiceConfigResponse
    /// POST /api/audio/speak {text}：服务端合成，回
    /// 执 JSON 内嵌 base64 data_url（非二进制流）；
    /// provider 未开通时 400 detail 明示， 实现映射
    /// 为 HermesError.speechProviderUnavailable
    func speak(config: ServerConfig, text: String) async throws -> SpeakResponse
    /// GET /api/audio/elevenlabs/voices：只读（现役
    /// 实例未配该 provider；音色展示不以它为准，
    /// 见 VoiceSpeech 头注）
    func elevenLabsVoices(config: ServerConfig) async throws -> ElevenLabsVoicesResponse

    // MARK: 设备认领（配对一期，台账 153/160）

    /// POST /v1/enrollment/codes（Bearer）：已登录侧
    /// 出码——领一次性认领码（5 分钟、待领上限 3），
    /// 给新设备扫码入驻（设置「添加设备」面）
    func issueEnrollmentCode(
        config: ServerConfig, apiKey: String
    ) async throws -> EnrollmentIssue
    /// POST /v1/enrollment/claim（免鉴权，码即凭据）：
    /// 扫码侧认领——成功回登录密钥＋服务器指纹；失
    /// 败按网关错误码分型（无效/过期/锁定）
    func claimEnrollment(
        config: ServerConfig, code: String
    ) async throws -> EnrollmentClaim
    /// POST /v1/push/tokens（Bearer）：登记/刷新本机
    /// APNs 令牌（总表 138，批 4b §4.1 草案契约）——
    /// 服务端未装机时回 404（pushEndpointNotReady），
    /// 调用方如实分型，不许冒充已登记
    func registerPushToken(
        config: ServerConfig, apiKey: String,
        body: PushTokenRegistrationBody
    ) async throws -> PushTokenRegisteredResponse

    // MARK: 短时票据与会话管理（#1 短时票据）

    /// POST /v1/auth/token（Bearer 长期登录钥）：换取 24h 短时访问票据＋30d 滑动换票凭据
    func exchangeShortLivedToken(
        config: ServerConfig, apiKey: String,
        deviceName: String?, appVersion: String?
    ) async throws -> ShortLivedTokenPair
    /// POST /v1/auth/refresh（免 Bearer，凭 refresh_token 轮换）：返回新票据对
    func refreshShortLivedToken(
        config: ServerConfig, refreshToken: String
    ) async throws -> ShortLivedTokenPair
    /// GET /v1/auth/sessions（Bearer）：列出当前已签发的设备会话
    func listAuthSessions(
        config: ServerConfig, apiKey: String
    ) async throws -> [AuthSessionSummary]
    /// DELETE /v1/auth/sessions/{session_id}（Bearer）：立即撤销指定设备会话
    func revokeAuthSession(
        config: ServerConfig, apiKey: String, sessionID: String
    ) async throws -> AuthRevokeReceipt

    // MARK: 命令授权（批 5，DESIGN §355；网关 Bearer 面）

    /// GET /v1/grants（Bearer）：统一授权清单——exec
    /// 命令授权＋写闸规则只读投影两源拼合（部署包
    /// 1.3.0）；双源皆败服务端回 503（不回假空清单），
    /// 单源败回 partial＋失败半边计数 null，模型如实
    /// 承接（GrantsListResponse）
    func listGrants(
        config: ServerConfig, apiKey: String
    ) async throws -> GrantsListResponse
    /// POST /v1/grants/revoke（Bearer）{source:"exec",
    /// pattern_key}：撤销一条 exec 命令授权（服务端
    /// 连别名一并删、端点内双自检）；写闸条目不走本
    /// 端点（服务端 400 wrong_channel，客户端结构上
    /// 不发）。非 2xx 以 serverError 连码上行供
    /// GrantRevokeDirective 分型；成败终局以事后清
    /// 单回读为准、不认回执自报
    func revokeGrant(
        config: ServerConfig, apiKey: String, patternKey: String
    ) async throws -> GrantRevocationReceipt

    // MARK: 待批聚合与只读探针（部署包批 2；DESIGN §357 连接自检）

    /// GET /v1/approvals（Bearer）：跨会话待批聚合
    /// ——待批计数＋账本降级旗（部署包 1.2.0）；投
    /// 影模块不可用回 503 approval_projection_
    /// unavailable，连码上行供呈现层分型
    func listApprovals(
        config: ServerConfig, apiKey: String
    ) async throws -> ApprovalsListResponse
    /// 只读路由探针（连接自检专用）：GET 指定路径，
    /// 只回状态码＋服务端错误码、永不抛错——传输失
    /// 败回 nil（呈现层据此显「未探」，不下结论）。
    /// 判据按部署包 CAPABILITIES 探针法（405＝POST
    /// 路由在位；404 结合错误码分流）。apiKey 为 nil
    /// 时不带 Bearer（免鉴权路由照探）
    func routeProbe(
        config: ServerConfig, apiKey: String?, path: String
    ) async -> RouteProbeResult?

    // MARK: 平台用户配对（H5，DESIGN §359；Dashboard cookie 面）

    /// GET /api/pairing（cookie）：消息平台用户配对
    /// 两列——待批（永不回码本体、只回 request_id）
    /// ＋已批准白名单。与设备 enrollment 是两物（见
    /// PairingModels 头注）。401 由 performAdmin 自动
    /// 重登兜底、终局 sessionExpired
    func pairingList(
        config: ServerConfig
    ) async throws -> PairingListResponse
    /// POST /api/pairing/approve {platform, request_id}：
    /// 按申请编号批准（不经手配对码本体）；404＝已过
    /// 期/已被处理、429＝平台锁定，均以 unexpected-
    /// Status 连码上行供 PairingActionDirective 分型；
    /// 成败终局以事后清单回读为准、不认回执自报
    func pairingApprove(
        config: ServerConfig, platform: String, requestID: String
    ) async throws -> PairingApproveReceipt
    /// POST /api/pairing/revoke {platform, user_id}：
    /// 把用户移出平台白名单（服务端同步镜像 allow-
    /// list）；404＝不在名单，同上行分型、回读为准
    func pairingRevoke(
        config: ServerConfig, platform: String, userID: String
    ) async throws
    /// POST /api/pairing/clear-pending：清空全部平台
    /// 待批（无按平台参数）；回执 cleared 为实清条数，
    /// 回读待批列为空才算清干净
    func pairingClearPending(
        config: ServerConfig
    ) async throws -> PairingClearPendingReceipt

    // MARK: 工具集治理（台账 34，DESIGN §358）

    /// GET /v1/toolsets（Bearer）：api_server 平台真值
    /// 清单——手机会话实际能用的工具集逐行 enabled/
    /// configured/tools（9119 的 /api/tools/toolsets 是
    /// 配置面视图、enabled 按 cli 等配置平台计，不作
    /// 本面真源）
    func toolsets(
        config: ServerConfig, apiKey: String
    ) async throws -> ToolsetsListResponse
    /// PUT /v1/toolsets/{name}（Bearer，34-S 新端点，
    /// 部署包 1.4.0）{enabled}：启停写 platform_
    /// toolsets.api_server（config-only 集镜像写自家
    /// config 节 enabled）；对新构建的 run 立即生效、
    /// 存量 run 不受影响。未知集 400 unknown_toolset
    /// 等错误连码上行供 ToolsetToggleDirective 分型；
    /// 成败终局以事后清单回读为准、不认回执自报
    func setToolsetEnabled(
        config: ServerConfig, apiKey: String,
        name: String, enabled: Bool
    ) async throws -> ToolsetToggleReceipt
    /// GET /api/tools/toolsets/{name}/config（9119 会
    /// 话）：细调面板——provider 矩阵＋各 provider 的
    /// env 密钥状态（只回 is_set、永不回值）
    func toolsetConfig(
        config: ServerConfig, name: String
    ) async throws -> ToolsetConfigPanel
    /// PUT /api/tools/toolsets/{name}/provider（9119
    /// 会话）{provider}：选服务商，写全局 config、全
    /// 平台生效；成败以事后回读面板为准
    func selectToolsetProvider(
        config: ServerConfig, name: String, provider: String
    ) async throws
    /// GET /api/tools/toolsets/{name}/models（9119 会
    /// 话）：后端模型目录（仅有目录的集 has_models）
    func toolsetModels(
        config: ServerConfig, name: String
    ) async throws -> ToolsetModelCatalog
    /// PUT /api/tools/toolsets/{name}/model（9119 会
    /// 话）{model}：选后端模型，写全局 config、全平台
    /// 生效；成败以事后回读目录为准
    func selectToolsetModel(
        config: ServerConfig, name: String, model: String
    ) async throws
    /// GET /api/tools/terminal/backends（9119 会话）：
    /// 终端后端清单＋健康状态（ready/needs_setup/
    /// unavailable 原样承接）
    func terminalBackends(
        config: ServerConfig
    ) async throws -> TerminalBackends
    /// PUT /api/tools/terminal/backend（9119 会话）
    /// {backend}：选终端后端，写全局 config ter-
    /// minal.backend、全平台生效；成败以事后回读为准
    func selectTerminalBackend(
        config: ServerConfig, backend: String
    ) async throws

    // MARK: 高级能力面（H8 委派路由／H9 MoA＋辅助端点／H11
    // Webhooks／H13 小件，DESIGN §390；Dashboard cookie 面，
    // 契约见 OneDayCore.HermesAdvancedModels 头注）

    /// GET /api/delegation/routing：委派路由全量——现行后端
    /// （含跑不了的原因）＋已注册后端＋模型路由＋档案路由
    func delegationRouting(
        config: ServerConfig
    ) async throws -> DelegationRouting
    /// PUT /api/delegation/backend {backend}：切换委派后端；
    /// 成败终局以 delegationRouting 回读为准、不认回执自报
    func setDelegationBackend(
        config: ServerConfig, backend: String
    ) async throws
    /// PUT /api/delegation/backends/model_map {options,
    /// default}：模型路由整块替换（服务端逐条校验）
    func setDelegationModelMap(
        config: ServerConfig, routes: [DelegationModelRoute],
        defaultRoute: String?
    ) async throws
    /// PUT /api/delegation/backends/profile_routes
    /// {profiles, default}：档案路由整块替换
    func setDelegationProfileRoutes(
        config: ServerConfig, routes: [DelegationProfileRoute],
        defaultRoute: String?
    ) async throws
    /// GET /api/model/moa：MoA 预设全图（normalize 形）
    func moaConfig(config: ServerConfig) async throws -> MoaConfig
    /// PUT /api/model/moa：MoA 整图写回；回执即服务端
    /// normalize 后的真值（写后回读同体，不另拉）
    func setMoaConfig(
        config: ServerConfig, moa: MoaConfig
    ) async throws -> MoaConfig
    /// GET /api/model/auxiliary：辅助用途现行分配（专用
    /// 端点，与 config 的 auxiliary 节同源同值）
    func auxiliaryTasks(
        config: ServerConfig
    ) async throws -> AuxiliaryTasksResponse
    /// POST /api/model/set {scope, task?, provider, model,
    /// confirm_expensive_model}：主槽或单个辅助槽赋值；
    /// 贵模型未确认回 ok=false＋confirm_required（非错误）
    func setModelAssignment(
        config: ServerConfig, scope: String, task: String?,
        provider: String, model: String, confirmExpensive: Bool
    ) async throws -> ModelSetReceipt
    /// GET /api/webhooks：平台开关＋订阅清单（摘要无密钥）
    func webhooksPage(config: ServerConfig) async throws -> WebhooksPage
    /// POST /api/webhooks：建订阅；回执带一次性密钥（只此一次）
    func createWebhook(
        config: ServerConfig, input: WebhookCreateInput
    ) async throws -> WebhookCreateReceipt
    /// DELETE /api/webhooks/{name}：删订阅（成败以回读为准）
    func deleteWebhook(config: ServerConfig, name: String) async throws
    /// PUT /api/webhooks/{name}/enabled {enabled}：启停一条
    /// （热生效、不重启网关）
    func setWebhookEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws
    /// POST /api/webhooks/enable：开 webhook 平台（服务端
    /// 伴随网关重启编排，回 needs_restart 供呈现如实交代）
    func enableWebhooks(
        config: ServerConfig
    ) async throws -> WebhooksEnableReceipt
    /// GET /api/curator：技能策展状态（启用/暂停/节奏/上次运行）
    func curatorStatus(config: ServerConfig) async throws -> CuratorStatus
    /// PUT /api/curator/paused {paused}：暂停/恢复策展
    func setCuratorPaused(config: ServerConfig, paused: Bool) async throws
    /// POST /api/curator/run：立即跑一次策展（后台动作；
    /// profile 非空时带 ?profile= 指名，多档案在役时服务端
    /// 拒绝对无名目标执行）
    func runCurator(
        config: ServerConfig, profile: String?
    ) async throws -> OpsSpawnResponse
    /// GET /api/sessions/stats：会话存储统计（名单折行同口径）
    func sessionStoreStats(
        config: ServerConfig
    ) async throws -> SessionStoreStats
    /// GET /api/ops/hooks：已配置 shell 钩子＋同意状态（只读）
    func opsHooks(config: ServerConfig) async throws -> OpsHooksPage

    // MARK: 消息反应（台账 187；网关 Bearer 面，与认领同族）

    /// PUT /v1/reactions/{session_id}/{row_id} {emoji}：
    /// 给一条服务端消息行点反应——服务端 Tapback 语
    /// 义（一人一条、异点替换）＋handler 幂等归一（同
    /// 值重试不撤回）；回执是该行写后反应全集，客户
    /// 端以它覆写镜像。行不在会话谱系→404 message_
    /// not_found，映射 HermesError.reactionTargetGone
    func setReaction(
        config: ServerConfig, apiKey: String,
        sessionID: String, rowID: Int, emoji: String
    ) async throws -> ReactionUpdate
    /// DELETE /v1/reactions/{session_id}/{row_id}：撤
    /// 回自己的反应——无反应时服务端同样回 200 空集
    /// （幂等），回执同上
    func clearReaction(
        config: ServerConfig, apiKey: String,
        sessionID: String, rowID: Int
    ) async throws -> ReactionUpdate

    // MARK: 工作区文件与系统（0.2.1）

    /// GET /api/files?path=（path 为 nil 时服务端回默认根，
    /// 2026-11-08 实查根被 locked_root 锁在 /opt/data）
    func files(config: ServerConfig, path: String?) async throws -> FilesListing
    /// DELETE /api/files {path, recursive}
    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws
    /// GET /api/files/download?path= → 原始字节（预览/下载共用）
    func fileData(config: ServerConfig, path: String) async throws -> Data
    /// 同端点带字节进度版（§452 聊天文件卡下载态）：
    /// onProgress 实报 (已收字节, 预计总字节)，预计
    /// 未知时 expected ≤ 0
    func fileDataWithProgress(
        config: ServerConfig, path: String,
        onProgress: @escaping @Sendable (_ received: Int64, _ expected: Int64) -> Void
    ) async throws -> Data
    /// POST /api/files/upload {path, data_url, overwrite}
    /// （openapi ManagedFileUpload，2026-11-09 据 docs 内
    /// OpenAPI 组件 schema 实查；与列表/删除同一 9119 会话
    /// 通道、同一 locked_root 约束。回执形态不依赖，调用
    /// 方以回读列表对账落定）
    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws
    /// 同端点解码版（0.36.29 文件真发送）：发送拼装
    /// 要回执 entry.path 拼 @file 引用，不能走「回读
    /// 对账」的哑版；契约见 file-upload-contract-
    /// 20261111（attachments/ 落点＋回执形态实测冻结）
    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String
    ) async throws -> ManagedFileUploadReceipt
    /// §237（P7）：同端点带真实字节进度版——进度
    /// 回调收到的是本次请求体的已发送比例（0...1，
    /// 由 URLSession 的 didSendBodyData 实报，不许
    /// 定时器估算）；取消经 Swift Task 取消传导，
    /// 取消错误以 CancellationError 形态上抛。
    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt
    /// §410：原始字节版——data_url 与请求体组包在客
    /// 户端内后台完成（流式写临时文件），调用方（主
    /// actor 发送链）不再付 base64＋JSON 体的同步成
    /// 形成本与 ≈2.7× 瞬时内存。语义与 dataURL 版一
    /// 致（同端点/同请求体/同进度口径）
    func uploadAttachment(
        config: ServerConfig, path: String, fileName: String,
        data: Data,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt
    /// POST /api/files/mkdir {path}（openapi
    /// ManagedDirectoryCreate，同上口径，回读确认）
    func makeDirectory(config: ServerConfig, path: String) async throws
    /// GET /api/system/stats
    func systemStats(config: ServerConfig) async throws -> SystemStats

    // MARK: 任务（P3：kanban 薄适配，9119 插件面）

    /// GET /api/plugins/kanban/workflow（版本探针：列集合校验）
    func kanbanWorkflow(config: ServerConfig) async throws -> KanbanWorkflow
    /// GET /api/plugins/kanban/boards → 板 slug 清单（专属板存在性判定）
    func kanbanBoards(config: ServerConfig) async throws -> [String]
    /// GET /api/plugins/kanban/board?board=
    func kanbanBoard(config: ServerConfig, board: String) async throws -> KanbanBoardSnapshot
    /// GET /api/plugins/kanban/tasks/{id}?board=
    func kanbanTaskDetail(config: ServerConfig, board: String, id: String) async throws -> KanbanTaskDetail
    /// POST /api/plugins/kanban/tasks?board=（建卡，初始 ready）
    func kanbanCreateTask(
        config: ServerConfig, board: String, title: String, body: String,
        idempotencyKey: String
    ) async throws -> KanbanTask
    /// POST /api/plugins/kanban/dispatch?board=（催派）
    func kanbanDispatch(config: ServerConfig, board: String) async throws -> KanbanDispatchReceipt
    /// PATCH /api/plugins/kanban/tasks/{id}?board= {status}
    func kanbanPatchTaskStatus(
        config: ServerConfig, board: String, id: String, status: String
    ) async throws
    /// DELETE /api/plugins/kanban/tasks/{id}?board=
    func kanbanDeleteTask(config: ServerConfig, board: String, id: String) async throws
    /// POST /api/plugins/kanban/tasks/{id}/comments?board=（答题注入）
    func kanbanComment(
        config: ServerConfig, board: String, id: String, body: String
    ) async throws
    /// POST /api/plugins/kanban/tasks/{id}/reclaim?board=（急停释放 claim）
    func kanbanReclaimTask(config: ServerConfig, board: String, id: String) async throws
    /// POST /api/plugins/kanban/tasks/{id}/decompose?board=
    /// （H8 附带，DESIGN §390）：把一张 triage 任务用辅助
    /// 模型拆成子任务；非 ok 不是 HTTP 错误——回执 reason
    /// 是服务端原文，成败以回执＋看板回读为准
    func kanbanDecompose(config: ServerConfig, board: String, id: String) async throws -> KanbanDecomposeReceipt
    /// POST /api/plugins/kanban/runs/{run_id}/terminate?board=（停止当前运行）
    func kanbanTerminateRun(config: ServerConfig, board: String, runID: Int) async throws
}

/// URLSession 实现。会话 cookie 走 .shared 存储：登录一次，
/// 后续 /api/* 自动带上；进程重启后 cookie 仍在（系统持久化），
/// 过期则由 AppState 的自动重登兜底。
extension HermesClientProtocol {
    /// §410 默认实现（测试替身/演示客户端用）：拼
    /// data_url 后转调既有 dataURL 版，行为与旧链一
    /// 致；真实客户端覆盖为后台流式组包版
    func uploadAttachment(
        config: ServerConfig, path: String, fileName: String,
        data: Data,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt {
        try await uploadAttachment(
            config: config, path: path,
            dataURL: FileSendAssembly.dataURL(
                fileName: fileName, data: data
            ),
            onProgress: onProgress
        )
    }

    /// 兼容旧调用方（未传 afterRowID 时默认为 nil）
    func sessionMessagesPage(
        config: ServerConfig, id: String, limit: Int, offset: Int
    ) async throws -> [SessionMessage] {
        try await sessionMessagesPage(
            config: config, id: id, limit: limit, offset: offset,
            afterRowID: nil
        )
    }

    func steerRun(
        config: ServerConfig, apiKey: String, runID: String, input: String
    ) async throws -> RunSteerReceipt {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("纠偏接口"), status: 501)
    }

    func respondRunApproval(
        config: ServerConfig, apiKey: String, runID: String,
        requestID: String?, choice: String, executionGeneration: Int?
    ) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("运行审批接口"), status: 501)
    }

    func respondRunClarify(
        config: ServerConfig, apiKey: String, runID: String,
        requestID: String, answer: String, executionGeneration: Int?
    ) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("运行澄清接口"), status: 501)
    }

    func forkServerSession(
        config: ServerConfig, apiKey: String, id: String, title: String?
    ) async throws -> ServerSession {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("会话分支接口"), status: 501)
    }

    func uploadCrashReports(
        config: ServerConfig, apiKey: String, reports: [CrashReportRecord]
    ) async throws -> CrashReportsUploadReceipt {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("崩溃上报接口"), status: 501)
    }

    func listServerCrashReports(
        config: ServerConfig, apiKey: String, limit: Int
    ) async throws -> [ServerCrashReportItem] {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("崩溃上报列表"), status: 501)
    }

    func memoryLayers(
        config: ServerConfig, apiKey: String
    ) async throws -> [MemoryLayerSummary] {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("记忆分层接口"), status: 501)
    }

    func searchLayeredMemory(
        config: ServerConfig, apiKey: String, query: String,
        limit: Int, mode: String
    ) async throws -> [MemorySearchHit] {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("记忆语义检索"), status: 501)
    }

    func memoryInsights(
        config: ServerConfig, apiKey: String
    ) async throws -> [MemoryInsightItem] {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("记忆洞察接口"), status: 501)
    }

    /// §452 默认实现（测试替身用）：无增量进度，
    /// 完成后回一次满格；真实客户端覆盖为带进
    /// 度回调版。
    func fileDataWithProgress(
        config: ServerConfig, path: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> Data {
        let data = try await fileData(config: config, path: path)
        onProgress(Int64(data.count), Int64(data.count))
        return data
    }

    func exchangeShortLivedToken(
        config: ServerConfig, apiKey: String,
        deviceName: String?, appVersion: String?
    ) async throws -> ShortLivedTokenPair {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("短时票据签发"), status: 501)
    }

    func refreshShortLivedToken(
        config: ServerConfig, refreshToken: String
    ) async throws -> ShortLivedTokenPair {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("短时票据刷新"), status: 501)
    }

    func listAuthSessions(
        config: ServerConfig, apiKey: String
    ) async throws -> [AuthSessionSummary] {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("登录会话列表"), status: 501)
    }

    func revokeAuthSession(
        config: ServerConfig, apiKey: String, sessionID: String
    ) async throws -> AuthRevokeReceipt {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("撤销登录会话"), status: 501)
    }

    func addMCPServer(
        config: ServerConfig, name: String, url: String?,
        command: String?, args: [String], env: [String: String],
        auth: String?, bearerToken: String?
    ) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("添加 MCP 服务"), status: 501)
    }

    func deleteMCPServer(config: ServerConfig, name: String) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("删除 MCP 服务"), status: 501)
    }

    func renameProfile(config: ServerConfig, name: String, newName: String) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("分身重命名"), status: 501)
    }

    func updateProfileDescription(config: ServerConfig, name: String, description: String) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("分身简介"), status: 501)
    }

    func autoDescribeProfile(config: ServerConfig, name: String, overwrite: Bool) async throws -> ProfileAutoDescribeResult {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("自动生成分身简介"), status: 501)
    }

    func updateProfileModel(config: ServerConfig, name: String, provider: String, model: String) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("分身模型绑定"), status: 501)
    }

    func startMCPOAuthFlow(config: ServerConfig, name: String) async throws -> MCPOAuthFlowSnapshot {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("MCP OAuth 授权"), status: 501)
    }

    func pollMCPOAuthFlow(config: ServerConfig, flowID: String) async throws -> MCPOAuthFlowSnapshot {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("MCP OAuth 状态"), status: 501)
    }

    func cancelMCPOAuthFlow(config: ServerConfig, flowID: String) async throws {
        throw HermesError.unexpectedStatus(endpoint: L10n.string("取消 MCP OAuth"), status: 501)
    }
}

/// §410：/api/files/upload 请求体的流式拼装器（纯
/// Foundation、无网络）：先以占位串编码信封——path
/// 的 JSON 转义仍由 JSONEncoder 负责、与旧链同口
/// 径；再把占位段替换为 data: 头＋分片 base64 写
/// 出。源 Data 只被分片读，不整份转串、不整份成
/// JSON 体，组包段瞬时内存从 ≈2.7× 文件大小降到
/// 分片量级（64KB）
enum UploadBodyFile {
    static func make(
        path: String, fileName: String, data: Data
    ) throws -> URL {
        // 占位段：纯 ASCII、JSONEncoder 不转义，信封
        // 编码后按字节定位替换；§410 接管修：每次调
        // 用 UUID 化——固定串若恰出现在 path 内会命
        // 中错位、静默写坏请求体，UUID 化整类消除
        let placeholder = "ODUPLOAD-\(UUID().uuidString)"
        let header = "data:"
            + FileBrowserLogic.mimeType(forFileName: fileName)
            + ";base64,"
        let envelope = try JSONEncoder().encode([
            "path": JSONValue.string(path),
            "data_url": JSONValue.string(header + placeholder),
            "overwrite": JSONValue.bool(true),
        ])
        let marker = Data(placeholder.utf8)
        guard let markerRange = envelope.range(of: marker)
        else {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("文件上传")
            )
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "od-upload-\(UUID().uuidString).json"
            )
        FileManager.default.createFile(
            atPath: url.path, contents: nil
        )
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(
                contentsOf: envelope[..<markerRange.lowerBound]
            )
            // 分片 base64：片长取 3 的倍数，非末片编码
            // 无填充、与整份编码逐字一致；末片填充由
            // base64EncodedData 按标准补齐
            let chunkSize = 57 * 1_024
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                try handle.write(
                    contentsOf: data
                        .subdata(in: offset..<end)
                        .base64EncodedData()
                )
                offset = end
            }
            try handle.write(
                contentsOf: envelope[markerRange.upperBound...]
            )
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return url
    }
}

final class HermesClient: HermesClientProtocol, @unchecked Sendable {
    /// 短请求会话（探活/提交/状态/会话面等普通请求）
    let session: URLSession
    /// 流式会话（0.36.20，§86.5）：只供 events 订阅与
    /// 遗留 chatStream——会话级空闲超时与请求级同为
    /// 600，把「会话级 30 与请求级 600 谁支配流空闲判
    /// 死」的口径之争从构造上掐死（见 §86.5 定谳）
    let streamSession: URLSession
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    /// 业务成功信号（0.36.20，§86.2）：任一业务端点
    /// 收到完整 HTTP 响应（任何状态码——收到响应本身
    /// 即证明通道可达）时回调一次，供 AppState 转给
    /// 在线判定清零（治审计 R4：业务与探活互不作证）。
    /// /health 不在此列（探活有自己的记账，别让探活
    /// 的响应先把失败计数洗掉）。回调在 URLSession 队
    /// 列触发、非隔离，转手方须自行跳回主隔离
    var onTransportSuccess: (@Sendable () -> Void)? {
        get { OneDayNetworkTransport.shared.onTransportSuccess }
        set { OneDayNetworkTransport.shared.onTransportSuccess = newValue }
    }

    init() {
        // 第五批 #2：HermesClient 与所有 BridgeClient 共用同一 OneDayNetworkTransport 连接池与传输通道
        session = OneDayNetworkTransport.shared.standardSession
        streamSession = OneDayNetworkTransport.shared.streamSession
    }

    // MARK: - 基础请求

    /// 网络层错误统一映射（0.20.0 收敛）：分型表归
    /// OneDayCore.HermesError.fromURLError 单测把守——
    /// 瞬断类（连接丢失/系统报无网/超时/连不上主机）
    /// 归 transientNetwork（文案只提示重试、不许甩锅
    /// 查地址），只有主机名解析失败留 unreachable 查
    /// 地址档。旧映射把瞬断全塞进 unreachable「网络
    /// 不可用＋检查地址」是 23:35「词与事实打架」的
    /// 出处，本版废止
    func mapNetworkError(_ error: Error) -> HermesError {
        if let hermesError = error as? HermesError {
            return hermesError
        }
        guard let urlError = error as? URLError else {
            return .unreachable(L10n.string("网络错误"))
        }
        return HermesError.fromURLError(urlError)
    }

    func dataRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await OneDayNetworkTransport.shared.performHTTP(
                request, using: session
            )
        } catch let error as HermesError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// 拼 query 的 URL：path 里已带路径参数时用 URLComponents 挂参
    func url(
        config: ServerConfig, path: String, query: [URLQueryItem] = []
    ) -> URL {
        let base = config.endpoint(path)
        guard !query.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        components.queryItems = query
        return components.url ?? base
    }

    func getJSON<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        query: [URLQueryItem] = [], bearer: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        var request = URLRequest(url: url(config: config, path: path, query: query))
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// Bearer GET＋解码（网关面只读三式：能力发现/深
    /// 度健康/待批聚合）：401/403 → apiKeyRejected；
    /// 其余非 200 统一经 HermesError.fromHTTPResponse 拦截
    func bearerGetJSON<T: Decodable>(
        config: ServerConfig, apiKey: String, path: String,
        endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// Bearer POST＋编码请求体＋解码响应：401/403 → apiKeyRejected；
    /// 其余非 2xx 统一经 HermesError.fromHTTPResponse 拦截
    func bearerPostJSON<T: Decodable, B: Encodable>(
        config: ServerConfig, apiKey: String, path: String,
        body: B, endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// 带 JSON body 的写请求：2xx 即成功；非 2xx 统一经错误码拦截器解析人话。
    func sendJSON(
        config: ServerConfig, path: String, method: String, endpoint: String,
        body: [String: JSONValue]? = nil, timeout: TimeInterval? = nil,
        query: [URLQueryItem] = []
    ) async throws {
        var request = URLRequest(url: url(config: config, path: path, query: query))
        request.httpMethod = method
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
    }

    /// 写请求并解码回执（创建类接口返回新建对象时使用）；
    /// 非 2xx 统一经 HermesError.fromHTTPResponse 提取结构化错误码与人话映射。
    func sendJSONDecoding<T: Decodable>(
        config: ServerConfig, path: String, method: String, endpoint: String,
        body: [String: JSONValue], bearer: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.fromHTTPResponse(
                endpoint: endpoint,
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    // MARK: - 探活与接口

    func health(config: ServerConfig) async throws -> HealthResponse {
        var request = URLRequest(url: config.endpoint("/health"))
        request.timeoutInterval = 15
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.healthCheckFailed(status: http.statusCode)
        }
        do {
            return try decoder.decode(HealthResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("健康检查"))
        }
    }

    func login(config: ServerConfig, username: String, password: String) async throws {
        // §244 一把密码统一（用户 2026-11-12 拍板）：不再直连
        // Hermes 9119 的部署密码登录——改走伴生登录桥
        // /api/companion/web-login，与网页端同一条链：桥以
        // 面板密码的 scrypt 校验验人（与面板登录同一限速池），
        // 验过后在服务器内部用部署凭据换 dashboard 会话
        // cookie 原样透传回来；部署密码永不出服务器、用户
        // 只需要记得面板这一把。cookie 落 URLSession 共享
        // 存储，后半程 revealEnvVar 换钥与旧直连链完全一致。
        var request = URLRequest(url: config.endpoint("/api/companion/web-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["username": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw HermesError.loginRejected
        case 429:
            throw HermesError.loginRateLimited
        default:
            throw HermesError.loginFailed(status: http.statusCode)
        }
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        try await getJSON(config: config, path: "/api/status", endpoint: L10n.string("状态接口"))
    }

    func updateCheck(config: ServerConfig) async throws -> UpdateCheckResponse {
        try await getJSON(
            config: config, path: "/api/hermes/update/check",
            endpoint: L10n.string("更新检查")
        )
    }

    func updateReceipt(config: ServerConfig) async throws -> UpdateReceiptResponse {
        // 404 是本部署常态（从不在容器内跑 update）：
        // 映射专属空态，不走 unexpectedStatus 通用失败面
        var request = URLRequest(url: config.endpoint("/api/hermes/update/receipt"))
        let (data, http) = try await dataRequest(request)
        if http.statusCode == 404 {
            throw UpdateReceiptError.absent
        }
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("更新回执"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(UpdateReceiptResponse.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("更新回执"))
        }
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        try await getJSON(config: config, path: "/api/config", endpoint: L10n.string("配置接口"))
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: config.endpoint("/v1/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(endpoint: L10n.string("模型接口"), status: http.statusCode)
        }
        do {
            return try decoder.decode(ModelsResponse.self, from: data).ids
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("模型接口"))
        }
    }

    func capabilities(
        config: ServerConfig, apiKey: String
    ) async throws -> CapabilitiesResponse {
        try await bearerGetJSON(
            config: config, apiKey: apiKey, path: "/v1/capabilities",
            endpoint: L10n.string("能力接口")
        )
    }

    func mailMessages(
        config: ServerConfig, apiKey: String, limit: Int = 50,
        offset: Int = 0
    ) async throws -> MailMessagesResponse {
        try await bearerGetJSON(
            config: config, apiKey: apiKey,
            path: "/v1/mail/messages?limit=\(limit)&offset=\(offset)",
            endpoint: L10n.string("邮件列表")
        )
    }

    func mailMessage(
        config: ServerConfig, apiKey: String, accountID: String,
        folder: String, uid: Int
    ) async throws -> MailMessage {
        let pathComponentCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        let account = accountID.addingPercentEncoding(
            withAllowedCharacters: pathComponentCharacters
        ) ?? accountID
        let mailbox = folder.addingPercentEncoding(
            withAllowedCharacters: pathComponentCharacters
        ) ?? folder
        return try await bearerGetJSON(
            config: config, apiKey: apiKey,
            path: "/v1/mail/messages/\(account)/\(mailbox)/\(uid)",
            endpoint: L10n.string("邮件详情")
        )
    }

    func mailDrafts(
        config: ServerConfig, apiKey: String
    ) async throws -> MailDraftsResponse {
        try await bearerGetJSON(
            config: config, apiKey: apiKey,
            path: "/v1/mail/drafts",
            endpoint: L10n.string("草稿列表")
        )
    }

    func createMailDraft(
        config: ServerConfig, apiKey: String, request: CreateDraftRequest
    ) async throws -> MailDraft {
        try await bearerPostJSON(
            config: config, apiKey: apiKey,
            path: "/v1/mail/drafts",
            body: request,
            endpoint: L10n.string("创建草稿")
        )
    }

    func sendMailDraft(
        config: ServerConfig, apiKey: String, draftID: String,
        request: SendDraftRequest
    ) async throws {
        let _: EmptyResponse = try await bearerPostJSON(
            config: config, apiKey: apiKey,
            path: "/v1/mail/drafts/\(draftID)/send",
            body: request,
            endpoint: L10n.string("发送邮件")
        )
    }

    func settingsRegistry(
        config: ServerConfig, apiKey: String
    ) async throws -> SettingsRegistryResponse {
        try await bearerGetJSON(
            config: config, apiKey: apiKey,
            path: "/v1/settings/registry",
            endpoint: L10n.string("设置注册表接口")
        )
    }

    func healthDetailed(
        config: ServerConfig, apiKey: String
    ) async throws -> HealthDetailedResponse {
        try await bearerGetJSON(
            config: config, apiKey: apiKey, path: "/health/detailed",
            endpoint: L10n.string("深度健康接口")
        )
    }

    // MARK: - 流式聊天

    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage],
        sessionID: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: config.endpoint("/v1/chat/completions"))
                    request.httpMethod = "POST"
                    // 0.21.0 会话模式：带上会话头，服务端
                    // 从 state.db 续该会话历史并把本轮交
                    // 换落进同一会话（研究档两轮记忆探针
                    // 实测背书）；nil 时请求与旧链逐字同
                    if let sessionID {
                        request.setValue(
                            sessionID, forHTTPHeaderField: "X-Hermes-Session-Id"
                        )
                    }
                    // 长回复逐字到达：单请求超时放宽到 10 分钟，
                    // 停止生成走 task.cancel()（onTermination 承接）
                    request.timeoutInterval = 600
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    // 0.8.0 修复（P1 实查）：消息按 ChatMessage
                    // 的 Codable 形态序列化——此前手工拼
                    // role/content 两字段，多模态消息的
                    // image_url parts 在出门前被丢弃、图片
                    // 从未真正发出去（模型层 parts 已落地、
                    // 客户端接线漏了这一环）
                    let messageObjects: [[String: Any]] = try messages.map { message in
                        let data = try JSONEncoder().encode(message)
                        let object = try JSONSerialization
                            .jsonObject(with: data)
                        return object as? [String: Any]
                            ?? ["role": message.role,
                                "content": message.content]
                    }
                    var payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messageObjects,
                    ]
                    // 逐请求切上游（0.3.0 接线，DESIGN-V4 §15）：
                    // 清单内模型带 provider=custom——网关裸
                    // model 不认、带此字段才按名落上游渠道
                    // （服务器实测口径，见 ChatModels 文件头）
                    if let provider = ChatModels.providerField(for: model) {
                        payload["provider"] = provider
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    // 流式走流式会话（§86.5：会话级空闲
                    // 超时同为 600，不与短请求共用 30 的会话）
                    let (bytes, response) = try await streamSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesError.unreachable(L10n.string("无响应"))
                    }
                    guard http.statusCode == 200 else {
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw HermesError.apiKeyRejected
                        }
                        throw HermesError.unexpectedStatus(
                            endpoint: L10n.string("聊天接口"), status: http.statusCode
                        )
                    }
                    let parser = SSEParser()
                    // 0.8.0：工具调用分片累积——拼装完成即
                    // 以整卡事件下发，流收尾 flush 余量
                    var toolAccumulator = ToolCallStreamAccumulator()
                    #if canImport(EventSource)
                    // #22 真切流：使用 RFC 8895 标准 mattt/EventSource 逐事件解析字节流
                    for try await sse in bytes.events {
                        if Task.isCancelled {
                            throw HermesError.cancelled
                        }
                        switch parser.consume(dataPayload: sse.data) {
                        case .delta(let text):
                            continuation.yield(.content(text))
                        case .reasoning(let text):
                            continuation.yield(.reasoning(text))
                        case .toolCalls(let fragments):
                            for card in toolAccumulator.ingest(fragments) {
                                continuation.yield(.toolCall(card))
                            }
                        case .done:
                            for card in toolAccumulator.flush() {
                                continuation.yield(.toolCall(card))
                            }
                            continuation.finish()
                            return
                        case nil:
                            continue
                        }
                    }
                    #else
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw HermesError.cancelled
                        }
                        switch parser.consume(line: line) {
                        case .delta(let text):
                            continuation.yield(.content(text))
                        case .reasoning(let text):
                            continuation.yield(.reasoning(text))
                        case .toolCalls(let fragments):
                            for card in toolAccumulator.ingest(fragments) {
                                continuation.yield(.toolCall(card))
                            }
                        case .done:
                            for card in toolAccumulator.flush() {
                                continuation.yield(.toolCall(card))
                            }
                            continuation.finish()
                            return
                        case nil:
                            continue
                        }
                    }
                    #endif
                    // 服务端未发 [DONE] 就收尾：已产出内容照常成篇
                    for card in toolAccumulator.flush() {
                        continuation.yield(.toolCall(card))
                    }
                    continuation.finish()
                } catch let error as HermesError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: HermesError.cancelled)
                } catch {
                    continuation.finish(throwing: mapNetworkError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - 任务制生成（/v1/runs，0.31.0）

    func submitRun(
        config: ServerConfig, apiKey: String, sessionID: String,
        input: RunInput, model: String, provider: String?,
        idempotencyKey: String
    ) async throws -> RunSubmitResponse {
        var request = URLRequest(url: config.endpoint("/v1/runs"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            idempotencyKey, forHTTPHeaderField: "Idempotency-Key"
        )
        var payload: [String: Any] = [
            "session_id": sessionID,
            "input": try input.encodedValue(),
            "model": model,
            // 台账 154（§383）：与 Idempotency-Key 头同值
            // 双带消息级幂等身份——hermes-deploy 1.5.0 起
            // 服务端在头缺失时按 body 的 client_message_
            // id 回原 run；旧服务端忽略未知字段、行为不
            // 变，无能力探测开关
            "client_message_id": idempotencyKey,
        ]
        // 逐请求切上游与 chat 通道同口径（§15）：清单
        // 内模型带 provider=custom 才按名落上游渠道
        if let provider {
            payload["provider"] = provider
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        case 429:
            // 发送失败机制包：限流是等待门不是失败
            // ——Retry-After 随错误上行，提交段按值
            // 等待自动续（旧形态与其它状态码同走
            // unexpectedStatus，等待值被丢弃、用户
            // 把限流看成发送失败）
            throw HermesError.rateLimited(
                retryAfterSeconds: Self.retryAfterSeconds(
                    from: http
                )
            )
        default:
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("发送接口"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                RunSubmitResponse.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("发送接口"))
        }
    }

    /// Retry-After 头解析（秒数形；HTTP 日期形不解、
    /// 回 nil 由调用方走缺省等待）
    static func retryAfterSeconds(
        from http: HTTPURLResponse
    ) -> Double? {
        guard let raw = http.value(
            forHTTPHeaderField: "Retry-After"
        ), let seconds = Double(raw), seconds >= 0
        else { return nil }
        return seconds
    }

    func runStatus(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws -> RunStatusResponse? {
        var request = URLRequest(
            url: config.endpoint("/v1/runs/\(runID)")
        )
        request.timeoutInterval = 30
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200:
            break
        case 404:
            return nil
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("生成状态接口"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                RunStatusResponse.self, from: data
            )
        } catch {
            throw HermesError.decodingFailed(
                endpoint: L10n.string("生成状态接口")
            )
        }
    }

    func runEvents(
        config: ServerConfig, apiKey: String, runID: String,
        lastSeq: Int
    ) -> AsyncStream<RunEventEnvelope> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(
                        url: config.endpoint(
                            "/v1/runs/\(runID)/events"
                        )
                    )
                    // 事件缓冲只保留约 300 秒且终态后流自
                    // 关：单次订阅超时放宽到 10 分钟与旧
                    // 流同口径，靠服务端关流/终态事件收尾
                    request.timeoutInterval = 600
                    request.setValue(
                        "Bearer \(apiKey)",
                        forHTTPHeaderField: "Authorization"
                    )
                    request.setValue(
                        "text/event-stream",
                        forHTTPHeaderField: "Accept"
                    )
                    if lastSeq >= 0 {
                        request.setValue(
                            String(lastSeq),
                            forHTTPHeaderField: "Last-Event-ID"
                        )
                    }
                    let (bytes, response) = try await streamSession.bytes(
                        for: request
                    )
                    guard let http = response as? HTTPURLResponse,
                          http.statusCode == 200 else {
                        // 404（缓冲已扫/记录过期）等一律静
                        // 默收尾：定性归状态轮询与 trans-
                        // cript 对账，不在此抛错
                        continuation.finish()
                        return
                    }
                    var parser = RunEventParser()
                    #if canImport(EventSource)
                    // #22 真切流：/v1/runs/{id}/events 同步切换 RFC 8895 EventSource 字节流解析
                    for try await sse in bytes.events {
                        if Task.isCancelled { break }
                        if let id = sse.id, !id.isEmpty {
                            _ = parser.consume(line: "id: \(id)")
                        }
                        if let eventName = sse.event, !eventName.isEmpty {
                            _ = parser.consume(line: "event: \(eventName)")
                        }
                        for dataLine in sse.data.split(separator: "\n", omittingEmptySubsequences: false) {
                            _ = parser.consume(line: "data: \(dataLine)")
                        }
                        if let envelope = parser.consume(line: "") {
                            continuation.yield(envelope)
                        }
                    }
                    #else
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let envelope = parser.consume(line: line) {
                            continuation.yield(envelope)
                        }
                    }
                    #endif
                    continuation.finish()
                } catch {
                    // 流断（切后台被掐/网络抖动）只收尾：
                    // 状态机据「未见终态」进结果未知，绝
                    // 不在此映射成网络错误（0.31.0 铁律）
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stopRun(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws {
        var request = URLRequest(
            url: config.endpoint("/v1/runs/\(runID)/stop")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data("{}".utf8)
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299, 404, 409:
            // 404/409＝run 已不在活动态（已终态/记录过
            // 期）：停止的目的已达或无从施加，均按受理
            // 处理，终局由对账定性
            break
        case 401, 403:
            throw HermesError.apiKeyRejected
        default:
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("停止接口"), status: http.statusCode
            )
        }
    }

    func steerRun(
        config: ServerConfig, apiKey: String, runID: String, input: String
    ) async throws -> RunSteerReceipt {
        try await sendJSONDecoding(
            config: config,
            path: "/v1/runs/\(runID)/steer",
            method: "POST",
            endpoint: L10n.string("纠偏接口"),
            body: ["input": .string(input)],
            bearer: apiKey
        )
    }

    func respondRunApproval(
        config: ServerConfig, apiKey: String, runID: String,
        requestID: String?, choice: String, executionGeneration: Int?
    ) async throws {
        var payload: [String: Any] = ["choice": choice]
        if let requestID, !requestID.isEmpty {
            payload["request_id"] = requestID
        }
        if let executionGeneration {
            payload["execution_generation"] = executionGeneration
        }
        var request = URLRequest(url: config.endpoint("/v1/runs/\(runID)/approval"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.fromHTTPResponse(
                endpoint: L10n.string("运行审批接口"),
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
    }

    func respondRunClarify(
        config: ServerConfig, apiKey: String, runID: String,
        requestID: String, answer: String, executionGeneration: Int?
    ) async throws {
        var payload: [String: Any] = [
            "request_id": requestID,
            "answer": answer,
        ]
        if let executionGeneration {
            payload["execution_generation"] = executionGeneration
        }
        var request = URLRequest(url: config.endpoint("/v1/runs/\(runID)/clarify"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.fromHTTPResponse(
                endpoint: L10n.string("运行澄清接口"),
                status: http.statusCode,
                data: data,
                retryAfterSeconds: Self.retryAfterSeconds(from: http)
            )
        }
    }

    func forkServerSession(
        config: ServerConfig, apiKey: String, id: String, title: String?
    ) async throws -> ServerSession {
        var body: [String: JSONValue] = [:]
        if let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            body["title"] = .string(trimmed)
        }
        let created: CreatedSession = try await sendJSONDecoding(
            config: config,
            path: "/api/sessions/\(id)/fork",
            method: "POST",
            endpoint: L10n.string("会话分支接口"),
            body: body,
            bearer: apiKey
        )
        return created.session
    }

    func uploadCrashReports(
        config: ServerConfig, apiKey: String, reports: [CrashReportRecord]
    ) async throws -> CrashReportsUploadReceipt {
        struct UploadBody: Encodable {
            let reports: [CrashReportRecord]
        }
        var request = URLRequest(
            url: config.endpoint("/v1/diagnostics/crash-reports")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        request.httpBody = try isoEncoder.encode(UploadBody(reports: reports))
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesError.apiKeyRejected
            }
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("崩溃上报接口"), status: http.statusCode
            )
        }
        do {
            return try decoder.decode(CrashReportsUploadReceipt.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: L10n.string("崩溃上报接口"))
        }
    }

    func listServerCrashReports(
        config: ServerConfig, apiKey: String, limit: Int
    ) async throws -> [ServerCrashReportItem] {
        let response: ServerCrashReportsListResponse = try await getJSON(
            config: config,
            path: "/v1/diagnostics/crash-reports",
            endpoint: L10n.string("崩溃上报列表"),
            query: [URLQueryItem(name: "limit", value: String(limit))],
            bearer: apiKey
        )
        return response.data
    }

    func memoryLayers(
        config: ServerConfig, apiKey: String
    ) async throws -> [MemoryLayerSummary] {
        let response: MemoryLayersResponse = try await bearerGetJSON(
            config: config,
            apiKey: apiKey,
            path: "/v1/memory/layers",
            endpoint: L10n.string("记忆分层接口")
        )
        return response.layers
    }

    func searchLayeredMemory(
        config: ServerConfig, apiKey: String, query: String,
        limit: Int, mode: String
    ) async throws -> [MemorySearchHit] {
        let response: MemorySearchResponse = try await getJSON(
            config: config,
            path: "/v1/memory/search",
            endpoint: L10n.string("记忆语义检索"),
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "mode", value: mode),
            ],
            bearer: apiKey
        )
        return response.hits
    }

    func memoryInsights(
        config: ServerConfig, apiKey: String
    ) async throws -> [MemoryInsightItem] {
        let response: MemoryInsightsResponse = try await bearerGetJSON(
            config: config,
            apiKey: apiKey,
            path: "/v1/memory/insights",
            endpoint: L10n.string("记忆洞察接口")
        )
        return response.insights
    }

    // MARK: - Cookie

    func clearCookies(config: ServerConfig) {
        guard let storage = session.configuration.httpCookieStorage,
              let host = config.endpoint("/").host else {
            return
        }
        let cookies = storage.cookies ?? []
        for cookie in cookies where cookie.domain.contains(host) || host.contains(cookie.domain) {
            storage.deleteCookie(cookie)
        }
    }

}

enum RewindError: Error {
    /// 400 invalid_params：target 非本会话 active 的
    /// user 行（assistant 行/未知 id/已回收/归档行）
    case invalidTarget
    /// 409 冲突对账后仍未截断、新围栏重试耗尽
    case conflictExhausted
}

/// 空响应类型：用于无返回体的 POST 端点（如发送邮件）
struct EmptyResponse: Decodable {}
