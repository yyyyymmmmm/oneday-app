import Foundation
import OneDayCore

/// 聊天文件下载状态源（§452.5，学 TG ChatMessage-
/// InteractiveFileNode 的状态机本地化）：按 path 记
/// idle/downloading/ready/failed 四态，字节落
/// Caches/ChatFileCache（按 path 哈希分目录、原名落
/// 盘），ready 以「文件在盘＋已知大小时大小吻合」
/// 判定、跨会话成立。下载走 HermesClient 进度法；
/// 同 path 单飞（重复调 download 挂同一任务）；取
/// 消归 idle 不挂失败。Exyte 二期 W7 的状态圆复用
/// 本店状态，不另立第二套。
@MainActor
@Observable
final class ChatFileStore {
    static let shared = ChatFileStore()

    enum State: Equatable {
        case idle
        case downloading(received: Int64, expected: Int64)
        case ready
        case failed
    }

    private(set) var states: [String: State] = [:]
    private var tasks: [String: Task<URL, Error>] = [:]
    private var progressSeen: [String: Int64] = [:]

    private init() {}

    // MARK: 状态读

    func state(for path: String) -> State {
        if tasks[path] != nil {
            return states[path] ?? .downloading(received: 0, expected: -1)
        }
        if let recorded = states[path], recorded == .failed {
            return .failed
        }
        if localURL(for: path) != nil {
            return .ready
        }
        return .idle
    }

    /// 已落盘的本地文件（大小已知时须吻合，防半截
    /// 文件冒充 ready）
    func localURL(for path: String) -> URL? {
        let url = Self.cacheURL(for: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        if let expected = FileMetadataStore.shared
            .metadata(for: path)?.size,
           let attrs = try? fm.attributesOfItem(atPath: url.path),
           let actual = attrs[.size] as? Int64,
           actual != expected {
            return nil
        }
        return url
    }

    // MARK: 下载

    /// 单飞下载：已在飞回同一任务；成功落盘回本地
    /// URL；取消抛 CancellationError、状态归 idle
    @discardableResult
    func download(
        path: String, appState: AppState
    ) async throws -> URL {
        if let existing = tasks[path] {
            return try await existing.value
        }
        if let ready = localURL(for: path) {
            states[path] = .ready
            return ready
        }
        states[path] = .downloading(received: 0, expected: -1)
        progressSeen[path] = 0
        let task = Task<URL, Error> {
            let data = try await appState.performAdmin { client, config in
                try await client.fileDataWithProgress(
                    config: config, path: path
                ) { [weak self] received, expected in
                    Task { @MainActor [weak self] in
                        self?.noteProgress(
                            path: path,
                            received: received, expected: expected
                        )
                    }
                }
            }
            let url = Self.cacheURL(for: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        }
        tasks[path] = task
        do {
            let url = try await task.value
            tasks[path] = nil
            states[path] = .ready
            return url
        } catch is CancellationError {
            tasks[path] = nil
            states[path] = .idle
            throw CancellationError()
        } catch {
            tasks[path] = nil
            states[path] = .failed
            throw error
        }
    }

    func cancel(path: String) {
        tasks[path]?.cancel()
    }

    private func noteProgress(
        path: String, received: Int64, expected: Int64
    ) {
        // 节流：每 ≥64KB 或到满才刷新一次状态，防高频
        // 回调把卡面拖进重绘风暴
        let last = progressSeen[path] ?? 0
        guard received - last >= 65_536
                || (expected > 0 && received >= expected)
        else { return }
        progressSeen[path] = received
        if tasks[path] != nil {
            states[path] = .downloading(
                received: received, expected: expected
            )
        }
    }

    // MARK: 缓存落点

    static func cacheURL(for path: String) -> URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ChatFileCache", isDirectory: true)
        let name = (path as NSString).lastPathComponent
        return base
            .appendingPathComponent(Self.hashKey(for: path), isDirectory: true)
            .appendingPathComponent(name.isEmpty ? "file" : name)
    }

    /// path → 稳定目录键（FNV-1a 64 位十六进制，不引
    /// 加密库作目录名）
    static func hashKey(for path: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
