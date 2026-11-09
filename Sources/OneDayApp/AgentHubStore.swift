import Foundation
import OneDayCore

/// 三期枢纽页数据中枢：按段懒加载、失败隔离（数据设计
/// 全局原则 3）——一段失败不清空其他段已取得的数据。
/// 打开时冻结 profile（原则 4）：首次请求前捕获档案名，
/// 加载完成后复查，变了就整页快照作废重拉，不把两次
/// 上下文的数据混在一页。
@MainActor
@Observable
final class AgentHubStore {
    private let appState: AppState
    private let gateClient: WriteGateClientProtocol

    init(appState: AppState, gateClient: WriteGateClientProtocol) {
        self.appState = appState
        self.gateClient = gateClient
    }

    // MARK: - 页头

    /// 打开时冻结的 profile 名（请求键与页头名同源）
    private(set) var frozenProfileName: String?
    private(set) var headerLoaded = false
    private var serverStatus: ServerStatus?
    private(set) var sessions: [ServerSession] = []
    private(set) var sessionsFailed = false

    /// 页头大名：档案人话名；无名时回落 Hermes（数据
    /// 设计 §1.1：不用空字符串冒充已加载）
    var displayName: String {
        guard let frozenProfileName else { return "Hermes" }
        return ServerLabels.profileName(frozenProfileName)
    }

    /// 活跃会话数：由会话列表 endedAt == nil 派生，不猜
    /// /api/status 的未建模字段（数据设计 §1.1）
    var activeSessionCount: Int {
        sessions.filter { $0.endedAt == nil }.count
    }

    /// 状态行（规格 §2 降级口径＋数据设计失败口径）：
    /// 网关运行 →「在线（· N 个会话进行中）」；状态拉取
    /// 失败显示「状态未确认」，不给离线假结论
    var statusText: String {
        guard let serverStatus else { return "状态未确认" }
        let word = ServerLabels.gatewayState(
            serverStatus.gatewayState, running: serverStatus.gatewayRunning
        )
        if word == "运行中" {
            return activeSessionCount > 0
                ? "在线 · \(activeSessionCount) 个会话进行中"
                : "在线"
        }
        return "网关\(word)"
    }

    var isOnline: Bool {
        guard let serverStatus else { return false }
        return ServerLabels.gatewayState(
            serverStatus.gatewayState, running: serverStatus.gatewayRunning
        ) == "运行中"
    }

    /// 分享摘要（页头分享圆钮）：名＋状态＋当前模型
    var shareText: String {
        "\(displayName) · \(statusText) · 当前模型 "
            + ChatModels.displayName(for: appState.chatModel)
    }

    // MARK: - 活动段

    private(set) var activityGroups: [HubActivityDayGroup]?
    private(set) var activityLoading = false

    // MARK: - 定时段

    private(set) var cronGroups: [(kind: HubCronKind, items: [HubCronItem])]?
    private(set) var cronFailed = false
    private(set) var cronLoading = false

    /// jobs 与 runs 跨段共享缓存（活动段与定时段同源，
    /// 不重复请求，数据设计 §3.1/§4.1）
    private var jobsCache: [CronJob]?
    private var runsCache: [String: [ServerSession]] = [:]

    // MARK: - 身份段

    private(set) var soulDocument: ProfileSoulDocument?
    private(set) var soulSections: SoulSections?
    private(set) var identityFailed = false
    private(set) var identityLoading = false
    private(set) var memoryStatus: MemoryStatus?

    // MARK: - 审核段

    private(set) var approvalState: ApprovalSectionState = .loading
    /// 正在裁决的卡 id（只禁用当前卡，数据设计 §5.4）
    private(set) var decidingIDs: Set<String> = []
    /// 卡内行内提示（409 变化提示/裁决失败人话）
    private(set) var cardNotes: [String: String] = [:]

    // MARK: - 浏览器段

    private(set) var browserState: BrowserHubState = .loading

    // MARK: - 初始加载（页头＋活动段）

    private var didLoadInitial = false
    private var didRecheckProfile = false

    func loadInitial() async {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        activityLoading = true

        // 冻结 profile：首次请求前捕获
        if frozenProfileName == nil {
            frozenProfileName = try? await appState.performAdmin { client, config in
                try await client.activeProfileName(config: config)
            } ?? nil
        }
        serverStatus = try? await appState.performAdmin { client, config in
            try await client.status(config: config)
        }
        do {
            let page = try await appState.performAdmin { client, config in
                try await client.serverSessions(config: config, limit: 100)
            }
            sessions = page.sessions
            sessionsFailed = false
        } catch {
            sessionsFailed = true
        }
        headerLoaded = true
        await assembleActivity()
        activityLoading = false
        await recheckProfileOnce()
    }

    /// profile 一致性复查（数据设计原则 4）：加载完成后
    /// active 已变 → 整页快照作废重拉一次
    private func recheckProfileOnce() async {
        guard !didRecheckProfile, let frozen = frozenProfileName else { return }
        didRecheckProfile = true
        let current = try? await appState.performAdmin { client, config in
            try await client.activeProfileName(config: config)
        } ?? nil
        guard let current, current != frozen else { return }
        frozenProfileName = current
        sessions = []
        jobsCache = nil
        runsCache = [:]
        activityGroups = nil
        cronGroups = nil
        soulDocument = nil
        soulSections = nil
        didLoadInitial = false
        await loadInitial()
    }

    private func loadJobs() async -> [CronJob] {
        if let jobsCache { return jobsCache }
        let jobs = (try? await appState.performAdmin { client, config in
            try await client.cronJobs(config: config)
        }) ?? []
        jobsCache = jobs
        return jobs
    }

    /// runs 补拉：最多前 20 个 job、并发上限 4（数据设计
    /// §4.1 预算）。走 performAdmin 后的新鲜 cookie 通道：
    /// 此方法在 sessions 拉取（已含 401 重登）之后调用，
    /// 这里直连 client 以便任务组并发，结果只作补充、
    /// 失败可降级
    private func loadRuns(for jobs: [CronJob]) async {
        guard let config = appState.config else { return }
        let client = appState.client
        let targets = jobs.prefix(20).filter { runsCache[$0.id] == nil }
        var index = 0
        while index < targets.count {
            let chunk = Array(targets[index..<min(index + 4, targets.count)])
            let fetched = await withTaskGroup(
                of: (String, [ServerSession]).self
            ) { group in
                for job in chunk {
                    group.addTask {
                        let runs = (try? await client.cronRuns(
                            config: config, id: job.id, limit: 3
                        )) ?? []
                        return (job.id, runs)
                    }
                }
                var collected: [String: [ServerSession]] = [:]
                for await (id, runs) in group {
                    collected[id] = runs
                }
                return collected
            }
            for (id, runs) in fetched {
                runsCache[id] = runs
            }
            index += 4
        }
    }

    private func assembleActivity() async {
        // sessions 是主实体：它失败整段失败，日志再完整
        // 也不能单独拼活动流（数据设计 §4.5）
        guard !sessionsFailed else {
            activityGroups = nil
            return
        }
        let jobs = await loadJobs()
        await loadRuns(for: jobs)
        let logLines = (try? await appState.performAdmin { client, config in
            try await client.logs(config: config, level: nil, search: nil, lines: 200)
        })?.lines ?? []
        let logs = logLines.map { LogEventParser.parse($0) }
        var jobTitles: [String: String] = [:]
        for job in jobs { jobTitles[job.id] = job.title }
        activityGroups = HubActivityAssembler.assemble(
            sessions: sessions,
            runsByJobID: runsCache,
            jobTitles: jobTitles,
            logs: logs,
            fetchedAt: Date(),
            now: Date()
        )
    }

    /// 活动段重试（sessions 失败后的唯一恢复路径）
    func reloadActivity() async {
        didLoadInitial = false
        await loadInitial()
    }

    // MARK: - 定时段（懒加载）

    func loadCronIfNeeded() async {
        guard cronGroups == nil, !cronLoading else { return }
        cronLoading = true
        cronFailed = false
        // jobs 拉取失败与「真无任务」要分开：loadJobs 的
        // 兜底空数组会把失败吞掉，这里直接请求判成败
        if jobsCache == nil {
            do {
                jobsCache = try await appState.performAdmin { client, config in
                    try await client.cronJobs(config: config)
                }
            } catch {
                cronFailed = true
                cronLoading = false
                return
            }
        }
        let jobs = jobsCache ?? []
        // 间隔行上次运行补拉：优先用共享 runsCache，缺的
        // 再单拉 limit 1（数据设计 §3.5，不为每个 job 拉）
        var lastRuns: [String: Date] = [:]
        for job in jobs {
            let item = CronHubClassifier.classify(job)
            if let cached = runsCache[job.id] {
                if let latest = cached.compactMap(\.startedDate).max() {
                    lastRuns[job.id] = latest
                }
            }
            guard item.kind == .interval,
                  item.lastRunAt == nil,
                  lastRuns[job.id] == nil else { continue }
            if let runs = try? await appState.performAdmin({ client, config in
                try await client.cronRuns(config: config, id: job.id, limit: 1)
            }), let latest = runs.compactMap(\.startedDate).max() {
                lastRuns[job.id] = latest
            }
        }
        cronGroups = CronHubClassifier.grouped(jobs, lastRuns: lastRuns)
        cronLoading = false
    }

    // MARK: - 身份段（懒加载）

    func loadIdentityIfNeeded() async {
        guard soulDocument == nil, !identityLoading else { return }
        identityLoading = true
        identityFailed = false
        if frozenProfileName == nil {
            frozenProfileName = try? await appState.performAdmin { client, config in
                try await client.activeProfileName(config: config)
            } ?? nil
        }
        guard let name = frozenProfileName else {
            identityFailed = true
            identityLoading = false
            return
        }
        do {
            let document = try await appState.performAdmin { client, config in
                try await client.profileSoul(config: config, name: name)
            }
            // 返回后复查捕获名：profile 已切换则丢弃结果
            // （数据设计 §2.7），下次进段以新名重拉
            if let docProfile = document.profileName,
               docProfile != name {
                identityLoading = false
                return
            }
            soulDocument = document
            soulSections = SoulSectionParser.parse(document.content)
        } catch {
            identityFailed = true
        }
        memoryStatus = try? await appState.performAdmin { client, config in
            try await client.memoryStatus(config: config)
        }
        identityLoading = false
    }

    // MARK: - 审核段（懒加载＋裁决）

    func loadApproval(force: Bool = false) async {
        if case .loading = approvalState, !force {
            // 首次进入即处于 loading，直接走加载
        } else if !force, approvalState != .loading {
            return
        }
        approvalState = .loading
        guard let config = appState.config else {
            approvalState = .bridgeUnavailable
            return
        }
        let status: WriteGateStatus
        do {
            status = try await gateClient.gateStatus(config: config)
        } catch let error as WriteGateError {
            approvalState = mapGateError(error)
            return
        } catch {
            approvalState = .failed("审批状态读取失败")
            return
        }
        guard status.supported else {
            approvalState = .bridgeUnavailable
            return
        }
        guard status.anyGateEnabled else {
            approvalState = .gateDisabled
            return
        }
        do {
            let list = try await gateClient.pendingList(config: config)
            approvalState = .ready(list.records)
        } catch let error as WriteGateError {
            approvalState = mapGateError(error)
        } catch {
            approvalState = .failed("待批列表读取失败")
        }
    }

    /// 桥错误 → 段状态：桥不存在/无钥/钥匙不对统一落
    /// 「通道未接通」；冲突落桥异常同态；其余人话失败
    private func mapGateError(_ error: WriteGateError) -> ApprovalSectionState {
        switch error {
        case .noKey, .bridgeMissing, .unauthorized, .conflict:
            return .bridgeUnavailable
        case .recordGone:
            return .bridgeUnavailable
        case .failed(let message):
            return .failed(message)
        }
    }

    /// diff 详情（点开卡片时按需拉，列表不带大正文）
    func loadDetail(
        _ record: WriteGateRecord
    ) async -> Result<WriteGateDetail, WriteGateError> {
        guard let config = appState.config else {
            return .failure(.noKey)
        }
        do {
            return .success(
                try await gateClient.detail(
                    config: config, subsystem: record.subsystem, id: record.id
                )
            )
        } catch let error as WriteGateError {
            return .failure(error)
        } catch {
            return .failure(.failed("改动读取失败"))
        }
    }

    /// 裁决（数据设计 §5.4 动作规则）：不做乐观移除——
    /// 服务端确认终态后才移卡；404 视为已被处理（移卡＋
    /// 提示）；409 保留卡片＋行内提示并刷新列表；网络
    /// 错误保留卡片与提示，不弹模态
    func decide(_ record: WriteGateRecord, approve: Bool) async {
        guard record.canDecide, let config = appState.config else { return }
        guard !decidingIDs.contains(record.id) else { return }
        decidingIDs.insert(record.id)
        cardNotes.removeValue(forKey: record.id)
        do {
            let response = approve
                ? try await gateClient.approve(
                    config: config, subsystem: record.subsystem, id: record.id
                )
                : try await gateClient.reject(
                    config: config, subsystem: record.subsystem, id: record.id
                )
            if response.success {
                removeRecord(record.id)
            } else {
                cardNotes[record.id] = "裁决未生效，请重新打开改动核对后再试。"
            }
        } catch let error as WriteGateError {
            switch error {
            case .recordGone:
                removeRecord(record.id)
            case .conflict:
                cardNotes[record.id] = "这条写入的内容已变化，已按最新状态刷新，请重新核对。"
                decidingIDs.remove(record.id)
                await loadApproval(force: true)
                return
            case .failed(let message):
                cardNotes[record.id] = message
            case .noKey, .bridgeMissing, .unauthorized:
                cardNotes[record.id] = "审批通道未接通，裁决没有发出。"
            }
        } catch {
            cardNotes[record.id] = "裁决发送失败，记录仍在待批中。"
        }
        decidingIDs.remove(record.id)
    }

    private func removeRecord(_ id: String) {
        if case .ready(var records) = approvalState {
            records.removeAll { $0.id == id }
            approvalState = .ready(records)
        }
    }

    // MARK: - 浏览器段（懒加载）

    private var browserLoaded = false

    func loadBrowserIfNeeded() async {
        guard !browserLoaded else { return }
        browserLoaded = true
        do {
            let status = try await appState.performAdmin { client, config in
                try await client.computerUseStatus(config: config)
            }
            browserState = .statusOnly(status, checkedAt: Date())
        } catch {
            browserState = .failed("浏览器工具状态读取失败")
        }
    }

    func reloadBrowser() async {
        browserLoaded = false
        browserState = .loading
        await loadBrowserIfNeeded()
    }
}
