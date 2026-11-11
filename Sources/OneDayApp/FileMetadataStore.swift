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
/// §129 扩：存在性账（助手侧文件牌的渲染门）——
/// 与元数据同源（父目录列表一趟既回填大小、又判
/// 存在），口径见 existence/verifyExistence。
///
/// §131（D1 大小前移）：卡片可见即回读走 ensure-
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
    /// 父目录 → 最近一次列表回读失败时刻（冷却判定
    /// 与重试节奏的宿主持久状态，判定走 Core 表）
    @ObservationIgnored private var listingFailedAt: [String: Date] = [:]

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
    /// 与旧版一致（失败静默、副行保持只显类型）。
    /// §129：吸收列表时顺手把兄弟文件记进存在性账
    /// 的 exists 边（同一次实测，不另发请求）
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
        absorb(listing)
        return byPath[path]?.size != nil
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

    /// 卡面回读入口（§131）：卡片/打开页可见时调用，
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
