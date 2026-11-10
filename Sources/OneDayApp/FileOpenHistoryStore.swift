import Foundation
import OneDayCore

/// 上次打开记录的宿主持久化（0.36.31，文件页 v2
/// §4.3）：纯值表 FileOpenHistory 落 UserDefaults
/// （JSON），打开动作即记即存。仅本机有效——排序辅
/// 助而已，丢了不伤数据（规格 §六切割声明）。
@MainActor
@Observable
final class FileOpenHistoryStore {
    private(set) var history: FileOpenHistory

    private static let defaultsKey = "files.openHistory.v1"

    init() {
        history = FileOpenHistory.deserialize(
            UserDefaults.standard.data(forKey: Self.defaultsKey)
        )
    }

    func record(path: String) {
        history.record(path: path, at: Date())
        if let data = history.serialized() {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// 排序入口（Core LibraryOrdering 的 openedAt 形态）
    var openedAtMap: [String: TimeInterval] {
        history.openedAtByPath
    }
}
