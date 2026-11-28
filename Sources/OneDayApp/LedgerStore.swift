import Foundation
import OneDayCore

/// 工作台账数据中枢：§259 起由 AppState 持有单例
/// （sharedLedgerStore），枢纽「活动」段与进展胶囊
/// 消费同一份（段内 .task 驱动，进页全量拉、可见
/// 时 10 秒增量轮询；轮询有在飞守卫，多面共用安
/// 全）。口径：
/// ①台账未上线如实露「还没上线」态——判据是 /ledger
/// 读面 404（旧伴生无此面），伴生探测只作旁证把话
/// 说准，绝不拿空列表或假数据冒充已上线；②失败保
/// 旧快照＋标陈旧（规格 §2.5：新鲜度独立露面，不许
/// 同字重同位置冒充现值）；③页首计数与列表同 payload
/// （桥 counts 优先，缺失才现算），不另拉计数接口。
@MainActor
@Observable
final class LedgerStore {
    /// 加载态与错误映射走 Core 共用定义（§139，与
    /// KanbanStore 同一口）：还没上线＝.unavailable(说明)
    /// （文案由 notLiveMessage / notLiveMessage(for:) 按
    /// 情形提供），失败＝StoreLoadState 映射
    private(set) var loadState: StoreLoadState = .loading
    private(set) var items: [LedgerItem] = []
    private(set) var summary: LedgerSummary?
    private(set) var snapshotSeq: Int?
    private(set) var ledgerUpdatedAt: Double?
    private(set) var collectorHeartbeatAt: Double?
    /// 服务端−本地时钟偏移（每次成功回执以 serverNow
    /// 校准）：已耗时与新鲜度一律在服务端时间轴上算
    private(set) var clockOffset: Double = 0
    /// 最近一次拉取成功后，我方与桥的联系中断（有旧
    /// 快照顶着）：与「采集器停更」分开露面（§2.5）
    private(set) var connectionLost = false
    /// 伴生探测旁证（仅未上线态用到）
    private(set) var probe: CompanionProbe?

    private(set) var detail: LedgerItem?
    private(set) var detailLoading = false
    private(set) var detailGone = false
    /// 线程详情回执（真步序列）与它对应的条目 id：
    /// 换条目即作废防串用；拉不到时为 nil＋itemID
    /// 照记（＝已试过、走回落），视图据此分流
    private(set) var threadDetail: LedgerThreadDetail?
    private(set) var threadDetailItemID: String?
    private var threadLoadInFlightFor: String?

    private let client = LedgerBridgeClient()
    /// 伴生探测走 front 客户端（桥-1 归位：探针本属
    /// front 面，本店只在台账未上线时借它作旁证）
    private let frontClient = CompanionFrontClient()
    private var loadInFlight = false

    // MARK: - 呈现派生（口径收口在 Core LedgerBoard）

    /// 当前服务端时刻（本地钟＋校准偏移）
    var serverNow: Double {
        Date().timeIntervalSince1970 + clockOffset
    }

    /// 任意本地时刻对应的服务端时刻（逐秒重算的副题
    /// 以 TimelineView 的 context.date 喂入走本口）
    func displayServerNow(at date: Date) -> Double {
        date.timeIntervalSince1970 + clockOffset
    }

    var freshness: LedgerFreshness {
        LedgerFreshness.evaluate(
            heartbeatAge: collectorHeartbeatAt.map {
                serverNow - $0
            }
        )
    }

    var headerCounts: (inProgress: Int, blockedApproval: Int) {
        LedgerBoard.headerCounts(items: items, summary: summary)
    }

    /// 全流（服务端单流：监测变化由服务端台账直供
    /// kind=monitor 条目、与工作条目同账同序，A-05
    /// 起客户端不再拼第二源）：分组呈现走全流；页
    /// 首计数同走本账（计数是「工作」的口径，监测
    /// 条目恒 completed、不冒充工作件数）
    var allItems: [LedgerItem] {
        LedgerMerge.sorted(items)
    }

    var dayGroups: [LedgerDayGroup] {
        LedgerBoard.dayGroups(
            allItems, now: Date(timeIntervalSince1970: serverNow)
        )
    }

    var hasActiveItems: Bool {
        items.contains { $0.status.isActive }
    }

    // MARK: - 加载

    /// 首次加载／重试／下拉刷新共用：全量拉取
    func load(appState: AppState) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .notConnected
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            let response = try await client.list(
                config: config, since: nil
            )
            let fetchedSummary = await summaryOrNil(config: config)
            apply(response, summaryOverride: fetchedSummary)
            loadState = .ready
        } catch let error as OneDayBridgeError {
            await handleLoadError(error, config: config)
        } catch {
            if loadState != .ready {
                loadState = .failed(L10n.string("台账没读出来，可能是网络或服务暂时没响应"))
            }
        }
    }

/// §416 新鲜度普查豁免：10 秒可见轮询＋since 增量合并，自带节奏，门不介入（判定表见 DESIGN §416）
    /// 可见轮询（面 .task 驱动、消失即取消）：就绪态
    /// 走 since 增量合并；未上线态每轮重试全量（服务
    /// 上线后页面自己活过来，与空态文案「会自动开始
    /// 记录」对得上）
    func runVisibleLoop(appState: AppState) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { break }
            switch loadState {
            case .ready:
                await poll(appState: appState)
            case .unavailable:
                await load(appState: appState)
            case .loading, .failed:
                break
            }
        }
    }

    private func poll(appState: AppState) async {
        guard !loadInFlight, let config = appState.config else {
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            let response = try await client.list(
                config: config, since: snapshotSeq
            )
            let fetchedSummary = await summaryOrNil(config: config)
            items = LedgerMerge.merge(
                existing: items, changes: response.items
            )
            snapshotSeq = response.snapshotSeq
            if let at = response.ledgerUpdatedAt {
                ledgerUpdatedAt = at
            }
            if let beat = response.collectorHeartbeatAt {
                collectorHeartbeatAt = beat
            }
            if let summary = fetchedSummary ?? response.counts {
                self.summary = summary
            }
            if let now = response.serverNow {
                clockOffset = now - Date().timeIntervalSince1970
            }
            connectionLost = false
        } catch {
            // 保旧快照、只标联系中断；新鲜度横幅另按心
            // 跳龄露面，两条线不许合并成一个「失败」
            connectionLost = true
        }
    }

    /// summary 面尽力而为：拿不到不影响列表主面（降级
    /// 位只是露面信息，缺了按列表 counts 顶）
    private func summaryOrNil(
        config: ServerConfig
    ) async -> LedgerSummary? {
        try? await client.summary(config: config)
    }

    private func apply(
        _ response: LedgerListResponse,
        summaryOverride: LedgerSummary?
    ) {
        // 防空硬化（2026-11-28 真机报「活动页退出重进
        // 就没有了」）：全量拉回空表而手头已有条目时，
        // 不许整表盖空——保旧列表、只标联系中断（呈现
        // 层自有陈旧弱化），等下一轮全量/增量对账
        if response.items.isEmpty, !items.isEmpty {
            snapshotSeq = response.snapshotSeq
            connectionLost = true
            return
        }
        items = LedgerMerge.sorted(response.items)
        snapshotSeq = response.snapshotSeq
        ledgerUpdatedAt = response.ledgerUpdatedAt
        collectorHeartbeatAt = response.collectorHeartbeatAt
        summary = summaryOverride ?? response.counts
        if let now = response.serverNow {
            clockOffset = now - Date().timeIntervalSince1970
        }
        connectionLost = false
        probe = nil
    }

    /// 错误落态走 Core 共用映射（§139）：钥匙类归
    /// unavailable（文案 notLiveMessage(for:)）、记录
    /// 消失与桥侧失败归 failed（已就绪时保旧快照不翻
    /// 态）；bridgeMissing 是本面专属语义——/ledger
    /// 读面不存在＝台账未上线，探测作旁证把说明说准
    /// （探测本身失败不改变结论），仍只产出共用态
    private func handleLoadError(
        _ error: OneDayBridgeError, config: ServerConfig
    ) async {
        if case .bridgeMissing = error {
            loadState = .unavailable(Self.notLiveMessage(probe: nil))
            let result = await frontClient.probeCompanion(config: config)
            probe = result
            if loadState != .ready {
                loadState = .unavailable(
                    Self.notLiveMessage(probe: result)
                )
            }
            return
        }
        switch error {
        case .recordGone, .failed:
            guard loadState != .ready else { return }
        case .noKey, .unauthorized:
            break
        case .bridgeMissing:
            return // 已在上方处理
        }
        loadState = StoreLoadState.from(
            bridgeError: error,
            unavailableMessage: Self.notLiveMessage(for:),
            recordGoneMessage: L10n.string("台账没读出来，可能是网络或服务暂时没响应")
        )
    }

    /// 钥匙类错误的「还没上线／还没连接」说明（共用
    /// 映射的文案供给口）：说清是登录信息缺失还是被
    /// 拒，不编时间不编版本
    static func notLiveMessage(
        for error: OneDayBridgeError
    ) -> String {
        switch error {
        case .noKey:
            return L10n.string("还没有可用的登录信息：台账用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。")
        case .unauthorized:
            return L10n.string("服务器拒绝了这次登录。请到「设置」里检查登录是否还有效。")
        case .bridgeMissing, .recordGone, .failed:
            return L10n.string("台账功能还没开通。开通后，这里会自动开始记录每件工作的进度。")
        }
    }

    /// 「还没上线」说明：探测到版本就点名版本，探测
    /// 不到就只说事实，不编版本不编时间
    static func notLiveMessage(probe: CompanionProbe?) -> String {
        switch probe {
        case .detected(let info):
            if let version = info.companionVersion,
               !version.isEmpty {
                return L10n.format("现在的服务是 %@ 版，还没有台账功能。等它升级后，这里会自动开始记录每件工作的进度。", version)
            }
            return L10n.string("服务还没有台账功能。等它升级后，这里会自动开始记录每件工作的进度。")
        case .missing:
            return L10n.string("还没有连上带台账功能的服务。台账开通后，这里会自动开始记录每件工作的进度。")
        case .unreadable, .unreachable, nil:
            return L10n.string("台账功能还没开通。开通后，这里会自动开始记录每件工作的进度。")
        }
    }

    // MARK: - 详情

    func loadDetail(appState: AppState, id: String) async {
        guard let config = appState.config else { return }
        detailLoading = true
        detailGone = false
        defer { detailLoading = false }
        do {
            detail = try await client.detail(config: config, id: id)
        } catch let error as OneDayBridgeError {
            if error == .recordGone {
                detailGone = true
            }
        } catch {
            // 详情拉不到不翻整页：列表快照的行数据还在
            // 详情面顶着，history 区以缺失如实呈现
        }
    }

    /// 详情页真步拉取：threadId 由 Core
    /// LedgerThreading 按服务端 classify/thread_key
    /// 同规反算。算不出（不组线程的条目）与拉不到
    /// （404/网络）都静默收口——步区自有 history
    /// 派生回落链，本拉取失败不翻任何态、不清已有
    /// 回执（同条目刷新失败保旧步，不许把已渲染的
    /// 真步打回回落态）
    func loadThreadDetail(appState: AppState, item: LedgerItem) async {
        guard let threadID = LedgerThreading.threadID(for: item)
        else {
            if threadDetailItemID != item.id {
                threadDetail = nil
                threadDetailItemID = item.id
            }
            return
        }
        guard let config = appState.config else { return }
        guard threadLoadInFlightFor != item.id else { return }
        threadLoadInFlightFor = item.id
        defer {
            if threadLoadInFlightFor == item.id {
                threadLoadInFlightFor = nil
            }
        }
        do {
            let fetched = try await client.threadDetail(
                config: config, threadId: threadID
            )
            threadDetail = fetched
            threadDetailItemID = item.id
        } catch {
            if threadDetailItemID != item.id {
                threadDetail = nil
                threadDetailItemID = item.id
            }
        }
    }
}
