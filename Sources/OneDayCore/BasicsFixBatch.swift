import Foundation

/// §237 基础正解批的 Core 地基：发送状态、待发附件
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
    /// 已受理（发送失败机制包·双轴语义，DESIGN 审
    /// 查 2026-11-24 第四节语义 1）：服务端 202 确
    /// 认收到——提交轴到此为止，但运行轴（生成）
    /// 未落定，条目仍在发件箱语义内（重试记账不
    /// 清、泵车道归账本管辖）。旧口径受理即标
    /// delivered 是死循环的根：delivered 的
    /// remainsInQueue=false 让条目在 run 真终态前
    /// 脱离发件箱，清账按「非发件箱」整批扫，计数
    /// 恒归零。delivered 自此只许运行轴落定成功时
    /// 置位。呈现与 delivered 同（满色、无时钟）：
    /// 已确认收到即发送成功呈现（§426 用户口径不
    /// 变），差别只在记账语义
    case accepted
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
        case .queued, .uploading, .linking, .sending,
             .accepted, .failed:
            return true
        case .delivered:
            return false
        }
    }

    public var mayAutoResume: Bool {
        switch self {
        case .queued, .uploading, .linking:
            return true
        case .sending, .accepted, .failed, .delivered:
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

    /// §410：在飞 stage 登记（stageAsync/stageDetached 的
    /// 写盘在后台任务里跑）——loadPayloads/transfer/remove
    /// 动同一条目目录前先等在飞写落定，防读到半写目录或
    /// 与原子换入相撞（旧同步 stage 无此问题：调用线程即
    /// 写者、返回时已落定）。按条目计数，同条目多次 stage
    /// 全部落定才放行
    private let stageFlightCondition = NSCondition()
    private var stageFlightCounts: [UUID: Int] = [:]

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

    /// §410：stage 的离主线程版——写盘整段走独立任务，
    /// 调用方（发送链主 actor）只等结果不付字节成本；
    /// 语义与 stage 逐项一致（原子换入、manifest 最后写）
    @discardableResult
    public func stageAsync(
        entryID: UUID, payloads: [StagedSendPayload]
    ) async throws -> [StagedSendAttachment] {
        beginStageFlight(entryID)
        return try await Task.detached(priority: .userInitiated) {
            // §410 接管修：在飞销账落写任务内——挂外层
            // defer 时调用方取消会先于写完销账、读侧提
            // 前放行；与 stageDetached 同式，写落定才销
            defer { self.endStageFlight(entryID) }
            return try self.stage(
                entryID: entryID, payloads: payloads
            )
        }.value
    }

    /// §410：即发即走版（发送链落点用）：写失败不拦发送
    /// （与旧 `try? stage` 同口径）；完成由在飞登记兜底，
    /// 读侧 loadPayloads/transfer/remove 会等它落定再动
    public func stageDetached(
        entryID: UUID, payloads: [StagedSendPayload]
    ) {
        beginStageFlight(entryID)
        Task.detached(priority: .userInitiated) {
            defer { self.endStageFlight(entryID) }
            try? self.stage(entryID: entryID, payloads: payloads)
        }
    }

    /// 该条目是否有 stage 正在后台写（§410 钉测/诊断用）
    public func stageInFlight(entryID: UUID) -> Bool {
        stageFlightCondition.lock()
        defer { stageFlightCondition.unlock() }
        return (stageFlightCounts[entryID] ?? 0) > 0
    }

    private func beginStageFlight(_ entryID: UUID) {
        stageFlightCondition.lock()
        stageFlightCounts[entryID, default: 0] += 1
        stageFlightCondition.unlock()
    }

    private func endStageFlight(_ entryID: UUID) {
        stageFlightCondition.lock()
        let remaining = (stageFlightCounts[entryID] ?? 1) - 1
        if remaining > 0 {
            stageFlightCounts[entryID] = remaining
        } else {
            stageFlightCounts.removeValue(forKey: entryID)
        }
        stageFlightCondition.broadcast()
        stageFlightCondition.unlock()
    }

    /// 读/移/删条目目录前等在飞 stage 落定（无人在飞时
    /// 立即返回）；只等同条目，不挡其他条目的读写
    private func waitForStageFlight(_ entryID: UUID) {
        stageFlightCondition.lock()
        while (stageFlightCounts[entryID] ?? 0) > 0 {
            stageFlightCondition.wait()
        }
        stageFlightCondition.unlock()
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
        waitForStageFlight(entryID)
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
        waitForStageFlight(sourceID)
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
        waitForStageFlight(entryID)
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

/// 服务端会话历史分页计划。`/messages` 分页口径
/// §331 订正：服务端（网关 8642 与面板 9119 两面）
/// 的 order 只认 oldest/latest——旧注释「OpenAPI
/// 冻结、按 desc 取页」是错误假设，desc 会被新版
/// 服务端以 400 invalid_pagination 拒（2026-11-18
/// 重装三连之三）。客户端按 latest 取最新页（页内
/// 时序），再把每页按消息 id 升序落盘，offset 只
/// 前进、不整表回拉。
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

/// §237 P7：进度聚合的线程安全外壳——URLSession
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
