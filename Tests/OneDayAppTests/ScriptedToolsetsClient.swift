import Foundation
import OneDayCore
#if canImport(UIKit)
import UIKit
#endif
@testable import OneDayApp


/// 工具集脚本盒（引用型，跨客户端值拷贝存活）：ScriptedToolsetsClient
/// 的工具集八口＋rawConfig 查它出演「服务端真值」。出演规则照 34-S
/// 真行为验收口径：
/// - 启停受理后真值翻转——普通集翻清单行的 enabled；config 承托集
///   （rawConfig 里节内带 enabled 键者，生产实测 stt）翻 config 的值、
///   清单行保持读面原样，与服务端落盘形态一致；
/// - 各 Applies 开关关掉时只回回执不翻真值（出演「受理未生效」，
///   供回读未确认景）；各 Error 注入非空时写口先抛它；
/// - 任一读面脚本缺席（nil／无此键）即抛 unreachable（桩未配），
///   与 FailingHermesClient 缺席口径一致。
final class ToolsetsScript: @unchecked Sendable {
    var listResponse: ToolsetsListResponse?
    var rawConfigValue: [String: JSONValue]?
    var toggleError: HermesError?
    var toggleApplies = true
    var panels: [String: ToolsetConfigPanel] = [:]
    var catalogs: [String: ToolsetModelCatalog] = [:]
    var backendsValue: TerminalBackends?
    var providerError: HermesError?
    var providerApplies = true
    var modelError: HermesError?
    var modelApplies = true
    var backendError: HermesError?
    var backendApplies = true
    /// 写口调用记录（断言「未就绪后端被本地拦截、没发写口」用）
    var toggleCalls: [(name: String, enabled: Bool)] = []
    var backendSelectCalls: [String] = []

    /// 出演服务端落盘：config 承托集翻 config 节 enabled（清单行
    /// 不动），其余集翻清单行 enabled
    func applyToggle(name: String, enabled: Bool) {
        if var raw = rawConfigValue,
           case .object(var fields) = raw[name],
           fields["enabled"] != nil {
            fields["enabled"] = .bool(enabled)
            raw[name] = .object(fields)
            rawConfigValue = raw
            return
        }
        guard let list = listResponse else { return }
        let rows = list.data.map { row -> ToolsetRow in
            guard row.name == name else { return row }
            return ToolsetRow(
                name: row.name, label: row.label,
                description: row.description, enabled: enabled,
                configured: row.configured, tools: row.tools
            )
        }
        listResponse = ToolsetsListResponse(
            object: list.object, platform: list.platform, data: rows
        )
    }

    /// 出演 provider 落盘：面板 active_provider 与逐行 is_active 同步翻
    func applyProvider(name: String, provider: String) {
        guard let panel = panels[name] else { return }
        panels[name] = ToolsetConfigPanel(
            name: panel.name, hasCategory: panel.hasCategory,
            providers: panel.providers.map { item in
                ToolsetProvider(
                    name: item.name, badge: item.badge, tag: item.tag,
                    envVars: item.envVars,
                    requiresNousAuth: item.requiresNousAuth,
                    isActive: item.name == provider, status: item.status
                )
            },
            activeProvider: provider
        )
    }

    /// 出演模型落盘：目录 current 翻到新模型
    func applyModel(name: String, model: String) {
        guard let catalog = catalogs[name] else { return }
        catalogs[name] = ToolsetModelCatalog(
            name: catalog.name, hasModels: catalog.hasModels,
            provider: catalog.provider, models: catalog.models,
            current: model, defaultModel: catalog.defaultModel
        )
    }

    /// 出演终端后端落盘：active 与逐行 active 同步翻
    func applyBackend(_ backend: String) {
        guard let value = backendsValue else { return }
        backendsValue = TerminalBackends(
            active: backend,
            backends: value.backends.map { item in
                TerminalBackend(
                    name: item.name, label: item.label,
                    description: item.description,
                    active: item.name == backend,
                    status: item.status, detail: item.detail
                )
            }
        )
    }
}

/// 工具集脚本客户端（DESIGN §358）：自 FailingHermesClient 机械
/// 变换生成——除工具集八口＋rawConfig 查 ToolsetsScript 脚本盒
/// 出演真值外，其余方法与原桩同口径恒抛 unreachable。原桩本体
/// 是 C-13 冻结面、不许长行为，故脚本行为只活在本文件；协议
/// 增删方法时照 gen_scripted.py 同式重跑对齐（编译器以协议
/// 一致性报错兜底）。
struct ScriptedToolsetsClient: HermesClientProtocol {
    /// 工具集脚本盒（引用型，跨值拷贝存活）
    var toolsetsScript = ToolsetsScript()

    func health(config: ServerConfig) async throws -> HealthResponse {
        throw HermesError.unreachable("离线桩")
    }

    func login(config: ServerConfig, password: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        throw HermesError.unreachable("离线桩")
    }

    func updateCheck(config: ServerConfig) async throws -> UpdateCheckResponse {
        throw HermesError.unreachable("离线桩")
    }

    func updateReceipt(config: ServerConfig) async throws -> UpdateReceiptResponse {
        throw HermesError.unreachable("离线桩")
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        throw HermesError.unreachable("离线桩")
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        throw HermesError.unreachable("离线桩")
    }

    func capabilities(config: ServerConfig, apiKey: String) async throws -> CapabilitiesResponse {
        throw HermesError.unreachable("离线桩")
    }

    func settingsRegistry(config: ServerConfig, apiKey: String) async throws -> SettingsRegistryResponse {
        throw HermesError.unreachable("离线桩")
    }

    func healthDetailed(config: ServerConfig, apiKey: String) async throws -> HealthDetailedResponse {
        throw HermesError.unreachable("离线桩")
    }

    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage],
        sessionID: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: HermesError.unreachable("离线桩")
            )
        }
    }

    func submitRun(
        config: ServerConfig, apiKey: String, sessionID: String,
        input: RunInput, model: String, provider: String?,
        idempotencyKey: String
    ) async throws -> RunSubmitResponse {
        throw HermesError.unreachable("离线桩")
    }

    func runStatus(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws -> RunStatusResponse? {
        throw HermesError.unreachable("离线桩")
    }

    func runEvents(
        config: ServerConfig, apiKey: String, runID: String,
        lastSeq: Int
    ) -> AsyncStream<RunEventEnvelope> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    func stopRun(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func clearCookies(config: ServerConfig) {}

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus {
        throw HermesError.unreachable("离线桩")
    }

    func setMemoryProvider(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig {
        throw HermesError.unreachable("离线桩")
    }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func resetMemory(config: ServerConfig, target: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func learningGraph(config: ServerConfig) async throws -> LearningGraph {
        throw HermesError.unreachable("离线桩")
    }

    func learningNode(
        config: ServerConfig, id: String
    ) async throws -> LearningNodeContent {
        throw HermesError.unreachable("离线桩")
    }

    func updateLearningNode(
        config: ServerConfig, id: String, content: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteLearningNode(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func skills(config: ServerConfig) async throws -> [SkillItem] {
        throw HermesError.unreachable("离线桩")
    }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent {
        throw HermesError.unreachable("离线桩")
    }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubSources(config: ServerConfig) async throws -> [HubSource] {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubSearch(
        config: ServerConfig, query: String, source: String?
    ) async throws -> [HubSkill] {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubPreview(
        config: ServerConfig, identifier: String
    ) async throws -> HubPreview {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubInstall(config: ServerConfig, identifier: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubUninstall(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func cronJobs(config: ServerConfig) async throws -> [CronJob] {
        throw HermesError.unreachable("离线桩")
    }

    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob {
        throw HermesError.unreachable("离线桩")
    }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func pauseCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func resumeCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func triggerCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] {
        throw HermesError.unreachable("离线桩")
    }
    func cronBlueprints(config: ServerConfig) async throws -> [CronBlueprint] {
        throw HermesError.unreachable("离线桩")
    }

    func instantiateBlueprint(
        config: ServerConfig, blueprint: String, values: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func cronDeliveryTargets(config: ServerConfig) async throws -> [CronDeliveryTarget] {
        throw HermesError.unreachable("离线桩")
    }

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        throw HermesError.unreachable("离线桩")
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        throw HermesError.unreachable("离线桩")
    }

    func createServerSession(config: ServerConfig, apiKey: String, id: String?, title: String?) async throws -> ServerSession {
        throw HermesError.unreachable("离线桩")
    }

    func createLinkedServerSession(config: ServerConfig, apiKey: String, id: String, model: String) async throws -> ServerSession {
        throw HermesError.unreachable("离线桩")
    }

    func importServerSession(
        config: ServerConfig, requestID: String,
        expectedRevision: Int, sessionBody: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMessagesPage(
        config: ServerConfig, id: String, limit: Int, offset: Int
    ) async throws -> [SessionMessage] {
        throw HermesError.unreachable("离线桩")
    }

    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit] {
        throw HermesError.unreachable("离线桩")
    }

    func sessionTimeline(
        config: ServerConfig, id: String,
        afterRowID: Int64?, limit: Int
    ) async throws -> SessionTimelinePage {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMessagesAround(
        config: ServerConfig, id: String,
        rowID: Int64, limit: Int
    ) async throws -> SessionAroundPage {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMutationSnapshot(config: ServerConfig, id: String) async throws -> SessionMutationSnapshot {
        throw HermesError.unreachable("离线桩")
    }

    func deleteServerSession(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func rewindSession(
        config: ServerConfig, id: String,
        targetMessageID: Int, predecessorRowID: Int?
    ) async throws -> RewindReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func emptySessionCount(config: ServerConfig) async throws -> Int {
        throw HermesError.unreachable("离线桩")
    }

    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage {
        throw HermesError.unreachable("离线桩")
    }

    func updateServerSession(
        config: ServerConfig, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func pruneSessions(
        config: ServerConfig, olderThanDays: Double, dryRun: Bool
    ) async throws -> Int? {
        throw HermesError.unreachable("离线桩")
    }

    func profiles(config: ServerConfig) async throws -> [ProfileItem] {
        throw HermesError.unreachable("离线桩")
    }

    func activeProfileName(config: ServerConfig) async throws -> String? {
        throw HermesError.unreachable("离线桩")
    }

    func activeProfile(
        config: ServerConfig
    ) async throws -> ActiveProfileResponse {
        throw HermesError.unreachable("离线桩")
    }

    func setActiveProfile(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func profileSoul(
        config: ServerConfig, name: String
    ) async throws -> ProfileSoulDocument {
        throw HermesError.unreachable("离线桩")
    }

    func updateProfileSoul(
        config: ServerConfig, name: String, content: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func createProfile(
        config: ServerConfig, name: String, cloneFrom: String?
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteProfile(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func exportProfile(
        config: ServerConfig, name: String
    ) async throws -> ProfileExportResult {
        throw HermesError.unreachable("离线桩")
    }

    func importProfile(
        config: ServerConfig, archive: String, name: String?
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func computerUseStatus(
        config: ServerConfig
    ) async throws -> ComputerUseStatus {
        throw HermesError.unreachable("离线桩")
    }

    func mcpServers(config: ServerConfig) async throws -> [MCPServerItem] {
        throw HermesError.unreachable("离线桩")
    }
    func mcpCatalog(config: ServerConfig) async throws -> MCPCatalogResponse {
        throw HermesError.unreachable("离线桩")
    }

    func installMCPCatalogEntry(
        config: ServerConfig, name: String, env: [String: String], enable: Bool
    ) async throws -> MCPInstallReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func setMCPServerEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func testMCPServer(
        config: ServerConfig, name: String
    ) async throws -> MCPTestResult {
        throw HermesError.unreachable("离线桩")
    }

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] {
        guard let raw = toolsetsScript.rawConfigValue else {
            throw HermesError.unreachable("离线桩")
        }
        return raw
    }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] {
        throw HermesError.unreachable("离线桩")
    }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteEnvVar(config: ServerConfig, key: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        throw HermesError.unreachable("离线桩")
    }

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics {
        throw HermesError.unreachable("离线桩")
    }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics {
        throw HermesError.unreachable("离线桩")
    }

    func modelOptions(config: ServerConfig) async throws -> [String] {
        throw HermesError.unreachable("离线桩")
    }

    func modelOptionsRaw(config: ServerConfig) async throws -> JSONValue {
        throw HermesError.unreachable("离线桩")
    }

    func setMainModel(
        config: ServerConfig, provider: String, model: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func mainModelAssignment(
        config: ServerConfig, providerNames: [String]
    ) async throws -> MainModelAssignment {
        throw HermesError.unreachable("离线桩")
    }

    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse {
        throw HermesError.unreachable("离线桩")
    }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus {
        throw HermesError.unreachable("离线桩")
    }

    func messagingPlatforms(config: ServerConfig) async throws -> MessagingPlatformsResponse {
        throw HermesError.unreachable("离线桩")
    }

    func updateMessagingPlatform(config: ServerConfig, platform: String, enabled: Bool, env: [String: String], clearEnv: [String]) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func gatewayRestart(config: ServerConfig) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func gatewayStart(config: ServerConfig) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func gatewayStop(config: ServerConfig) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func opsDoctor(config: ServerConfig) async throws -> OpsSpawnResponse {
        throw HermesError.unreachable("离线桩")
    }

    func opsSecurityAudit(config: ServerConfig) async throws -> OpsSpawnResponse {
        throw HermesError.unreachable("离线桩")
    }

    func opsActionStatus(config: ServerConfig, name: String, lines: Int) async throws -> OpsActionStatus {
        throw HermesError.unreachable("离线桩")
    }

    func opsBackup(config: ServerConfig) async throws -> OpsSpawnResponse {
        throw HermesError.unreachable("离线桩")
    }

    func opsCheckpoints(config: ServerConfig) async throws -> CheckpointsResponse {
        throw HermesError.unreachable("离线桩")
    }

    func voiceConfig(config: ServerConfig) async throws -> VoiceConfigResponse {
        throw HermesError.unreachable("离线桩")
    }

    func speak(config: ServerConfig, text: String) async throws -> SpeakResponse {
        throw HermesError.unreachable("离线桩")
    }

    func issueEnrollmentCode(config: ServerConfig, apiKey: String) async throws -> EnrollmentIssue {
        throw HermesError.unreachable("离线桩")
    }

    func claimEnrollment(config: ServerConfig, code: String) async throws -> EnrollmentClaim {
        throw HermesError.unreachable("离线桩")
    }

    func registerPushToken(config: ServerConfig, apiKey: String, body: PushTokenRegistrationBody) async throws -> PushTokenRegisteredResponse {
        throw HermesError.unreachable("离线桩")
    }

    func listGrants(config: ServerConfig, apiKey: String) async throws -> GrantsListResponse {
        throw HermesError.unreachable("离线桩")
    }

    func listApprovals(config: ServerConfig, apiKey: String) async throws -> ApprovalsListResponse {
        throw HermesError.unreachable("离线桩")
    }

    func routeProbe(config: ServerConfig, apiKey: String?, path: String) async -> RouteProbeResult? {
        nil
    }

    func revokeGrant(config: ServerConfig, apiKey: String, patternKey: String) async throws -> GrantRevocationReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func pairingList(config: ServerConfig) async throws -> PairingListResponse {
        throw HermesError.unreachable("离线桩")
    }

    func pairingApprove(config: ServerConfig, platform: String, requestID: String) async throws -> PairingApproveReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func pairingRevoke(config: ServerConfig, platform: String, userID: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func pairingClearPending(config: ServerConfig) async throws -> PairingClearPendingReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func toolsets(config: ServerConfig, apiKey: String) async throws -> ToolsetsListResponse {
        guard let response = toolsetsScript.listResponse else {
            throw HermesError.unreachable("离线桩")
        }
        return response
    }

    func setToolsetEnabled(config: ServerConfig, apiKey: String, name: String, enabled: Bool) async throws -> ToolsetToggleReceipt {
        toolsetsScript.toggleCalls.append((name: name, enabled: enabled))
        if let error = toolsetsScript.toggleError { throw error }
        if toolsetsScript.toggleApplies {
            toolsetsScript.applyToggle(name: name, enabled: enabled)
        }
        return ToolsetToggleReceipt(ok: true, name: name, enabled: enabled)
    }

    func toolsetConfig(config: ServerConfig, name: String) async throws -> ToolsetConfigPanel {
        guard let panel = toolsetsScript.panels[name] else {
            throw HermesError.unreachable("离线桩")
        }
        return panel
    }

    func selectToolsetProvider(config: ServerConfig, name: String, provider: String) async throws {
        if let error = toolsetsScript.providerError { throw error }
        if toolsetsScript.providerApplies {
            toolsetsScript.applyProvider(name: name, provider: provider)
        }
    }

    func toolsetModels(config: ServerConfig, name: String) async throws -> ToolsetModelCatalog {
        guard let catalog = toolsetsScript.catalogs[name] else {
            throw HermesError.unreachable("离线桩")
        }
        return catalog
    }

    func selectToolsetModel(config: ServerConfig, name: String, model: String) async throws {
        if let error = toolsetsScript.modelError { throw error }
        if toolsetsScript.modelApplies {
            toolsetsScript.applyModel(name: name, model: model)
        }
    }

    func terminalBackends(config: ServerConfig) async throws -> TerminalBackends {
        guard let value = toolsetsScript.backendsValue else {
            throw HermesError.unreachable("离线桩")
        }
        return value
    }

    func selectTerminalBackend(config: ServerConfig, backend: String) async throws {
        toolsetsScript.backendSelectCalls.append(backend)
        if let error = toolsetsScript.backendError { throw error }
        if toolsetsScript.backendApplies {
            toolsetsScript.applyBackend(backend)
        }
    }

    func setReaction(config: ServerConfig, apiKey: String, sessionID: String, rowID: Int, emoji: String) async throws -> ReactionUpdate {
        throw HermesError.unreachable("离线桩")
    }

    func clearReaction(config: ServerConfig, apiKey: String, sessionID: String, rowID: Int) async throws -> ReactionUpdate {
        throw HermesError.unreachable("离线桩")
    }

    func elevenLabsVoices(config: ServerConfig) async throws -> ElevenLabsVoicesResponse {
        throw HermesError.unreachable("离线桩")
    }

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        throw HermesError.unreachable("离线桩")
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func fileData(config: ServerConfig, path: String) async throws -> Data {
        throw HermesError.unreachable("离线桩")
    }

    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String
    ) async throws -> ManagedFileUploadReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func makeDirectory(config: ServerConfig, path: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanWorkflow(config: ServerConfig) async throws -> KanbanWorkflow {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanBoards(config: ServerConfig) async throws -> [String] {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanBoard(
        config: ServerConfig, board: String
    ) async throws -> KanbanBoardSnapshot {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanTaskDetail(
        config: ServerConfig, board: String, id: String
    ) async throws -> KanbanTaskDetail {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanCreateTask(
        config: ServerConfig, board: String, title: String, body: String,
        idempotencyKey: String
    ) async throws -> KanbanTask {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanDispatch(
        config: ServerConfig, board: String
    ) async throws -> KanbanDispatchReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanPatchTaskStatus(
        config: ServerConfig, board: String, id: String, status: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanDeleteTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanComment(
        config: ServerConfig, board: String, id: String, body: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanReclaimTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanTerminateRun(
        config: ServerConfig, board: String, runID: Int
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }
}

// MARK: - 高级能力面离线桩（工具集脚本客户端）（H8/H9/H11/H13，DESIGN §390）：
// 与本体同口径恒抛 unreachable；脚本化行为只活在
// ScriptedAdvancedClient，不许长进冻结桩本体。
extension ScriptedToolsetsClient {
    func delegationRouting(config: ServerConfig) async throws -> DelegationRouting {
        throw HermesError.unreachable("离线桩")
    }
    func setDelegationBackend(config: ServerConfig, backend: String) async throws {
        throw HermesError.unreachable("离线桩")
    }
    func setDelegationModelMap(config: ServerConfig, routes: [DelegationModelRoute], defaultRoute: String?) async throws {
        throw HermesError.unreachable("离线桩")
    }
    func setDelegationProfileRoutes(config: ServerConfig, routes: [DelegationProfileRoute], defaultRoute: String?) async throws {
        throw HermesError.unreachable("离线桩")
    }
    func moaConfig(config: ServerConfig) async throws -> MoaConfig {
        throw HermesError.unreachable("离线桩")
    }
    func setMoaConfig(config: ServerConfig, moa: MoaConfig) async throws -> MoaConfig {
        throw HermesError.unreachable("离线桩")
    }
    func auxiliaryTasks(config: ServerConfig) async throws -> AuxiliaryTasksResponse {
        throw HermesError.unreachable("离线桩")
    }
    func setModelAssignment(config: ServerConfig, scope: String, task: String?, provider: String, model: String, confirmExpensive: Bool) async throws -> ModelSetReceipt {
        throw HermesError.unreachable("离线桩")
    }
    func webhooksPage(config: ServerConfig) async throws -> WebhooksPage {
        throw HermesError.unreachable("离线桩")
    }
    func createWebhook(config: ServerConfig, input: WebhookCreateInput) async throws -> WebhookCreateReceipt {
        throw HermesError.unreachable("离线桩")
    }
    func deleteWebhook(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }
    func setWebhookEnabled(config: ServerConfig, name: String, enabled: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }
    func enableWebhooks(config: ServerConfig) async throws -> WebhooksEnableReceipt {
        throw HermesError.unreachable("离线桩")
    }
    func curatorStatus(config: ServerConfig) async throws -> CuratorStatus {
        throw HermesError.unreachable("离线桩")
    }
    func setCuratorPaused(config: ServerConfig, paused: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }
    func runCurator(config: ServerConfig, profile: String?) async throws -> OpsSpawnResponse {
        throw HermesError.unreachable("离线桩")
    }
    func sessionStoreStats(config: ServerConfig) async throws -> SessionStoreStats {
        throw HermesError.unreachable("离线桩")
    }
    func opsHooks(config: ServerConfig) async throws -> OpsHooksPage {
        throw HermesError.unreachable("离线桩")
    }
    func kanbanDecompose(config: ServerConfig, board: String, id: String) async throws -> KanbanDecomposeReceipt {
        throw HermesError.unreachable("离线桩")
    }
}
