import Foundation
import OneDayCore

/// 文件元数据缓存（§125）：文件牌与打开页的「类型 ·
/// 大小」副行需要字节数，但聊天条目只存路径——大小
/// 只许来自实测回填，不许编造。回填三路：①发送回
/// 填点记本地字节数；②打开/下载完成记实际字节数；
/// ③父目录列表回读（WorkspaceFileEntry 带 size，
/// 失败静默）。三路都拿不到时副行只显类型、打开页
/// 内再补全。进程内缓存（ServerImageCache 先例），
/// 不落盘、不冒充服务端真源。
///
/// §127（D1 大小前移）：卡片可见即回读走 ensure-
/// Size——旧 backfillFromListing 首试失败即静默放
/// 弃，冷启动/通道未就绪时首试必败、大小要等打开
/// 页再试才补（对差表 D1 的「首见常缺」成因）。现
/// 改：失败按父目录留痕＋冷却（FileBackfillPolicy
/// 单源），ensureSize 在卡可见周期内递增间隔重试
/// 至多 3 试；同目录仍只并发一轮、整目录一并入账，
/// 不逐卡单发；三试皆败保持只显类型、不编造。
@MainActor
@Observable
final class FileMetadataStore {
    static let shared = FileMetadataStore()

    struct Metadata: Equatable {
        var size: Int64?
        var modifiedAt: Date?
    }

    private(set) var byPath: [String: Metadata] = [:]
    @ObservationIgnored private var listingInFlight: Set<String> = []
    /// 父目录 → 最近一次列表回读失败时刻（冷却判定
    /// 与重试节奏的宿主持久状态，判定走 Core 表）
    @ObservationIgnored private var listingFailedAt: [String: Date] = [:]

    func metadata(for path: String) -> Metadata? {
        byPath[path]
    }

    /// 合并记录：只收非空值，后到不覆盖已有实测
    func record(path: String, size: Int64?, modifiedAt: Date?) {
        guard size != nil || modifiedAt != nil else { return }
        var entry = byPath[path] ?? Metadata()
        if let size { entry.size = size }
        if let modifiedAt { entry.modifiedAt = modifiedAt }
        byPath[path] = entry
    }

    func recordDownload(path: String, byteCount: Int) {
        record(path: path, size: Int64(byteCount), modifiedAt: nil)
    }

    /// 改名/删除后清账：旧路径的实测不许再喂给同名
    /// 新文件（改名由调用方随后 record 新路径）
    func forget(path: String) {
        byPath[path] = nil
    }

    /// 父目录列表回读回填：同目录只并发一轮，整目录
    /// 兄弟条目一并入账（列表本就带 size/mtime）。
    /// 返回该路径大小是否已到手：已到手/本轮回读命
    /// 中回 true；失败（留痕进冷却）、同目录在飞、列
    /// 表里没有它回 false——ensureSize 据此决定是否
    /// 隔时再试。旧调用方（打开页）不看返回值，行为
    /// 与旧版一致（失败静默、副行保持只显类型）
    @discardableResult
    func backfillFromListing(path: String, appState: AppState) async -> Bool {
        if byPath[path]?.size != nil { return true }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return false }
        // 冷却内不发网络：通道未就绪时同目录几十张卡
        // 同屏，逐卡重试是无谓轰击（FileBackfillPolicy）
        if FileBackfillPolicy.isCoolingDown(
            lastFailureAt: listingFailedAt[parent], now: Date()
        ) { return false }
        guard listingInFlight.insert(parent).inserted else { return false }
        defer { listingInFlight.remove(parent) }
        guard let listing = try? await appState.performAdmin({
            client, config in
            try await client.files(config: config, path: parent)
        }) else {
            listingFailedAt[parent] = Date()
            return false
        }
        listingFailedAt[parent] = nil
        for entry in listing.entries where !entry.isDirectory {
            record(
                path: entry.path, size: entry.size,
                modifiedAt: entry.modifiedAt
            )
        }
        return byPath[path]?.size != nil
    }

    /// 卡面回读入口（§127）：卡片/打开页可见时调用，
    /// 按 FileBackfillPolicy 递增间隔重试至多 max-
    /// Attempts 试；视图消失任务取消即停（.task 语
    /// 义），不留后台重试尾巴。查不到保持无大小——
    /// 副行只显类型
    func ensureSize(path: String, appState: AppState) async {
        var attempt = 0
        while byPath[path]?.size == nil,
              attempt < FileBackfillPolicy.maxAttempts {
            attempt += 1
            if await backfillFromListing(path: path, appState: appState) {
                return
            }
            guard let delay = FileBackfillPolicy.delay(
                afterFailedAttempt: attempt
            ) else { return }
            do {
                try await Task.sleep(
                    for: .seconds(delay)
                )
            } catch {
                return
            }
        }
    }
}
