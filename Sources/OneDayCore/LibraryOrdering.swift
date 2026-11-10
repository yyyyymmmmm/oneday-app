import Foundation

/// 文件页（资料库面）显示方式（0.36.31，文件页 v2 规
/// 格 §4.2）：页级状态、两段共用、宿主持久化。rawValue
/// 即落盘键值，改名等于清掉用户既有偏好，不许随手改。
public enum LibraryDisplayMode: String, CaseIterable, Sendable {
    case list
    case grid

    public var label: String {
        switch self {
        case .list: return "显示为列表"
        case .grid: return "以网格显示"
        }
    }
}

/// 文件页排序三义（规格 §4.2/§1.4，照 Muse iOS 实拍
/// 菜单）：上次打开（默认）/上次修改/标题。对号规则在
/// 宿主菜单层（每组单选、当前项占对号列）。
public enum LibrarySort: String, CaseIterable, Sendable {
    case lastOpened
    case lastModified
    case title

    public var label: String {
        switch self {
        case .lastOpened: return "上次打开"
        case .lastModified: return "上次修改"
        case .title: return "标题"
        }
    }
}

/// 资料库排序与「最近」分组（纯函数）：上次打开的时
/// 刻来自宿主本地记录表（FileOpenHistory，path→epoch
/// 秒）；服务端条目只有 mtime，没有打开时间——从未打
/// 开过的条目在「上次打开」序里以 mtime 兜底排位（新
/// 文件不至于沉底消失），同刻再以标题兜底保稳定。
public enum LibraryOrdering {
    /// 「最近」时间窗：7 天（OneDay 自有落值，规格 §4.5
    /// 明示不冒充 Muse 判定）
    public static let recentWindow: TimeInterval = 7 * 24 * 3600

    public static func sorted(
        _ entries: [WorkspaceFileEntry],
        by sort: LibrarySort,
        openedAt: [String: TimeInterval]
    ) -> [WorkspaceFileEntry] {
        entries.sorted { a, b in
            switch sort {
            case .lastOpened:
                let ao = openedAt[a.path] ?? 0
                let bo = openedAt[b.path] ?? 0
                if ao != bo { return ao > bo }
                let am = a.mtime ?? 0
                let bm = b.mtime ?? 0
                if am != bm { return am > bm }
            case .lastModified:
                let am = a.mtime ?? 0
                let bm = b.mtime ?? 0
                if am != bm { return am > bm }
            case .title:
                break
            }
            return DeliverableFileType.displayTitle(forFileName: a.name)
                .localizedStandardCompare(
                    DeliverableFileType.displayTitle(forFileName: b.name)
                ) == .orderedAscending
        }
    }

    /// 最近判定：7 天内被打开过或被修改过，任一成立
    public static func isRecent(
        entry: WorkspaceFileEntry,
        openedAt: [String: TimeInterval],
        now: Date
    ) -> Bool {
        let cutoff = now.timeIntervalSince1970 - recentWindow
        if let opened = openedAt[entry.path], opened >= cutoff {
            return true
        }
        if let mtime = entry.mtime, mtime >= cutoff {
            return true
        }
        return false
    }

    /// 网格分组（规格 §4.5）：已排序条目切「最近/全部」
    /// 两段；没有最近条目、或全部都是最近条目时回单组
    /// 无题（不摆空组、不摆只有一组的假分组）。列表态
    /// 与标题序不分组，由宿主决定不调用本函数。
    public struct Section: Equatable, Sendable {
        public let title: String?
        public let entries: [WorkspaceFileEntry]

        public init(title: String?, entries: [WorkspaceFileEntry]) {
            self.title = title
            self.entries = entries
        }
    }

    public static func grouped(
        _ sortedEntries: [WorkspaceFileEntry],
        openedAt: [String: TimeInterval],
        now: Date
    ) -> [Section] {
        let recent = sortedEntries.filter {
            isRecent(entry: $0, openedAt: openedAt, now: now)
        }
        guard !recent.isEmpty, recent.count < sortedEntries.count
        else {
            return [Section(title: nil, entries: sortedEntries)]
        }
        let recentPaths = Set(recent.map(\.path))
        let rest = sortedEntries.filter {
            !recentPaths.contains($0.path)
        }
        return [
            Section(title: "最近", entries: recent),
            Section(title: "全部", entries: rest),
        ]
    }
}

/// 上次打开记录表（0.36.31 §三/§4.3）：path→最近打开
/// 时刻（epoch 秒）的纯值表，宿主持久化进 UserDefaults
/// （JSON）。与聊天双账切割声明（规格 §六）：它只是排
/// 序辅助、丢了不伤数据，不构成第二真源；仅本机有效，
/// 换机清零、多端不一致，与 Muse 账户级真源的差距
/// 如实存在。
public struct FileOpenHistory: Equatable, Sendable {
    public private(set) var openedAtByPath: [String: TimeInterval]

    public init(openedAtByPath: [String: TimeInterval] = [:]) {
        self.openedAtByPath = openedAtByPath
    }

    public mutating func record(path: String, at date: Date) {
        openedAtByPath[path] = date.timeIntervalSince1970
    }

    public func lastOpened(path: String) -> Date? {
        openedAtByPath[path].map {
            Date(timeIntervalSince1970: $0)
        }
    }

    public func serialized() -> Data? {
        try? JSONEncoder().encode(openedAtByPath)
    }

    public static func deserialize(_ data: Data?) -> FileOpenHistory {
        guard let data,
              let table = try? JSONDecoder().decode(
                  [String: TimeInterval].self, from: data
              )
        else { return FileOpenHistory() }
        return FileOpenHistory(openedAtByPath: table)
    }
}
