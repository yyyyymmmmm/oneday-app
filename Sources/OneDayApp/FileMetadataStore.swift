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

    func recordDownload(path: String, byteCount: Int) {
        record(path: path, size: Int64(byteCount), modifiedAt: nil)
    }

    /// 父目录列表回读回填：同目录只并发一轮，整目录
    /// 兄弟条目一并入账（列表本就带 size/mtime）；
    /// 失败静默（副行保持只显类型）
    func backfillFromListing(path: String, appState: AppState) async {
        if byPath[path]?.size != nil { return }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return }
        guard listingInFlight.insert(parent).inserted else { return }
        defer { listingInFlight.remove(parent) }
        guard let listing = try? await appState.performAdmin({
            client, config in
            try await client.files(config: config, path: parent)
        }) else { return }
        for entry in listing.entries where !entry.isDirectory {
            record(
                path: entry.path, size: entry.size,
                modifiedAt: entry.modifiedAt
            )
        }
    }
}
