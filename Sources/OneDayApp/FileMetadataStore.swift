import Foundation
import OneDayCore

/// 文件元数据缓存（§125）：文件牌与打开页的「类型 ·
/// 大小」副行需要字节数，但聊天条目只存路径——大小
/// 只许来自实测回填，不许编造。回填两路：①发送回
/// 填点记本地字节数；②父目录列表回读（Workspace-
/// FileEntry 带 size，失败静默）。两路都拿不到时
/// 副行只显类型、打开页内再补全。进程内缓存
/// （ServerImageCache 先例），不落盘、不冒充服务
/// 端真源。
///
/// 复杂度清理（2026-11-11，审计第 6 项）：原第三
/// 路「下载回填」已砍——下载是用户动作、不兼任元
/// 数据源（打开页本来就会走②回读补上）；§127 给
/// ②加的退避状态机（3 试＋1.5s/4s 计时退避＋同目
/// 录冷却记账）已随 FileBackfillPolicy 降级为「卡
/// 面可见时查一次、失败不记账、下次露面再查」。
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

    /// 改名/删除后清账：旧路径的实测不许再喂给同名
    /// 新文件（改名由调用方随后 record 新路径）
    func forget(path: String) {
        byPath[path] = nil
    }

    /// 父目录列表回读回填：同目录只并发一轮，整目录
    /// 兄弟条目一并入账（列表本就带 size/mtime）；
    /// §129 的存在性校验与本路同路同趟（同一次列表
    /// 既回填大小、又判存在），不另发请求。返回该路
    /// 径大小是否已到手：已到手/本轮回读命中回
    /// true；失败、同目录在飞、列表里没有它回
    /// false。失败不记账（不留冷却痕），下次露面照
    /// 常再查；旧调用方（打开页）不看返回值，行为
    /// 与旧版一致（失败静默、副行保持只显类型）
    @discardableResult
    func backfillFromListing(path: String, appState: AppState) async -> Bool {
        if byPath[path]?.size != nil { return true }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return false }
        guard listingInFlight.insert(parent).inserted else { return false }
        defer { listingInFlight.remove(parent) }
        guard let listing = try? await appState.performAdmin({
            client, config in
            try await client.files(config: config, path: parent)
        }) else {
            return false
        }
        for entry in listing.entries where !entry.isDirectory {
            record(
                path: entry.path, size: entry.size,
                modifiedAt: entry.modifiedAt
            )
        }
        return byPath[path]?.size != nil
    }

    /// 卡面回读入口：卡片/打开页可见时调用，一次露
    /// 面只查一趟（FileBackfillPolicy.maxAttemptsPer-
    /// Appearance＝1）；查不到保持无大小——副行只显
    /// 类型，视图下次露面（新的 .task 周期）再查
    func ensureSize(path: String, appState: AppState) async {
        for _ in 0..<FileBackfillPolicy.maxAttemptsPerAppearance {
            if await backfillFromListing(path: path, appState: appState) {
                return
            }
        }
    }
}
