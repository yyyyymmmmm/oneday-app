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
            case .approved: return L10n.string("已批准")
            case .rejected: return L10n.string("已驳回")
            case .approvedAlways: return L10n.string("已批准 · 已记住这一类")
            case .ruleApproved: return L10n.string("已按规则放行")
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
    /// 网关状态快照：页头状态行自用＋状态页身份头共
    /// 享读（台账 198 收敛 C4——同一份状态只此一处取
    /// 数，状态页不再自拉一份）；写口仍只在本店
    private(set) var serverStatus: ServerStatus?

    /// 身份名（0.6.1，用户真机点名）：soul 里取得到的
    /// 身份名（初始加载时顺带拉一次 soul 解析，见
    /// loadInitial）；旧口径拿档案名翻译（default→
    /// 「默认档案」）当大标题是实体错位——档案是配置
    /// 实体、不是智能体身份，「默认档案」退出标题位
    private(set) var identityName: String?

    /// 页头大名：全局身份名（AppState 名字缓存，服
    /// 务端单真值的本机副本，§253）→ 本店 soul 解析
    /// → 回落 Hermes；与抽屉/胶囊同源同值。旧本机
    /// 档案覆盖层（0.36.22）已随 C-2 收敛退役
    var displayName: String {
        appState.identityName
            ?? identityName
            ?? AgentName.fallback
    }

    /// 状态行（0.6.1 改口径，用户真机点名）：只报可证
    /// 事实——N 条待审批（审核段已加载且非空时）／网
    /// 关既报状态；旧「在线 · N 个会话进行中」退役：
    /// Hermes 不写 ended_at、endedAt 为空的计数实为
    /// 会话总数、是假进行中。状态未拉到时显示「状态
    /// 未确认」，不给离线假结论（失败口径沿数据设计）
    /// §474（2026-11-24 用户亲令）：「在线」字样全
    /// 删——本行是活动行（工作状态／台账活动优先，
    /// 见 AgentHubView.statusLine），连接在否不占本
    /// 行；运行中且无待审批时返回空串＝不呈现回落行
    var statusText: String {
        guard let serverStatus else { return L10n.string("状态未确认") }
        let word = ServerLabels.gatewayState(
            serverStatus.gatewayState, running: serverStatus.gatewayRunning
        )
        // 比较与 gatewayState 的返回值同源取词（同一
        // uiLocale 解析），语言切换后仍恒等（0.42.1）
        if word == L10n.string("运行中") {
            if case .ready(let records) = approvalState, !records.isEmpty {
                return L10n.format(
                    "%lld 条待审批", records.count
                )
            }
            return ""
        }
        return L10n.format("网关%@", word)
    }

    var isOnline: Bool {
        guard let serverStatus else { return false }
        return ServerLabels.gatewayState(
            serverStatus.gatewayState, running: serverStatus.gatewayRunning
        ) == L10n.string("运行中")
    }

    // 注：旧 shareText（分享摘要，含当前模型）已随
    // §227 删除——分享面 0.36.22 起换名片图、该属性无
    // 调用方，且它是第三个按 SideChatStore 副本独立
    // 取键读模型账的点，留着有朝一日被误接即复活账
    // 本分叉（见 DESIGN §227 第 4 条）

    // 活动段拼装与定时段取数已退役（台账 198 收敛
    // C1＋普查 R4/D2）：旧「活动」拼装流（sessions＋
    // logs＋cronRuns 汇编 HubActivity）全仓零消费者、
    // 每次开枢纽白拉三路，已整段删除（Core 汇编器同
    // 删）；定时数据归共享 CronStore 单源，本店不再
    // 私拉一份。工作台账由 LedgerStore 自持、与此无关

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

    /// 「总是允许」一次点按后的轻量撤销通知（5 秒自动收起）
    struct AlwaysAllowToast: Identifiable, Equatable {
        let id = UUID()
        let rule: WriteGateRule
        let scopeLabel: String
    }
    private(set) var alwaysAllowToast: AlwaysAllowToast?
    private var alwaysAllowToastTask: Task<Void, Never>?

    /// 是否存在未决待审批记录（聊天页拦截发送用）
    var hasPendingApprovals: Bool {
        if case .ready(let records) = approvalState {
            return !records.isEmpty
        }
        return false
    }

    // MARK: - 授权账本（§434 审核格；能力 #12 活证）

    /// grants 回读状态：ready 即端点在位且清单读回
    /// ——分格注册表（HubSegmentRegistry）据此决定
    /// 审核格长不长（与审批账回读互为冗余，任一成
    /// 立即长格）；读不回按 unavailable 诚实降级，
    /// 不给假清单
    enum GrantsState: Equatable {
        case loading
        case ready(GrantsListResponse)
        case unavailable
    }

    private(set) var grantsState: GrantsState = .loading
    /// 正在撤销的授权键（只禁用当前行）
    private(set) var revokingGrantKeys: Set<String> = []
    /// 授权面行内提示（撤销失败等人话）
    private(set) var grantsNote: String?

    /// GET /v1/grants 回读（网关 Bearer 面，部署包
    /// 1.3.0）：exec 命令授权＋写闸规则只读投影两源
    /// 拼合；双源皆败服务端回 503、走 unavailable
    func loadGrants(force: Bool = false) async {
        if case .loading = grantsState, !force {
            // 首次进入即 loading，直接走加载
        } else if !force, grantsState != .loading {
            return
        }
        grantsState = .loading
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            grantsState = .unavailable
            return
        }
        do {
            let response = try await appState.client
                .listGrants(config: config, apiKey: apiKey)
            grantsState = .ready(response)
        } catch {
            grantsState = .unavailable
        }
    }

    /// 撤销一条 exec 授权（写闸条目不走本端点，客户
    /// 端结构上不发）：成败终局以事后清单回读为准、
    /// 不认回执自报（HermesClient 头注口径）
    func revokeGrant(_ entry: GrantEntry) async {
        guard entry.source == .exec,
              let patternKey = entry.patternKey,
              let config = appState.config,
              let apiKey = appState.apiKey else { return }
        revokingGrantKeys.insert(entry.grantKey)
        defer { revokingGrantKeys.remove(entry.grantKey) }
        do {
            _ = try await appState.client.revokeGrant(
                config: config, apiKey: apiKey,
                patternKey: patternKey
            )
            grantsNote = nil
            await loadGrants(force: true)
        } catch {
            grantsNote = L10n.string("撤销没成，请稍后再试")
        }
    }

    // 浏览器段已于 0.9.0 迁出本 Store：状态改读盒桥，
    // 由 BrowserFaceView 自持 BoxBridgeStore（见
    // HubBrowserSection），本 Store 不再留错位源状态。

    // MARK: - 初始加载（页头）

    private var didLoadInitial = false
    private var didRecheckProfile = false

/// §416 新鲜度普查豁免：段内懒载单拉＋裁决 force 回读，会话级口径（判定表见 DESIGN §416）
    /// 页头初始加载（台账 198 收敛 C1 瘦身后）：只剩
    /// profile 冻结＋网关状态＋身份名解析三件——旧版
    /// 顺带拉的 serverSessions 100 条只喂已退役的活
    /// 动拼装流（零消费者），整段删除、不再白拉
    func loadInitial() async {
        guard !didLoadInitial else { return }
        didLoadInitial = true

        // 冻结 profile：首次请求前捕获
        if frozenProfileName == nil {
            frozenProfileName = try? await appState.performAdmin { client, config in
                try await client.activeProfileName(config: config)
            } ?? nil
        }
        serverStatus = try? await appState.performAdmin { client, config in
            try await client.status(config: config)
        }
        headerLoaded = true
        // 身份名顺带解析（0.6.1）：复用身份段的 soul 拉
        // 取（同一份数据、段内已加载不重拉），只为页头
        // 大名取身份名；取不到/失败回落 Hermes，不阻塞
        // 活动流
        await loadIdentityIfNeeded()
        if let content = soulDocument?.content {
            identityName = AgentName.resolve(soulContent: content)
            if let identityName {
                // §253：枢纽拉到的同一份 soul 顺带刷新
                // 全局名字缓存（时刻取文档回执）——全
                // App 露脸面同值，枢纽不另起一份名账
                appState.agentProfileStore.applyName(
                    identityName,
                    serverUpdatedAt: soulDocument?.updatedAt
                )
            }
        }
        await recheckProfileOnce()
    }

    /// 网关状态回读（台账 198 收敛 C4）：状态页身份头
    /// 改读本店快照后，其出现/下拉刷新经此触发回读
    /// ——取数仍只在本店一处、消费方不自拉；失败保留
    /// 旧快照（与 loadInitial 的 try? 口径一致，不拿
    /// 一次失败冒充离线）
    func refreshServerStatus() async {
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.status(config: config)
        }) {
            serverStatus = loaded
        }
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
        soulDocument = nil
        soulSections = nil
        didLoadInitial = false
        await loadInitial()
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

    // MARK: - 身份段·soul 保存（§155 HUB-1，规格 §2.7 环 3–5）

    /// 保存结果：只有 confirmed 才许编辑面报「已保存」
    enum SoulSaveOutcome: Equatable {
        /// 已写入且重新取回比对一致
        case confirmed
        /// 写入或取回失败、或取回内容对不上：没确认存
        /// 好，草稿由编辑面保留
        case unconfirmed
        /// 编辑期间档案已被切换：冻结名与当前在用名不
        /// 一致，已拦下未写（不把这份人设写到别份头上）
        case profileChanged
        /// 身份数据还没读到（无冻结名/无原文），不许存
        case notReady
    }

    private(set) var soulSaving = false

    /// 保存 soul 全文：保存前先复核在用档案名（环 5）
    /// → 写入（环 3，本包是 updateProfileSoul 的第一个
    /// 调用点）→ 立即重新取回比对（环 4，Core
    /// SoulSaveVerification 口径）；确认后才更新本店呈
    /// 现并让 AppState 重解析显示名
    func saveSoul(content: String) async -> SoulSaveOutcome {
        guard let name = frozenProfileName, soulDocument != nil else {
            return .notReady
        }
        guard !soulSaving else { return .unconfirmed }
        soulSaving = true
        defer { soulSaving = false }

        let current = try? await appState.performAdmin { client, config in
            try await client.activeProfileName(config: config)
        } ?? nil
        // 在用名取不到＝无法复核，保守不写；取到但与冻
        // 结名不一致＝档案已切换，拦下不写
        guard let current else { return .unconfirmed }
        guard current == name else { return .profileChanged }

        do {
            try await appState.performAdmin { client, config in
                try await client.updateProfileSoul(
                    config: config, name: name, content: content
                )
            }
            let fetched = try await appState.performAdmin { client, config in
                try await client.profileSoul(config: config, name: name)
            }
            if let fetchedName = fetched.profileName, fetchedName != name {
                return .unconfirmed
            }
            guard SoulSaveVerification.isConfirmed(
                submitted: content, fetched: fetched.content
            ) else { return .unconfirmed }
            soulDocument = fetched
            soulSections = SoulSectionParser.parse(fetched.content)
            identityName = AgentName.resolve(soulContent: fetched.content)
            appState.reresolveIdentityName(soulContent: fetched.content)
            return .confirmed
        } catch {
            return .unconfirmed
        }
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
            approvalState = .failed(L10n.string("审批状态没读出来，可能是网络或服务暂时没响应"))
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
            approvalState = .failed(L10n.string("待批列表没读出来，可能是网络或服务暂时没响应"))
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
        await refreshAnchorDecisionsIfStale()
        notifyAnchorDataRefreshed()
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

    // MARK: - 审批锚点（§165，规格 §4.2/§4.3）

    /// 锚点物化回调：App 层（ChatView）注入——store 自
    /// 身不碰 SwiftData（与 onApprovalChanged 同分工）；
    /// 每次审批数据刷新成功后触发，物化方读本 store 的
    /// pending/decisions 现态落锚定条目并回写下方两份
    /// 派生状态。未注入（枢纽独立呈现等）时锚点机制整
    /// 体静默，行为与 §165 之前逐字一致
    var onAnchorDataRefreshed: (() -> Void)?

    /// 全 App 已落锚的记录 id 集（物化方回写）：流末
    /// 尾区据此排除已锚记录（单源呈现），锚定行据此
    /// 不再依赖本地逐线程扫描
    var anchoredRecordIDs: Set<String> = []
    /// 已落锚记录的连续缺席轮数（物化方回写，键＝锚
    /// 定键）：记录在 pending 与 decisions 两处皆无的
    /// 刷新轮数——满两轮锚定行才转「已失效」（Core
    /// ApprovalAnchor.isStale），一轮缺席不判死
    var anchorMissCounts: [String: Int] = [:]
    /// 锚点回溯专用已决集（大 limit 拉取、低频刷新）：
    /// 日常 decisionHistory 只取最近 50 条，30 天回溯
    /// 窗内的带锚记录可能在窗口外——本集只作已决全
    /// 集的宽窗输入（见 decidedRecords），不再被消费
    /// 方直接读取
    private(set) var anchorDecisions: [WriteGateDecisionRecord]?

    /// 已决记录全集（§259 单源合成，全 App 唯一查账
    /// 面）：近窗（decisionHistory）∪ 回溯宽窗
    /// （anchorDecisions），合成规则在 Core
    /// DecisionRecordHistory 一处。此前同一本账在三
    /// 处消费点各自现拼（通知落点、台账详情两处
    /// View 层＋本类 anchorRowState），自此凡查已决
    /// 记录只许读本面——两扇窗口的拉取仍归本类
    /// （refreshDecisionHistory /
    /// refreshAnchorDecisionsIfStale），合成不许外溢。
    /// 例外只一处：裁决回路内刚刷新近窗的回读确认
    /// （decide 的 recordGone 落账与结果行对账）——那
    /// 是写路径对新拉近窗的即时核对、非呈现查账
    var decidedRecords: [WriteGateDecisionRecord] {
        DecisionRecordHistory.merge(
            recent: decisionHistory, wide: anchorDecisions)
    }
    private var anchorDecisionsFetchedAt: Date?

    /// 锚定行呈现态（单源判定，逻辑在 Core
    /// ApprovalAnchor.rowState）：待批集/已决集（含回
    /// 溯宽集）命中即现态；两处皆无才看缺席计数与数
    /// 据就绪位
    func anchorRowState(
        recordID: String
    ) -> ApprovalAnchor.RowState {
        let pending: [WriteGateRecord]
        let dataReady: Bool
        if case .ready(let records) = approvalState {
            pending = records
            dataReady = true
        } else {
            pending = []
            dataReady = false
        }
        let decisions = decidedRecords
        let key = anchoredKey(forRecordID: recordID)
        return ApprovalAnchor.rowState(
            recordID: recordID, dataReady: dataReady,
            pending: pending, decisions: decisions,
            missCount: key.flatMap { anchorMissCounts[$0] } ?? 0
        )
    }

    private func anchoredKey(forRecordID id: String) -> String? {
        anchorMissCounts.keys.first { key in
            ApprovalAnchor.recordID(fromKey: key) == id
        }
    }

    /// 回溯已决集低频刷新：距上次成功拉取 <10 分钟跳
    /// 过（回溯是补历史、低频即可）；失败保持旧值
    private func refreshAnchorDecisionsIfStale() async {
        if let at = anchorDecisionsFetchedAt,
           Date().timeIntervalSince(at) < 600 {
            return
        }
        guard let config = appState.config else { return }
        if let wide = try? await gateClient.decisionsForAnchor(
            config: config, limit: 500
        ) {
            anchorDecisions = wide
            anchorDecisionsFetchedAt = Date()
        }
    }

    private func notifyAnchorDataRefreshed() {
        onAnchorDataRefreshed?()
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
            return .failure(.failed(L10n.string("改动没读出来，可能是网络或服务暂时没响应")))
        }
    }

    /// 裁决（数据设计 §5.4 动作规则）：不做乐观移除——
    /// 服务端确认终态后才移卡；404 视为已被处理（移卡＋
    /// 提示）；409 保留卡片＋行内提示并刷新列表；网络
    /// 错误保留卡片与提示，不弹模态
    func decide(_ record: WriteGateRecord, approve: Bool) async {
        guard record.canDecide, let config = appState.config else { return }
        guard !decidingIDs.contains(record.id) else { return }
        // 防呆守卫（§245）：桥侧已判定确定性批不了的
        // 记录，批准路径在 store 层同样不开口——卡面
        // 已不给批准钮，这里防其他调用方绕过卡面；
        // 驳回不受影响（死单的唯一出路）。B-05
        // （§301）：提示行经 Core reasonLine 单读口；
        // isBlocked 蕴含 reason 非空、行恒有值，万一
        // 不然守卫仍不开口（防呆优先于提示完整）
        if approve, record.isBlocked {
            cardNotes[record.id] = ApprovalCardCopy.reasonLine(for: record)
            return
        }
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
                // §245：桥回了结构化失败原因就直出它
                // （与记录面预检原因同一「原因上卡面」
                // 通道），替代泛化红字——旧文案让用户
                // 以为重开详情再批就能过，实为确定性
                // 失败时纯属误导（生产个案 62927061）。
                // B-05（§301）：经 Core reasonLine 单
                // 读口取行（回执 reason＋execution 阶段）
                if let reasonLine = ApprovalCardCopy.reasonLine(for: response) {
                    cardNotes[record.id] = reasonLine
                } else {
                    cardNotes[record.id] = L10n.string("裁决未生效，请重新打开改动核对后再试。")
                }
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
                cardNotes[record.id] = L10n.string("这条写入的内容已变化，已按最新状态刷新，请重新核对。")
                decidingIDs.remove(record.id)
                await loadApproval(force: true)
                return
            case .failed(let message):
                cardNotes[record.id] = message
            case .noKey, .bridgeMissing, .unauthorized:
                cardNotes[record.id] = L10n.string("审批通道未接通，裁决没有发出。")
            }
        } catch {
            cardNotes[record.id] = L10n.string("裁决发送失败，记录仍在待批中。")
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
        // 防呆守卫（§245）：「总是允许」＝立即批准＋
        // 立规则，批不了的死单两步都无意义——不建规
        // 则、不批准，只留原因（与 decide 同口径、
        // 同一 reasonLine 单读口，§301）
        if record.isBlocked {
            cardNotes[record.id] = ApprovalCardCopy.reasonLine(for: record)
            return
        }
        decidingIDs.insert(record.id)
        cardNotes.removeValue(forKey: record.id)
        let createdRule: WriteGateRule
        do {
            createdRule = try await gateClient.createRule(
                config: config, subsystem: record.subsystem,
                origin: record.origin
            )
        } catch {
            cardNotes[record.id] = L10n.string(
                "「总是允许」没能记住（规则建立失败），这条仍在待批中。"
            )
            decidingIDs.remove(record.id)
            return
        }
        await loadRules()
        alwaysApproveMarks.insert(record.id)
        decidingIDs.remove(record.id)
        await decide(record, approve: true)
        showAlwaysAllowToast(
            rule: createdRule,
            scopeLabel: ApprovalCardCopy.alwaysAllowScope(for: record)
        )
    }

    private func showAlwaysAllowToast(
        rule: WriteGateRule, scopeLabel: String
    ) {
        alwaysAllowToastTask?.cancel()
        let toast = AlwaysAllowToast(rule: rule, scopeLabel: scopeLabel)
        alwaysAllowToast = toast
        alwaysAllowToastTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if alwaysAllowToast?.id == toast.id {
                alwaysAllowToast = nil
            }
        }
    }

    func dismissAlwaysAllowToast() {
        alwaysAllowToastTask?.cancel()
        alwaysAllowToastTask = nil
        alwaysAllowToast = nil
    }

    func undoAlwaysAllowToast() async {
        guard let toast = alwaysAllowToast else { return }
        dismissAlwaysAllowToast()
        await revokeRule(toast.rule)
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
                rulesNote = L10n.string("撤销没能生效，请稍后再试。")
            }
            await loadRules()
        } catch {
            rulesNote = L10n.string("撤销没能生效，请稍后再试。")
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
        await refreshAnchorDecisionsIfStale()
        notifyAnchorDataRefreshed()
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
