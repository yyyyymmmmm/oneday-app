import Foundation
import OneDayCore

/// 工作台账数据中枢：枢纽「活动」段自持（段内 .task
/// 驱动，进页全量拉、可见时 10 秒增量轮询）。口径：
/// ①台账未上线如实露「还没上线」态——判据是 /ledger
/// 读面 404（旧伴生无此面），伴生探测只作旁证把话
/// 说准，绝不拿空列表或假数据冒充已上线；②失败保
/// 旧快照＋标陈旧（规格 §2.5：新鲜度独立露面，不许
/// 同字重同位置冒充现值）；③页首计数与列表同 payload
/// （桥 counts 优先，缺失才现算），不另拉计数接口。
@MainActor
@Observable
final class LedgerStore {
    enum LoadState: Equatable {
        case loading
        /// 台账还没上线／还没连接（说明文案说清是哪种）
        case notLive(String)
        case failed(String)
        case ready
    }

    private(set) var loadState: LoadState = .loading
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

    private let client = LedgerBridgeClient()
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

    var dayGroups: [LedgerDayGroup] {
        LedgerBoard.dayGroups(
            items, now: Date(timeIntervalSince1970: serverNow)
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
            loadState = .failed(L10n.string("尚未连接服务器。"))
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
                loadState = .failed(L10n.string("台账读取失败，请稍后重试。"))
            }
        }
    }

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
            case .notLive:
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

    private func handleLoadError(
        _ error: OneDayBridgeError, config: ServerConfig
    ) async {
        switch error {
        case .noKey:
            loadState = .notLive(
                L10n.string("还没有可用的登录信息：台账用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。")
            )
        case .unauthorized:
            loadState = .notLive(
                L10n.string("服务器拒绝了这次登录。请到「设置」里检查登录是否还有效。")
            )
        case .bridgeMissing:
            // /ledger 读面不存在＝台账未上线（伴生旧版
            // 无此面）；探测作旁证把说明说准，探测本身
            // 失败不改变结论
            loadState = .notLive(Self.notLiveMessage(probe: nil))
            let result = await client.probeCompanion(config: config)
            probe = result
            if loadState != .ready {
                loadState = .notLive(
                    Self.notLiveMessage(probe: result)
                )
            }
        case .recordGone:
            if loadState != .ready {
                loadState = .failed(L10n.string("台账读取失败，请稍后重试。"))
            }
        case .failed(let message):
            if loadState != .ready {
                loadState = .failed(message)
            }
        }
    }

    /// 「还没上线」说明：探测到版本就点名版本，探测
    /// 不到就只说事实，不编版本不编时间
    static func notLiveMessage(probe: CompanionProbe?) -> String {
        switch probe {
        case .detected(let info):
            if let version = info.companionVersion,
               !version.isEmpty {
                return L10n.format("现在这台伴生服务是 %@ 版，还没有台账功能。等它升级后，这里会自动开始记录每件工作的进度。", version)
            }
            return L10n.string("伴生服务还没有台账功能。等它升级后，这里会自动开始记录每件工作的进度。")
        case .missing:
            return L10n.string("还没有探测到带台账的伴生服务。台账上线后，这里会自动开始记录每件工作的进度。")
        case .unreadable, .unreachable, nil:
            return L10n.string("台账服务还没上线。上线后，这里会自动开始记录每件工作的进度。")
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
}
