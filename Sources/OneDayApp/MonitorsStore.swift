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
/// 0.12.1 桥上线后补控制动作（新建/立即检查/暂停
/// 恢复/删除）：一律动作→回读确认（出现/时刻推进/
/// 状态翻转/消失）才算成，未确认与失败的人话留
/// 行内（notes），不许乐观假成功。
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
    /// 正在执行控制动作的监测 id（只禁用当前条）
    private(set) var actingIDs: Set<String> = []
    /// 行内提示（动作未确认/失败的人话，留在行内不弹模态）
    private(set) var notes: [String: String] = [:]
    private(set) var creating = false
    private(set) var createError: String?

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
            loadState = .failed(L10n.string("尚未连接服务器。"))
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
            loadState = .failed(L10n.string("监测读取失败，请稍后重试。"))
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
                L10n.string("还没有可用的登录信息：监测用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。")
            )
        case .unauthorized:
            return .notConnected(
                L10n.string("服务器拒绝了这次登录。请到「设置」里检查登录是否还有效。")
            )
        case .bridgeMissing:
            return .sourceNotOpened(
                L10n.string("服务器上的数据桥还没有开通监测面。开通后，你盯着的页面和对象有变化就会出现在这里。")
            )
        case .recordGone:
            return .failed(L10n.string("这条记录已经不在了，请刷新后重试。"))
        case .failed(let message):
            return .failed(message)
        }
    }

    static func message(for error: OneDayBridgeError) -> String {
        switch error {
        case .noKey:
            return L10n.string("数据桥未连接：还没有可用的登录信息。")
        case .unauthorized:
            return L10n.string("数据桥未连接：服务器拒绝了这次登录。")
        case .bridgeMissing:
            return L10n.string("监测数据源还没有开通。")
        case .recordGone:
            return L10n.string("这条记录已经不在了。")
        case .failed(let message):
            return message
        }
    }

    // MARK: - 变化记录

    func loadChanges(appState: AppState, monitorID: String) async {
        guard !changesLoading.contains(monitorID) else { return }
        guard let config = appState.config else {
            changesErrors[monitorID] = L10n.string("尚未连接服务器。")
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
                changesErrors[monitorID] = L10n.string("变化记录读取失败，请稍后重试。")
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

    // MARK: - 新建（POST→回读确认出现才算完成，0.12.1）

    func clearCreateError() {
        createError = nil
    }

    func create(
        appState: AppState, name: String, target: String,
        frequency: MonitorFrequency
    ) async -> Bool {
        guard !creating else { return false }
        if let problem = MonitorCreateValidation.problem(
            name: name, target: target
        ) {
            createError = problem
            return false
        }
        guard let config = appState.config else {
            createError = L10n.string("尚未连接服务器。")
            return false
        }
        creating = true
        createError = nil
        defer { creating = false }
        let request = BridgeMonitorCreateRequest.make(
            name: name, target: target, frequency: frequency
        )
        do {
            let created = try await client.createMonitor(
                config: config, request: request
            )
            await refetch(appState: appState)
            if monitors.contains(where: { $0.id == created.id }) {
                return true
            }
            createError = L10n.string("监测已提交，但还没有在列表里确认出现，请关闭后刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            createError = Self.message(for: error)
            return false
        } catch {
            createError = L10n.string("监测创建失败，请稍后重试。")
            return false
        }
    }

    // MARK: - 立即检查（POST→回读状态与未读数对账）

    /// 确认口径：回读后该监测还在、且 lastCheckedAt
    /// 严格晚于动作前（检查落账必刷新该时刻）；已
    /// 暂停时桥回 409，人话原样留在行内
    func checkNow(appState: AppState, monitorID: String) async {
        guard !actingIDs.contains(monitorID) else { return }
        guard let config = appState.config else {
            notes[monitorID] = L10n.string("尚未连接服务器。")
            return
        }
        actingIDs.insert(monitorID)
        notes.removeValue(forKey: monitorID)
        defer { actingIDs.remove(monitorID) }
        let previousCheckedAt = monitor(id: monitorID)?.lastCheckedAt
        do {
            _ = try await client.checkMonitor(
                config: config, monitorID: monitorID
            )
            await refetch(appState: appState)
            guard let current = monitor(id: monitorID) else {
                notes[monitorID] = L10n.string("检查已发出，但再确认时监测不见了，请刷新核对。")
                return
            }
            let advanced = (current.lastCheckedAt ?? -.infinity)
                > (previousCheckedAt ?? -.infinity)
            if !advanced {
                notes[monitorID] = L10n.string("检查已发出，但再确认时状态还没更新，请刷新核对。")
            }
        } catch let error as OneDayBridgeError {
            notes[monitorID] = Self.message(for: error)
        } catch {
            notes[monitorID] = L10n.string("检查失败，请稍后重试。")
        }
    }

    // MARK: - 暂停/恢复（POST→回读确认 enabled 已翻转）

    func setEnabled(
        appState: AppState, monitorID: String, enabled: Bool
    ) async {
        guard !actingIDs.contains(monitorID) else { return }
        guard let config = appState.config else {
            notes[monitorID] = L10n.string("尚未连接服务器。")
            return
        }
        actingIDs.insert(monitorID)
        notes.removeValue(forKey: monitorID)
        defer { actingIDs.remove(monitorID) }
        do {
            if enabled {
                _ = try await client.resumeMonitor(
                    config: config, monitorID: monitorID
                )
            } else {
                _ = try await client.pauseMonitor(
                    config: config, monitorID: monitorID
                )
            }
            await refetch(appState: appState)
            guard let current = monitor(id: monitorID) else {
                notes[monitorID] = L10n.string("操作已发出，但再确认时监测不见了，请刷新核对。")
                return
            }
            if current.enabled != enabled {
                notes[monitorID] = enabled
                    ? L10n.string("恢复已发出，但再确认时仍是暂停状态，请刷新核对。")
                    : L10n.string("暂停已发出，但再确认时仍是启用状态，请刷新核对。")
            }
        } catch let error as OneDayBridgeError {
            notes[monitorID] = Self.message(for: error)
        } catch {
            notes[monitorID] = enabled
                ? L10n.string("恢复失败，请稍后重试。")
                : L10n.string("暂停失败，请稍后重试。")
        }
    }

    // MARK: - 删除（DELETE→回读确认消失才算完成）

    func delete(appState: AppState, monitorID: String) async -> Bool {
        guard !actingIDs.contains(monitorID) else { return false }
        guard let config = appState.config else {
            notes[monitorID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(monitorID)
        notes.removeValue(forKey: monitorID)
        defer { actingIDs.remove(monitorID) }
        do {
            try await client.deleteMonitor(
                config: config, monitorID: monitorID
            )
            await refetch(appState: appState)
            if monitor(id: monitorID) == nil {
                purgeCaches(monitorID: monitorID)
                return true
            }
            notes[monitorID] = L10n.string("删除已发出，但列表里还在，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            // 记录本就已不在＝删除目的已达（回读同口径）
            if case .recordGone = error {
                await refetch(appState: appState)
                if monitor(id: monitorID) == nil {
                    purgeCaches(monitorID: monitorID)
                    return true
                }
            }
            notes[monitorID] = Self.message(for: error)
            return false
        } catch {
            notes[monitorID] = L10n.string("删除失败，请稍后重试。")
            return false
        }
    }

    /// 删除成功后清该监测的变化缓存与行内提示，
    /// 不留孤儿数据
    private func purgeCaches(monitorID: String) {
        changes.removeValue(forKey: monitorID)
        changesErrors.removeValue(forKey: monitorID)
        notes.removeValue(forKey: monitorID)
    }
}
