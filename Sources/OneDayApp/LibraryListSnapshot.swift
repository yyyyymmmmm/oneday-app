import Foundation
import OneDayCore

/// 资源库派生快照（§363，流畅度 S4）：一趟 body 只算一
/// 次——过滤（文件/影音分段＋搜索词）→当前段排序→按路径
/// 字典，下传给内容面/行/菜单闭包共用。取代旧形态：计
/// 算属性 sortedDocuments/sortedMedia 每次访问都整表重
/// 排（rotor＋内容＋列表一趟三排、行点按与影音格预取
/// 每次触发再排），deliverable(for:) 每查一次线性扫描
/// 整表（行构建口径 O(N²) 的一半）。
///
/// 等价口径（钉测把守）：过滤谓词与旧 matchesQuery 逐
/// 字同（条目名 localizedCaseInsensitiveContains、词先
/// 去空白、空词全过）；排序直接走 LibraryOrdering
/// .sorted 单源、入参顺序与旧 ordered() 同（过滤后原
/// 序）；字典同路径取首个（与旧 first(where:) 同义），
/// 查无回落 Deliverable(entry:source: "") 与旧兜底逐字
/// 同。排序口味不在本包（标题序的汉字/拼音口径是用户
/// 待裁项，本包只搬运不改判）。
struct LibraryListSnapshot {
    /// 过滤后文件段（未排序）
    let documents: [Deliverable]
    /// 过滤后影音段（未排序）
    let mediaItems: [Deliverable]
    /// 当前段已排序条目（非当前段为空数组，本趟无人消费）
    let sortedDocuments: [WorkspaceFileEntry]
    let sortedMedia: [WorkspaceFileEntry]
    /// §452 定版③统一集：搜索＋类别片＋来源过滤后
    /// 的全集（未排序）与已排序条目——单列表单数据
    /// 源；文件/影音分段旧字段只剩兼容计算（视图不
    /// 再消费）
    let items: [Deliverable]
    let sortedItems: [WorkspaceFileEntry]
    /// 路径→交付物（同路径首个优先，与旧线性首命中同义）
    let deliverableByPath: [String: Deliverable]

    /// 按路径查交付物：字典直达，缺失回落旧兜底形态
    func deliverable(for entry: WorkspaceFileEntry) -> Deliverable {
        deliverableByPath[entry.path]
            ?? Deliverable(entry: entry, source: "")
    }

    /// 过滤＋字典（不排序）：reveal 消费等只需成员判定
    /// 的事件路径走这里，不付排序账
    static func filtered(
        deliverables: [Deliverable]?,
        query: String,
        category: LibraryCategory = .all,
        source: String = ""
    ) -> (
        documents: [Deliverable],
        mediaItems: [Deliverable],
        items: [Deliverable],
        byPath: [String: Deliverable]
    ) {
        let all = deliverables ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        func matches(_ item: Deliverable) -> Bool {
            trimmed.isEmpty
                || item.entry.name.localizedCaseInsensitiveContains(trimmed)
        }
        func matchesSource(_ item: Deliverable) -> Bool {
            if LibrarySourceFilter.isExcludedBackgroundOutput(item) {
                return false
            }
            if source.isEmpty { return true }
            if source == LibrarySourceFilter.agent.rawValue {
                return LibrarySourceFilter.classify(deliverable: item) == .agent
            }
            if source == LibrarySourceFilter.user.rawValue {
                return LibrarySourceFilter.classify(deliverable: item) == .user
            }
            return item.source == source
        }
        var byPath: [String: Deliverable] = [:]
        byPath.reserveCapacity(all.count)
        for item in all where byPath[item.entry.path] == nil {
            byPath[item.entry.path] = item
        }
        return (
            documents: all.filter {
                $0.entry.mediaKind == nil && matches($0)
            },
            mediaItems: all.filter {
                $0.entry.mediaKind != nil && matches($0)
            },
            items: all.filter {
                matches($0)
                    && category.includes($0.entry)
                    && matchesSource($0)
            },
            byPath: byPath
        )
    }

    /// 整快照：过滤＋字典＋当前段排序（segment 0＝文件、
    /// 1＝影音，与宿主分段口径同）
    static func make(
        deliverables: [Deliverable]?,
        query: String,
        sort: LibrarySort,
        openedAt: [String: TimeInterval],
        pinned: Set<String>,
        segment: Int,
        category: LibraryCategory = .all,
        source: String = ""
    ) -> LibraryListSnapshot {
        let base = filtered(
            deliverables: deliverables, query: query,
            category: category, source: source
        )
        let sortedDocuments = segment == 0
            ? LibraryOrdering.sorted(
                base.documents.map(\.entry), by: sort,
                openedAt: openedAt, pinned: pinned
            )
            : []
        let sortedMedia = segment == 1
            ? LibraryOrdering.sorted(
                base.mediaItems.map(\.entry), by: sort,
                openedAt: openedAt, pinned: pinned
            )
            : []
        return LibraryListSnapshot(
            documents: base.documents,
            mediaItems: base.mediaItems,
            sortedDocuments: sortedDocuments,
            sortedMedia: sortedMedia,
            items: base.items,
            sortedItems: LibraryOrdering.sorted(
                base.items.map(\.entry), by: sort,
                openedAt: openedAt, pinned: pinned
            ),
            deliverableByPath: base.byPath
        )
    }
}


/// 资源库派生快照缓存（F1，手感快速项 2026-11-23）：
/// 快照按全输入指纹缓存——输入未变直接复用上一份，
/// body 因无关状态（sheet 呈现／选中态／搜索框显隐
/// 等）重跑时不再整趟重付过滤＋排序（审计实测：标
/// 题序一趟 39.3ms、默认序地板 3.7ms，输入没变照
/// 付）。指纹＝六入参逐值比对（名单逐项 entry＋
/// source、搜索词、排序、openedAt 表、pinned 集、
/// 分段），任一变即整趟重算——不许显旧（钉测把
/// 守变更矩阵）。本类自含、无外部状态，宿主只持
/// 有实例（现行视图 @State；C4 名单店 §369 落地
/// 后可整体搬入店内、内部不改）。只许主线程触碰
/// （宿主皆为主 actor 上下文），不做跨线程同步。
final class LibrarySnapshotCache {
    private var lastDeliverables: [Deliverable]?
    private var lastQuery: String?
    private var lastSort: LibrarySort?
    private var lastOpenedAt: [String: TimeInterval] = [:]
    private var lastPinned: Set<String> = []
    private var lastSegment: Int?
    private var lastCategory: LibraryCategory?
    private var lastSource: String?
    private var lastSnapshot: LibraryListSnapshot?

    /// 与 LibraryListSnapshot.make 同参同果：首调
    /// 与输入变更时走 make 整趟，命中时回存量快照
    func snapshot(
        deliverables: [Deliverable]?,
        query: String,
        sort: LibrarySort,
        openedAt: [String: TimeInterval],
        pinned: Set<String>,
        segment: Int,
        category: LibraryCategory = .all,
        source: String = ""
    ) -> LibraryListSnapshot {
        if let lastSnapshot,
           lastQuery == query,
           lastSort == sort,
           lastSegment == segment,
           lastCategory == category,
           lastSource == source,
           lastOpenedAt == openedAt,
           lastPinned == pinned,
           Self.deliverablesEqual(lastDeliverables, deliverables) {
            return lastSnapshot
        }
        let made = LibraryListSnapshot.make(
            deliverables: deliverables,
            query: query,
            sort: sort,
            openedAt: openedAt,
            pinned: pinned,
            segment: segment,
            category: category,
            source: source
        )
        lastDeliverables = deliverables
        lastQuery = query
        lastSort = sort
        lastOpenedAt = openedAt
        lastPinned = pinned
        lastSegment = segment
        lastCategory = category
        lastSource = source
        lastSnapshot = made
        return made
    }

    /// 名单逐值比对：nil 与空数组分开记（与 make
    /// 的 nil→空表回落同果，但指纹口径不混——载
    /// 荷从无到有不许被误判未变）
    private static func deliverablesEqual(
        _ a: [Deliverable]?, _ b: [Deliverable]?
    ) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a?, b?):
            return a == b
        default:
            return false
        }
    }
}

/// 资源库来源三档筛选（大厂口径：只收录聊天页里智能体主动发给用户的与用户发送的，排除定时任务/快报/简报等后台产物）
enum LibrarySourceFilter: String, CaseIterable, Equatable, Hashable {
    case all = ""
    case agent = "智能体发送"
    case user = "用户发送"

    var label: String {
        switch self {
        case .all: return "全部来源"
        case .agent: return "智能体发送"
        case .user: return "用户发送"
        }
    }

    /// 排除定时任务、快报、简报、动态、监测与内部缓存等非聊天主动发送产物
    static func isExcludedBackgroundOutput(_ deliverable: Deliverable) -> Bool {
        let s = deliverable.source.lowercased()
        let p = deliverable.entry.path.lowercased()
        let excludedKeywords = [
            "cron", "定时", "快报", "简报", "brief", "digest",
            "feed", "动态", "monitor", "监测", "scratch"
        ]
        for kw in excludedKeywords {
            if s.contains(kw) || p.contains("/\(kw)") || p.contains("\(kw)/") {
                return true
            }
        }
        return false
    }

    static func classify(deliverable: Deliverable) -> LibrarySourceFilter {
        let s = deliverable.source.lowercased()
        let p = deliverable.entry.path.lowercased()
        if s.contains("用户") || s.contains("上传") || s.contains("附件")
            || s.contains("upload") || s.contains("attachment")
            || p.contains("/uploads/") || p.contains("/attachments/") {
            return .user
        }
        return .agent
    }

    static func displayLabel(for deliverable: Deliverable) -> String {
        classify(deliverable: deliverable).label
    }
}
