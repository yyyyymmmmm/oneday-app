import Foundation

/// §247（2026-11-14）流式块级增量产物（换代包 4）
///
/// 出处：native-list-migration-blueprint-20261113.md
/// §1.4＋§2 包 4。蓝图口径：流式与落定同一条管线
/// ——流式条目是一个普通快照条目，其产物按 markdown
/// 块增量生长：已闭合的块产物冻结、只有未闭合的尾
/// 块重算；落定＝同一条目产物补齐最后一块＋状态位
/// 翻转、无视图树换装。
///
/// 本文件是这条管线的 Core 面（纯值与纯函数）：
/// - 块切分（StreamingBlockSegmenter）：§409
///   步 C/D 退役、§494 重建（解析源改现行树解
///   析，差异注记在簇内）；块产物身份（Stream-
///   ingBlockIdentity）与组合账随产物通道退役
///   不重建——行高走合成器 markdownHeight 单源。
/// - 行身份与落定映射（StreamingRowIdentity／
///   StreamingSettleMap）：流式行以本轮用户条目 id
///   为键，落定新建的助手条目沿用同一键在承载侧
///   原位 reconfigure，即「落定不换装」的身份基础。
/// - 流式呈现开关（ChatStreamingFeature）：§503
///   退役——流式呈现定死常开（用户终裁：呈现类开
///   关收敛），枚举与死读口 isIncrementalEnabled
///   一并删除；键 chat.streaming.gen4 本体保留不
///   读（存量值惰性，同退役键先例）。
///
/// 行高口径与主线裁定一致（包 3 登记待裁已裁）：
/// 产物估算起步＋托管量实回填覆盖同 key 估算、量
/// 实不落盘（WWDC19 estimated 同构）——块产物只
/// 喂估算侧，量实覆盖在承载侧（ChatListCarrier），
/// 本文件不持任何量实值。

// MARK: - 流式呈现开关（§503 退役）

// ChatStreamingFeature（回滚开关）已于 §503 删除：
// 流式呈现定死常开、不再有回 TokenFlow 旧路的用户
// 开关（TokenFlow 元件本体早已退役）。键 chat.
// streaming.gen4 在设备上可能残留存量值——无任何消
// 费方（惰性残留，不读不写不清，同 188 退役键先例）。

// MARK: - 打字动画开关与入场计划（第 104 条）

/// 打字动画开关（2026-11-15 流式块级口径拍板时备好
/// 的规格、2026-11-16 第 104 条落地）：原设置→外观
/// 「回复呈现」节的「打字动画」开关已于 §503 退役
/// ——打字渐显定死常开（ChatView 入场计划恒传 true，
/// 仍服从 Reduce Motion 的恒压过）。本枚举保留为键
/// 名档案（退役元件 StreamingText 仍引本键名、键名
/// 字面量单源纪律不破）；isEnabled 自 §503 起无生
/// 产消费方
public enum StreamingTypewriterFeature {
    public static let defaultsKey = "chat.streaming.typewriter"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

/// 流式词元入场计划（第 104 条到达减法，纯函数单点
/// 裁定）：到达瞬间只许一个主动画——
///
/// - 首批（本代次尚无任一词元已显形，含指示器退场
///   的换装拍与换代重发）：**整批直显**。指示器与正
///   文同拍交接、不许出现「内容不可见而占位已全
///   宽」的光标药丸帧，正文以最终落位静态出现
/// - 开关关或 Reduce Motion：全程整批直显（Reduce
///   Motion 优先于开关）
/// - 其余批次：整批同拍单次轻渐显（batchFade）——
///   同批词元共享一次 opacity 渐显，不逐词元错开、
///   不带 blur；已显形词元永不重演
public enum StreamingEntrance {
    public enum Plan: Equatable, Sendable {
        case instant
        case batchFade
    }

    public static func plan(
        typewriterEnabled: Bool,
        reduceMotion: Bool,
        isFirstBatchOfGeneration: Bool
    ) -> Plan {
        guard typewriterEnabled, !reduceMotion,
              !isFirstBatchOfGeneration
        else { return .instant }
        return .batchFade
    }
}

// MARK: - 流式块模型（§494 重建）

/// 流式块类：与 MarkdownBlock 一一对应，分「文本
/// 块」（散文呈现族）与「结构块」两族——分族口径
/// 与装配层分流同源（散文/引用/普通列表为文本，
/// 代码/表格/任务清单/分割线为结构；含任务项的
/// 列表整块归结构，与装配层一致）。§247 原版同名
/// 件，§409 步 C/D 退役、§494 按现行解析核重建
public enum StreamingBlockKind: Equatable, Sendable {
    case paragraph
    case heading
    case list
    case blockquote
    case code
    case table
    case taskList
    case divider

    /// 是否进散文呈现族（结构块恒 false）
    public var isTextual: Bool {
        switch self {
        case .paragraph, .heading, .list, .blockquote:
            return true
        case .code, .table, .taskList, .divider:
            return false
        }
    }

    /// 装配器并段集（MarkdownMessageAssembler 的
    /// prose 累积口径）：段落／标题／列表进同一散
    /// 文段；引用／代码／表格／任务列表／分隔各自
    /// 成段。呈现侧段距两级口径（台账 185）据此判
    /// 相邻块界距走 paragraphSpacing 还是 spacingSM
    public var isProseMergeable: Bool {
        self == .paragraph || self == .heading
            || self == .list
    }
}

/// 一块流式内容（不可变值）：块类＋规范源文本＋
/// 尾块标记。规范源文本是解析块的渲染等价重构
/// （见 StreamingBlockSegmenter 的逐项口径），只
/// 作内容身份（哈希）与闭合前缀拼装两用
public struct StreamingBlock: Equatable, Sendable {
    public var index: Int
    public var kind: StreamingBlockKind
    public var sourceText: String
    /// 序列最后一块：仍可随增量生长，其余块在追
    /// 加式增长下内容冻结（解析的状态修订只发生
    /// 在尾部块域内——表头/分隔行合并、未闭合围
    /// 栏续渲都在最后一块内完成）
    public var isTail: Bool

    public init(
        index: Int, kind: StreamingBlockKind,
        sourceText: String, isTail: Bool
    ) {
        self.index = index
        self.kind = kind
        self.sourceText = sourceText
        self.isTail = isTail
    }

    /// 内容哈希（与 LayoutProductKey 同算法同源）
    public var contentHash: UInt64 {
        LayoutProductKey.fnv1a(sourceText)
    }

    public var contentByteCount: Int {
        sourceText.utf8.count
    }

    /// 文本块判定：列表块含任务项时整块归结构
    /// （装配层把含任务项的列表分流为结构段，本
    /// 判定在切分时已按块内容定死，见 segmenter）
    public var isTextual: Bool { kind.isTextual }
}

// MARK: - 块切分（§494 重建）

/// 块切分：MarkdownParser 块序列 → 流式块序列。
/// 只做结构映射与规范源重构，不新造解析规则；
/// 半截口径全随解析层既有定版（未闭合围栏续渲
/// 成代码块、半截表格不成表、行内未闭合标记字
/// 面——都落在尾块内，不影响已闭合块）
///
/// §494 重建注记（与 §247/§348 原版的差异）：解
/// 析源改现行 MarkdownParser.parse（§417 树解
/// 析＋解析备忘）——旧 parseWithRanges 孤岛（旧
/// 状态机＋行号）不随本簇复活；§348 的追加链增
/// 量随之不重建：树解析自带全文备忘、单拍切分
/// 成本由发布门节流封顶（≤20Hz），链的「只重
/// 切尾域」优化在当前成本量级无必要。输出口径
/// 与原版逐块同义（分类/规范源/闭合前缀/尾块）
public enum StreamingBlockSegmenter {
    /// 全文备忘（同文再查即表：同拍多调用点收敛
    /// 为一次真求值；§167 备忘同制，容量只须覆
    /// 盖同拍多调用与近期快照）
    private static let memo =
        ParseMemoBox<[StreamingBlock]>(capacity: 64)

    public static func blocks(
        for text: String
    ) -> [StreamingBlock] {
        guard !text.isEmpty else { return [] }
        return memo.value(for: text) { segment(text) }
    }

    /// 强制全量切分（差分钉测的独立参照＋排障回
    /// 退阀）：绕过备忘，与 blocks(for:) 同输出
    /// 口径
    public static func blocksForcingFullEvaluation(
        for text: String
    ) -> [StreamingBlock] {
        guard !text.isEmpty else { return [] }
        return segment(text)
    }

    /// 测试隔离：清备忘（用例间互不串扰）
    public static func resetCachesForTesting() {
        memo.removeAll()
    }

    /// 一次真切分（解析＋规范重构）
    private static func segment(
        _ text: String
    ) -> [StreamingBlock] {
        let parsed = MarkdownParser.parse(text)
        return parsed.enumerated().map { index, block in
            let (kind, source) = canonical(block)
            return StreamingBlock(
                index: index,
                kind: kind,
                sourceText: source,
                isTail: index == parsed.count - 1
            )
        }
    }

    /// 闭合前缀：全部非尾块的规范源以空行连接
    /// （块间分隔的源形态）——呈现侧以此串走落
    /// 定同路渲染（MarkdownText），再解析回同一
    /// 块序列（往返一致由单测钉住代表样本）。无
    /// 闭合块时为空串
    public static func closedPrefix(
        of blocks: [StreamingBlock]
    ) -> String {
        blocks.filter { !$0.isTail }
            .map { closedSource($0) }
            .joined(separator: "\n\n")
    }

    /// 尾块规范源（呈现侧尾块渲染的输入）；无块
    /// 时为空串
    public static func tailSource(
        of blocks: [StreamingBlock]
    ) -> String {
        blocks.last?.sourceText ?? ""
    }

    /// 块在闭合前缀中的源形态：与 sourceText 的
    /// 唯一差异是代码块补闭合围栏——sourceText
    /// 为身份/尾块口径保留「围栏开＋正文」的源前
    /// 缀形态（流式尾块正是未闭合围栏），拼进前
    /// 缀时若不补闭合，后续块会被未闭合围栏吞进
    /// 代码块
    private static func closedSource(
        _ block: StreamingBlock
    ) -> String {
        if block.kind == .code {
            return block.sourceText + "\n```"
        }
        return block.sourceText
    }

    /// 解析块 →（流式块类，规范源）。规范源逐项
    /// 口径：只求渲染等价与确定性，不求与原始源
    /// 逐字一致（尾随空白、列表标记字符一类不影
    /// 响渲染的差异在重构中归一）
    private static func canonical(
        _ block: MarkdownBlock
    ) -> (StreamingBlockKind, String) {
        switch block {
        case .paragraph(let text):
            return (.paragraph, text)
        case .heading(let text, let level):
            let marks = String(repeating: "#", count: level)
            return (.heading, "\(marks) \(text)")
        case .code(let code, let language):
            return (.code, "```\(language ?? "")\n\(code)")
        case .blockquote(let lines):
            let source = lines.map {
                String(repeating: ">", count: $0.depth)
                    + " " + $0.text
            }.joined(separator: "\n")
            return (.blockquote, source)
        case .list(let items):
            let hasTask = items.contains { item in
                switch item.marker {
                case .task: return true
                case .bullet, .ordered: return false
                }
            }
            let source = items.map { item in
                let indent = String(
                    repeating: "  ", count: item.level
                )
                let marker: String
                switch item.marker {
                case .bullet:
                    marker = "-"
                case .ordered(let number):
                    marker = "\(number)."
                case .task(let checked):
                    marker = checked ? "- [x]" : "- [ ]"
                }
                return "\(indent)\(marker) \(item.text)"
            }.joined(separator: "\n")
            // 含任务项：整块归结构类 .taskList（与
            // 装配层「含任务项的列表独立成段」的分
            // 流一致），规范源同式重构（任务标记以
            // - [ ]/- [x] 回写、再解析同形）
            return (hasTask ? .taskList : .list, source)
        case .table(let header, let alignments, let rows):
            // 单元格内的字面 | 回逃逸（解析侧以 \|
            // 占位拆格，规范源不逃逸则重解析错位）
            let esc: (String) -> String = {
                $0.replacingOccurrences(of: "|", with: "\\|")
            }
            let headerLine = "| "
                + header.map(esc).joined(separator: " | ")
                + " |"
            let alignLine = "| " + alignments.map {
                switch $0 {
                case .left: return ":---"
                case .center: return ":---:"
                case .right: return "---:"
                }
            }.joined(separator: " | ") + " |"
            let rowLines = rows.map {
                "| " + $0.map(esc).joined(separator: " | ")
                    + " |"
            }
            let source = ([headerLine, alignLine] + rowLines)
                .joined(separator: "\n")
            return (.table, source)
        case .divider:
            return (.divider, "---")
        }
    }
}

// MARK: - 行身份与落定映射

/// 流式行键：以本轮用户条目 id 为身份（发送互斥
/// 保证同线程同刻只有一轮在飞，用户条目 id 即回
/// 合的稳定身份）。落定新建的助手条目沿用此键，
/// 承载侧据键认行——同键＋版本变＝原位 recon-
/// figure，这就是「落定不换装」在本承载（手动
/// 帧布局＋托管窗口）的等价实现
public enum StreamingRowIdentity {
    public static func streamRowKey(
        userEntryID: String
    ) -> String {
        "stream-\(userEntryID)"
    }

    /// 账本缺位时的回落键（演示种子轮等无账本轮
    /// 次）：线程内唯一在飞轮的回落身份，落定映
    /// 射同以此键登记
    public static func fallbackStreamRowKey(
        threadID: UUID
    ) -> String {
        "stream-thread-\(threadID.uuidString)"
    }
}

/// 落定映射（会话内记账、不落盘）：助手条目 id
/// → 其流式行键。落定时由落定口登记（applySet-
/// tledTurn 建条目处），行构建时查询（条目行键
/// 优先取映射、缺位回本名）。守则：同一流式行
/// 键只许被一个条目认领（首个登记者得）——重发
/// 同一用户条目的第二轮落定时若首轮条目尚在，
/// 次轮不抢键、按本名建行（降级为常规换行，无
/// 正确性问题）；首轮条目已被整段替换删除的情
/// 形下映射随条目消亡由构建侧自然失效（查不到
/// 对应在列条目时映射不参与）
public struct StreamingSettleMap: Equatable, Sendable {
    private var rowKeyByEntryID: [UUID: String] = [:]
    private var claimedKeys: Set<String> = []

    public init() {}

    @discardableResult
    public mutating func record(
        entryID: UUID, streamRowKey: String
    ) -> Bool {
        guard !claimedKeys.contains(streamRowKey) else {
            return false
        }
        claimedKeys.insert(streamRowKey)
        rowKeyByEntryID[entryID] = streamRowKey
        return true
    }

    public func rowKey(for entryID: UUID) -> String? {
        rowKeyByEntryID[entryID]
    }

    public var count: Int { rowKeyByEntryID.count }
}

// MARK: - 统一流式渲染协调器（移植自 refactor/standard-architecture Phase 3.4）

/// 统一流式渲染协调器：提供 30fps 固定帧率节拍发布与已完成块冻结缓存，
/// 供 iOS 与 macOS 双端共用，同时保留既有底层类型兼容存量单测。
public struct StreamRenderCoordinator: Equatable, Sendable {
    public struct Snapshot: Equatable, Sendable {
        public let text: String
        public let blocks: [StreamingBlock]
        public let isComplete: Bool

        public init(text: String, blocks: [StreamingBlock], isComplete: Bool) {
            self.text = text
            self.blocks = blocks
            self.isComplete = isComplete
        }
    }

    private var lastPublishedAt: TimeInterval = 0
    private let minInterval: TimeInterval
    private var accumulatedText: String = ""
    private var cachedBlocks: [StreamingBlock] = []
    private var isComplete: Bool = false

    public init(minInterval: TimeInterval = 1.0 / 30.0) {
        self.minInterval = minInterval
    }

    public mutating func reset() {
        lastPublishedAt = 0
        accumulatedText = ""
        cachedBlocks = []
        isComplete = false
    }

    /// 喂入新文本增量；仅在满足固定帧率节拍（或强制完成）时产出新快照，避免主线程高频重排。
    public mutating func ingest(
        delta: String,
        now: TimeInterval,
        forcePublish: Bool = false
    ) -> Snapshot? {
        guard !delta.isEmpty || forcePublish else { return nil }
        accumulatedText += delta
        if !forcePublish && lastPublishedAt > 0 && (now - lastPublishedAt) < minInterval {
            return nil
        }
        lastPublishedAt = now
        cachedBlocks = StreamingBlockSegmenter.blocks(for: accumulatedText)
        return Snapshot(text: accumulatedText, blocks: cachedBlocks, isComplete: isComplete)
    }

    /// 流结束时强制落盘并冻结全部块。
    public mutating func finish(now: TimeInterval) -> Snapshot {
        isComplete = true
        lastPublishedAt = now
        cachedBlocks = StreamingBlockSegmenter.blocks(for: accumulatedText)
        return Snapshot(text: accumulatedText, blocks: cachedBlocks, isComplete: true)
    }

    public var currentSnapshot: Snapshot {
        Snapshot(text: accumulatedText, blocks: cachedBlocks, isComplete: isComplete)
    }
}
