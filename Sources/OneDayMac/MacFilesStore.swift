import Foundation
import Observation
import OneDayCore

/// 打开历史一条（本机账，与 iOS FileOpenHistoryStore
/// 同义：只记路径/名/时刻，不存文件内容）
struct MacFileOpenRecord: Codable, Equatable, Identifiable {
    let path: String
    let name: String
    let at: Double

    var id: String { path }
}

/// 文件库状态店（棒 3，对位 #5/#37/#38）：聚合读面
/// 消费单流；置顶与打开历史是本机账（UserDefaults，
/// 与 iOS FilePinStore/FileOpenHistoryStore 同口径）；
/// 文件字节经网关下载口取，落本机缓存目录供预览/
/// 打开/导出三路共用。
@MainActor
@Observable
final class MacFilesStore {
    private(set) var items: [FileLibraryItem] = []
    private(set) var loading = false
    private(set) var loaded = false
    var loadError: String?
    var actionNote: String?

    private(set) var pins: Set<String> = []
    private(set) var history: [MacFileOpenRecord] = []

    private let pinsKey = "mac.filePins.v1"
    private let historyKey = "mac.fileHistory.v1"
    private let historyLimit = 30

    init() {
        pins = Set(
            UserDefaults.standard.stringArray(forKey: pinsKey) ?? []
        )
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode(
               [MacFileOpenRecord].self, from: data
           ) {
            history = decoded
        }
    }

    var pinnedItems: [FileLibraryItem] {
        items.filter { pins.contains($0.entry.path) }
    }

    func refresh(session: SessionStore) async {
        guard !loading else { return }
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            items = []
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let page = try await session.chatClient.fileLibrary(
                config: config, apiKey: key
            )
            items = page.items
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = "文件库加载失败"
        }
        loaded = true
    }

    // MARK: - 置顶（本机账）

    func isPinned(_ path: String) -> Bool { pins.contains(path) }

    func togglePin(_ path: String) {
        if pins.contains(path) {
            pins.remove(path)
        } else {
            pins.insert(path)
        }
        UserDefaults.standard.set(
            Array(pins), forKey: pinsKey
        )
    }

    // MARK: - 打开历史（本机账）

    func recordOpen(_ item: FileLibraryItem) {
        history.removeAll { $0.path == item.entry.path }
        history.insert(
            MacFileOpenRecord(
                path: item.entry.path, name: item.entry.name,
                at: Date().timeIntervalSince1970
            ),
            at: 0
        )
        history = Array(history.prefix(historyLimit))
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    // MARK: - 字节落盘（预览/打开/导出共用）

    /// 下载到本机缓存（按路径＋修改时刻命名，命中同
    /// 版本直接复用）；失败原样上抛，详情面走兜底面
    func localCopy(
        session: SessionStore, item: FileLibraryItem
    ) async throws -> URL {
        guard let config = session.config, let key = session.apiKey
        else { throw HermesError.apiKeyRejected }
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneDayMacFiles", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true
        )
        let stamp = item.entry.mtime.map { String(Int($0)) } ?? "0"
        let safeName = "\(stamp)-\(item.entry.name)"
        let target = cacheDir.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        let data = try await session.chatClient.fileDownload(
            config: config, apiKey: key, path: item.entry.path
        )
        try data.write(to: target, options: .atomic)
        return target
    }
}
