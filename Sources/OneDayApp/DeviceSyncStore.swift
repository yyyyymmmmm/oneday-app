import Foundation
import OneDayCore

/// 同步制偏好（0.36.14）：逐数据集同步开关（默认
/// 关）/ 说明屏已读标记 / 本地回执 / 最近上报的权
/// 限与范围。回执只是状态行的兜底，真状态以桥
/// status 为准（桥取不到时才用回执拼新鲜度行）
extension DevicePreferences {
    private static var defaults: UserDefaults { .standard }

    private static func syncKey(
        _ dataset: DeviceSyncDataset, _ suffix: String
    ) -> String {
        "device.sync.\(dataset.bridgeName).\(suffix)"
    }

    static func syncEnabled(for dataset: DeviceSyncDataset) -> Bool {
        defaults.bool(forKey: syncKey(dataset, "enabled"))
    }

    static func setSyncEnabled(
        _ on: Bool, for dataset: DeviceSyncDataset
    ) {
        defaults.set(on, forKey: syncKey(dataset, "enabled"))
    }

    static func syncIntroAcked(for dataset: DeviceSyncDataset)
        -> Bool
    {
        defaults.bool(forKey: syncKey(dataset, "introAcked"))
    }

    static func setSyncIntroAcked(for dataset: DeviceSyncDataset) {
        defaults.set(true, forKey: syncKey(dataset, "introAcked"))
    }

    /// 本地同步回执（条数与时刻取桥 complete 的回执）
    struct SyncReceipt: Codable, Equatable, Sendable {
        let count: Int
        let syncedAt: TimeInterval
        let authRange: String
    }

    static func syncReceipt(for dataset: DeviceSyncDataset)
        -> SyncReceipt?
    {
        guard let data = defaults.data(
            forKey: syncKey(dataset, "receipt")
        ) else { return nil }
        return try? JSONDecoder().decode(SyncReceipt.self, from: data)
    }

    static func setSyncReceipt(
        _ receipt: SyncReceipt?, for dataset: DeviceSyncDataset
    ) {
        guard let receipt,
              let data = try? JSONEncoder().encode(receipt)
        else {
            defaults.removeObject(forKey: syncKey(dataset, "receipt"))
            return
        }
        defaults.set(data, forKey: syncKey(dataset, "receipt"))
    }

    /// 最近一次上报桥的权限与范围（没变不上报）
    static func syncLastReported(for dataset: DeviceSyncDataset)
        -> (permission: String, range: String)?
    {
        guard let permission = defaults.string(
            forKey: syncKey(dataset, "reportedPermission")
        ) else { return nil }
        return (
            permission,
            defaults.string(forKey: syncKey(dataset, "reportedRange"))
                ?? ""
        )
    }

    static func setSyncLastReported(
        permission: String, range: String,
        for dataset: DeviceSyncDataset
    ) {
        defaults.set(
            permission, forKey: syncKey(dataset, "reportedPermission")
        )
        defaults.set(range, forKey: syncKey(dataset, "reportedRange"))
    }

    /// 通讯录「整本重灌」标记：桥在范围变化时回
    /// reimport_required 时落下，下一轮同步整本传、
    /// 成功即清
    static func contactsForceFull() -> Bool {
        defaults.bool(forKey: "device.sync.contacts.forceFull")
    }

    static func setContactsForceFull(_ on: Bool) {
        defaults.set(on, forKey: "device.sync.contacts.forceFull")
    }
}

/// 同步控制器（0.36.14，规格 §3–§7）：五数据集的
/// 状态拉取/单件同步/状态上报/副本删除。同步资格
/// 只看两层——系统权限可用＋同步开关开（§6.1 三
/// 层分层：「允许智能体调用」管供给不管同步）；
/// 权限撤销的停供由桥据上报判定，本层保证回前台
/// 第一时间上报。授权铁律：每轮先同步读权限现态，
/// 仅未决定时走那一次请求（DevicePermissions 内判）；
/// 回调隔离铁律：本层不挂任何系统回调闭包
@MainActor
@Observable
final class DeviceSyncController {
    /// 桥 status 读到的逐件状态（真状态源）
    private(set) var statuses:
        [DeviceSyncDataset: DeviceSyncDatasetStatus] = [:]
    /// 逐件同步开关（与偏好同值，视图绑定读这里）
    private(set) var syncEnabledState: [DeviceSyncDataset: Bool]
    /// 逐件进度人话（非 nil＝正在同步）
    private(set) var progress: [DeviceSyncDataset: String] = [:]
    /// 逐件最近一次失败人话（成功即清）
    private(set) var lastErrors: [DeviceSyncDataset: String] = [:]
    /// 逐件本地回执（状态行兜底）
    private(set) var receipts:
        [DeviceSyncDataset: DevicePreferences.SyncReceipt]

    private let client = DeviceBridgeClient()
    let photosEngine = PhotosEngine()
    let motionEngine = MotionEngine()

    /// 由 AppState 接线（与设备会话共用同一分发器
    /// 的引擎：日历/提醒/通讯录读走它）
    var dispatcher: DeviceToolDispatcher?

    private var foregroundTask: Task<Void, Never>?

    init() {
        var enabled: [DeviceSyncDataset: Bool] = [:]
        var receipts: [DeviceSyncDataset: DevicePreferences.SyncReceipt]
            = [:]
        for dataset in DeviceSyncDataset.allCases {
            enabled[dataset] = DevicePreferences.syncEnabled(
                for: dataset
            )
            if let receipt = DevicePreferences.syncReceipt(
                for: dataset
            ) {
                receipts[dataset] = receipt
            }
        }
        syncEnabledState = enabled
        self.receipts = receipts
    }

    func isSyncEnabled(_ dataset: DeviceSyncDataset) -> Bool {
        syncEnabledState[dataset] ?? false
    }

    func setSyncEnabled(_ dataset: DeviceSyncDataset, _ on: Bool) {
        syncEnabledState[dataset] = on
        DevicePreferences.setSyncEnabled(on, for: dataset)
    }

    func isRunning(_ dataset: DeviceSyncDataset) -> Bool {
        progress[dataset] != nil
    }

    /// 删副本后桥状态重读前的本地清账（回执作废）
    private func clearReceipt(_ dataset: DeviceSyncDataset) {
        receipts[dataset] = nil
        DevicePreferences.setSyncReceipt(nil, for: dataset)
    }

    // MARK: - 状态拉取

    /// 拉桥 status 刷新逐件状态（失败静默保旧值：
    /// 页面有本地回执兜底，不拿失败吓人）
    func refreshStatus(config: ServerConfig?) async {
        guard let config else { return }
        guard let data = try? await client.syncStatusData(
            config: config
        ) else { return }
        statuses = DeviceSyncStatusResponse.decode(data)
    }

    // MARK: - 前台检查（回前台/冷启/连接就绪时调）

    /// 顺序：①先上报各件权限与范围变化（撤销→桥
    /// 停供、范围变→下轮整本重灌）②再按计划器逐件
    /// 判定节流同步。整轮串行慢工，异步自跑不挡界面
    func foregroundCheck(config: ServerConfig?) {
        guard let config else { return }
        foregroundTask?.cancel()
        foregroundTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatus(config: config)
            let permissions = DevicePermissions.currentStates()
            for dataset in DeviceSyncDataset.allCases {
                if Task.isCancelled { return }
                let permission = permissions[dataset.sourceID]
                    ?? .notDetermined
                await self.reportStateIfChanged(
                    dataset: dataset, permission: permission,
                    config: config
                )
                let decision = DeviceSyncPlanner.foregroundDecision(
                    dataset: dataset,
                    permissionUsable: permission.isUsable,
                    syncEnabled: self.isSyncEnabled(dataset),
                    lastSuccessAt: self.statuses[dataset]?.syncedAt
                        ?? self.receipts[dataset].map {
                            Date(timeIntervalSince1970: $0.syncedAt)
                        },
                    pendingWrite:
                        self.statuses[dataset]?.pendingWrite ?? false,
                    now: Date()
                )
                if decision == .sync {
                    _ = await self.syncNow(
                        dataset, config: config
                    )
                }
            }
        }
    }

    // MARK: - 单件同步

    /// 一轮同步：门（权限→开关）→ 组装 → 分批暂存
    /// → 完成确认整批换入 → 回执＋状态刷新。任一步
    /// 失败：桥上旧副本原样保留（暂存不换入），错
    /// 误人话落 lastErrors
    @discardableResult
    func syncNow(
        _ dataset: DeviceSyncDataset, config: ServerConfig?
    ) async -> Bool {
        guard let config else {
            lastErrors[dataset] = "还没连上服务器，同步不了"
            return false
        }
        guard progress[dataset] == nil else { return false }
        // 铁律第一步：同步读权限现态
        var permission = DevicePermissions.currentStates()[
            dataset.sourceID
        ] ?? .notDetermined
        if permission == .notDetermined {
            // 真未决定才发那一次请求（请求口内自判）
            permission = await DevicePermissions.requestAccess(
                for: dataset.sourceID
            )
        }
        await reportStateIfChanged(
            dataset: dataset, permission: permission, config: config
        )
        guard permission.isUsable else {
            lastErrors[dataset] = permission == .restricted
                ? "这件被系统限制住了（家长控制等），同步不了"
                : "系统权限还没给这一件，去上方开启后再同步"
            return false
        }
        guard isSyncEnabled(dataset) else {
            lastErrors[dataset] = "这一件的同步开关还没开"
            return false
        }
        guard let dispatcher else {
            lastErrors[dataset] = "设备通道还没准备好，稍后再试"
            return false
        }
        progress[dataset] = "正在读取手机上的清单…"
        defer { progress[dataset] = nil }
        do {
            let result = try await assemble(
                dataset: dataset, config: config,
                dispatcher: dispatcher
            )
            let completedAt = Date()
            let batchId = UUID().uuidString
            try await uploadBatches(
                config: config, dataset: dataset, batchId: batchId,
                records: result.records, mode: result.mode
            )
            let reply = try await client.syncComplete(
                config: config, dataset: dataset, batchId: batchId,
                expectedTotal: result.records.count,
                deviceCompletedAt: completedAt, mode: result.mode,
                coverage: result.coverage, aggregates: result.aggregates,
                removedIds: result.removedIds,
                authRange: Self.authRange(
                    for: dataset, permission: permission
                ),
                rangeNote: Self.rangeNote(
                    for: dataset, permission: permission
                ),
                // 同步成功即「可用」：显式上报清掉桥
                // 侧可能残留的撤销标记
                permissionState: "granted"
            )
            let receipt = DevicePreferences.SyncReceipt(
                count: reply.totalInStore,
                syncedAt: (reply.syncedAt ?? completedAt)
                    .timeIntervalSince1970,
                authRange: reply.authRange ?? Self.authRange(
                    for: dataset, permission: permission
                )
            )
            receipts[dataset] = receipt
            DevicePreferences.setSyncReceipt(receipt, for: dataset)
            DevicePreferences.setSyncLastReported(
                permission: "granted", range: receipt.authRange,
                for: dataset
            )
            if dataset == .contacts {
                DevicePreferences.setContactsForceFull(false)
            }
            lastErrors[dataset] = nil
            await refreshStatus(config: config)
            return true
        } catch let error as DeviceBridgeError {
            lastErrors[dataset] = Self.humanError(error)
            return false
        } catch {
            lastErrors[dataset] =
                "同步没成：\(error.localizedDescription)；服务器上的副本还是上一份"
            return false
        }
    }

    private static func humanError(_ error: DeviceBridgeError)
        -> String
    {
        switch error {
        case .noKey:
            return "还没填登录密钥，连不上自己的服务器"
        case .badEndpoint:
            return "服务器地址不对，同步不了"
        case .failed(let detail) where detail == "sync_count_mismatch":
            return "这一批条数对不上，桥没有收；服务器上的副本还是上一份，下次同步会从头重来"
        case .failed(let detail):
            return "同步没成（\(detail)）；服务器上的副本还是上一份"
        }
    }

    // MARK: - 组装（逐数据集的同步策略落点）

    private struct Assembled {
        let records: [[String: JSONValue]]
        let mode: String
        let coverage: [String: JSONValue]?
        let aggregates: [String: JSONValue]?
        let removedIds: [String]?
    }

    /// 逐件组装待传记录（策略对照规格 §4）：
    /// 通讯录＝清单比对增量（副本空/范围变→整本）；
    /// 日历＝窗口整换；提醒＝未完成全量＋聚合；
    /// 照片＝整本索引；步数＝近 7 天按日（合并）
    private func assemble(
        dataset: DeviceSyncDataset, config: ServerConfig,
        dispatcher: DeviceToolDispatcher
    ) async throws -> Assembled {
        switch dataset {
        case .contacts:
            let snapshot = try dispatcher.contacts.syncSnapshot()
            progress[.contacts] = "正在和服务器上的副本比对清单…"
            let manifest = try await client.syncManifest(
                config: config, entries: snapshot.entries
            )
            if manifest.currentTotal == 0
                || DevicePreferences.contactsForceFull()
            {
                // 副本为空或授权范围变了：整本传
                return Assembled(
                    records: snapshot.records.map(\.json),
                    mode: "full", coverage: nil, aggregates: nil,
                    removedIds: nil
                )
            }
            let changed = Set(manifest.changed)
            let delta = snapshot.records.filter {
                changed.contains($0.id)
            }
            return Assembled(
                records: delta.map(\.json), mode: "incremental",
                coverage: nil, aggregates: nil,
                removedIds: manifest.removed
            )
        case .calendar:
            let bounds = SyncCalendarWindow.bounds(now: Date())
            let records = dispatcher.events.syncOccurrences(
                from: bounds.start, to: bounds.end
            )
            return Assembled(
                records: records.map(\.json), mode: "full",
                coverage: [
                    "start": .string(DeviceISO8601.format(bounds.start)),
                    "end": .string(DeviceISO8601.format(bounds.end)),
                ],
                aggregates: nil, removedIds: nil
            )
        case .reminders:
            let snapshot = await dispatcher.events
                .reminderSyncSnapshot()
            return Assembled(
                records: snapshot.records.map(\.json), mode: "full",
                coverage: nil,
                aggregates: snapshot.aggregates.json,
                removedIds: nil
            )
        case .photos:
            let records = photosEngine.collectRecords()
            return Assembled(
                records: records.map(\.json), mode: "full",
                coverage: nil, aggregates: nil, removedIds: nil
            )
        case .motion:
            let records = await motionEngine.recentDays()
            return Assembled(
                records: records.map(\.json), mode: "merge",
                coverage: nil, aggregates: nil, removedIds: nil
            )
        }
    }

    /// 分批暂存（批大小走 Core 的 SyncBatchPlan；
    /// 条数为 0 也发一个空批次先登记，complete 才
    /// 有批次可核）
    private func uploadBatches(
        config: ServerConfig, dataset: DeviceSyncDataset,
        batchId: String, records: [[String: JSONValue]],
        mode: String
    ) async throws {
        var sent = 0
        for range in SyncBatchPlan.ranges(total: records.count) {
            let slice = Array(records[range])
            _ = try await client.syncBatch(
                config: config, dataset: dataset, batchId: batchId,
                records: slice, mode: mode
            )
            sent += slice.count
            if records.count > SyncBatchPlan.batchSize {
                progress[dataset] =
                    "已送 \(sent) / \(records.count) \(dataset.countUnit)"
            }
        }
    }

    // MARK: - 状态上报（停供/重灌的触发面）

    /// 权限或范围与上次上报不同才打桥：撤销→桥把
    /// 该件标停供（查库工具只回状态错误）；范围变化
    /// （含受限↔完整互转）→桥回 reimport_required，
    /// 通讯录落本地标记、下轮整本重灌
    private func reportStateIfChanged(
        dataset: DeviceSyncDataset,
        permission: DevicePermissionState,
        config: ServerConfig
    ) async {
        let range = Self.authRange(for: dataset, permission: permission)
        let reported = permission.isUsable ? "granted" : "revoked"
        let last = DevicePreferences.syncLastReported(for: dataset)
        // 从没可用过、也没上报过：没有副本可停供，
        // 不拿「撤销」噪音打桥
        guard permission.isUsable || last != nil else { return }
        if last?.permission == reported, last?.range == range {
            return
        }
        guard let reimport = try? await client.syncReportState(
            config: config, dataset: dataset,
            permissionState: reported, authRange: range,
            rangeNote: Self.rangeNote(
                for: dataset, permission: permission
            )
        ) else { return }
        DevicePreferences.setSyncLastReported(
            permission: reported, range: range, for: dataset
        )
        if reimport, dataset == .contacts {
            DevicePreferences.setContactsForceFull(true)
        }
    }

    // MARK: - 删除副本

    /// 删单件副本（手机数据/权限/配对都不动；开关
    /// 还开着的话，下次打开 App 会重新同步回来）
    @discardableResult
    func deleteCopy(
        _ dataset: DeviceSyncDataset, config: ServerConfig?
    ) async -> Bool {
        guard let config else { return false }
        guard (try? await client.syncDelete(
            config: config, dataset: dataset
        )) != nil else { return false }
        clearReceipt(dataset)
        await refreshStatus(config: config)
        return true
    }

    /// 删全部五件副本（总览页入口）
    @discardableResult
    func deleteAllCopies(config: ServerConfig?) async -> Bool {
        guard let config else { return false }
        guard (try? await client.syncDelete(
            config: config, dataset: nil
        )) != nil else { return false }
        for dataset in DeviceSyncDataset.allCases {
            clearReceipt(dataset)
        }
        await refreshStatus(config: config)
        return true
    }

    // MARK: - 范围口径

    /// 授权范围：只有通讯录/照片有「部分」形态（系
    /// 统受限授权＝用户勾选子集），余件完整
    static func authRange(
        for dataset: DeviceSyncDataset,
        permission: DevicePermissionState
    ) -> String {
        switch dataset {
        case .contacts, .photos:
            return permission == .limited ? "limited" : "full"
        case .calendar, .reminders, .motion:
            return "full"
        }
    }

    static func rangeNote(
        for dataset: DeviceSyncDataset,
        permission: DevicePermissionState
    ) -> String? {
        guard permission == .limited else { return nil }
        switch dataset {
        case .contacts:
            return "这是用户在系统里勾选的部分联系人，不是全部"
        case .photos:
            return "这是用户在系统里勾选的部分照片，不是全部"
        case .calendar, .reminders, .motion:
            return nil
        }
    }
}
