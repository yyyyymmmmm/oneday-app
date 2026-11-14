import Foundation

/// §233 基础正解批的 Core 地基：发送状态、待发附件
/// 的持久暂存、服务端历史分页与上传进度聚合。这里
/// 只放可单测的纯逻辑/文件逻辑；网络与 SwiftData
/// 接线在 App 层。
///
/// 成熟做法对照（详见施工报告 §1）：
/// - 待发消息先落本地队列、附件以应用自有文件引用
///   保存，进程重启后按条目 id 重建，而不是把 Data
///   塞进视图内存；
/// - 历史接口用服务端 limit/offset 分页，客户端逐
///   页落盘，不再整表一次性载入；
/// - 上传进度只认 URLSession 实际已发送字节，聚合
///   后单调递增，不用计时器伪造百分比。
public enum ChatSendState: String, Codable, CaseIterable, Equatable, Sendable {
    case queued
    case uploading
    case linking
    case sending
    case failed
    case delivered

    /// 旧字段兼容读口：新字段缺失时，依次按失败标
    /// 记、待发标记还原。两者都没有即无待发状态。
    public static func restored(
        rawValue: String?, sendFailed: Bool, deliveryState: String?
    ) -> ChatSendState? {
        if let rawValue, let state = ChatSendState(rawValue: rawValue) {
            return state
        }
        if sendFailed { return .failed }
        if deliveryState == "pending" { return .queued }
        return nil
    }

    /// 进程重启后仍应留在待发队列里的状态。`failed`
    /// 只允许用户点按重发，不自动重发；其余未落定
    /// 状态可由恢复逻辑重新接管。
    public var remainsInQueue: Bool {
        switch self {
        case .queued, .uploading, .linking, .sending, .failed:
            return true
        case .delivered:
            return false
        }
    }

    public var mayAutoResume: Bool {
        switch self {
        case .queued, .uploading, .linking:
            return true
        case .sending, .failed, .delivered:
            return false
        }
    }
}

public struct StagedSendPayload: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public struct StagedSendAttachment: Codable, Equatable, Sendable {
    public let fileName: String
    public let relativePath: String
    public let byteCount: Int

    public init(fileName: String, relativePath: String, byteCount: Int) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

public enum StagedSendAttachmentStoreError: Error, Equatable, Sendable {
    case missingFile(String)
    case byteCountMismatch(String)
}

/// 待发附件持久暂存：每个 ChatEntry 一个目录，文件
/// 本体落 Application Support，manifest.json 最后写
/// 入；重新构造一个 store 实例即可读回，模拟/等价
/// 于进程重启后的重建路径。目录只由条目 id 寻址，
/// 不把用户文件名直接当目录名。
public final class StagedSendAttachmentStore: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public static func defaultStore(
        fileManager: FileManager = .default
    ) -> StagedSendAttachmentStore {
        let base = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return StagedSendAttachmentStore(
            rootURL: base
                .appendingPathComponent("OneDay", isDirectory: true)
                .appendingPathComponent(
                    "PendingSendAttachments", isDirectory: true
                ),
            fileManager: fileManager
        )
    }

    private func entryDirectory(_ entryID: UUID) -> URL {
        rootURL.appendingPathComponent(
            entryID.uuidString, isDirectory: true
        )
    }

    private func manifestURL(_ entryID: UUID) -> URL {
        entryDirectory(entryID).appendingPathComponent("manifest.json")
    }

    /// 原子换入：先在同级临时目录写全文件与 manifest，
    /// 再替换正式目录。进程在写入中途退出时，旧的完
    /// 整暂存仍在；没有旧暂存时只会留下无 manifest
    /// 的临时目录，load 读作空，不会半条重建。
    @discardableResult
    public func stage(
        entryID: UUID, payloads: [StagedSendPayload]
    ) throws -> [StagedSendAttachment] {
        try fileManager.createDirectory(
            at: rootURL, withIntermediateDirectories: true
        )
        let finalDirectory = entryDirectory(entryID)
        let temporaryDirectory = rootURL.appendingPathComponent(
            ".\(entryID.uuidString).tmp-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: temporaryDirectory, withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        var records: [StagedSendAttachment] = []
        for (index, payload) in payloads.enumerated() {
            let safeName = (payload.name as NSString).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = safeName.isEmpty ? "attachment" : safeName
            let relativePath = String(
                format: "%04d-%@", index, fileName
            )
            let url = temporaryDirectory.appendingPathComponent(
                relativePath
            )
            try payload.data.write(to: url, options: [.atomic])
            records.append(
                StagedSendAttachment(
                    fileName: fileName,
                    relativePath: relativePath,
                    byteCount: payload.data.count
                )
            )
        }
        let manifest = try JSONEncoder().encode(records)
        try manifest.write(
            to: temporaryDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        if fileManager.fileExists(atPath: finalDirectory.path) {
            try fileManager.removeItem(at: finalDirectory)
        }
        try fileManager.moveItem(
            at: temporaryDirectory, to: finalDirectory
        )
        return records
    }

    public func manifest(
        entryID: UUID
    ) throws -> [StagedSendAttachment] {
        let url = manifestURL(entryID)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(
            [StagedSendAttachment].self, from: data
        )
    }

    /// 按 manifest 顺序重建载荷，并逐个核对字节数；
    /// 文件缺失/损坏时抛错，不许静默退化成纯文本。
    public func loadPayloads(
        entryID: UUID
    ) throws -> [StagedSendPayload] {
        let records = try manifest(entryID: entryID)
        let directory = entryDirectory(entryID)
        return try records.map { record in
            let url = directory.appendingPathComponent(
                record.relativePath
            )
            guard fileManager.fileExists(atPath: url.path) else {
                throw StagedSendAttachmentStoreError.missingFile(
                    record.fileName
                )
            }
            let data = try Data(contentsOf: url)
            guard data.count == record.byteCount else {
                throw StagedSendAttachmentStoreError.byteCountMismatch(
                    record.fileName
                )
            }
            return StagedSendPayload(name: record.fileName, data: data)
        }
    }

    /// 失败条目复制到线程末尾重发时，暂存随新条目
    /// id 转移；旧 id 不再保留同一批文件。
    public func transfer(
        from sourceID: UUID, to destinationID: UUID
    ) throws {
        guard sourceID != destinationID else { return }
        let source = entryDirectory(sourceID)
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        let destination = entryDirectory(destinationID)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(
            at: rootURL, withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: source, to: destination)
    }

    public func remove(entryID: UUID) throws {
        let directory = entryDirectory(entryID)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    /// 清掉已不存在的条目留下的暂存。只按调用方给
    /// 的现存 id 集合清理，不扫描/猜测其他目录。
    public func prune(keeping validEntryIDs: Set<UUID>) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }
        let children = try fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        )
        for child in children {
            guard let id = UUID(uuidString: child.lastPathComponent),
                  !validEntryIDs.contains(id) else {
                continue
            }
            try fileManager.removeItem(at: child)
        }
    }
}

/// 服务端会话历史分页计划。Hermes 0.23 官方
/// OpenAPI 已冻结 `/messages` 的 limit/offset/order
/// 参数；客户端按 desc 取最新页，再把每页按消息 id
/// 升序落盘，offset 只前进、不整表回拉。
public enum SessionHistoryPagePlanner {
    public static let pageSize = 100

    public static func nextOffset(
        currentOffset: Int, receivedCount: Int, pageSize: Int = pageSize
    ) -> Int? {
        guard receivedCount >= pageSize, pageSize > 0 else {
            return nil
        }
        return currentOffset + receivedCount
    }

    public static func chronological(
        _ messages: [SessionMessage]
    ) -> [SessionMessage] {
        messages.sorted { $0.id < $1.id }
    }

    public static func unseen(
        _ messages: [SessionMessage], seenIDs: Set<Double>
    ) -> [SessionMessage] {
        messages.filter { !seenIDs.contains($0.id) }
    }
}

/// 多文件上传的真实进度聚合：已完成文件字节数 +
/// 当前文件由 URLSession 回报的已发送比例。聚合值
/// 只前进不后退，避免多文件切换时百分比跳水。
public struct UploadProgressAggregator: Equatable, Sendable {
    public let totalBytes: Int
    private var completedBytes: Int = 0
    private var currentFileBytes: Int = 0
    private var currentFileFraction: Double = 0
    private var peak: Double = 0

    public init(fileSizes: [Int]) {
        totalBytes = fileSizes.reduce(0) { $0 + max(0, $1) }
    }

    public mutating func beginFile(size: Int) {
        currentFileBytes = max(0, size)
        currentFileFraction = 0
    }

    @discardableResult
    public mutating func updateCurrentFile(fraction: Double) -> Double {
        currentFileFraction = min(1, max(0, fraction))
        peak = max(peak, rawFraction)
        return peak
    }

    @discardableResult
    public mutating func finishCurrentFile() -> Double {
        completedBytes += currentFileBytes
        currentFileBytes = 0
        currentFileFraction = 0
        peak = max(peak, rawFraction)
        return peak
    }

    private var rawFraction: Double {
        guard totalBytes > 0 else { return 0 }
        let raw = (
            Double(completedBytes)
                + Double(currentFileBytes) * currentFileFraction
        ) / Double(totalBytes)
        return min(1, max(0, raw))
    }

    public var fractionCompleted: Double {
        max(peak, rawFraction)
    }
}

/// §233 P7：进度聚合的线程安全外壳——URLSession
/// 的进度回调在会话队列触发，与主线程的开始/收尾
/// 记账并发，聚合值本体是值类型，靠锁串行化读写；
/// 回调方拿到的是某一刻的聚合比例，只报数不决策。
public final class UploadProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var aggregator: UploadProgressAggregator

    public init(fileSizes: [Int]) {
        aggregator = UploadProgressAggregator(fileSizes: fileSizes)
    }

    public func beginFile(size: Int) {
        lock.lock()
        defer { lock.unlock() }
        aggregator.beginFile(size: size)
    }

    @discardableResult
    public func updateCurrentFile(fraction: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return aggregator.updateCurrentFile(fraction: fraction)
    }

    @discardableResult
    public func finishCurrentFile() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return aggregator.finishCurrentFile()
    }

    public var fractionCompleted: Double {
        lock.lock()
        defer { lock.unlock() }
        return aggregator.fractionCompleted
    }
}
