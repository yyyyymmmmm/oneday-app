import Foundation
import OneDayCore

/// Hermes 服务端对接协议：连接页三步探活、总览与聊天走对话面，
/// 智能体/设置的总览外全部功能走 Dashboard 管理面（/api/*，
/// 会话 cookie 鉴权，401 由 AppState 自动重登兜底）。
/// 接口路径与请求体口径全部对 docs/hermes-0.23.0-openapi.json
/// 与 2026-11-08 GET 实测结构（见 docs/API-SURFACE.md）。
protocol HermesClientProtocol: Sendable {
    /// 探活一：GET /health（免鉴权）
    func health(config: ServerConfig) async throws -> HealthResponse
    /// 探活二：POST /auth/password-login 拿会话 cookie
    /// （cookie 由 URLSession 共享存储持有，本方法只判成败）
    func login(config: ServerConfig, username: String, password: String) async throws
    /// GET /api/status（免登录）
    func status(config: ServerConfig) async throws -> ServerStatus
    /// GET /api/config（需会话；401 由调用方走重登重试）
    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary
    /// 探活三：GET /v1/models（Bearer API 密钥），返回模型 id 列表
    func models(config: ServerConfig, apiKey: String) async throws -> [String]
    /// POST /v1/chat/completions 流式：逐段产出通道事件
    /// （正文增量／思考增量分开，0.5.1 §32）
    /// sessionID（0.21.0）：非 nil 时带 X-Hermes-Session-Id
    /// 头走会话模式（服务端持上下文、只发本轮新消息）；
    /// nil＝无状态重放（主线与未链接线程的旧链，形态不变）
    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage],
        sessionID: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
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

    /// GET /api/sessions?limit=
    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage
    /// GET /api/sessions/{id}
    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession
    /// 建会话（0.7.0 主线钦定）：id/title 由 App 指定，
    /// 服务端回执的 id 为准（服务端改派时以回执改存）
    func createServerSession(config: ServerConfig, id: String?, title: String?) async throws -> ServerSession
    /// 建旁聊真会话（0.21.0）：POST /api/sessions 带
    /// model＋require_model_lock（模型锁＝建时胶囊所
    /// 选、锁后不许回退）；**不带 title**——服务端两
    /// 段式标题（derived→llm）须由首轮内容自生，App
    /// 指定标题会占住标题位、AI 标题回不了流
    func createLinkedServerSession(config: ServerConfig, id: String, model: String) async throws -> ServerSession
    /// 会话内切换模型（0.21.0）：POST /api/sessions/
    /// {id}/model——服务端自动按确认锁持久化；已链
    /// 接线程胶囊改选时推一次（口径见 SideChatLink
    /// .needsModelRelock）
    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws
    /// GET /api/sessions/{id}/messages
    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage]
    /// GET /api/sessions/search?q=&limit=（P10；生产实样
    /// {"results":[…]}，2026-11-09 只读联调验过）
    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit]
    /// DELETE /api/sessions/{id}
    func deleteServerSession(config: ServerConfig, id: String) async throws
    /// POST /api/sessions/bulk-delete {ids}
    func bulkDeleteServerSessions(config: ServerConfig, ids: [String]) async throws
    /// GET /api/sessions/empty/count
    func emptySessionCount(config: ServerConfig) async throws -> Int
    /// DELETE /api/sessions/empty
    func deleteEmptySessions(config: ServerConfig) async throws
    /// GET /api/sessions?limit=&offset=&archived=（0.18.0
    /// 「全部对话」管理面分页拉全；archived 取
    /// exclude/only/include，nil 不带参数走服务端默认）
    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage
    /// PATCH /api/sessions/{id}（SessionRename 子集，
    /// 只带要改的字段；并发守卫 expected_revision 等
    /// 不带——施工纪律禁对生产发写探针，落定靠调用
    /// 方 GET 回读对账，立项档 O-4 就此定案）。2xx
    /// 只算服务端受理、不算落定
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
    /// GET /api/logs?level=&search=&lines=
    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse
    /// GET /api/egress/status
    func egressStatus(config: ServerConfig) async throws -> EgressStatus

    /// POST /api/gateway/restart
    func gatewayRestart(config: ServerConfig) async throws
    /// POST /api/gateway/start
    func gatewayStart(config: ServerConfig) async throws
    /// POST /api/gateway/stop
    func gatewayStop(config: ServerConfig) async throws

    // MARK: 工作区文件与系统（0.2.1）

    /// GET /api/files?path=（path 为 nil 时服务端回默认根，
    /// 2026-11-08 实查根被 locked_root 锁在 /opt/data）
    func files(config: ServerConfig, path: String?) async throws -> FilesListing
    /// DELETE /api/files {path, recursive}
    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws
    /// GET /api/files/download?path= → 原始字节（预览/下载共用）
    func fileData(config: ServerConfig, path: String) async throws -> Data
    /// POST /api/files/upload {path, data_url, overwrite}
    /// （openapi ManagedFileUpload，2026-11-09 据 docs 内
    /// OpenAPI 组件 schema 实查；与列表/删除同一 9119 会话
    /// 通道、同一 locked_root 约束。回执形态不依赖，调用
    /// 方以回读列表对账落定）
    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws
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
    /// POST /api/plugins/kanban/runs/{run_id}/terminate?board=（停止当前运行）
    func kanbanTerminateRun(config: ServerConfig, board: String, runID: Int) async throws
}

/// URLSession 实现。会话 cookie 走 .shared 存储：登录一次，
/// 后续 /api/* 自动带上；进程重启后 cookie 仍在（系统持久化），
/// 过期则由 AppState 的自动重登兜底。
final class HermesClient: HermesClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
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
    private func mapNetworkError(_ error: Error) -> HermesError {
        if let hermesError = error as? HermesError {
            return hermesError
        }
        guard let urlError = error as? URLError else {
            return .unreachable("网络错误")
        }
        return HermesError.fromURLError(urlError)
    }

    private func dataRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HermesError.unreachable("无响应")
            }
            return (data, http)
        } catch let error as HermesError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// 拼 query 的 URL：path 里已带路径参数时用 URLComponents 挂参
    private func url(
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

    private func getJSON<T: Decodable>(
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
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    /// 带 JSON body 的写请求：2xx 即成功，不解码响应体
    /// （各写接口的回执形态不一，调用方需要新状态时自行重拉）。
    private func sendJSON(
        config: ServerConfig, path: String, method: String, endpoint: String,
        body: [String: JSONValue]? = nil, timeout: TimeInterval? = nil
    ) async throws {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = method
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (_, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
        }
    }

    /// 写请求并解码回执（创建类接口返回新建对象时使用）
    private func sendJSONDecoding<T: Decodable>(
        config: ServerConfig, path: String, method: String, endpoint: String,
        body: [String: JSONValue]
    ) async throws -> T {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: endpoint, status: http.statusCode)
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
            throw HermesError.decodingFailed(endpoint: "健康检查")
        }
    }

    func login(config: ServerConfig, username: String, password: String) async throws {
        var request = URLRequest(url: config.endpoint("/auth/password-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 登录契约（2026-11-08 实测）：JSON 四字段，缺 provider 返回 422
        let body: [String: String] = [
            "provider": "basic",
            "username": username,
            "password": password,
            "next": "/",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, http) = try await dataRequest(request)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403, 422:
            throw HermesError.loginRejected
        default:
            throw HermesError.loginFailed(status: http.statusCode)
        }
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        try await getJSON(config: config, path: "/api/status", endpoint: "状态接口")
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        try await getJSON(config: config, path: "/api/config", endpoint: "配置接口")
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
            throw HermesError.unexpectedStatus(endpoint: "模型接口", status: http.statusCode)
        }
        do {
            return try decoder.decode(ModelsResponse.self, from: data).ids
        } catch {
            throw HermesError.decodingFailed(endpoint: "模型接口")
        }
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

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesError.unreachable("无响应")
                    }
                    guard http.statusCode == 200 else {
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw HermesError.apiKeyRejected
                        }
                        throw HermesError.unexpectedStatus(
                            endpoint: "聊天接口", status: http.statusCode
                        )
                    }
                    let parser = SSEParser()
                    // 0.8.0：工具调用分片累积——拼装完成即
                    // 以整卡事件下发，流收尾 flush 余量
                    var toolAccumulator = ToolCallStreamAccumulator()
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

    // MARK: - 记忆

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus {
        try await getJSON(config: config, path: "/api/memory", endpoint: "记忆接口")
    }

    func setMemoryProvider(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/provider", method: "PUT",
            endpoint: "记忆提供方切换", body: ["provider": .string(name)]
        )
    }

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig {
        try await getJSON(
            config: config,
            path: "/api/memory/providers/\(name)/config",
            endpoint: "记忆提供方配置"
        )
    }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/providers/\(name)/config",
            method: "PUT", endpoint: "记忆提供方配置",
            body: ["values": .object(values)]
        )
    }

    func resetMemory(config: ServerConfig, target: String) async throws {
        try await sendJSON(
            config: config, path: "/api/memory/reset", method: "POST",
            endpoint: "记忆重置", body: ["target": .string(target)]
        )
    }

    // MARK: - 技能

    func skills(config: ServerConfig) async throws -> [SkillItem] {
        try await getJSON(config: config, path: "/api/skills", endpoint: "技能接口")
    }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent {
        try await getJSON(
            config: config, path: "/api/skills/content", endpoint: "技能内容",
            query: [URLQueryItem(name: "name", value: name)]
        )
    }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/content", method: "PUT",
            endpoint: "技能内容",
            body: ["name": .string(name), "content": .string(content)]
        )
    }

    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/toggle", method: "PUT",
            endpoint: "技能开关",
            body: ["name": .string(name), "enabled": .bool(enabled)]
        )
    }

    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/lock", method: "PUT",
            endpoint: "技能锁定",
            body: ["name": .string(name), "locked": .bool(locked)]
        )
    }

    // MARK: - 技能商店（P10）

    /// hub 三读的长超时：服务端要抓外部注册表，本部署
    /// 实测 30s 无响应（出网受阻）——客户端放宽到 120s
    /// 等它自己失败/返回，超时按失败态呈给用户，不假装
    /// 商店里没东西
    private static let hubTimeout: TimeInterval = 120

    func skillHubSources(config: ServerConfig) async throws -> [HubSource] {
        let response: HubSourcesResponse = try await getJSON(
            config: config, path: "/api/skills/hub/sources",
            endpoint: "技能商店来源", timeout: Self.hubTimeout
        )
        return response.sources
    }

    func skillHubSearch(
        config: ServerConfig, query: String, source: String?
    ) async throws -> [HubSkill] {
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "30"),
        ]
        if let source, !source.isEmpty {
            queryItems.append(URLQueryItem(name: "source", value: source))
        }
        let response: HubSearchResponse = try await getJSON(
            config: config, path: "/api/skills/hub/search",
            endpoint: "技能商店搜索", query: queryItems,
            timeout: Self.hubTimeout
        )
        return response.results
    }

    func skillHubPreview(
        config: ServerConfig, identifier: String
    ) async throws -> HubPreview {
        try await getJSON(
            config: config, path: "/api/skills/hub/preview",
            endpoint: "技能预览",
            query: [URLQueryItem(name: "identifier", value: identifier)],
            timeout: Self.hubTimeout
        )
    }

    func skillHubInstall(config: ServerConfig, identifier: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/hub/install", method: "POST",
            endpoint: "技能安装",
            body: ["identifier": .string(identifier)],
            timeout: Self.hubTimeout
        )
    }

    func skillHubUninstall(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/skills/hub/uninstall", method: "POST",
            endpoint: "技能卸载",
            body: ["name": .string(name)],
            timeout: Self.hubTimeout
        )
    }

    // MARK: - 定时任务

    func cronJobs(config: ServerConfig) async throws -> [CronJob] {
        try await getJSON(config: config, path: "/api/cron/jobs", endpoint: "定时任务接口")
    }

    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob {
        var body: [String: JSONValue] = [
            "prompt": .string(prompt),
            "schedule": .string(schedule),
        ]
        if let name, !name.isEmpty {
            body["name"] = .string(name)
        }
        if let deliver, !deliver.isEmpty {
            body["deliver"] = .string(deliver)
        }
        return try await sendJSONDecoding(
            config: config, path: "/api/cron/jobs", method: "POST",
            endpoint: "定时任务创建", body: body
        )
    }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)", method: "PUT",
            endpoint: "定时任务更新", body: ["updates": .object(updates)]
        )
    }

    func deleteCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)", method: "DELETE",
            endpoint: "定时任务删除"
        )
    }

    func pauseCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/pause", method: "POST",
            endpoint: "定时任务暂停"
        )
    }

    func resumeCronJob(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/resume", method: "POST",
            endpoint: "定时任务恢复"
        )
    }

    func triggerCronJob(config: ServerConfig, id: String) async throws {
        // 触发是同步执行：服务端等任务跑完才回执，放宽超时
        try await sendJSON(
            config: config, path: "/api/cron/jobs/\(id)/trigger", method: "POST",
            endpoint: "定时任务触发", timeout: 600
        )
    }

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] {
        let response: CronRunsResponse = try await getJSON(
            config: config, path: "/api/cron/jobs/\(id)/runs",
            endpoint: "定时任务运行记录",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.runs
    }

    // MARK: - 服务端会话

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        try await getJSON(
            config: config, path: "/api/sessions", endpoint: "服务端会话",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        try await getJSON(
            config: config, path: "/api/sessions/\(id)", endpoint: "服务端会话详情"
        )
    }

    func createServerSession(config: ServerConfig, id: String?, title: String?) async throws -> ServerSession {
        var body: [String: JSONValue] = [:]
        if let id { body["id"] = .string(id) }
        if let title { body["title"] = .string(title) }
        let created: CreatedSession = try await sendJSONDecoding(
            config: config, path: "/api/sessions", method: "POST",
            endpoint: "服务端会话创建", body: body
        )
        return created.session
    }

    func createLinkedServerSession(config: ServerConfig, id: String, model: String) async throws -> ServerSession {
        // 0.21.0：研究档实测链口径——建会话带 model＋
        // require_model_lock:true 得确认锁（route 无法
        // 落锁时服务端 409 拒、不会静默兜底）；title
        // 不带（见协议注）
        let body: [String: JSONValue] = [
            "id": .string(id),
            "model": .string(model),
            "require_model_lock": .bool(true),
        ]
        let created: CreatedSession = try await sendJSONDecoding(
            config: config, path: "/api/sessions", method: "POST",
            endpoint: "旁聊会话创建", body: body
        )
        return created.session
    }

    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/\(id)/model", method: "POST",
            endpoint: "会话模型切换", body: ["model": .string(model)]
        )
    }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        let response: SessionMessagesResponse = try await getJSON(
            config: config, path: "/api/sessions/\(id)/messages",
            endpoint: "服务端会话消息"
        )
        return response.messages
    }

    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit] {
        let response: SessionSearchResponse = try await getJSON(
            config: config, path: "/api/sessions/search",
            endpoint: "会话搜索",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return response.results
    }

    func deleteServerSession(config: ServerConfig, id: String) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/\(id)", method: "DELETE",
            endpoint: "服务端会话删除"
        )
    }

    func bulkDeleteServerSessions(config: ServerConfig, ids: [String]) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/bulk-delete", method: "POST",
            endpoint: "服务端会话批量删除",
            body: ["ids": .array(ids.map(JSONValue.string))]
        )
    }

    func emptySessionCount(config: ServerConfig) async throws -> Int {
        struct CountResponse: Decodable { let count: Int? }
        let response: CountResponse = try await getJSON(
            config: config, path: "/api/sessions/empty/count",
            endpoint: "空会话计数"
        )
        return response.count ?? 0
    }

    func deleteEmptySessions(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/sessions/empty", method: "DELETE",
            endpoint: "空会话清理"
        )
    }

    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let archived {
            query.append(URLQueryItem(name: "archived", value: archived))
        }
        return try await getJSON(
            config: config, path: "/api/sessions", endpoint: "服务端会话",
            query: query
        )
    }

    func updateServerSession(
        config: ServerConfig, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let pinned { body["pinned"] = .bool(pinned) }
        if let archived { body["archived"] = .bool(archived) }
        try await sendJSON(
            config: config, path: "/api/sessions/\(id)", method: "PATCH",
            endpoint: "服务端会话更新", body: body
        )
    }

    func pruneSessions(
        config: ServerConfig, olderThanDays: Double, dryRun: Bool
    ) async throws -> Int? {
        let receipt: JSONValue = try await sendJSONDecoding(
            config: config, path: "/api/sessions/prune", method: "POST",
            endpoint: "服务端会话清理",
            body: [
                "older_than_days": .number(olderThanDays),
                "dry_run": .bool(dryRun),
            ]
        )
        return SessionPruneReceipt.count(from: receipt)
    }

    // MARK: - 档案

    func profiles(config: ServerConfig) async throws -> [ProfileItem] {
        let response: ProfilesResponse = try await getJSON(
            config: config, path: "/api/profiles", endpoint: "档案接口"
        )
        return response.profiles
    }

    func activeProfileName(config: ServerConfig) async throws -> String? {
        let response: ActiveProfileResponse = try await getJSON(
            config: config, path: "/api/profiles/active", endpoint: "当前档案"
        )
        return response.name
    }

    func setActiveProfile(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: "/api/profiles/active", method: "POST",
            endpoint: "档案切换", body: ["name": .string(name)]
        )
    }

    /// profile 名按单个 path segment 百分号编码：profile
    /// 名是用户可控字符串，不许把 "/" 等分隔符带进路径
    /// （数据设计 §2.4；现有客户端多处直接插值 id，soul
    /// 方法不复制这个缺口）
    private func soulPath(name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return "/api/profiles/\(encoded)/soul"
    }

    func profileSoul(
        config: ServerConfig, name: String
    ) async throws -> ProfileSoulDocument {
        try await getJSON(
            config: config, path: soulPath(name: name), endpoint: "档案人设"
        )
    }

    func updateProfileSoul(
        config: ServerConfig, name: String, content: String
    ) async throws {
        try await sendJSON(
            config: config, path: soulPath(name: name), method: "PUT",
            endpoint: "档案人设",
            body: ["content": .string(content)]
        )
    }

    /// 档案名 path 段编码（与 soulPath 同口径：用户可控
    /// 字符串不许带分隔符进路径）
    private func profilePath(name: String, suffix: String = "") -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return "/api/profiles/\(encoded)\(suffix)"
    }

    func createProfile(
        config: ServerConfig, name: String, cloneFrom: String?
    ) async throws {
        var body: [String: JSONValue] = ["name": .string(name)]
        if let cloneFrom, !cloneFrom.isEmpty {
            body["clone_from"] = .string(cloneFrom)
        }
        try await sendJSON(
            config: config, path: "/api/profiles", method: "POST",
            endpoint: "档案创建", body: body
        )
    }

    func deleteProfile(config: ServerConfig, name: String) async throws {
        try await sendJSON(
            config: config, path: profilePath(name: name), method: "DELETE",
            endpoint: "档案删除"
        )
    }

    func exportProfile(
        config: ServerConfig, name: String
    ) async throws -> ProfileExportResult {
        try await sendJSONDecoding(
            config: config, path: profilePath(name: name, suffix: "/export"),
            method: "POST", endpoint: "档案导出", body: [:]
        )
    }

    func importProfile(
        config: ServerConfig, archive: String, name: String?
    ) async throws {
        var body: [String: JSONValue] = ["archive": .string(archive)]
        if let name, !name.isEmpty {
            body["name"] = .string(name)
        }
        try await sendJSON(
            config: config, path: "/api/profiles/import", method: "POST",
            endpoint: "档案导入", body: body
        )
    }

    // MARK: - MCP 连接（P10）

    /// MCP 名 path 段编码（同 profilePath 口径）
    private func mcpPath(name: String, suffix: String = "") -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? name
        return "/api/mcp/servers/\(encoded)\(suffix)"
    }

    func mcpServers(config: ServerConfig) async throws -> [MCPServerItem] {
        let response: MCPServersResponse = try await getJSON(
            config: config, path: "/api/mcp/servers", endpoint: "MCP 连接"
        )
        return response.servers
    }

    func setMCPServerEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws {
        try await sendJSON(
            config: config, path: mcpPath(name: name, suffix: "/enabled"),
            method: "PUT", endpoint: "MCP 开关",
            body: ["enabled": .bool(enabled)]
        )
    }

    func testMCPServer(
        config: ServerConfig, name: String
    ) async throws -> MCPTestResult {
        try await sendJSONDecoding(
            config: config, path: mcpPath(name: name, suffix: "/test"),
            method: "POST", endpoint: "MCP 测试", body: [:]
        )
    }

    func computerUseStatus(
        config: ServerConfig
    ) async throws -> ComputerUseStatus {
        try await getJSON(
            config: config, path: "/api/tools/computer-use/status",
            endpoint: "电脑操作状态"
        )
    }

    // MARK: - 配置与密钥

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] {
        try await getJSON(config: config, path: "/api/config", endpoint: "配置接口")
    }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws {
        try await sendJSON(
            config: config, path: "/api/config", method: "PUT",
            endpoint: "配置写入", body: ["config": .object(newConfig)]
        )
    }

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] {
        let response: EnvVars = try await getJSON(
            config: config, path: "/api/env", endpoint: "密钥接口"
        )
        return response.entries
    }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws {
        try await sendJSON(
            config: config, path: "/api/env", method: "PUT",
            endpoint: "密钥写入",
            body: ["key": .string(key), "value": .string(value)]
        )
    }

    func deleteEnvVar(config: ServerConfig, key: String) async throws {
        try await sendJSON(
            config: config, path: "/api/env", method: "DELETE",
            endpoint: "密钥删除", body: ["key": .string(key)]
        )
    }

    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        var request = URLRequest(url: config.endpoint("/api/env/reveal"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["key": JSONValue.string(key)])
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(endpoint: "密钥查看", status: http.statusCode)
        }
        // 回执形态宽容：{"value": "…"} / {"key": "…", "value": "…"} / 纯字符串
        let value = try decoder.decode(JSONValue.self, from: data)
        switch value {
        case .string(let text):
            return text
        case .object(let object):
            if let text = object["value"]?.stringValue {
                return text
            }
            throw HermesError.decodingFailed(endpoint: "密钥查看")
        default:
            throw HermesError.decodingFailed(endpoint: "密钥查看")
        }
    }

    // MARK: - 用量与日志

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics {
        try await getJSON(
            config: config, path: "/api/analytics/usage", endpoint: "用量接口",
            query: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics {
        try await getJSON(
            config: config, path: "/api/analytics/models", endpoint: "模型用量接口",
            query: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func modelOptions(config: ServerConfig) async throws -> [String] {
        // 回执在 OpenAPI 里未定型：先以 JSONValue 整树接住，
        // 再由 ModelCatalog 宽容提取（形状容忍优先于强解码）
        let root: JSONValue = try await getJSON(
            config: config, path: "/api/model/options", endpoint: "模型列表接口"
        )
        return ModelCatalog.extractModelIDs(from: root)
    }

    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse {
        var query = [URLQueryItem(name: "lines", value: String(lines))]
        if let level, !level.isEmpty {
            query.append(URLQueryItem(name: "level", value: level))
        }
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        return try await getJSON(
            config: config, path: "/api/logs", endpoint: "日志接口", query: query
        )
    }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus {
        try await getJSON(config: config, path: "/api/egress/status", endpoint: "出口状态")
    }

    // MARK: - 网关动作

    func gatewayRestart(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/restart", method: "POST",
            endpoint: "网关重启", timeout: 120
        )
    }

    func gatewayStart(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/start", method: "POST",
            endpoint: "网关启动", timeout: 120
        )
    }

    func gatewayStop(config: ServerConfig) async throws {
        try await sendJSON(
            config: config, path: "/api/gateway/stop", method: "POST",
            endpoint: "网关停止", timeout: 120
        )
    }

    // MARK: - 工作区文件与系统（0.2.1）

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        var query: [URLQueryItem] = []
        if let path, !path.isEmpty {
            query.append(URLQueryItem(name: "path", value: path))
        }
        return try await getJSON(
            config: config, path: "/api/files", endpoint: "文件列表", query: query
        )
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws {
        try await sendJSON(
            config: config, path: "/api/files", method: "DELETE",
            endpoint: "删除文件",
            body: ["path": .string(path), "recursive": .bool(recursive)]
        )
    }

    func fileData(config: ServerConfig, path: String) async throws -> Data {
        let request = URLRequest(
            url: url(
                config: config, path: "/api/files/download",
                query: [URLQueryItem(name: "path", value: path)]
            )
        )
        let (data, http) = try await dataRequest(request)
        guard http.statusCode == 200 else {
            throw HermesError.unexpectedStatus(endpoint: "文件下载", status: http.statusCode)
        }
        return data
    }

    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws {
        // data_url 是 base64 JSON 体（25MB 原始上限膨胀后约
        // 34MB），超时给 180 秒；服务端回执不解码，落定以
        // 调用方回读列表对账为准（sendJSON 既有口径）
        try await sendJSON(
            config: config, path: "/api/files/upload", method: "POST",
            endpoint: "文件上传",
            body: [
                "path": .string(path),
                "data_url": .string(dataURL),
                "overwrite": .bool(overwrite),
            ],
            timeout: 180
        )
    }

    func makeDirectory(config: ServerConfig, path: String) async throws {
        try await sendJSON(
            config: config, path: "/api/files/mkdir", method: "POST",
            endpoint: "新建文件夹",
            body: ["path": .string(path)]
        )
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats {
        try await getJSON(config: config, path: "/api/system/stats", endpoint: "系统状态")
    }
}

// MARK: - Kanban（P3 任务薄适配）
//
// 走 9119 dashboard 插件面 /api/plugins/kanban，与其
// 他 /api/* 同一条会话 cookie 通道（performAdmin 的
// 401 重登兜底同样适用）。全部请求带 ?board= 指名
// 专属板（spike 数据隔离口径）；写动作的回执只作参
// 考，生效与否由 KanbanStore 回读确认，不乐观假成功。

extension HermesClient {
    private var kanbanBase: String { "/api/plugins/kanban" }

    private func kanbanQuery(board: String) -> [URLQueryItem] {
        [URLQueryItem(name: "board", value: board)]
    }

    /// kanban 写请求（带 query 版 sendJSON：既有助手
    /// 不支持 query 参数，插件面每条都要带 board）
    private func kanbanSend(
        config: ServerConfig, path: String, method: String, endpoint: String,
        query: [URLQueryItem] = [], body: [String: JSONValue]? = nil
    ) async throws {
        var request = URLRequest(
            url: url(config: config, path: path, query: query)
        )
        request.httpMethod = method
        if let body {
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try encoder.encode(body)
        }
        let (_, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: http.statusCode
            )
        }
    }

    /// kanban 写请求并解码回执（建卡/催派用）
    private func kanbanSendDecoding<T: Decodable>(
        config: ServerConfig, path: String, method: String, endpoint: String,
        query: [URLQueryItem] = [], body: [String: JSONValue]? = nil
    ) async throws -> T {
        var request = URLRequest(
            url: url(config: config, path: path, query: query)
        )
        request.httpMethod = method
        if let body {
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try encoder.encode(body)
        }
        let (data, http) = try await dataRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: endpoint, status: http.statusCode
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesError.decodingFailed(endpoint: endpoint)
        }
    }

    func kanbanWorkflow(config: ServerConfig) async throws -> KanbanWorkflow {
        try await getJSON(
            config: config, path: "\(kanbanBase)/workflow",
            endpoint: "任务系统探针"
        )
    }

    func kanbanBoards(config: ServerConfig) async throws -> [String] {
        let value: JSONValue = try await getJSON(
            config: config, path: "\(kanbanBase)/boards",
            endpoint: "任务板清单"
        )
        return KanbanBoardList.slugs(from: value)
    }

    func kanbanBoard(
        config: ServerConfig, board: String
    ) async throws -> KanbanBoardSnapshot {
        try await getJSON(
            config: config, path: "\(kanbanBase)/board",
            endpoint: "任务板", query: kanbanQuery(board: board)
        )
    }

    func kanbanTaskDetail(
        config: ServerConfig, board: String, id: String
    ) async throws -> KanbanTaskDetail {
        try await getJSON(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            endpoint: "任务详情", query: kanbanQuery(board: board)
        )
    }

    func kanbanCreateTask(
        config: ServerConfig, board: String, title: String, body: String,
        idempotencyKey: String
    ) async throws -> KanbanTask {
        var payload: [String: JSONValue] = [
            "title": .string(title),
            "assignee": .string(KanbanContract.defaultAssignee),
            "idempotency_key": .string(idempotencyKey),
        ]
        if !body.isEmpty {
            payload["body"] = .string(body)
        }
        return try await kanbanSendDecoding(
            config: config, path: "\(kanbanBase)/tasks", method: "POST",
            endpoint: "任务创建", query: kanbanQuery(board: board),
            body: payload
        )
    }

    func kanbanDispatch(
        config: ServerConfig, board: String
    ) async throws -> KanbanDispatchReceipt {
        try await kanbanSendDecoding(
            config: config, path: "\(kanbanBase)/dispatch", method: "POST",
            endpoint: "任务派发", query: kanbanQuery(board: board)
        )
    }

    func kanbanPatchTaskStatus(
        config: ServerConfig, board: String, id: String, status: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            method: "PATCH", endpoint: "任务状态更新",
            query: kanbanQuery(board: board),
            body: ["status": .string(status)]
        )
    }

    func kanbanDeleteTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)",
            method: "DELETE", endpoint: "任务删除",
            query: kanbanQuery(board: board)
        )
    }

    func kanbanComment(
        config: ServerConfig, board: String, id: String, body: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)/comments",
            method: "POST", endpoint: "任务答题",
            query: kanbanQuery(board: board),
            body: [
                "body": .string(body),
                "author": .string(KanbanContract.answerAuthor),
            ]
        )
    }

    func kanbanReclaimTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/tasks/\(id)/reclaim",
            method: "POST", endpoint: "任务急停",
            query: kanbanQuery(board: board),
            body: ["reason": .string("App 停止")]
        )
    }

    func kanbanTerminateRun(
        config: ServerConfig, board: String, runID: Int
    ) async throws {
        try await kanbanSend(
            config: config, path: "\(kanbanBase)/runs/\(runID)/terminate",
            method: "POST", endpoint: "运行终止",
            query: kanbanQuery(board: board),
            body: ["reason": .string("App 停止")]
        )
    }
}
