import Foundation
import OneDayCore

/// 置顶集宿主持久化（§131，D8）：纯值表 FilePinSet
/// 落 UserDefaults（JSON）。全 App 单例（打开页切
/// 换态、文件页排序共读同一份，与 FileMetadata-
/// Store.shared 同式）；仅本机有效——置顶是客户端
/// 整理，换机清零、不冒充服务端状态（规格切割声
/// 明见 Core FilePinSet）。
@MainActor
@Observable
final class FilePinStore {
    static let shared = FilePinStore()

    private(set) var pinSet: FilePinSet

    private static let defaultsKey = "files.pinned.v1"

    init() {
        pinSet = FilePinSet.deserialize(
            UserDefaults.standard.data(forKey: Self.defaultsKey)
        )
    }

    /// 排序入口（Core LibraryOrdering 的 pinned 形态）
    var pinnedPaths: Set<String> { pinSet.paths }

    func isPinned(path: String) -> Bool {
        pinSet.contains(path: path)
    }

    /// 切换置顶，返回切换后状态；即切即存
    @discardableResult
    func toggle(path: String) -> Bool {
        let state = pinSet.toggle(path: path)
        persist()
        return state
    }

    /// 改名跟随（宿主改名链成功后调用）：置顶不因改
    /// 名静默丢失
    func renamed(from oldPath: String, to newPath: String) {
        pinSet.renamed(from: oldPath, to: newPath)
        persist()
    }

    /// 删除后清理（宿主删除链成功后调用）
    func removed(path: String) {
        pinSet.removed(path: path)
        persist()
    }

    private func persist() {
        if let data = pinSet.serialized() {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
