import Foundation
import OneDayCore

/// 监测数据中枢（P6，0.12.0 客户端先行）：oneday-bridge
/// 监测面的唯一状态面。数据源定案（契约档 monitor-
/// bridge-contract-20261109.md）：Hermes 无 monitor
/// 实体、cron 无指纹/结果字段，监测面须桥扩展
/// /monitors 才成立——桥未扩展时集合 404，本店露
/// 「监测数据源未开通」，绝不拿 cron 列表或假数据
/// 冒充监测。口径与 GoalsStore 同纪律：钥匙问题
/// （noKey/401）露桥未连接；已就绪后刷新失败保持
/// 旧数据不翻态；标记已读后回读列表对账未读数。
@MainActor
@Observable
final class MonitorsStore {
    enum LoadState: Equatable {
        case loading
        /// 桥未连接（钥匙没粘/被拒，消息说清是哪一种）
        case notConnected(String)
        /// 桥在、监测面未开通（集合端点 404）
        case sourceNotOpened(String)
        case failed(String)
        case ready
    }

    private(set) var loadState: LoadState = .loading
    private(set) var monitors: [BridgeMonitor] = []
    /// 变化记录缓存（按监测 id；进详情时拉取）
    private(set) var changes: [String: [BridgeMonitorChange]] = [:]
    private(set) var changesLoading: Set<String> = []
    private(set) var changesErrors: [String: String] = [:]
    /// 正在标记已读的变化 id（防重复提交）
    private(set) var markingIDs: Set<String> = []

    private let client = OneDayBridgeClient()
    private var loadInFlight = false

    /// 呈现序（未读多者靠前，纯函数在 Core）
    var sortedMonitors: [BridgeMonitor] {
        MonitorOrdering.sorted(monitors)
    }

    var totalUnread: Int {
        MonitorPresentation.totalUnread(monitors)
    }

    func monitor(id: String) -> BridgeMonitor? {
        monitors.first { $0.id == id }
    }

    // MARK: - 加载

    func load(appState: AppState) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .failed("尚未连接服务器。")
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            monitors = try await client.monitors(config: config)
            loadState = .ready
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = Self.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed("监测读取失败，请稍后重试。")
        }
    }

    /// 静默回读（标记已读对账专用）：失败不翻态、不动旧数
    private func refetch(appState: AppState) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.monitors(config: config) {
            monitors = fetched
        }
    }

    static func state(for error: OneDayBridgeError) -> LoadState {
        switch error {
        case .noKey:
            return .notConnected(
                "还没有粘贴数据桥钥匙。在设置里粘贴桥钥匙后，监测就能用了。"
            )
        case .unauthorized:
            return .notConnected(
                "数据桥钥匙被拒绝了。请到设置里检查桥钥匙是否粘对。"
            )
        case .bridgeMissing:
            return .sourceNotOpened(
                "服务器上的数据桥还没有开通监测面。开通后，你盯着的页面和对象有变化就会出现在这里。"
            )
        case .recordGone:
            return .failed("这条记录已经不在了，请刷新后重试。")
        case .failed(let message):
            return .failed(message)
        }
    }

    static func message(for error: OneDayBridgeError) -> String {
        switch error {
        case .noKey:
            return "数据桥未连接：还没有粘贴桥钥匙。"
        case .unauthorized:
            return "数据桥未连接：桥钥匙被拒绝。"
        case .bridgeMissing:
            return "监测数据源还没有开通。"
        case .recordGone:
            return "这条记录已经不在了。"
        case .failed(let message):
            return message
        }
    }

    // MARK: - 变化记录

    func loadChanges(appState: AppState, monitorID: String) async {
        guard !changesLoading.contains(monitorID) else { return }
        guard let config = appState.config else {
            changesErrors[monitorID] = "尚未连接服务器。"
            return
        }
        changesLoading.insert(monitorID)
        changesErrors.removeValue(forKey: monitorID)
        defer { changesLoading.remove(monitorID) }
        do {
            let fetched = try await client.monitorChanges(
                config: config, monitorID: monitorID
            )
            changes[monitorID] = MonitorChangeOrdering.sorted(fetched)
        } catch let error as OneDayBridgeError {
            // 已有缓存时保持旧数据（同列表刷新口径）
            if changes[monitorID] == nil {
                changesErrors[monitorID] = Self.message(for: error)
            }
        } catch {
            if changes[monitorID] == nil {
                changesErrors[monitorID] = "变化记录读取失败，请稍后重试。"
            }
        }
    }

    // MARK: - 标记已读（POST→本地即时翻已读＋回读对账未读数）

    func markRead(
        appState: AppState, monitorID: String, changeID: String
    ) async {
        guard !markingIDs.contains(changeID) else { return }
        guard let config = appState.config else { return }
        guard let current = changes[monitorID]?
            .first(where: { $0.id == changeID }),
            !current.read
        else { return }
        markingIDs.insert(changeID)
        defer { markingIDs.remove(changeID) }
        do {
            try await client.markMonitorChangeRead(
                config: config, monitorID: monitorID, changeID: changeID
            )
            // 本地即时翻已读（呈现不等待回读往返）
            if var list = changes[monitorID] {
                list = list.map {
                    $0.id == changeID ? $0.markingRead() : $0
                }
                changes[monitorID] = list
            }
            // 未读数以服务端计数为权威：回读列表对账
            await refetch(appState: appState)
        } catch {
            // 标记失败不假装已读：本地保持未读，
            // 详情页不弹错（下次打开会再试）
            return
        }
    }
}
