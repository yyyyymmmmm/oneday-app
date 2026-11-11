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
/// §129 扩：存在性账（助手侧文件牌的渲染门）——
/// 与元数据同源（父目录列表一趟既回填大小、又判
/// 存在），口径见 existence/verifyExistence。
@MainActor
@Observable
final class FileMetadataStore {
    static let shared = FileMetadataStore()

    struct Metadata: Equatable {
        var size: Int64?
        var modifiedAt: Date?
    }

    /// 存在性判定（§129）：exists/missing 只来自一
    /// 次成功的父目录列表（列表里有＝在、列表成功
    /// 但没它＝不在）；unverified＝查过但没查成
    /// （网络/登录态等），**不等于不存在**——渲染
    /// 层按纯文本处理但不许下「文件已不在」的结论，
    /// 下次出现时可重查（只有 exists/missing 是终局
    /// 缓存）。账未落（nil）＝还没查。
    enum Existence: Equatable {
        case exists
        case missing
        case unverified
    }

    private(set) var byPath: [String: Metadata] = [:]
    private(set) var existenceByPath: [String: Existence] = [:]
    @ObservationIgnored private var listingInFlight: Set<String> = []
    @ObservationIgnored private var verifyInFlight: Set<String> = []

    func metadata(for path: String) -> Metadata? {
        byPath[path]
    }

    func existence(for path: String) -> Existence? {
        existenceByPath[path]
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
    /// 失败静默（副行保持只显类型）。§129：吸收列
    /// 表时顺手把兄弟文件记进存在性账的 exists 边
    /// （同一次实测，不另发请求）
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
        absorb(listing)
    }

    /// 存在性校验（§129.2）：助手侧文件牌渲染前核
    /// 一次——exists 才成牌、missing 降纯文本、
    /// unverified 同样先按纯文本（不阻塞渲染），但
    /// 账上只记 unverified，下次出现重查，绝不把
    /// 网络故障误判成不存在。已落终局账（exists/
    /// missing）不重查；校验通道与元数据回填同源
    /// （父目录列表），整目录兄弟的 exists 顺手入
    /// 账。缓存口径：进程内、按路径记账、不落盘。
    func verifyExistence(path: String, appState: AppState) async {
        if let known = existenceByPath[path],
           known == .exists || known == .missing { return }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return }
        guard verifyInFlight.insert(path).inserted else { return }
        defer { verifyInFlight.remove(path) }
        do {
            let listing = try await appState.performAdmin {
                client, config in
                try await client.files(config: config, path: parent)
            }
            absorb(listing)
            // 列表成功且吸收后仍无此路径＝确证不在
            // （路径若是目录条目也不成文件牌，同判）
            if existenceByPath[path] != .exists {
                existenceByPath[path] = .missing
            }
        } catch {
            existenceByPath[path] = .unverified
        }
    }

    /// 吸收一次目录列表：文件条目记元数据＋存在性
    /// exists；目录条目不入账（牌只指向文件）
    private func absorb(_ listing: FilesListing) {
        for entry in listing.entries where !entry.isDirectory {
            record(
                path: entry.path, size: entry.size,
                modifiedAt: entry.modifiedAt
            )
            existenceByPath[entry.path] = .exists
        }
    }
}
