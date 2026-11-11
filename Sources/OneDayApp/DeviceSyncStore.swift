import Foundation
import OneDayCore

/// 同步制偏好（0.36.14）：本地回执 / 最近上报的权
/// 限与范围 / 同步日志。回执只是状态行的兜底，真
/// 状态以桥 status 为准（桥取不到时才用回执拼新
/// 鲜度行）。0.36.18 起不再有同步开关与说明已读标
/// 记可存——授权即自动同步，旧键留在 defaults 里
/// 不读不管（无副本数据、不必清理）
extension DevicePreferences {
    private static var defaults: UserDefaults { .standard }

    private static func syncKey(
        _ dataset: DeviceSyncDataset, _ suffix: String
    ) -> String {
        "device.sync.\(dataset.bridgeName).\(suffix)"
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

    /// 同步日志（0.36.16）：逐数据集一本，JSON 落
    /// UserDefaults；条目构造与上限在 Core 的
    /// DeviceSyncLogBook，这里只管存取
    static func syncLog(for dataset: DeviceSyncDataset)
        -> [DeviceSyncLogEntry]
    {
        guard let data = defaults.data(
            forKey: syncKey(dataset, "log")
        ) else { return [] }
        return (try? JSONDecoder().decode(
            [DeviceSyncLogEntry].self, from: data
        )) ?? []
    }

    static func setSyncLog(
        _ entries: [DeviceSyncLogEntry],
        for dataset: DeviceSyncDataset
    ) {
        guard let data = try? JSONEncoder().encode(entries)
        else { return }
        defaults.set(data, forKey: syncKey(dataset, "log"))
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

/// 同步控制器（0.36.14 立制，0.36.18 改「权限即
/// 同步」）：五数据集的状态拉取/单件同步/状态上
/// 报/副本删除/同步日志。供给与同步的唯一门是系
/// 统权限——授权即自动同步、权限关即完全停供；
/// 0.36.16 的同步开关态与镜像层整组退役，本层不
/// 再持有任何开关。自动触发三路：①回前台对账
/// ②系统变更记号（DeviceChangeWatcher）③进详情
/// 页补查。权限撤销的停供由桥据上报判定，本层保
/// 证回前台第一时间上报。授权铁律：每轮先同步读
/// 权限现态，仅未决定时走那一次请求（Device-
/// Permissions 内判）；回调隔离铁律：系统变更回
/// 调只在观察者内转手，不进本类
@MainActor
@Observable
final class DeviceSyncController {
    /// 桥 status 读到的逐件状态（真状态源）
    private(set) var statuses:
        [DeviceSyncDataset: DeviceSyncDatasetStatus] = [:]
    /// 逐件进度人话（非 nil＝正在同步）
    private(set) var progress: [DeviceSyncDataset: String] = [:]
    /// 逐件最近一次失败人话（成功即清）
    private(set) var lastErrors: [DeviceSyncDataset: String] = [:]
    /// 逐件本地回执（状态行兜底）
    private(set) var receipts:
        [DeviceSyncDataset: DevicePreferences.SyncReceipt]
    /// 逐件同步日志（新在上，与偏好同值落盘）
    private(set) var logs:
        [DeviceSyncDataset: [DeviceSyncLogEntry]] = [:]

    private let client = DeviceBridgeClient()
    let photosEngine = PhotosEngine()
    let motionEngine = MotionEngine()

    /// 由 AppState 接线（与设备会话共用同一分发器
    /// 的引擎：日历/提醒/通讯录读走它）
    var dispatcher: DeviceToolDispatcher?

    private var foregroundTask: Task<Void, Never>?
    /// 最近一次可用的服务器配置（变更记号与详情
    /// 页补查的对账目标；没连上过就没有，记号攒着
    /// 等下一次前台检查消费）
    private var lastConfig: ServerConfig?
    /// 系统变更记号（触发②）：观察者落记、防抖合
    /// 并后统一对账（日历/通讯录的编辑是连珠炮式
    /// 通知，逐条同步只会空转）
    private var pendingChanges: Set<DeviceSyncDataset> = []
    private var changeDebounceTask: Task<Void, Never>?
    private let changeWatcher = DeviceChangeWatcher()

    init() {
        var receipts: [DeviceSyncDataset: DevicePreferences.SyncReceipt]
            = [:]
        var logs: [DeviceSyncDataset: [DeviceSyncLogEntry]] = [:]
        for dataset in DeviceSyncDataset.allCases {
            if let receipt = DevicePreferences.syncReceipt(
                for: dataset
            ) {
                receipts[dataset] = receipt
            }
            logs[dataset] = DevicePreferences.syncLog(for: dataset)
        }
        self.receipts = receipts
        self.logs = logs
        changeWatcher.onChange = { [weak self] dataset in
            // 观察者保证在主队列转手，这里再按本仓
            // 观察者惯例跳回 MainActor 落记
            Task { @MainActor [weak self] in
                self?.noteExternalChange(dataset)
            }
        }
    }

    // MARK: - 同步日志（0.36.16）

    /// 落一条日志（真实事件时刻、新在上、落盘）
    func appendLog(
        _ dataset: DeviceSyncDataset, kind: DeviceSyncLogEntry.Kind,
        added: Int? = nil, total: Int? = nil, reason: String? = nil
    ) {
        let entry = DeviceSyncLogEntry(
            at: Date(), kind: kind, added: added, total: total,
            reason: reason
        )
        let updated = DeviceSyncLogBook.appending(
            logs[dataset] ?? [], entry
        )
        logs[dataset] = updated
        DevicePreferences.setSyncLog(updated, for: dataset)
    }

    /// 开权限动作第一步（先于那一次系统请求落账，
    /// 请求被拒/被打断也留痕——先落账纪律）
    func noteEnabling(_ dataset: DeviceSyncDataset) {
        appendLog(dataset, kind: .enabling)
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

    // MARK: - 自动对账（三路触发共用一副骨架）

    /// 单件对账：先上报权限与范围变化（撤销→桥停
    /// 供、范围变→下轮整本重灌），再按计划器判定要
    /// 不要真同步（节流/变更记号都在计划器里）
    private func reconcile(
        dataset: DeviceSyncDataset,
        permission: DevicePermissionState,
        config: ServerConfig, changePending: Bool
    ) async {
        await reportStateIfChanged(
            dataset: dataset, permission: permission, config: config
        )
        let decision = DeviceSyncPlanner.foregroundDecision(
            dataset: dataset,
            permissionUsable: permission.isUsable,
            lastSuccessAt: statuses[dataset]?.syncedAt
                ?? receipts[dataset].map {
                    Date(timeIntervalSince1970: $0.syncedAt)
                },
            pendingWrite: statuses[dataset]?.pendingWrite ?? false,
            changePending: changePending,
            now: Date()
        )
        if decision == .sync {
            _ = await syncNow(dataset, config: config)
        }
    }

    /// 触发①（回前台/冷启/连接就绪时调）：逐件对
    /// 账；途中攒下的变更记号一并消费。整轮串行慢
    /// 工，异步自跑不挡界面
    func foregroundCheck(config: ServerConfig?) {
        guard let config else { return }
        lastConfig = config
        foregroundTask?.cancel()
        foregroundTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatus(config: config)
            let permissions = DevicePermissions.currentStates()
            for dataset in DeviceSyncDataset.allCases {
                if Task.isCancelled { return }
                await self.reconcile(
                    dataset: dataset,
                    permission: permissions[dataset.sourceID]
                        ?? .notDetermined,
                    config: config,
                    changePending:
                        self.pendingChanges.remove(dataset) != nil
                )
            }
        }
    }

    /// 触发③（进详情页时调）：状态先刷新，再对本
    /// 件对账——数据没过期只回状态、不真跑同步
    func detailPageCheck(
        dataset: DeviceSyncDataset, config: ServerConfig?
    ) async {
        guard let config else { return }
        lastConfig = config
        await refreshStatus(config: config)
        let permission = DevicePermissions.currentStates()[
            dataset.sourceID
        ] ?? .notDetermined
        await reconcile(
            dataset: dataset, permission: permission,
            config: config,
            changePending: pendingChanges.remove(dataset) != nil
        )
    }

    /// 触发②落记：系统变更通知到手只记一笔，防抖
    /// 2.5 秒合并后统一对账（配置还没就绪就攒着，
    /// 等触发①消费）
    private func noteExternalChange(_ dataset: DeviceSyncDataset) {
        pendingChanges.insert(dataset)
        changeDebounceTask?.cancel()
        changeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled { return }
            guard let self, let config = self.lastConfig else {
                return
            }
            let marked = self.pendingChanges
            self.pendingChanges.removeAll()
            guard !marked.isEmpty else { return }
            await self.refreshStatus(config: config)
            let permissions = DevicePermissions.currentStates()
            for dataset in marked {
                await self.reconcile(
                    dataset: dataset,
                    permission: permissions[dataset.sourceID]
                        ?? .notDetermined,
                    config: config, changePending: true
                )
            }
        }
    }

    // MARK: - 单件同步

    /// 同步发起方：用户在场的（开权限后首同步/详
    /// 情页补查）门前失败要落日志；自动对账的门前
    /// 失败保持静默（不拿节流期的状态刷日志）。引
    /// 擎一旦真启动，起止成败两方都落账
    enum SyncOrigin {
        case user
        case foreground
    }

    /// 一轮同步：权限门 → 组装 → 分批暂存 → 完成
    /// 确认整批换入 → 回执＋状态刷新（0.36.18 起没
    /// 有开关门，权限是唯一门）。任一步失败：桥上
    /// 旧副本原样保留（暂存不换入），错误人话落
    /// lastErrors 并进同步日志（日志是失败的正式
    /// 出口，不再只有一行橙字）
    @discardableResult
    func syncNow(
        _ dataset: DeviceSyncDataset, config: ServerConfig?,
        origin: SyncOrigin = .foreground
    ) async -> Bool {
        guard let config else {
            lastErrors[dataset] = L10n.string("还没连上服务器，同步不了")
            if origin == .user {
                appendLog(
                    dataset, kind: .syncFailed,
                    reason: lastErrors[dataset]
                )
            }
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
                ? L10n.string("这件被系统限制住了（家长控制等），同步不了")
                : L10n.string("系统权限还没开：打开这一页上方那一个开关就能开启")
            if origin == .user {
                appendLog(
                    dataset, kind: .syncFailed,
                    reason: lastErrors[dataset]
                )
            }
            return false
        }
        guard let dispatcher else {
            lastErrors[dataset] = L10n.string("设备通道还没准备好，稍后再试")
            if origin == .user {
                appendLog(
                    dataset, kind: .syncFailed,
                    reason: lastErrors[dataset]
                )
            }
            return false
        }
        appendLog(dataset, kind: .syncStarted)
        progress[dataset] = L10n.string("正在读取手机上的清单…")
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
            // 完成落账的「新增」按总量差算：先取旧
            // 总数（桥状态优先、无则本地回执），再
            // 覆盖回执——顺序反了增量就成了 0
            let previousTotal: Int? =
                (statuses[dataset]?.synced == true)
                ? statuses[dataset]?.itemCount
                : receipts[dataset]?.count
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
            appendLog(
                dataset, kind: .syncCompleted,
                added: DeviceSyncLogBook.addedCount(
                    previousTotal: previousTotal,
                    newTotal: reply.totalInStore
                ),
                total: reply.totalInStore
            )
            await refreshStatus(config: config)
            return true
        } catch let error as DeviceBridgeError {
            lastErrors[dataset] = Self.humanError(error)
            appendLog(
                dataset, kind: .syncFailed,
                reason: lastErrors[dataset]
            )
            return false
        } catch {
            lastErrors[dataset] = L10n.format(
                "同步没成：%@；服务器上的副本还是上一份",
                error.localizedDescription
            )
            appendLog(
                dataset, kind: .syncFailed,
                reason: lastErrors[dataset]
            )
            return false
        }
    }

    private static func humanError(_ error: DeviceBridgeError)
        -> String
    {
        switch error {
        case .noKey:
            return L10n.string("还没填登录密钥，连不上自己的服务器")
        case .unauthorized:
            return L10n.string("登录密钥被服务器拒绝了，去设置里检查一次")
        case .unknownSession:
            return L10n.string("设备会话对不上，回到前台重连后再同步")
        case .failed(let detail) where detail == "sync_count_mismatch":
            return L10n.string("这一批条数对不上，没有收下；服务器上的副本还是上一份，下次同步会从头重来")
        case .failed(let detail):
            return L10n.format(
                "同步没成（%@）；服务器上的副本还是上一份", detail
            )
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
            progress[.contacts] = L10n.string("正在和服务器上的副本比对清单…")
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
                progress[dataset] = L10n.format(
                    "已送 %lld / %lld %@",
                    sent, records.count, dataset.countUnit
                )
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
        // 权限翻转落日志（0.36.16）：首次上报（last
        // 为 nil）不算翻转，不拿「恢复」噪音开账
        if let last, last.permission != reported {
            appendLog(
                dataset,
                kind: reported == "revoked"
                    ? .permissionRevoked : .permissionRestored
            )
        }
        if reimport, dataset == .contacts {
            DevicePreferences.setContactsForceFull(true)
        }
    }

    // MARK: - 删除副本

    /// 删单件副本（手机数据/权限/配对都不动；权限
    /// 还开着的话，下次打开 App 会自动同步回来）
    @discardableResult
    func deleteCopy(
        _ dataset: DeviceSyncDataset, config: ServerConfig?
    ) async -> Bool {
        guard let config else { return false }
        guard (try? await client.syncDelete(
            config: config, dataset: dataset
        )) != nil else { return false }
        clearReceipt(dataset)
        appendLog(dataset, kind: .copyDeleted)
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
            appendLog(dataset, kind: .copyDeleted)
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
            return L10n.string("这是用户在系统里勾选的部分联系人，不是全部")
        case .photos:
            return L10n.string("这是用户在系统里勾选的部分照片，不是全部")
        case .calendar, .reminders, .motion:
            return nil
        }
    }
}
