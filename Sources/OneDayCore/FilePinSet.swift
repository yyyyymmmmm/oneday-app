import Foundation

/// 置顶文件集（§131 对齐包，D8）：path 集合的纯值
/// 表，宿主持久化进 UserDefaults（JSON 数组）。语
/// 义与 Muse 的 Pin 对齐——纯客户端整理：置顶只
/// 决定文件页的呈现次序（LibraryOrdering 的 pinned
/// 入参），不分享、不发布、不改变服务器上任何状
/// 态；仅本机有效、丢了不伤数据（与 FileOpenHis-
/// tory 同切割声明）。重命名时由宿主调 renamed 保
/// 置顶跟随新路径，不静默丢失。
public struct FilePinSet: Equatable, Sendable {
    public private(set) var paths: Set<String>

    public init(paths: Set<String> = []) {
        self.paths = paths
    }

    public func contains(path: String) -> Bool {
        paths.contains(path)
    }

    public mutating func setPinned(_ pinned: Bool, path: String) {
        if pinned {
            paths.insert(path)
        } else {
            paths.remove(path)
        }
    }

    /// 切换并返回切换后的状态
    @discardableResult
    public mutating func toggle(path: String) -> Bool {
        let next = !paths.contains(path)
        setPinned(next, path: path)
        return next
    }

    /// 文件改名后置顶跟随：旧路径在集内才迁移，同名
    /// （from == to）不动
    public mutating func renamed(from oldPath: String, to newPath: String) {
        guard oldPath != newPath, paths.remove(oldPath) != nil else {
            return
        }
        paths.insert(newPath)
    }

    /// 删除后清理：路径已不存在时置顶项随之消亡，
    /// 不留指向空文件的呈现指令
    public mutating func removed(path: String) {
        paths.remove(path)
    }

    public func serialized() -> Data? {
        try? JSONEncoder().encode(paths.sorted())
    }

    public static func deserialize(_ data: Data?) -> FilePinSet {
        guard let data,
              let list = try? JSONDecoder().decode(
                  [String].self, from: data
              )
        else { return FilePinSet() }
        return FilePinSet(paths: Set(list))
    }
}
