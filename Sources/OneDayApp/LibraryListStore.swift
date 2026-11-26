import Foundation
import OneDayCore

/// 资源库／影音名单店（§369，缓存审计 C4 包）：文件
/// 格名单的取数层——名单不再只活在视图 @State 里随
/// 视图生死（审计定性 ①③：冷启必从 nil 整表 GET、
/// 删一个文件整表重拉），改走「AppState 共享店（内
/// 存）＋落盘快照」两级：进面先以快照播种上屏（stale
/// 半边），随后恰一次全量对账、差异合并换新（reval-
/// idate 半边）；删除本地先摘行、真接口确认，成功不
/// 重拉、失败回滚原位＋人话提醒（全局纲：本地先响
/// 应、失败恢复）。呈现与滚动归 S4（§363 Library-
/// ListSnapshot 计算层语义不动），本店只治取数、两
/// 包分开记账。
///
/// 快照口径（§369.2 逐项）：
/// - 载体：Caches/LibraryListSnapshot-v1.json——可
///   重建缓存，系统清了只是退回冷拉、不伤真值；形
///   式照身份落盘缓存先例（Codable JSON＋时间戳）。
/// - 键：载荷内嵌连接配置键（ServerConfig.base-
///   String，与 CronStore／归档店／自检摘要同口
///   径）；当前键与快照键不符即弃用——快照不得跨
///   服务器／账号串用，内存名单同理（属别台的货不
///   上屏）。
/// - 失效事件：对账成功整份覆写；本地删除（成功／
///   回滚）后同步覆写；配置键变化自然失效；文件损
///   坏或解码失败按无快照处理（不崩、不冒充）。
///
/// §416（新鲜度双轨收口）：对账时机收编 Freshness-
/// Gate（§367 现行口径）——refreshIfNeeded 是读触
/// 发口（播种逐字不变、门内新鲜零请求），refresh
/// 是强制口（不经门、成功落 stamp）；改名等名单
/// 外写动作经 invalidateFreshness 失效。快照播种
/// 与差异合并语义不动，行为对拍见 Freshness-
/// Unify416Tests。
@MainActor
@Observable
final class LibraryListStore {

    /// 落盘快照载荷：条目 DTO 扁平化（不动 Core
    /// WorkspaceFileEntry 的可编码性），与 Deliver-
    /// able 逐字段对映
    struct SnapshotPayload: Codable, Equatable {
        var configKey: String
        var savedAt: Date
        var items: [Item]

        struct Item: Codable, Equatable {
            var name: String
            var path: String
            var isDirectory: Bool
            var size: Int64?
            var mtime: Double?
            var mimeType: String?
            var deliveryID: String?
            var source: String

            init(_ item: Deliverable) {
                name = item.entry.name
                path = item.entry.path
                isDirectory = item.entry.isDirectory
                size = item.entry.size
                mtime = item.entry.mtime
                mimeType = item.entry.mimeType
                deliveryID = item.entry.deliveryID
                source = item.source
            }

            var deliverable: Deliverable {
                Deliverable(
                    entry: WorkspaceFileEntry(
                        name: name, path: path,
                        isDirectory: isDirectory, size: size,
                        mtime: mtime, mimeType: mimeType,
                        deliveryID: deliveryID
                    ),
                    source: source
                )
            }
        }
    }

    /// 对账结局（视图据此维持既有 loadError 口径：
    /// 只有「无数据且失败／无配置」才给错误态）
    enum RefreshOutcome: Equatable {
        /// 拉到新名单、已差异合并并落盘
        case loaded
        /// 拉失败，保留既有名单（快照或旧集）不清屏
        case keptAfterFailure
        /// 拉失败且手里没有任何名单
        case failedNoData
        /// 无连接配置（fetch 不会被调用）
        case noConfig
        /// 已有对账在飞，本次跳过（单飞，与各店同式）
        case alreadyInFlight
        /// 读触发过门判新鲜、整轮跳过（§416）：名单
        /// 已在屏（快照或内存），视图按已载处理
        case stillFresh
    }

    /// 删除结局：失败带人话（HermesError.userMessage
    /// 优先，与视图旧口径逐字同）
    enum DeleteOutcome: Equatable {
        case success
        case failed(message: String)
    }

    /// 当前呈现名单；nil＝从未载入（视图据此分加
    /// 载／失败／空态，与旧 @State 口径同）
    private(set) var deliverables: [Deliverable]?
    /// 内存名单所属配置键。不变量：与 deliverables
    /// 同生同灭（deliverables == nil ⟺ 本值 == nil）
    private(set) var deliverablesConfigKey: String?

    /// 对账单飞守卫（.task 与上传完成回调可并发触发）
    private var isRefreshing = false

    /// 新鲜度门（§416 收编，§367 口径）：本店手写
    /// 快照冷启是 SWR 的 stale 半边，对账时机自此
    /// 归门判定——读触发过门、强制口不经门
    private var freshness = FreshnessGate(
        ttl: FreshnessGate.standardListTTL
    )
    /// 门失效代次（§416）：invalidate 自增；对账落
    /// stamp 前对账，横跨失效的轮次不落账冒充新鲜
    /// （与 SessionLedger §370 epoch 同式）
    private var freshnessEpoch = 0

    private let snapshotFileURL: URL

    nonisolated static var defaultSnapshotFileURL: URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        return caches.appendingPathComponent(
            "LibraryListSnapshot-v1.json"
        )
    }

    init(
        snapshotFileURL: URL = LibraryListStore
            .defaultSnapshotFileURL
    ) {
        self.snapshotFileURL = snapshotFileURL
    }

    // MARK: - 快照播种（stale 半边）

    /// 播种：内存无名单或名单属别台时，先清外来货、
    /// 再试以本键快照上屏。当前键为 nil（未连接）不
    /// 动现状（无从判定归属，照旧 collect 口径保留
    /// 已有名单）。同步完成、无网络——进面 .task 首
    /// 跳内调用，网络返回前名单已在屏。
    func seedFromSnapshotIfNeeded(currentConfigKey: String?) {
        guard let key = currentConfigKey else { return }
        if deliverables != nil, deliverablesConfigKey == key {
            return
        }
        if deliverablesConfigKey != key {
            deliverables = nil
            deliverablesConfigKey = nil
        }
        guard deliverables == nil,
              let payload = loadSnapshotPayload(),
              payload.configKey == key
        else { return }
        deliverables = payload.items.map(\.deliverable)
        deliverablesConfigKey = key
    }

    // MARK: - 对账（revalidate 半边）

    /// 对账（强制口）：先播种、再恰一次全量拉取；
    /// 成功差异合并换新并覆写快照，失败保留现有名
    /// 单不清屏。fetch 只在当前键非 nil 且无对账在
    /// 飞时调用。不经新鲜度门（上传落定/失败重试
    /// 走本口），成功落 stamp（§416）
    func refresh(
        currentConfigKey: String?,
        fetch: @MainActor () async throws -> [Deliverable]
    ) async -> RefreshOutcome {
        seedFromSnapshotIfNeeded(
            currentConfigKey: currentConfigKey
        )
        guard let key = currentConfigKey else {
            return .noConfig
        }
        guard !isRefreshing else { return .alreadyInFlight }
        return await performRefresh(
            key: key, now: Date(), fetch: fetch
        )
    }

    /// 对账（读触发口，§416）：播种与 refresh 逐字
    /// 同（冷启首帧先显快照的口径不变）；门内新鲜
    /// 即整轮跳过、回 .stillFresh、零请求；首拉/
    /// 过期/换服务器/失效后走对账本体全量
    func refreshIfNeeded(
        currentConfigKey: String?,
        now: Date = Date(),
        fetch: @MainActor () async throws -> [Deliverable]
    ) async -> RefreshOutcome {
        seedFromSnapshotIfNeeded(
            currentConfigKey: currentConfigKey
        )
        guard let key = currentConfigKey else {
            return .noConfig
        }
        guard !isRefreshing else { return .alreadyInFlight }
        guard !freshness.isFresh(configKey: key, now: now)
        else { return .stillFresh }
        return await performRefresh(
            key: key, now: now, fetch: fetch
        )
    }

    /// 对账本体（两口共用）：单飞＋全量拉取＋差异
    /// 合并＋落盘；成功落 freshness stamp——拉取横
    /// 跨一次 invalidateFreshness 的轮次不落账
    private func performRefresh(
        key: String, now: Date,
        fetch: @MainActor () async throws -> [Deliverable]
    ) async -> RefreshOutcome {
        isRefreshing = true
        defer { isRefreshing = false }
        let epochAtStart = freshnessEpoch
        do {
            let fresh = try await fetch()
            deliverables = Self.reconciled(
                old: deliverables, fresh: fresh
            )
            deliverablesConfigKey = key
            persistSnapshot()
            if freshnessEpoch == epochAtStart {
                freshness.stamp(configKey: key, now: now)
            }
            return .loaded
        } catch {
            return deliverables == nil
                ? .failedNoData : .keptAfterFailure
        }
    }

    /// 名单外写事件的失效口（§416）：改名等不经本
    /// 店的写动作落定后调——下一次读触发必真拉，
    /// 写后一致性优先于省请求（与 SessionLedger
    /// invalidateListFreshness 同式）
    func invalidateFreshness() {
        freshnessEpoch += 1
        freshness = FreshnessGate(
            ttl: FreshnessGate.standardListTTL
        )
    }

    /// 当某个资源库文件在服务端确证不存在（404）时，
    /// 立即从本地缓存快照摘除并失效新鲜度，避免幽灵条目残留
    func removeMissingPath(_ path: String) {
        if let current = deliverables {
            let filtered = current.filter { $0.entry.path != path }
            if filtered.count != current.count {
                deliverables = filtered
                persistSnapshot()
            }
        }
        invalidateFreshness()
    }

    /// 差异合并（纯函数）：结果与 fresh 逐项等价（同
    /// 序、同条目、同来源）；旧名单中未变的条目原值
    /// 复用，消失的丢弃、新增的采纳——换新是一次原
    /// 子替换，不经过空白态
    static func reconciled(
        old: [Deliverable]?, fresh: [Deliverable]
    ) -> [Deliverable] {
        guard let old else { return fresh }
        var oldByPath: [String: Deliverable] = [:]
        oldByPath.reserveCapacity(old.count)
        for item in old where oldByPath[item.entry.path] == nil {
            oldByPath[item.entry.path] = item
        }
        return fresh.map { item in
            if let prior = oldByPath[item.entry.path],
               prior.entry == item.entry,
               prior.source == item.source {
                return prior
            }
            return item
        }
    }

    // MARK: - 删除（本地摘行，不重拉）

    /// 删除：本地先摘行（单删／批量同口径）并同步落
    /// 盘，随后逐个走真接口删除；全部成功即定案、不
    /// 发任何名单请求；任一失败把已摘行按原位回滚、
    /// 快照同步恢复，并回人话。无名单时（查看器等旁
    /// 路）只走真接口、不做本地手术。
    func delete(
        paths: [String],
        perform: @MainActor (String) async throws -> Void
    ) async -> DeleteOutcome {
        guard !paths.isEmpty else { return .success }
        var removed: [(index: Int, item: Deliverable)] = []
        if let current = deliverables {
            let pathSet = Set(paths)
            var kept: [Deliverable] = []
            kept.reserveCapacity(current.count)
            for (index, item) in current.enumerated() {
                if pathSet.contains(item.entry.path) {
                    removed.append((index, item))
                } else {
                    kept.append(item)
                }
            }
            if !removed.isEmpty {
                deliverables = kept
                persistSnapshot()
            }
        }
        do {
            for path in paths {
                try await perform(path)
            }
            return .success
        } catch {
            if !removed.isEmpty {
                var restored = deliverables ?? []
                for (index, item) in removed {
                    restored.insert(
                        item, at: min(index, restored.count)
                    )
                }
                deliverables = restored
                persistSnapshot()
            }
            return .failed(
                message: (error as? HermesError)?.userMessage
                    ?? "删除失败，请稍后再试。"
            )
        }
    }

    // MARK: - 落盘

    private func loadSnapshotPayload() -> SnapshotPayload? {
        guard let data = try? Data(
            contentsOf: snapshotFileURL
        ) else { return nil }
        return try? JSONDecoder().decode(
            SnapshotPayload.self, from: data
        )
    }

    /// 以内存名单整份覆写快照（键＝名单所属键）；无
    /// 名单或无归属键时不动磁盘（不拿空账冒充快照）
    private func persistSnapshot() {
        guard let deliverables, let key = deliverablesConfigKey
        else { return }
        let payload = SnapshotPayload(
            configKey: key, savedAt: Date(),
            items: deliverables.map { SnapshotPayload.Item($0) }
        )
        guard let data = try? JSONEncoder().encode(payload)
        else { return }
        try? data.write(to: snapshotFileURL, options: .atomic)
    }
}
