import Foundation
import OneDayCore

/// 三期枢纽页数据中枢：按段懒加载、失败隔离（数据设计
/// 全局原则 3）——一段失败不清空其他段已取得的数据。
/// 打开时冻结 profile（原则 4）：首次请求前捕获档案名，
/// 加载完成后复查，变了就整页快照作废重拉，不把两次
/// 上下文的数据混在一页。
/// 就地审批卡的裁决结果行（0.36.21）：卡被裁决（或
/// 被规则放行）后原地收成的一行——标题（裁决当时的人
/// 话头条）＋结果措辞；上限 20 条，超出弃最旧（呈现
/// 层痕迹，权威账本是桥 /decisions）
struct ApprovalResolvedLine: Identifiable, Equatable {
    enum Outcome: Equatable {
        case approved
        case rejected
        /// 经「总是允许」裁掉（规则已建成并落账）
        case approvedAlways
        /// 被既有规则自动放行（桥账本 via_rule）
        case ruleApproved

        var label: String {
            switch self {
            case .approved: return "已批准"
            case .rejected: return "已驳回"
            case .approvedAlways: return "已批准 · 已记住这一类"
            case .ruleApproved: return "已按规则放行"
            }
        }

        var isPositive: Bool { self != .rejected }
    }

    let id: String
    let summary: String
    let outcome: Outcome
    let at: Date
}

@MainActor
@Observable
final class AgentHubStore {
    private let appState: AppState
    private let gateClient: WriteGateClientProtocol
    /// 审批终态回调（0.6.0）：活动格据此刷新总览桥角标，
    /// 不等下一轮 30 秒轮询。0.36.21 起 store 由
    /// AppState 共享持有，回调改由呈现枢纽的 AgentHub-
    /// View 在注入时赋值（全 App 只有 ChatView 一处呈
    /// 现枢纽，见 AppState.sharedHubStore）
    var onApprovalChanged: (() -> Void)?

    init(
        appState: AppState, gateClient: WriteGateClientProtocol,
        onApprovalChanged: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.gateClient = gateClient
        self.onApprovalChanged = onApprovalChanged
    }

    // MARK: - 页头

    /// 打开时冻结的 profile 名（请求键与页头名同源）
    private(set) var frozenProfileName: String?
    private(set) var headerLoaded = false
    private var serverStatus: ServerStatus?
    private(set) var sessions: [ServerSession] = []
    private(set) var sessionsFailed = false

    /// 身份名（0.6.1，用户真机点名）：soul 里取得到的
    /// 身份名（初始加载时顺带拉一次 soul 解析，见
    /// loadInitial）；旧口径拿档案名翻译（default→
    /// 「默认档案」）当大标题是实体错位——档案是配置
    /// 实体、不是智能体身份，「默认档案」退出标题位
    private(set) var identityName: String?

    /// 页头大名：全局身份名（AppState，全局唯一解析
    /// 点）→ 本店 soul 解析 → 回落 Hermes；与抽屉/
    /// 胶囊同源同值（OneDayCore.AgentName）
    var displayName: String {
        appState.identityName ?? identityName ?? AgentName.fallback
    }

    /// 状态行（0.6.1 改口径，用户真机点名）：只报可证
    /// 事实——在线／在线 · N 条待审批（审核段已加载且
    /// 非空时）／网关既报状态；旧「在线 · N 个会话进
    /// 行中」退役：Hermes 不写 ended_at、endedAt 为空
    /// 的计数实为会话总数、是假进行中。状态未拉到时
    /// 显示「状态未确认」，不给离线假结论（失败口径
    /// 沿数据设计）
    var statusText: String {
        guard let serverStatus else { return "状态未确认" }
        let word = ServerLabels.gatewayState(
            serverStatus.gatewayState, running: serverStatus.gatewayRunning
        )
        if word == "运行中" {
            if case .ready(let records) = approvalState, !records.isEmpty {
                return "在线 · \(records.count) 条待审批"
            }
            return "在线"
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
    /// 已决历史（P10）：与待批同轮 best-effort 拉取——
    /// 拉不到保持上次值（首拉为空），不拖累待批呈现
    private(set) var decisionHistory: [WriteGateDecisionRecord] = []
    /// 「总是允许」规则（0.36.21）：桥侧规则的只读镜
    /// 像——规则只存桥、App 不落本地；拉取 best-effort，
    /// 失败保持旧值（rulesLoaded 区分「拉过且为空」与
    /// 「还没拉到」，枢纽规则区据此诚实呈现）
    private(set) var approvalRules: [WriteGateRule] = []
    private(set) var rulesLoaded = false
    /// 规则面行内提示（撤销失败等人话）
    private(set) var rulesNote: String?
    /// 正在撤销的规则 id（只禁用当前行）
    private(set) var revokingRuleIDs: Set<String> = []
    /// 就地卡裁决结果行（0.36.21）：本进程内已收口的
    /// 卡——裁决后原地收成一行，不凭空消失（规格 §1）；
    /// 权威账本仍是桥 /decisions，这里只是呈现层痕迹
    private(set) var resolvedLines: [ApprovalResolvedLine] = []
    /// 经「总是允许」路径批准中的记录 id（裁决落定后
    /// 据此把结果行标成 approvedAlways，decide 成功分
    /// 支消费后即除名）
    private var alwaysApproveMarks: Set<String> = []

    // 浏览器段已于 0.9.0 迁出本 Store：状态改读盒桥，
    // 由 BrowserFaceView 自持 BoxBridgeStore（见
    // HubBrowserSection），本 Store 不再留错位源状态。

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
        // 身份名顺带解析（0.6.1）：复用身份段的 soul 拉
        // 取（同一份数据、段内已加载不重拉），只为页头
        // 大名取身份名；取不到/失败回落 Hermes，不阻塞
        // 活动流
        await loadIdentityIfNeeded()
        if let content = soulDocument?.content {
            identityName = AgentName.resolve(soulContent: content)
        }
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
        // 派生标题素材（0.6.1）：列表接口无标题字段，
        // 先经全局解析器按预算补齐首条消息再拼装，与
        // 抽屉行共用同一缓存/派生
        await appState.sessionTitles.ensureTitles(
            for: sessions, appState: appState, budget: 10
        )
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
            now: Date(),
            firstUserMessages: appState.sessionTitles.firstUserMessages
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
        let previousPending = currentPendingRecords()
        do {
            let list = try await gateClient.pendingList(config: config)
            approvalState = .ready(list.records)
        } catch let error as WriteGateError {
            approvalState = mapGateError(error)
            return
        } catch {
            approvalState = .failed("待批列表读取失败")
            return
        }
        await refreshDecisionHistory()
        // 结果行对账（0.36.21）：上一轮还在待批、本轮
        // 已消失且已决账本里查得到的记录，补一行结果
        // ——覆盖「卡已显示、又被规则自动放行」的生命
        // 周期，卡不许无声蒸发
        reconcileResolvedLines(
            previous: previousPending, current: currentPendingRecords()
        )
        await loadRules()
    }

    /// 已决历史刷新（P10）：桥 /decisions 现成面；失败
    /// 静默保持旧值——历史缺失不许把待批段打成失败态
    private func refreshDecisionHistory() async {
        guard let config = appState.config else { return }
        if let history = try? await gateClient.decisions(
            config: config, limit: 50
        ) {
            decisionHistory = history
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
                // 0.36.5（联动 C 部）：记本人裁决——
                // 本条的回执通知生成后由总览桥状态层
                // 按 id 自动消账，不再回头占角标
                appState.noteSelfDecision(recordID: record.id)
                // 触感矩阵（0.36.2，规格 §2.3）：审批
                // 落定才响——批准＝success、驳回＝
                // warning（需注意类决定、未失败）；
                // 未生效/异常分支不响
                if approve {
                    Haptics.success()
                } else {
                    Haptics.warning()
                }
                // 决刚落账，此时刷新已决历史最准（P10）
                await refreshDecisionHistory()
                // 结果行（0.36.21）：卡原地收成一行，
                // 不凭空消失；经「总是允许」路径的标明
                // 规则已记住
                appendResolvedLine(
                    id: record.id, summary: record.headline,
                    outcome: alwaysApproveMarks.contains(record.id)
                        ? .approvedAlways
                        : (approve ? .approved : .rejected)
                )
                alwaysApproveMarks.remove(record.id)
            } else {
                cardNotes[record.id] = "裁决未生效，请重新打开改动核对后再试。"
            }
        } catch let error as WriteGateError {
            switch error {
            case .recordGone:
                removeRecord(record.id)
                await refreshDecisionHistory()
                if let entry = decisionHistory.first(
                    where: { $0.id == record.id }
                ) {
                    appendResolvedLine(
                        id: entry.id, summary: entry.headline,
                        outcome: entry.isRuleApproved
                            ? .ruleApproved
                            : (entry.isApproved ? .approved : .rejected)
                    )
                }
                alwaysApproveMarks.remove(record.id)
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
        onApprovalChanged?()
    }

    // MARK: - 「总是允许」与规则（0.36.21，规格 §4）

    /// 第三档裁决：先建规则、后批准（顺序是失败语义的
    /// 关键）。规则没建成——不批准、不移除，卡面留痕
    /// 说明「没能记住」，记录仍在待批中，绝不假装已记
    /// 住；规则建成—再走既有 approve 路径，结果行标
    /// 「已批准 · 已记住这一类」。规则由桥落（App 不
    /// 本地存），此后同（子系统，来源）的写入由桥自
    /// 动放行并以 via_rule 留痕
    func decideAlways(_ record: WriteGateRecord) async {
        guard record.canDecide, let config = appState.config else { return }
        guard !decidingIDs.contains(record.id) else { return }
        decidingIDs.insert(record.id)
        cardNotes.removeValue(forKey: record.id)
        do {
            _ = try await gateClient.createRule(
                config: config, subsystem: record.subsystem,
                origin: record.origin
            )
        } catch {
            cardNotes[record.id] =
                "「总是允许」没能记住（规则建立失败），这条仍在待批中。"
            decidingIDs.remove(record.id)
            return
        }
        await loadRules()
        alwaysApproveMarks.insert(record.id)
        decidingIDs.remove(record.id)
        await decide(record, approve: true)
    }

    /// 规则列表刷新：best-effort，失败保持旧值（与已
    /// 决历史同口径），rulesLoaded 只在成功后置真
    func loadRules() async {
        guard let config = appState.config else { return }
        if let rules = try? await gateClient.rules(config: config) {
            approvalRules = rules
            rulesLoaded = true
        }
    }

    /// 撤销一条规则（枢纽规则管理区）：成功即从镜像
    /// 移除；失败保留并留人话提示，随后按桥真值重拉
    /// 对账（404「已不存在」时重拉会自然消失）
    func revokeRule(_ rule: WriteGateRule) async {
        guard let config = appState.config else { return }
        guard !revokingRuleIDs.contains(rule.id) else { return }
        revokingRuleIDs.insert(rule.id)
        rulesNote = nil
        do {
            try await gateClient.deleteRule(config: config, id: rule.id)
            approvalRules.removeAll { $0.id == rule.id }
        } catch let error as WriteGateError {
            if case .failed(let message) = error {
                rulesNote = message
            } else {
                rulesNote = "撤销没能生效，请稍后重试。"
            }
            await loadRules()
        } catch {
            rulesNote = "撤销没能生效，请稍后重试。"
        }
        revokingRuleIDs.remove(rule.id)
    }

    // MARK: - 聊天侧刷新与结果行对账（0.36.21）

    /// 聊天侧静默刷新（就地卡的触发点调用）：已在
    /// ready 态时不打回 loading（卡面不闪），整段 best-
    /// effort——失败保留现态，聊天里不闹；从未成功加
    /// 载过则走完整 loadApproval 把状态立起来（状态异
    /// 常由枢纽如实呈现，就地卡仅 ready 时渲染）
    func refreshApprovalForChat() async {
        guard case .ready = approvalState else {
            await loadApproval(force: true)
            return
        }
        guard let config = appState.config,
              let status = try? await gateClient.gateStatus(config: config),
              status.supported, status.anyGateEnabled,
              let list = try? await gateClient.pendingList(config: config)
        else { return }
        let previous = currentPendingRecords()
        await refreshDecisionHistory()
        approvalState = .ready(list.records)
        reconcileResolvedLines(previous: previous, current: list.records)
        await loadRules()
    }

    private func currentPendingRecords() -> [WriteGateRecord] {
        if case .ready(let records) = approvalState { return records }
        return []
    }

    /// 结果行对账：上一轮待批、本轮消失、且已决账本
    /// 里有据的记录补一行（via_rule→已按规则放行）
    private func reconcileResolvedLines(
        previous: [WriteGateRecord], current: [WriteGateRecord]
    ) {
        guard !previous.isEmpty else { return }
        let currentIDs = Set(current.map(\.id))
        for record in previous where !currentIDs.contains(record.id) {
            guard let entry = decisionHistory.first(
                where: { $0.id == record.id }
            ) else { continue }
            appendResolvedLine(
                id: entry.id, summary: entry.headline,
                outcome: entry.isRuleApproved
                    ? .ruleApproved
                    : (entry.isApproved ? .approved : .rejected)
            )
        }
    }

    private func appendResolvedLine(
        id: String, summary: String,
        outcome: ApprovalResolvedLine.Outcome
    ) {
        guard !resolvedLines.contains(where: { $0.id == id }) else { return }
        resolvedLines.append(
            ApprovalResolvedLine(
                id: id, summary: summary, outcome: outcome, at: Date()
            )
        )
        if resolvedLines.count > 20 {
            resolvedLines.removeFirst(resolvedLines.count - 20)
        }
    }

}
