import Foundation
import OneDayCore

/// 体检留痕（H1-a）：每台服务器只存最近一次体检的结
/// 论摘要（时间＋四态＋各组计数），原始日志永不落盘
/// （可能含敏感路径/配置值）。归宿与 ThreadReadMark-
/// Store 同式（UserDefaults JSON）；体检面与状态页次
/// 入口共读同一份（shared）。
@MainActor
@Observable
final class HealthSummaryStore {
    static let shared = HealthSummaryStore()

    private let defaults: UserDefaults
    private var summaries: [String: HealthCheckSummary] = [:]

    private static let defaultsKey = "health.lastSummary.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(
               [String: HealthCheckSummary].self, from: data
           ) {
            summaries = decoded
        }
    }

    func summary(for serverBase: String?) -> HealthCheckSummary? {
        guard let serverBase else { return nil }
        return summaries[serverBase]
    }

    func save(_ summary: HealthCheckSummary) {
        summaries[summary.serverBase] = summary
        if let data = try? JSONEncoder().encode(summaries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// 体检动作（服务端 action 名即日志名）
enum HealthAction: String, Sendable {
    case doctor = "doctor"
    case securityAudit = "security-audit"

    var name: String { rawValue }
}

/// 引擎内部错误（对外只翻人话，见 humanMessage）
enum HealthCheckEngineError: Error {
    /// 轮询超时（含本轮标记一直没落盘）
    case timedOut
}

/// 体检引擎（H1-a）：两组依次跑（doctor → security-
/// audit）——服务端同一 action 只有一个跟踪槽、日志
/// 又是多方共享的追加文件，并行只会互相串轮（H1-0
/// 探活口径）。每组独立状态：一组失败不拖垮整面，失
/// 败组可单独重试；整轮结束把结论摘要落留痕。
@MainActor
@Observable
/// §416 新鲜度普查豁免：检查面——显式触发汇总，无读触发全量拉取（判定表见 DESIGN §416）
final class HealthCheckStore {
    enum Phase: Equatable {
        case idle
        case running(since: Date)
        case finished
        /// 失败的人话原因（这一项没跑成，与「没跑完」
        /// 的检查结论分开：这是客户端/网络层没跑成）
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    /// 一轮动作的执行口：注入点在「按动作名跑到终态
    /// 并带回本轮日志切片＋退出码」这一层——生产实现
    /// 是 spawn＋poll（liveExecutor），测试注入脚本。
    typealias ActionExecutor =
        @MainActor (HealthAction) async throws -> ActionResult

    struct ActionResult: Sendable {
        var lines: [String]
        var exitCode: Int?
    }

    /// 身份对账的取数口（H1-d）：注入点在「装配一份
    /// 对账输入快照」这一层——生产实现现拉目录＋状态
    /// ＋档案（liveIdentityFetcher），判定在 Core 纯
    /// 函数 IdentityReconciler，测试注入 fixture 快照。
    typealias IdentityFetcher =
        @MainActor () async throws -> IdentityReconciliationInput

    private(set) var doctorPhase: Phase = .idle
    private(set) var auditPhase: Phase = .idle
    private(set) var identityPhase: Phase = .idle
    private(set) var doctorRun: DoctorRun?
    private(set) var auditRun: SecurityAuditRun?
    private(set) var identityRun: IdentityReconciliation?

    private let summaryStore: HealthSummaryStore

    init(summaryStore: HealthSummaryStore = .shared) {
        self.summaryStore = summaryStore
    }

    var isRunning: Bool {
        doctorPhase.isRunning || auditPhase.isRunning
            || identityPhase.isRunning
    }

    /// 「开始体检」可用性：任一组在跑时整面禁用重入
    /// （同名动作串行化口径，见类头注）
    var canStart: Bool { !isRunning }

    func phase(for action: HealthAction) -> Phase {
        switch action {
        case .doctor: return doctorPhase
        case .securityAudit: return auditPhase
        }
    }

    // MARK: - 对外入口（生产）

    func runAll(appState: AppState) async {
        guard let base = appState.config?.baseString else {
            doctorPhase = .failed("还没连上服务器")
            auditPhase = .failed("还没连上服务器")
            identityPhase = .failed("还没连上服务器")
            return
        }
        await runAll(
            serverBase: base,
            execute: Self.liveExecutor(appState: appState),
            fetchIdentity: Self.liveIdentityFetcher(
                appState: appState
            )
        )
    }

    /// 单组重试（失败组的人话重试按钮）
    func retry(_ action: HealthAction, appState: AppState) async {
        guard let base = appState.config?.baseString else {
            setPhase(action, .failed("还没连上服务器"))
            return
        }
        await retry(
            action, serverBase: base,
            execute: Self.liveExecutor(appState: appState)
        )
    }

    /// 身份对账单组重试（它不是 spawn 动作，取数口
    /// 与体检两组不同，单开一口）
    func retryIdentity(appState: AppState) async {
        guard let base = appState.config?.baseString else {
            identityPhase = .failed("还没连上服务器")
            return
        }
        await retryIdentity(
            serverBase: base,
            fetchIdentity: Self.liveIdentityFetcher(
                appState: appState
            )
        )
    }

    // MARK: - 状态机（测试可注入执行口）

    /// 两组版（H1-a 原口）：身份组不参与——它的留痕
    /// 在 saveSummary 里沿用上次，不被两组跑动冲掉
    func runAll(
        serverBase: String, execute: ActionExecutor
    ) async {
        await runAll(
            serverBase: serverBase, execute: execute,
            fetchIdentity: nil
        )
    }

    /// 全组版：三组依次跑（doctor → security-audit
    /// → 身份对账）；fetchIdentity 为 nil 时跳过身份
    /// 组（两组版口径）。身份组是同步读面、不占服务
    /// 端动作槽，排在最后不影响两段式的串行口径
    func runAll(
        serverBase: String, execute: ActionExecutor,
        fetchIdentity: IdentityFetcher?
    ) async {
        guard !isRunning else { return }
        await performGroup(.doctor, execute: execute)
        await performGroup(.securityAudit, execute: execute)
        if let fetchIdentity {
            await performIdentity(fetch: fetchIdentity)
        }
        saveSummary(serverBase: serverBase)
    }

    func retry(
        _ action: HealthAction, serverBase: String,
        execute: ActionExecutor
    ) async {
        guard !isRunning else { return }
        await performGroup(action, execute: execute)
        saveSummary(serverBase: serverBase)
    }

    func retryIdentity(
        serverBase: String, fetchIdentity: IdentityFetcher
    ) async {
        guard !isRunning else { return }
        await performIdentity(fetch: fetchIdentity)
        saveSummary(serverBase: serverBase)
    }

    private func performIdentity(fetch: IdentityFetcher) async {
        identityPhase = .running(since: Date())
        do {
            let input = try await fetch()
            identityRun = IdentityReconciler.reconcile(input)
            identityPhase = .finished
        } catch {
            identityPhase = .failed(Self.humanMessage(for: error))
        }
    }

    private func performGroup(
        _ action: HealthAction, execute: ActionExecutor
    ) async {
        setPhase(action, .running(since: Date()))
        do {
            let result = try await execute(action)
            switch action {
            case .doctor:
                doctorRun = DoctorLogParser.parse(
                    lines: result.lines, exitCode: result.exitCode
                )
            case .securityAudit:
                auditRun = SecurityAuditLogParser.parse(
                    lines: result.lines, exitCode: result.exitCode
                )
            }
            setPhase(action, .finished)
        } catch {
            setPhase(action, .failed(Self.humanMessage(for: error)))
        }
    }

    private func setPhase(_ action: HealthAction, _ phase: Phase) {
        switch action {
        case .doctor: doctorPhase = phase
        case .securityAudit: auditPhase = phase
        }
    }

    /// 留痕合成：本轮跑过的组用本轮结论，失败组记
    /// 「没跑完」，没跑的组沿用上次留痕（单组重试不
    /// 冲掉另一组的旧结论）
    private func saveSummary(serverBase: String) {
        let previous = summaryStore.summary(for: serverBase)
        let doctorSummary = groupSummary(
            for: .doctor, previous: previous?.doctor
        )
        let auditSummary = groupSummary(
            for: .securityAudit, previous: previous?.audit
        )
        let identitySummary = identityGroupSummary(
            previous: previous?.identity
        )
        guard doctorSummary != nil || auditSummary != nil
            || identitySummary != nil else { return }
        summaryStore.save(
            HealthCheckSummary(
                date: Date(), serverBase: serverBase,
                doctor: doctorSummary, audit: auditSummary,
                identity: identitySummary
            )
        )
    }

    /// 身份组留痕合成（与两组同式）：本轮跑完用本轮
    /// 结论，取数失败记「没跑完」，没跑沿用上次
    private func identityGroupSummary(
        previous: HealthGroupSummary?
    ) -> HealthGroupSummary? {
        switch identityPhase {
        case .finished:
            return identityRun?.groupSummary
        case .failed:
            return HealthGroupSummary(
                verdict: .incomplete, headline: "身份对账没跑完"
            )
        case .idle, .running:
            return previous
        }
    }

    private func groupSummary(
        for action: HealthAction,
        previous: HealthGroupSummary?
    ) -> HealthGroupSummary? {
        switch phase(for: action) {
        case .finished:
            switch action {
            case .doctor: return doctorRun?.groupSummary
            case .securityAudit: return auditRun?.groupSummary
            }
        case .failed:
            return HealthGroupSummary(
                verdict: .incomplete,
                headline: action == .doctor
                    ? "自检没跑完" : "安全审计没跑完"
            )
        case .idle, .running:
            return previous
        }
    }

    /// 失败人话化：不甩状态码与内部名（G-03 同族口径）
    static func humanMessage(for error: Error) -> String {
        if let engine = error as? HealthCheckEngineError {
            switch engine {
            case .timedOut:
                return "等太久了，这一轮没等到结果"
            }
        }
        if let hermes = error as? HermesError {
            switch hermes {
            case .sessionExpired, .loginRejected:
                return "登录已过期，重新连接后再试"
            case .unreachable, .transientNetwork, .notSentOffline:
                // notSentOffline（§414 增补分型）：保形
                // 同落——拆分前经 transientNetwork 归此句
                return "连不上服务器，检查网络后再试"
            case .demoLimitReached:
                return "演示模式下不能体检"
            default:
                return "这一项没跑成，稍后再试"
            }
        }
        return "这一项没跑成，稍后再试"
    }

    // MARK: - 生产执行口（spawn＋poll）

    /// 两段式执行走 OpsActionRunner（H1-b 起与存档段
    /// 共用同一套 spawn＋poll，不另造）：体检两组只在
    /// 「按动作名选触发端点」这一处分工。
    static func liveExecutor(
        appState: AppState
    ) -> ActionExecutor {
        { action in
            let outcome = try await OpsActionRunner.run(
                appState: appState, actionName: action.name,
                timeout: action == .doctor ? 120 : 60
            ) { client, config in
                switch action {
                case .doctor:
                    return try await client.opsDoctor(config: config)
                case .securityAudit:
                    return try await client.opsSecurityAudit(
                        config: config
                    )
                }
            }
            return ActionResult(
                lines: outcome.lines, exitCode: outcome.exitCode
            )
        }
    }

    // MARK: - 身份对账生产取数口（H1-d）

    /// 装配对账输入快照：三个服务端来源各自独立取，
    /// 任一取不到只把那一份记 nil（组内对应项降级
    /// 「暂无法对账」），不整组失败——目录拉不到时网
    /// 关那项照样能判，反之亦然。判定在 Core 的
    /// IdentityReconciler，本口只负责取数与投影。
    static func liveIdentityFetcher(
        appState: AppState
    ) -> IdentityFetcher {
        {
            let ledger = appState.sessionLedger

            // 目录：现拉全量（含归档段）＋完整性口径
            // 原样带出；本地投影条数只作漂移提示
            var catalog: IdentityReconciliationInput
                .CatalogSnapshot?
            var localProjectionCount: Int?
            if let snapshot = try? await ledger
                .identityCatalogSnapshot(appState: appState) {
                catalog = .init(
                    rows: snapshot.sessions.map { session in
                        .init(
                            id: session.id,
                            title: session.serverTitle,
                            isArchived: session.isArchived ?? false,
                            messageCount: session.messageCount
                        )
                    },
                    incompleteNote: snapshot.incompleteReason?
                        .traceLabel
                )
                localProjectionCount =
                    ledger.localCatalogProjectionCount
            }

            // 网关：/api/status 的网关段（免登录面）
            let status = try? await appState.performAdmin {
                client, config in
                try await client.status(config: config)
            }
            let gateway = status.map { status in
                IdentityReconciliationInput.GatewaySnapshot(
                    running: status.gatewayRunning,
                    state: status.gatewayState,
                    apiServerState: status
                        .platforms["api_server"]?.state,
                    version: status.version
                )
            }

            // 当前档案：认 current（本进程实际所辖），
            // 缺失回落 active；只呈现、不判定
            let profile = try? await appState.performAdmin {
                client, config in
                try await client.activeProfile(config: config)
            }

            return IdentityReconciliationInput(
                boundMainSessionID: ledger.mainServerSessionID,
                expectedMainTitle: SideChatStore.mainTitle,
                catalog: catalog,
                localProjectionCount: localProjectionCount,
                gateway: gateway,
                currentProfile: profile?.current
                    ?? profile?.active
            )
        }
    }
}

/// ops 动作 spawn＋poll 通用执行口（H1-a 体检两组与
/// H1-b 备份共用，口径据 H1-0 探活冻结）：
/// 1. 先读一次状态：同名动作已在跑（可能来自其他
///    客户端）就直接收养那一轮，不重复触发——服务
///    端按名只有一个跟踪槽，后触发会覆盖先触发；
/// 2. 触发前记下最后一个 started 标记的整行文本
///    作基线身份，轮询只认「最后一个标记 ≠ 基线」
///    的新轮，旧轮的「已跑完」状态不许误收（日志
///    多方共享）。不数序号：状态端点只回文件尾的
///    滑动窗口，本轮输出会把旧标记挤出窗口、序号
///    永远凑不齐（2026-11-20 真机定因）；
/// 3. 2.5 秒一轮询；总超时按动作传（缺省 60 秒；
///    doctor 修复后常态约 46 秒，单独放宽到 120
///    秒）；超时抛 timedOut，界面落「没等到结果」
///    ＋重试，不无限转圈。
enum OpsActionRunner {
    struct Outcome: Sendable {
        var lines: [String]
        var exitCode: Int?
        /// 本轮由我们触发时 spawn 回执带回的值（backup
        /// 的 archive 产物路径）；收养他人在飞轮时为 nil
        var spawnArchive: String?
    }

    static func run(
        appState: AppState, actionName: String,
        timeout: TimeInterval = 60,
        spawn: @MainActor (
            HermesClientProtocol, ServerConfig
        ) async throws -> OpsSpawnResponse
    ) async throws -> Outcome {
        let pre = try await appState.performAdmin { client, config in
            try await client.opsActionStatus(
                config: config, name: actionName, lines: 2000
            )
        }
        // 基线身份＝触发前最后一个标记的整行文本；
        // 收养在飞轮时该轮标记已在日志里，基线退到
        // 它前一个标记（没有前一个就 nil），认轮时
        // 在飞标记即被认作本轮
        let markerTotal = OpsActionLog.markerCount(
            lines: pre.lines, actionName: actionName
        )
        let baselineIndex = pre.running
            ? markerTotal - 2 : markerTotal - 1
        let baselineMarkerLine = baselineIndex >= 0
            ? OpsActionLog.markerLine(
                lines: pre.lines, actionName: actionName,
                at: baselineIndex
            )
            : nil
        var spawnArchive: String?
        if !pre.running {
            let receipt = try await appState.performAdmin {
                client, config in
                try await spawn(client, config)
            }
            spawnArchive = receipt.archive
        }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let status = try await appState.performAdmin {
                client, config in
                try await client.opsActionStatus(
                    config: config, name: actionName, lines: 2000
                )
            }
            if !status.running,
               let sliced = OpsActionLog.sliceForNewRound(
                   lines: status.lines, actionName: actionName,
                   baselineMarkerLine: baselineMarkerLine
               ) {
                return Outcome(
                    lines: sliced, exitCode: status.exitCode,
                    spawnArchive: spawnArchive
                )
            }
            if Date() > deadline {
                throw HealthCheckEngineError.timedOut
            }
            try await Task.sleep(for: .seconds(2.5))
        }
    }
}
