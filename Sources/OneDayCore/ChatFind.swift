import Foundation

/// 对话内查找（§503）：命中计算／就近起点／着色
/// 区间的纯判定单源——findBar 自 D9 起计数与翻页
/// 是真的，但滚动触发只写不读、点亮标记只读不写、
/// 输入不实搜、首命中恒最老一条，四件病灶的共性
/// 是「判定散在视图层、无单源可钉」；本层把判定
/// 收成纯函数＋会话状态机，视图层只剩接线（算完
/// 命中即经会话取目标、直调收敛落点＋置点亮）。
/// 匹配口径与 D9 旧实现逐字一致：普通消息正文大
/// 小写不敏感包含；工具卡／思考 trace／回响／审
/// 批条目不在范围（isSearchable 由调用方按条目
/// 标记折算，本层不认条目类型）。
public enum ChatFind {
    /// 条目的最小投影：判定只需要 id、正文与可搜
    /// 标记；喂入序即线程时间升序（sortedEntries
    /// 序），下标就是 Match.position 的坐标系
    public struct EntryStub: Equatable, Sendable {
        public let id: UUID
        public let content: String
        public let isSearchable: Bool

        public init(id: UUID, content: String, isSearchable: Bool) {
            self.id = id
            self.content = content
            self.isSearchable = isSearchable
        }
    }

    /// 一条命中：条目 id＋其在喂入全序中的位置
    public struct Match: Equatable, Sendable {
        public let id: UUID
        public let position: Int

        public init(id: UUID, position: Int) {
            self.id = id
            self.position = position
        }
    }

    /// 查询归一：去首尾空白，空串 → nil（无查询即
    /// 无查找）；大小写折叠在匹配/着色处做，归一
    /// 本身保留原字面（着色按原字面找、忽略大小写）
    public static func normalizedQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 命中集：可搜条目中正文（大小写不敏感）包含
    /// 查询者，按喂入全序位置升序返回
    public static func matches(
        entries: [EntryStub], query: String
    ) -> [Match] {
        guard let needle = normalizedQuery(query) else { return [] }
        let folded = needle.lowercased()
        var result: [Match] = []
        for (index, entry) in entries.enumerated() {
            guard entry.isSearchable else { continue }
            if entry.content.lowercased().contains(folded) {
                result.append(Match(id: entry.id, position: index))
            }
        }
        return result
    }

    /// 就近起点（§503 第 6 件）：命中位置列＋当前
    /// 阅读锚位置（同为全序下标）→ 起点在命中列中
    /// 的下标。口径：距离最小者胜；同距时锚后（更
    /// 新方向）优先——读者刚滑过的上方命中回头即
    /// 是上一条，向下先达更合翻页直觉；锚缺失（列
    /// 表未报顶可见行）→ 0（D9 旧口径最老一条兜底）
    public static func nearestMatchIndex(
        matchPositions: [Int], anchorPosition: Int?
    ) -> Int {
        guard !matchPositions.isEmpty else { return 0 }
        guard let anchor = anchorPosition else { return 0 }
        var best = 0
        var bestDistance = Int.max
        var bestIsBefore = true
        for (index, position) in matchPositions.enumerated() {
            let distance = abs(position - anchor)
            let isBefore = position < anchor
            if distance < bestDistance
                || (distance == bestDistance && bestIsBefore && !isBefore) {
                best = index
                bestDistance = distance
                bestIsBefore = isBefore
            }
        }
        return best
    }

    /// 着色区间：text 中 query 的全部出现（大小写
    /// 不敏感、非重叠、自左向右），NSRange 口径供
    /// NSAttributedString 施加背景色。作用对象是
    /// 「呈现出来的字符串」而非原始正文——markdown
    /// 语法符不在呈现串里，跨语法边界的查询在此自
    /// 然落空（呈现所见即着色所及，口径自洽）
    public static func occurrenceRanges(
        in text: String, query: String
    ) -> [NSRange] {
        guard let needle = normalizedQuery(query), !text.isEmpty
        else { return [] }
        let haystack = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(
            location: 0, length: haystack.length
        )
        while searchRange.length > 0 {
            let found = haystack.range(
                of: needle, options: [.caseInsensitive],
                range: searchRange
            )
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let next = found.location + max(found.length, 1)
            guard next < haystack.length else { break }
            searchRange = NSRange(
                location: next, length: haystack.length - next
            )
        }
        return ranges
    }
}

/// 查找会话状态机（§503）：命中集＋当前下标的决
/// 策单源——重算落座／上翻／下翻（环绕）各返回
/// 「应当落点＋点亮的目标 id」，视图层拿到非 nil
/// 即直调收敛落点并置点亮标记（一处赋值口，不再
/// 有只写不读的触发器）。计数 x/y 由视图层读
/// matches.count／currentIndex 呈现
public struct ChatFindSession: Equatable, Sendable {
    public private(set) var matches: [UUID] = []
    public private(set) var currentIndex: Int = 0

    public init() {}

    /// 当前命中（下标越界/空集 → nil）
    public var currentMatchID: UUID? {
        matches.indices.contains(currentIndex)
            ? matches[currentIndex] : nil
    }

    /// 重算落座：换上新命中集、下标钉到起点（越界
    /// 夹紧），返回落点目标；空集回 nil 并归零下标
    @discardableResult
    public mutating func recompute(
        matches newMatches: [UUID], startIndex: Int
    ) -> UUID? {
        matches = newMatches
        currentIndex = newMatches.isEmpty
            ? 0
            : min(max(startIndex, 0), newMatches.count - 1)
        return currentMatchID
    }

    /// 下一条（环绕）；空集回 nil
    @discardableResult
    public mutating func moveNext() -> UUID? {
        guard !matches.isEmpty else { return nil }
        currentIndex = (currentIndex + 1) % matches.count
        return currentMatchID
    }

    /// 上一条（环绕）；空集回 nil
    @discardableResult
    public mutating func movePrevious() -> UUID? {
        guard !matches.isEmpty else { return nil }
        currentIndex = (currentIndex - 1 + matches.count)
            % matches.count
        return currentMatchID
    }

    /// 收栏清账：命中集与下标一并归零
    public mutating func reset() {
        matches = []
        currentIndex = 0
    }
}
