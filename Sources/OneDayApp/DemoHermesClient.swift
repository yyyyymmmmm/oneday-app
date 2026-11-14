import Foundation
import OneDayCore
#if canImport(UIKit)
import UIKit
#endif

/// 演示模式的假客户端：实现 HermesClientProtocol，不发出任何
/// 网络请求。演示面自复杂化全清·第 4 项起冻结（口径见
/// demo-surface-freeze-20261111.md）：只保冻结清单内的种子面
/// 有本地静态样本——连接页探活（health/login/models）、对话
/// 主面只读浏览（会话列表/详情/消息/搜索＋种子会话的 run 流
/// 补完）、文件列表与数据、以及点子「开始吧」背后的任务板
/// 样本；清单外接口不再逐个写假实现，一律抛统一空态信号
/// HermesError.demoLimitReached（界面文案一条：「演示模式
/// 到此为止，连接你的服务器后可用。」）。新功能默认不进
/// 演示，进演示须在施工单里点名。保留样本的读数口径对齐
/// 2026-11-08 线上实测：版本 0.23.0、网关 running、模型
/// deepseek-chat，时间相对当前时刻生成。
struct DemoHermesClient: HermesClientProtocol {
    func health(config: ServerConfig) async throws -> HealthResponse {
        decode(HealthResponse.self, #"{"status": "ok", "platform": "hermes-agent", "version": "0.23.0"}"#)
    }

    func login(config: ServerConfig, username: String, password: String) async throws {
        // 演示探活：恒成功，不发请求
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        decode(ServerStatus.self, """
        {
            "version": "0.23.0",
            "release_date": "2026.9.24",
            "config_version": 52,
            "gateway_running": true,
            "gateway_state": "running",
            "gateway_platforms": {
                "api_server": {"state": "connected", "error_message": null},
                "dashboard": {"state": "connected", "error_message": null}
            }
        }
        """)
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        decode(ServerConfigSummary.self, """
        {
            "model": "deepseek-chat",
            "providers": {"deepseek": {}},
            "toolsets": ["hermes-cli"]
        }
        """)
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        ["hermes-agent"]
    }

    /// 演示上游候选（与网关别名 hermes-agent 分开：选择器里
    /// 只该出现这一组，含一个别名 deepseek-chat 供标注演示）
    func modelOptions(config: ServerConfig) async throws -> [String] {
        ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat"]
    }

    /// 演示回执（§153）：与生产定型同构——一行网关
    /// custom（含默认 flash 与别名 chat 供别名收一演
    /// 示）、is_current 落网关行。
    /// 2026-11-13（枢纽溢出 rig 补盲）：目录灌到生产
    /// 量级 61 条——原三条打头、顺序与语义不变（默
    /// 认 flash／别名 chat／v4-pro 探针行都在原位），
    /// 其后补 58 条常见网关 id 凑足生产规模；装配测
    /// 试（TopBarSingleActionTapTests 枢纽回归）靠这
    /// 个量级复现「目录撑爆枢纽」的生产条件，3 条的
    /// 小目录永远测不出溢出
    func modelOptionsRaw(config: ServerConfig) async throws -> JSONValue {
        .object([
            "model": .string("deepseek-flash"),
            "provider": .string("custom"),
            "providers": .array([
                .object([
                    "slug": .string("custom"),
                    "is_current": .bool(true),
                    "models": .array([
                        .string("deepseek-flash"),
                        .string("deepseek-v4-pro"),
                        .string("deepseek-chat"),
                        .string("claude-sonnet-4-6"),
                        .string("claude-sonnet-4-5"),
                        .string("claude-opus-4-5"),
                        .string("claude-opus-5-5"),
                        .string("claude-haiku-4-5-20251001"),
                        .string("claude-haiku-3-5"),
                        .string("claude-sonnet-3-7"),
                        .string("claude-opus-4-1"),
                        .string("claude-fable-5"),
                        .string("claude-mythos-5"),
                        .string("gpt-5.6"),
                        .string("gpt-5.6-sol"),
                        .string("gpt-5.6-terra"),
                        .string("gpt-5.6-luna"),
                        .string("gpt-5.5"),
                        .string("gpt-5.4"),
                        .string("gpt-5.4-mini"),
                        .string("gpt-5.3"),
                        .string("gpt-5.2"),
                        .string("gpt-5.1"),
                        .string("gpt-5"),
                        .string("gpt-4.1"),
                        .string("gemini-3.6-flash-high"),
                        .string("gemini-3.6-flash"),
                        .string("gemini-3.5-pro"),
                        .string("gemini-3.5-flash"),
                        .string("gemini-3.1-pro"),
                        .string("gemini-3.0-flash"),
                        .string("gemini-2.5-pro"),
                        .string("gemini-2.5-flash"),
                        .string("gemini-2.5-flash-lite"),
                        .string("gemini-2.0-flash"),
                        .string("llama-4-maverick"),
                        .string("llama-4-scout"),
                        .string("llama-3.3-70b"),
                        .string("qwen-3-max"),
                        .string("qwen-3-plus"),
                        .string("qwen-3-turbo"),
                        .string("qwen-2.5-72b"),
                        .string("kimi-k2"),
                        .string("glm-4.6"),
                        .string("glm-4.5"),
                        .string("mistral-large-3"),
                        .string("mistral-medium-3"),
                        .string("mistral-small-3"),
                        .string("command-r-plus"),
                        .string("command-r"),
                        .string("sonar-pro"),
                        .string("sonar"),
                        .string("grok-4.5"),
                        .string("grok-4.3"),
                        .string("grok-4.2"),
                        .string("grok-4.1"),
                        .string("phi-4"),
                        .string("nemotron-70b"),
                        .string("wizardlm-2"),
                        .string("mixtral-8x22b"),
                        .string("dbrx-instruct"),
                    ]),
                ]),
            ]),
        ])
    }

    func setMainModel(
        config: ServerConfig, provider: String, model: String
    ) async throws {}

    func mainModelAssignment(
        config: ServerConfig, providerNames: [String]
    ) async throws -> MainModelAssignment {
        MainModelAssignment(owner: .gateway, model: "deepseek-flash")
    }

    /// 演示流式：把定稿回复逐字慢速产出，演示态能看到
    /// 「已出半截字＋流式光标」的流式效果；总时长约 14 秒。
    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage],
        sessionID: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let reply = """
        好。那我先从定时任务模块动手：列表、新建、暂停、立即触发、运行记录，五条接口都是现成的，第一版只做查看和启停，编辑放第二轮。做完先出包给你验，通过了我再碰技能和会话。
        """
        return AsyncThrowingStream { continuation in
            let task = Task {
                let characters = Array(reply)
                var index = 0
                while index < characters.count {
                    if Task.isCancelled {
                        continuation.finish(throwing: HermesError.cancelled)
                        return
                    }
                    let next = min(index + 1, characters.count)
                    continuation.yield(.content(String(characters[index..<next])))
                    index = next
                    try? await Task.sleep(for: .milliseconds(130))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 任务制生成（0.31.0 演示等价）：提交即回
    // 假 run_id，事件流逐字产出定稿回复＋终态事件，
    // 状态查询恒 completed 带全文——演示态同样走
    // run 驱动全链（提交→订阅→终态）

    func submitRun(
        config: ServerConfig, apiKey: String, sessionID: String,
        input: RunInput, model: String, provider: String?,
        idempotencyKey: String
    ) async throws -> RunSubmitResponse {
        RunSubmitResponse(
            runID: "demo-run", statusRaw: "started", replayed: false
        )
    }

    func runStatus(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws -> RunStatusResponse? {
        RunStatusResponse(
            runID: runID, status: .completed,
            output: Self.demoReply, error: nil, sessionID: nil
        )
    }

    func runEvents(
        config: ServerConfig, apiKey: String, runID: String,
        lastSeq: Int
    ) -> AsyncStream<RunEventEnvelope> {
        AsyncStream { continuation in
            let task = Task {
                let characters = Array(Self.demoReply)
                var index = 0
                var seq = 0
                while index < characters.count {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    let next = min(index + 1, characters.count)
                    continuation.yield(RunEventEnvelope(
                        seq: seq,
                        event: .contentDelta(
                            String(characters[index..<next])
                        )
                    ))
                    seq += 1
                    index = next
                    try? await Task.sleep(for: .milliseconds(130))
                }
                continuation.yield(RunEventEnvelope(
                    seq: seq,
                    event: .terminal(
                        kind: .completed, output: Self.demoReply
                    )
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stopRun(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws {
        // 演示停止：静默成功（事件流由视图侧任务取消收尾）
    }

    /// 演示定稿回复（与 chatStream 旧演示同文）
    static let demoReply = """
        好。那我先从定时任务模块动手：列表、新建、暂停、立即触发、运行记录，五条接口都是现成的，第一版只做查看和启停，编辑放第二轮。做完先出包给你验，通过了我再碰技能和会话。
        """

    func clearCookies(config: ServerConfig) {
        // 演示模式没有 cookie 可清
    }

    // MARK: - 记忆（样本结构对实测：active 空串＝内置当值）

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus { throw HermesError.demoLimitReached }

    func setMemoryProvider(config: ServerConfig, name: String) async throws { throw HermesError.demoLimitReached }

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig { throw HermesError.demoLimitReached }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws { throw HermesError.demoLimitReached }

    func resetMemory(config: ServerConfig, target: String) async throws { throw HermesError.demoLimitReached }

    // MARK: - 技能

    func skills(config: ServerConfig) async throws -> [SkillItem] { throw HermesError.demoLimitReached }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent { throw HermesError.demoLimitReached }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws { throw HermesError.demoLimitReached }
    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws { throw HermesError.demoLimitReached }
    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws { throw HermesError.demoLimitReached }

    // MARK: - 技能商店（P10，演示样本；写动作静默成功
    // 不落状态，沿本文件既定演示口径）

    func skillHubSources(config: ServerConfig) async throws -> [HubSource] { throw HermesError.demoLimitReached }

    func skillHubSearch(
        config: ServerConfig, query: String, source: String?
    ) async throws -> [HubSkill] { throw HermesError.demoLimitReached }

    func skillHubPreview(
        config: ServerConfig, identifier: String
    ) async throws -> HubPreview { throw HermesError.demoLimitReached }

    func skillHubInstall(config: ServerConfig, identifier: String) async throws { throw HermesError.demoLimitReached }
    func skillHubUninstall(config: ServerConfig, name: String) async throws { throw HermesError.demoLimitReached }

    // MARK: - 定时任务

    func cronJobs(config: ServerConfig) async throws -> [CronJob] { throw HermesError.demoLimitReached }

    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob { throw HermesError.demoLimitReached }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws { throw HermesError.demoLimitReached }

    func deleteCronJob(config: ServerConfig, id: String) async throws { throw HermesError.demoLimitReached }
    func pauseCronJob(config: ServerConfig, id: String) async throws { throw HermesError.demoLimitReached }
    func resumeCronJob(config: ServerConfig, id: String) async throws { throw HermesError.demoLimitReached }
    func triggerCronJob(config: ServerConfig, id: String) async throws { throw HermesError.demoLimitReached }

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] { throw HermesError.demoLimitReached }

    // MARK: - 服务端会话

    /// 演示会话写回存（类头「写方法不落状态」口径的
    /// 局部例外）：0.18.0 会话四件（改名/置顶/归档/
    /// 删除）全部带回读对账，纯静态样本会让演示里
    /// 每次操作都报未落定——仅会话写面在此留进程内
    /// 覆盖表、读面合并呈现；进程重启复位，与演示
    /// 数据总口径一致
    private static let sessionWrites = DemoSessionWriteStore()

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        decode(
            SessionsPage.self,
            demoSessionsJSON(limit: limit, offset: 0, archived: "exclude")
        )
    }

    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage {
        decode(
            SessionsPage.self,
            demoSessionsJSON(
                limit: limit, offset: offset,
                archived: archived ?? "exclude"
            )
        )
    }

    /// 演示会话全集（相对时刻生成）：写回存的删除恒
    /// 过滤、归档按 archived 口径分流，其余字段合并
    /// 覆盖值（标题/置顶/归档）
    private func demoSessionsJSON(
        limit: Int, offset: Int, archived: String
    ) -> String {
        let now = Date().timeIntervalSince1970
        let all: [(id: String, json: String)] = [
            ("sess-live", """
            {"id": "sess-live", "source": "dashboard", "display_name": "帮我看看服务器状态",
             \(demoTitleFields(id: "sess-live", baseTitle: "看看服务器状态", baseSource: "llm")),
             \(demoFlagFields(id: "sess-live")),
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 25 * 60), "ended_at": null,
             "message_count": 9, "tool_call_count": 2,
             "input_tokens": 18200, "output_tokens": 2400}
            """),
            ("sess-cron-1", """
            {"id": "sess-cron-1", "source": "cron", "display_name": "节点巡检",
             \(demoTitleFields(id: "sess-cron-1", baseTitle: "节点巡检", baseSource: "llm")),
             \(demoFlagFields(id: "sess-cron-1")),
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 2 * 3600), "ended_at": \(now - 2 * 3600 + 95),
             "end_reason": "completed", "message_count": 6, "tool_call_count": 3,
             "input_tokens": 5200, "output_tokens": 640}
            """),
            ("sess-old", """
            {"id": "sess-old", "source": "api_server", "display_name": null,
             \(demoTitleFields(id: "sess-old", baseTitle: nil, baseSource: nil)),
             \(demoFlagFields(id: "sess-old")),
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 30 * 3600), "ended_at": \(now - 30 * 3600 + 240),
             "end_reason": "completed", "message_count": 4, "tool_call_count": 0,
             "input_tokens": 2100, "output_tokens": 480}
            """),
            // 抽屉长按 XCUITest 的未收养行样本：oneday-ai-
            // 前缀按出生证明分类为 mine，且不关联本地线程。
            ("oneday-ai-drawer-longpress", """
            {"id": "oneday-ai-drawer-longpress", "source": "api_server",
             "display_name": "演示未收养旁聊",
             \(demoTitleFields(id: "oneday-ai-drawer-longpress", baseTitle: "演示未收养旁聊", baseSource: "llm")),
             \(demoFlagFields(id: "oneday-ai-drawer-longpress")),
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 60 * 60), "ended_at": \(now - 60 * 60 + 30),
             "end_reason": "completed", "message_count": 2, "tool_call_count": 0,
             "input_tokens": 120, "output_tokens": 80}
            """),
        ]
        let visible = all.filter { item in
            if Self.sessionWrites.isDeleted(item.id) { return false }
            let isArchived = Self.sessionWrites.archived(for: item.id) ?? false
            switch archived {
            case "only": return isArchived
            case "include": return true
            default: return !isArchived
            }
        }
        let page = visible.dropFirst(offset).prefix(limit)
        return """
        {"sessions": [\(page.map { $0.json }.joined(separator: ", "))],
         "total": \(visible.count), "limit": \(limit), "offset": \(offset)}
        """
    }

    /// 标题字段片段：写回存有改名→user 来源；否则基
    /// 样本标题（llm）；基样本无标题→双 null（回落
    /// 链演示：本地派生/未命名）
    private func demoTitleFields(
        id: String, baseTitle: String?, baseSource: String?
    ) -> String {
        if let renamed = Self.sessionWrites.title(for: id) {
            return "\"title\": \(Self.jsonQuoted(renamed)), \"title_source\": \"user\""
        }
        if let baseTitle {
            return "\"title\": \(Self.jsonQuoted(baseTitle)), "
                + "\"title_source\": \"\(baseSource ?? "llm")\""
        }
        return "\"title\": null, \"title_source\": null"
    }

    /// 归档/置顶字段片段（写回存优先、默认双 false）
    private func demoFlagFields(id: String) -> String {
        let archived = Self.sessionWrites.archived(for: id) ?? false
        let pinned = Self.sessionWrites.pinned(for: id) ?? false
        return "\"archived\": \(archived), \"pinned\": \(pinned)"
    }

    private static func jsonQuoted(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        if Self.sessionWrites.isDeleted(id) {
            throw HermesError.unexpectedStatus(
                endpoint: "服务端会话详情", status: 404
            )
        }
        // 含归档行在内的全集里找（回读对账要能读到
        // 刚归档的行）
        let page = decode(
            SessionsPage.self,
            demoSessionsJSON(limit: 100, offset: 0, archived: "include")
        )
        return page.sessions.first { $0.id == id } ?? page.sessions[0]
    }

    func createServerSession(config: ServerConfig, apiKey: String, id: String?, title: String?) async throws -> ServerSession { throw HermesError.demoLimitReached }

    /// 演示建会话（0.21.0 旧注作废）：0.27.0 起无头
    /// 回退整类删除、链接失败整轮不发——演示若继续
    /// 抛错，旁聊在演示里将发不出任何消息；演示本
    /// 就是全假数据面，就地回一份假会话让链接/会话
    /// 模式形态在演示里同样走通，会话头只进演示请
    /// 求、不碰生产
    func createLinkedServerSession(config: ServerConfig, apiKey: String, id: String, model: String) async throws -> ServerSession { throw HermesError.demoLimitReached }

    /// 演示种子导入（0.27.0）：无操作成功——演示历
    /// 史只在本地，导入形态走通即可
    func importServerSession(
        config: ServerConfig, requestID: String,
        expectedRevision: Int, sessionBody: [String: JSONValue]
    ) async throws { throw HermesError.demoLimitReached }

    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws { throw HermesError.demoLimitReached }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        let now = Date().timeIntervalSince1970
        return decode(SessionMessagesResponse.self, """
        {"session_id": "\(id)", "profile": "default", "messages": [
            {"id": 1, "role": "user", "content": "帮我看看服务器现在的状态。",
             "timestamp": \(now - 1500)},
            {"id": 2, "role": "assistant",
             "content": "刚查过，一切正常：网关运行中，API 服务已连接，健康检查返回 ok。",
             "timestamp": \(now - 1440)}
        ]}
        """).messages
    }

    /// 演示搜索（P10）：在演示会话标题/预览里按词过滤，
    /// 命中形态对齐生产实样（results 元素字段）
    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit] {
        let now = Date().timeIntervalSince1970
        let all = decode(SessionSearchResponse.self, """
        {"results": [
            {"session_id": "sess-live", "id": "sess-live", "title": "帮我看看服务器状态",
             "snippet": "服务器", "role": "user", "source": "dashboard",
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 25 * 60), "message_count": 9,
             "preview": "帮我看看服务器现在的状态。"},
            {"session_id": "sess-cron-1", "id": "sess-cron-1", "title": "节点巡检",
             "snippet": "巡检", "role": "assistant", "source": "cron",
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 2 * 3600), "message_count": 6,
             "preview": "节点巡检"}
        ]}
        """).results
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return all.filter { hit in
            (hit.title?.contains(needle) ?? false)
                || (hit.preview?.contains(needle) ?? false)
                || (hit.snippet?.contains(needle) ?? false)
        }
    }

    func sessionMutationSnapshot(config: ServerConfig, id: String) async throws -> SessionMutationSnapshot { throw HermesError.demoLimitReached }
    func deleteServerSession(config: ServerConfig, id: String) async throws { throw HermesError.demoLimitReached }

    func bulkDeleteServerSessions(config: ServerConfig, ids: [String]) async throws { throw HermesError.demoLimitReached }

    func emptySessionCount(config: ServerConfig) async throws -> Int { throw HermesError.demoLimitReached }
    func deleteEmptySessions(config: ServerConfig) async throws { throw HermesError.demoLimitReached }

    /// 演示更新（0.18.0）：写回存记覆盖值，读面合并
    /// 呈现——回读对账在演示里同样成立
    func updateServerSession(
        config: ServerConfig, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws { throw HermesError.demoLimitReached }

    /// 演示清理（0.18.0）：恒报 2 条（样本里两条已结
    /// 束会话）；真跑不真删样本——演示数据口径如此
    func pruneSessions(
        config: ServerConfig, olderThanDays: Double, dryRun: Bool
    ) async throws -> Int? { throw HermesError.demoLimitReached }

    // MARK: - 档案

    func profiles(config: ServerConfig) async throws -> [ProfileItem] { throw HermesError.demoLimitReached }

    func activeProfileName(config: ServerConfig) async throws -> String? { throw HermesError.demoLimitReached }

    func setActiveProfile(config: ServerConfig, name: String) async throws { throw HermesError.demoLimitReached }

    // MARK: - 档案增删与导入导出（P10，演示口径同上）

    func createProfile(
        config: ServerConfig, name: String, cloneFrom: String?
    ) async throws { throw HermesError.demoLimitReached }

    func deleteProfile(config: ServerConfig, name: String) async throws { throw HermesError.demoLimitReached }

    func exportProfile(
        config: ServerConfig, name: String
    ) async throws -> ProfileExportResult { throw HermesError.demoLimitReached }

    func importProfile(
        config: ServerConfig, archive: String, name: String?
    ) async throws { throw HermesError.demoLimitReached }

    /// 演示 soul：带「人设」「风格」两段标题的合成样本
    /// （不放真实 soul 文本，数据设计 §2.4）
    func profileSoul(
        config: ServerConfig, name: String
    ) async throws -> ProfileSoulDocument { throw HermesError.demoLimitReached }

    func updateProfileSoul(
        config: ServerConfig, name: String, content: String
    ) async throws { throw HermesError.demoLimitReached }

    func computerUseStatus(
        config: ServerConfig
    ) async throws -> ComputerUseStatus { throw HermesError.demoLimitReached }

    // MARK: - MCP 连接（P10，演示样本：box 行形态对齐
    // 生产实样——插件预置；外加一条手动配置示例）

    func mcpServers(config: ServerConfig) async throws -> [MCPServerItem] { throw HermesError.demoLimitReached }

    func setMCPServerEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws { throw HermesError.demoLimitReached }

    func testMCPServer(
        config: ServerConfig, name: String
    ) async throws -> MCPTestResult { throw HermesError.demoLimitReached }

    // MARK: - 配置与密钥

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] { throw HermesError.demoLimitReached }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws { throw HermesError.demoLimitReached }

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] { throw HermesError.demoLimitReached }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws { throw HermesError.demoLimitReached }
    func deleteEnvVar(config: ServerConfig, key: String) async throws { throw HermesError.demoLimitReached }
    func revealEnvVar(config: ServerConfig, key: String) async throws -> String { throw HermesError.demoLimitReached }

    // MARK: - 用量与日志

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics { throw HermesError.demoLimitReached }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics { throw HermesError.demoLimitReached }

    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse { throw HermesError.demoLimitReached }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus { throw HermesError.demoLimitReached }

    // MARK: - 网关动作

    func gatewayRestart(config: ServerConfig) async throws { throw HermesError.demoLimitReached }
    func gatewayStart(config: ServerConfig) async throws { throw HermesError.demoLimitReached }
    func gatewayStop(config: ServerConfig) async throws { throw HermesError.demoLimitReached }

    // MARK: - 工作区文件与系统（0.2.1 样本，结构对实查回执）

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        let root = "/opt/data"
        switch path ?? root {
        case "/opt/data/cache/images":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/images", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "生成图-节点拓扑.png", "path": "/opt/data/cache/images/生成图-节点拓扑.png",
                 "is_directory": false, "size": 48213, "mtime": 1794141188.0,
                 "mime_type": "image/png"},
                {"name": "巡检截图.png", "path": "/opt/data/cache/images/巡检截图.png",
                 "is_directory": false, "size": 35110, "mtime": 1794054788.0,
                 "mime_type": "image/png"}
             ]}
            """)
        case "/opt/data/cache/videos":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/videos", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "演示录屏.mp4", "path": "/opt/data/cache/videos/演示录屏.mp4",
                 "is_directory": false, "size": 5242880, "mtime": 1793968388.0,
                 "mime_type": "video/mp4"}
             ]}
            """)
        case "/opt/data/cache/audio":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/audio", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "语音备忘.m4a", "path": "/opt/data/cache/audio/语音备忘.m4a",
                 "is_directory": false, "size": 96256, "mtime": 1793881988.0,
                 "mime_type": "audio/mp4"}
             ]}
            """)
        case "/opt/data/cache/documents":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/documents", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "网络巡检周报.md", "path": "/opt/data/cache/documents/网络巡检周报.md",
                 "is_directory": false, "size": 3110, "mtime": 1794054788.0,
                 "mime_type": "text/markdown"}
             ]}
            """)
        case "/opt/data/cache/screenshots":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/screenshots", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "官网首页截图.png", "path": "/opt/data/cache/screenshots/官网首页截图.png",
                 "is_directory": false, "size": 66410, "mtime": 1793881988.0,
                 "mime_type": "image/png"}
             ]}
            """)
        case "/opt/data/cron/output":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cron/output", "parent": "/opt/data/cron",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "每日简报-1108.txt", "path": "/opt/data/cron/output/每日简报-1108.txt",
                 "is_directory": false, "size": 1890, "mtime": 1793968388.0,
                 "mime_type": "text/plain"}
             ]}
            """)
        case "/opt/data/image_cache":
            return decode(FilesListing.self, """
            {"path": "/opt/data/image_cache", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "参考图-架构.png", "path": "/opt/data/image_cache/参考图-架构.png",
                 "is_directory": false, "size": 51200, "mtime": 1793795588.0,
                 "mime_type": "image/png"}
             ]}
            """)
        case "/opt/data/images":
            return decode(FilesListing.self, """
            {"path": "/opt/data/images", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "nodes-status.png", "path": "/opt/data/images/nodes-status.png",
                 "is_directory": false, "size": 48213, "mtime": 1794141188.0,
                 "mime_type": "image/png"},
                {"name": "chart-weekly.png", "path": "/opt/data/images/chart-weekly.png",
                 "is_directory": false, "size": 35110, "mtime": 1794054788.0,
                 "mime_type": "image/png"},
                {"name": "screen-record.mp4", "path": "/opt/data/images/screen-record.mp4",
                 "is_directory": false, "size": 5242880, "mtime": 1793968388.0,
                 "mime_type": "video/mp4"},
                {"name": "voice-note.m4a", "path": "/opt/data/images/voice-note.m4a",
                 "is_directory": false, "size": 96256, "mtime": 1793881988.0,
                 "mime_type": "audio/mp4"}
             ]}
            """)
        case "/opt/data/reports":
            return decode(FilesListing.self, """
            {"path": "/opt/data/reports", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "weekly.md", "path": "/opt/data/reports/weekly.md",
                 "is_directory": false, "size": 3110, "mtime": 1794054788.0,
                 "mime_type": "text/markdown"}
             ]}
            """)
        case "/opt/data/cache/scratch", "/opt/data/audio_cache":
            let emptyPath = path ?? root
            return decode(FilesListing.self, """
            {"path": "\(emptyPath)", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false, "entries": []}
            """)
        case "/opt/data":
            return decode(FilesListing.self, """
            {"path": "/opt/data", "parent": null,
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "images", "path": "/opt/data/images",
                 "is_directory": true, "size": null, "mtime": 1794141188.0,
                 "mime_type": null},
                {"name": "reports", "path": "/opt/data/reports",
                 "is_directory": true, "size": null, "mtime": 1794054788.0,
                 "mime_type": null},
                {"name": "交付说明.md", "path": "/opt/data/交付说明.md",
                 "is_directory": false, "size": 2048, "mtime": 1793711588.0,
                 "mime_type": "text/markdown"}
             ]}
            """)
        default:
            let unknownPath = path ?? root
            return decode(FilesListing.self, """
            {"path": "\(unknownPath)", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false, "entries": []}
            """)
        }
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws { throw HermesError.demoLimitReached }

    // 演示模式不落真实数据（与 deleteFile 同口径 no-op；
    // 演示样本为静态集，上传/建夹在演示里不回显）
    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws { throw HermesError.demoLimitReached }

    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String
    ) async throws -> ManagedFileUploadReceipt { throw HermesError.demoLimitReached }

    func makeDirectory(config: ServerConfig, path: String) async throws { throw HermesError.demoLimitReached }

    func fileData(config: ServerConfig, path: String) async throws -> Data {
        if path.hasSuffix(".png") {
            return Self.placeholderPNG(label: (path as NSString).lastPathComponent)
        }
        if path.hasSuffix(".md") {
            return Data("# 演示文件\n\n这是演示模式的文本预览样本。\n".utf8)
        }
        if path.hasSuffix(".txt") {
            return Data("每日简报（演示）\n节点 41 个全部在线，电费余额读数正常。\n".utf8)
        }
        if path.hasSuffix(".json") {
            return Data("{\"demo\": true, \"count\": 3}\n".utf8)
        }
        if path.hasSuffix(".log") {
            return Data("INFO demo log line\n".utf8)
        }
        return Data()
    }

    /// 演示缩略图：纯色块＋文件名（UIKit 渲染，不连网）
    private static func placeholderPNG(label: String) -> Data {
        #if canImport(UIKit)
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.85, green: 0.91, blue: 0.98, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor(red: 0.1, green: 0.25, blue: 0.55, alpha: 1),
            ]
            let text = label as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
        }
        return image.pngData() ?? Data()
        #else
        return Data()
        #endif
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats { throw HermesError.demoLimitReached }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // 样本与模型同仓维护，解码失败即开发期错误，直接暴露
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

// MARK: - 任务（P3 演示样本：专属板已开通＋四态样本任务）

extension DemoHermesClient {
    func kanbanWorkflow(config: ServerConfig) async throws -> KanbanWorkflow {
        decode(KanbanWorkflow.self, """
        {"columns": ["triage", "todo", "scheduled", "ready",
                     "running", "blocked", "review", "done"]}
        """)
    }

    func kanbanBoards(config: ServerConfig) async throws -> [String] {
        ["default", KanbanContract.boardSlug]
    }

    func kanbanBoard(
        config: ServerConfig, board: String
    ) async throws -> KanbanBoardSnapshot {
        KanbanBoardSnapshot(
            tasks: Self.demoTasks, latestEventId: 12
        )
    }

    func kanbanTaskDetail(
        config: ServerConfig, board: String, id: String
    ) async throws -> KanbanTaskDetail {
        let now = Date()
        let task = Self.demoTasks.first { $0.id == id }
            ?? Self.demoTasks[0]
        if task.presentation == .needsInput {
            return KanbanTaskDetail(
                task: task,
                comments: [
                    KanbanComment(
                        id: "1", author: "default",
                        body: "照片是按年份分，还是按地点分？",
                        createdAt: now.addingTimeInterval(-900)
                    ),
                ],
                events: [
                    KanbanEvent(
                        id: "3", kind: "created", text: nil,
                        createdAt: task.createdAt
                    ),
                    KanbanEvent(
                        id: "9", kind: "blocked", text: nil,
                        createdAt: now.addingTimeInterval(-900),
                        // 问题原文的真实存放处（P3 验收
                        // 实形：payload.reason＋kind）
                        payloadReason: "照片是按年份分，还是按地点分？",
                        payloadKind: "needs_input"
                    ),
                ],
                runs: [
                    KanbanRun(
                        id: 5, status: "blocked", outcome: "blocked",
                        summary: "照片是按年份分，还是按地点分？",
                        startedAt: now.addingTimeInterval(-1500),
                        endedAt: now.addingTimeInterval(-900)
                    ),
                ],
                attachmentNames: []
            )
        }
        return KanbanTaskDetail(
            task: task, comments: [], events: [], runs: [],
            attachmentNames: []
        )
    }

    func kanbanCreateTask(
        config: ServerConfig, board: String, title: String, body: String,
        idempotencyKey: String
    ) async throws -> KanbanTask {
        KanbanTask(
            id: "demo-new", title: title, body: body, status: "ready",
            assignee: KanbanContract.defaultAssignee,
            idempotencyKey: idempotencyKey, createdAt: Date()
        )
    }

    func kanbanDispatch(
        config: ServerConfig, board: String
    ) async throws -> KanbanDispatchReceipt {
        KanbanDispatchReceipt(spawnedCount: 1)
    }

    func kanbanPatchTaskStatus(
        config: ServerConfig, board: String, id: String, status: String
    ) async throws {
        // 演示写方法静默成功（类头口径）
    }

    func kanbanDeleteTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        // 演示写方法静默成功（类头口径）
    }

    func kanbanComment(
        config: ServerConfig, board: String, id: String, body: String
    ) async throws {
        // 演示写方法静默成功（类头口径）
    }

    func kanbanReclaimTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        // 演示写方法静默成功（类头口径）
    }

    func kanbanTerminateRun(
        config: ServerConfig, board: String, runID: Int
    ) async throws {
        // 演示写方法静默成功（类头口径）
    }

    /// 演示任务样本：运行/待审批/等你回答/已完成四态，
    /// 时刻相对当前生成（类头口径：截图不出现过期日期）
    private static var demoTasks: [KanbanTask] {
        let now = Date()
        return [
            KanbanTask(
                id: "demo-run", title: "整理下载目录文件清单",
                body: "列出下载目录全部文件，按类型分组汇总。",
                status: "running",
                assignee: KanbanContract.defaultAssignee,
                currentRunId: 3,
                createdAt: now.addingTimeInterval(-1800),
                startedAt: now.addingTimeInterval(-1740)
            ),
            KanbanTask(
                id: "demo-review", title: "给相册照片按月份归档",
                body: "把照片目录按月份建子文件夹归档。",
                status: "review",
                assignee: KanbanContract.defaultAssignee,
                latestSummary: "归档方案已生成，等待确认后执行移动。",
                createdAt: now.addingTimeInterval(-3600)
            ),
            KanbanTask(
                id: "demo-ask", title: "归档旧截图",
                body: "把旧截图移进归档目录。",
                status: "blocked",
                assignee: KanbanContract.defaultAssignee,
                blockKind: "needs_input",
                // 问题原文不在 task 上（生产实查无
                // block_reason 字段）——在详情的
                // blocked 事件 payload 与 run summary
                // 里（见 kanbanTaskDetail 演示详情）
                createdAt: now.addingTimeInterval(-5400)
            ),
            KanbanTask(
                id: "demo-done", title: "检查某网页有没有更新",
                body: "打开页面比对标题与昨天是否一致。",
                status: "done",
                assignee: KanbanContract.defaultAssignee,
                result: "页面标题无变化，无需处理。",
                latestSummary: "页面标题无变化，无需处理。",
                createdAt: now.addingTimeInterval(-86400),
                completedAt: now.addingTimeInterval(-86300)
            ),
        ]
    }
}

/// 演示会话写回存（DemoHermesClient 会话段专用）：
/// 进程内覆盖表（改名/置顶/归档/删除），NSLock 守
/// 护；进程重启即复位，与演示数据总口径一致。
final class DemoSessionWriteStore: @unchecked Sendable {
    private let lock = NSLock()
    private var titles: [String: String] = [:]
    private var pinnedValues: [String: Bool] = [:]
    private var archivedValues: [String: Bool] = [:]
    private var deletedIDs: Set<String> = []

    func title(for id: String) -> String? {
        lock.withLock { titles[id] }
    }

    func pinned(for id: String) -> Bool? {
        lock.withLock { pinnedValues[id] }
    }

    func archived(for id: String) -> Bool? {
        lock.withLock { archivedValues[id] }
    }

    func isDeleted(_ id: String) -> Bool {
        lock.withLock { deletedIDs.contains(id) }
    }

    func setTitle(_ title: String, for id: String) {
        lock.withLock { titles[id] = title }
    }

    func setPinned(_ pinned: Bool, for id: String) {
        lock.withLock { pinnedValues[id] = pinned }
    }

    func setArchived(_ archived: Bool, for id: String) {
        lock.withLock { archivedValues[id] = archived }
    }

    func markDeleted(_ id: String) {
        lock.withLock { deletedIDs.insert(id) }
    }
}
