import Foundation

/// 搜索落点目标解析（台账 150，客户端先行）：服务
/// 端会话搜索命中只带会话 id＋命中摘要（snippet）
/// 与命中角色、不带消息 id（SessionSearchHit 生产
/// 实样）——落到哪条只能在本地线程里按摘要回找：
/// 摘要按空白归一后取最长连续段（服务端摘要可能
/// 带省略号截断）作针，在同角色条目的归一正文里
/// 做包含匹配，首个命中即目标；摘要太短（<4 字）
/// 或无命中 → nil，调用方如实落空（会话照常打开
/// 落底，不假装定位成功——与 OB「滚动失败保留现
/// 位置、聊天照常显示」同口径）。
public enum SearchTargetResolution {
    /// 条目的最小投影：判定只需要 id、角色与正文
    public struct EntryStub: Equatable, Sendable {
        public let id: UUID
        public let role: String
        public let content: String

        public init(id: UUID, role: String, content: String) {
            self.id = id
            self.role = role
            self.content = content
        }
    }

    /// 针的最短可用长度（归一后计）：整段摘要低于
    /// 此数不匹配（太短必误中）
    public static let minimumNeedleLength = 4
    /// 分段取针的段长下限：省略号分段后，长段优先
    /// 作针；全段皆短于此数才退回整段
    public static let segmentNeedleLength = 8

    /// 空白归一：任意空白串（含换行）压成单个空格
    /// 并去首尾——服务端摘要与本地正文的换行/缩进
    /// 差异不许挡住匹配
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// 取针：按省略号（…/...）分段取最长段；最长
    /// 段仍短于 segmentNeedleLength 时用整段归一摘
    /// 要；最终针短于 minimumNeedleLength → nil
    public static func needle(fromSnippet snippet: String) -> String? {
        let whole = normalized(snippet)
        let segments = whole
            .components(separatedBy: "…")
            .flatMap { $0.components(separatedBy: "...") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let longest = segments.max(by: { $0.count < $1.count })
        let candidate: String
        if let longest, longest.count >= segmentNeedleLength {
            candidate = longest
        } else {
            candidate = whole
        }
        guard candidate.count >= minimumNeedleLength
        else { return nil }
        return candidate
    }

    /// 解析目标条目：role 为服务端命中角色（"user"
    /// /"assistant"）时只在同角色条目里找；role 缺
    /// 失或未知值则全集找。首个正文包含针的条目即
    /// 目标（同文重复时取最早一条，确定性口径）
    public static func targetEntryID(
        entries: [EntryStub], snippet: String?,
        role: String?
    ) -> UUID? {
        guard let snippet,
              let needle = needle(fromSnippet: snippet)
        else { return nil }
        let scoped = (role == "user" || role == "assistant")
            ? entries.filter { $0.role == role }
            : entries
        for entry in scoped {
            if normalized(entry.content).contains(needle) {
                return entry.id
            }
        }
        return nil
    }
}

/// 搜索落点收敛状态机（台账 150，学 OpenBot 的
/// focus 定位算法形态——FOCUS_PLACE 常量同值）：
/// 先按估算帧滚过去，周围行量实后落点会漂移；每
/// 拍量一次目标行的屏上位置，位置不再移动（相邻
/// 两拍差 ≤1pt）视为收敛；最多 6 次滚动，预算耗
/// 尽即停（残差如实保留、不无限追）。用户拖动即
/// 弃（读者的位置优先于机器落点，OB 同口径）。
/// 本机只管判定，滚动与量测由宿主（原生列表控制
/// 器）在落定拍喂入/执行。
public struct SearchFocusConvergence: Equatable, Sendable {
    /// 滚动次数上限（OB FOCUS_PLACE_ATTEMPTS 同值）
    public static let maxAttempts = 6
    /// 收敛容差：相邻两拍屏上位置差 ≤ 此值视为
    /// 已停稳（OB FOCUS_PLACE_TOLERANCE 同值，pt）
    public static let tolerance: CGFloat = 1
    /// 落点间隙：目标行顶停在顶留位下方此数处
    /// （OB FOCUS_GAP 同值，pt）
    public static let topGap: CGFloat = 12

    /// 一次评估的裁决
    public enum Evaluation: Equatable, Sendable {
        /// 位置仍在漂移且预算未尽：再滚一次
        case scrollAgain
        /// 位置停稳：收敛收官
        case converged
        /// 预算耗尽/已不在进行中：停手收官
        case exhausted
    }

    /// 已执行的滚动次数（begin 记第一次）
    public private(set) var attempts = 0
    public private(set) var isActive = false
    private var lastShownPosition: CGFloat?

    public init() {}

    /// 开始一次落点：调用方随即执行第一次滚动
    public mutating func begin() {
        attempts = 1
        lastShownPosition = nil
        isActive = true
    }

    /// 每拍布局落定后喂入目标行的屏上位置（行顶
    /// 相对视口顶的距离）：首拍无前值只记账；其后
    /// 与上拍差 ≤ tolerance → 收敛；预算用尽 →
    /// 耗尽；其余再滚
    @discardableResult
    public mutating func evaluate(
        shownPosition: CGFloat
    ) -> Evaluation {
        guard isActive else { return .exhausted }
        if let last = lastShownPosition,
           abs(shownPosition - last) <= Self.tolerance {
            isActive = false
            return .converged
        }
        lastShownPosition = shownPosition
        if attempts >= Self.maxAttempts {
            isActive = false
            return .exhausted
        }
        attempts += 1
        return .scrollAgain
    }

    /// 用户接管（拖动开始）：立即弃权
    public mutating func abort() {
        isActive = false
    }
}
