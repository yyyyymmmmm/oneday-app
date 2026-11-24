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

    /// 落盘原值解析（文件页菜单勾选口径，样式二期
    /// S2-04）：菜单改系统 Picker 承载后勾由系统绘制，
    /// 喂 Picker 的 selection 恒经此解析——命中枚举
    /// 回它本身，未知/空/缺失回落默认档，保证任一时
    /// 刻恰一勾、不错挂（同 ModelMenuSelection 口径，
    /// 苹果反馈 FB16679936：菜单带勾正道只有
    /// Toggle/Picker）
    public static func resolved(
        rawValue: String?
    ) -> LibraryDisplayMode {
        guard let rawValue,
              let mode = Self(rawValue: rawValue)
        else { return .list }
        return mode
    }
}

/// 文件页排序三义（规格 §4.2/§1.4，照 Muse iOS 实拍
/// 菜单）：上次打开（默认）/上次修改/标题。勾选由宿
/// 主菜单的系统 Picker 承载（样式二期 S2-04：勾由系
/// 统按 selection 绘制、占固定槽；旧手工对勾塞图标
/// 位的形态已退役，见 resolved 解析口径）。
public enum LibrarySort: String, CaseIterable, Sendable {
    case lastOpened
    case lastModified
    case title
    /// 大小档（§452 资源库定版②补：排序菜单含名称/大小；
    /// 大到小、未知大小沉底，平局回标题序保稳定）
    case size

    public var label: String {
        switch self {
        case .lastOpened: return "上次打开"
        case .lastModified: return "上次修改"
        case .title: return "标题"
        case .size: return "大小"
        }
    }

    /// 落盘原值解析（同 LibraryDisplayMode.resolved
    /// 口径）：未知/空/缺失回落默认档。§452 资源库定
    /// 版②「排列最近在前」：默认档改「上次修改」（新
    /// 产生的文件天然在前；旧注「默认上次打开」就此
    /// 修订，已落盘的显式选择不受影响）
    public static func resolved(
        rawValue: String?
    ) -> LibrarySort {
        guard let rawValue,
              let option = Self(rawValue: rawValue)
        else { return .lastModified }
        return option
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

    /// pinned（§131，D8 置顶集）：非空时置顶条目整
    /// 段排在最前（段内仍按所选排序），与 Muse Pin
    /// 的「客户端置顶整理」同语义；默认空集＝旧行为
    /// 逐字不变
    public static func sorted(
        _ entries: [WorkspaceFileEntry],
        by sort: LibrarySort,
        openedAt: [String: TimeInterval],
        pinned: Set<String> = []
    ) -> [WorkspaceFileEntry] {
        // F1（手感快速项，2026-11-23）：排序键按需预
        // 计算——旧形态每次比较现算两遍 displayTitle
        // （NSString 扩名处理）＋一遍 ICU collation，
        // N=2000 标题序一趟约 37ms（审计实测）。两
        // 路落法：标题序下标题是主键、每比较必走——
        // upfront 全算入账（标题计算从约 2.2 万次降
        // 到 N 次、实测全序 36.2ms→12.3ms）；时间序
        // 下标题仅平局兜底——懒备忘（TitleKeyMemo，
        // 同条目一次排序内只算一次、无平局零计算，
        // 不为 upfront 全算白付约 1.4ms）。比较语义
        // 逐字不变：同键同较、标题较仍由 localized-
        // StandardCompare 唯一裁决（排序口味是用户
        // 待裁项，本包只降本、不改判）
        switch sort {
        case .title:
            let keyed = entries.map { entry in
                (
                    entry: entry,
                    title: DeliverableFileType.displayTitle(
                        forFileName: entry.name
                    )
                )
            }
            return keyed.sorted { a, b in
                if !pinned.isEmpty {
                    let ap = pinned.contains(a.entry.path)
                    let bp = pinned.contains(b.entry.path)
                    if ap != bp { return ap }
                }
                return a.title.localizedStandardCompare(b.title)
                    == .orderedAscending
            }.map(\.entry)
        case .size:
            let titleMemo = TitleKeyMemo()
            return entries.sorted { a, b in
                if !pinned.isEmpty {
                    let ap = pinned.contains(a.path)
                    let bp = pinned.contains(b.path)
                    if ap != bp { return ap }
                }
                let asz = a.size ?? -1
                let bsz = b.size ?? -1
                if asz != bsz { return asz > bsz }
                return titleMemo.title(for: a)
                    .localizedStandardCompare(
                        titleMemo.title(for: b)
                    ) == .orderedAscending
            }
        case .lastOpened, .lastModified:
            let titleMemo = TitleKeyMemo()
            return entries.sorted { a, b in
                if !pinned.isEmpty {
                    let ap = pinned.contains(a.path)
                    let bp = pinned.contains(b.path)
                    if ap != bp { return ap }
                }
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
                case .title, .size:
                    break
                }
                return titleMemo.title(for: a)
                    .localizedStandardCompare(
                        titleMemo.title(for: b)
                    ) == .orderedAscending
            }
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

    /// 网格分组带置顶段（§131）：入参已由 sorted 按
    /// pinned 排过（置顶在最前）——有置顶条目时先切
    /// 出「置顶」段置于一切分组之前，余下条目再走
    /// 最近/全部旧口径；无置顶时与旧 grouped 逐字
    /// 同果
    public static func grouped(
        _ sortedEntries: [WorkspaceFileEntry],
        openedAt: [String: TimeInterval],
        now: Date,
        pinned: Set<String> = []
    ) -> [Section] {
        let pinnedEntries = sortedEntries.filter {
            pinned.contains($0.path)
        }
        guard !pinnedEntries.isEmpty else {
            return groupedPlain(
                sortedEntries, openedAt: openedAt, now: now
            )
        }
        let rest = sortedEntries.filter {
            !pinned.contains($0.path)
        }
        // 全部置顶时只回置顶一段，不留空的无题尾段
        guard !rest.isEmpty else {
            return [Section(title: "置顶", entries: pinnedEntries)]
        }
        return [Section(title: "置顶", entries: pinnedEntries)]
            + groupedPlain(rest, openedAt: openedAt, now: now)
    }

    private static func groupedPlain(
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

/// 标题键懒备忘（F1）：一次 sorted 调用内同条目
/// 只算一次 displayTitle——时间序下标题仅作平局
/// 兜底，多数条目根本不触发计算；全平局时退化为
/// 每条目各算一次（与标题序 upfront 同界）。只在
/// 单次排序内使用、不跨调用存活
private final class TitleKeyMemo {
    private var cache: [String: String] = [:]

    func title(for entry: WorkspaceFileEntry) -> String {
        if let cached = cache[entry.path] { return cached }
        let value = DeliverableFileType.displayTitle(
            forFileName: entry.name
        )
        cache[entry.path] = value
        return value
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
