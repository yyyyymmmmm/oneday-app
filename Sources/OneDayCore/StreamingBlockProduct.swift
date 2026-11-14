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
/// - 块切分（StreamingBlockSegmenter）：以既有
///   MarkdownParser 的块序列为唯一结构源，不另立
///   第二套解析；每块产出「规范源文本」——渲染等
///   价的源重构，只作内容身份（哈希）与闭合前缀拼
///   装两用，不回渲为呈现。
/// - 块产物身份（StreamingBlockIdentity）：块内容
///   派生确定性条目 id，使块产物可直接复用包 2 的
///   LayoutProduct 通道（键＝派生 id×内容哈希×宽
///   ×样式键，与条目产物同构）——闭合块跨拍、跨
///   条目同键命中，单拍新增量测只剩尾块。
/// - 行身份与落定映射（StreamingRowIdentity／
///   StreamingSettleMap）：流式行以本轮用户条目 id
///   为键，落定新建的助手条目沿用同一键在承载侧
///   原位 reconfigure，即「落定不换装」的身份基础。
/// - 流式呈现开关（ChatStreamingFeature）：新路
///   （块级增量）与旧路（TokenFlow 逐词元全量
///   arrange）的独立回滚开关，包 6 清理。
///
/// 行高口径与主线裁定一致（包 3 登记待裁已裁）：
/// 产物估算起步＋托管量实回填覆盖同 key 估算、量
/// 实不落盘（WWDC19 estimated 同构）——块产物只
/// 喂估算侧，量实覆盖在承载侧（ChatListCarrier），
/// 本文件不持任何量实值。

// MARK: - 流式呈现开关（回滚路）

/// 流式呈现路径开关（蓝图 §2 包 4 回滚条款：流式
/// 呈现路径独立开关回 TokenFlow 旧路、保留一包、
/// 包 6 清理）。UserDefaults 布尔键，**缺省 true**
/// ＝块级增量新路（本包交付物即默认形态）；显式
/// false 才回旧路——与 ChatCarrierFeature 的缺省
/// false 方向相反，因为本键管的是呈现算法而非承
/// 载：承载默认旧（包 3 开关）时本键无消费方，承
/// 载切新后呈现默认走新路、出问题单独关本键即回
/// 逐词渐显，不必连承载一并退回
public enum ChatStreamingFeature {
    public static let defaultsKey = "chat.streaming.gen4"

    public static func isIncrementalEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

// MARK: - 块模型

/// 流式块类：与 MarkdownBlock 一一对应，分「文本
/// 块」（进 TextKit 量测、产文本高）与「结构块」
/// （高由承载侧定、只记计数）两族——分族口径与
/// LayoutProductPlan 的段分类同源（散文/引用/普
/// 通列表为文本，代码/表格/任务清单/分割线为结
/// 构；含任务项的列表整块归结构，与装配层分流
/// 一致）
public enum StreamingBlockKind: Equatable, Sendable {
    case paragraph
    case heading
    case list
    case blockquote
    case code
    case table
    case taskList
    case divider

    /// 是否进文本量测（结构块恒 false）
    public var isTextual: Bool {
        switch self {
        case .paragraph, .heading, .list, .blockquote:
            return true
        case .code, .table, .taskList, .divider:
            return false
        }
    }
}

/// 一块流式内容（不可变值）：块类＋规范源文本＋
/// 尾块标记。规范源文本是解析块的渲染等价重构
/// （见 StreamingBlockSegmenter 的逐项口径），两
/// 个用途：内容身份（哈希）与闭合前缀拼装（多块
/// 规范源以空行连接、可再解析回同一块序列）
public struct StreamingBlock: Equatable, Sendable {
    public var index: Int
    public var kind: StreamingBlockKind
    public var sourceText: String
    /// 序列最后一块：仍可随增量生长，其余块在追
    /// 加式增长下内容冻结（解析的状态机修订只发
    /// 生在尾部块域内——表头/分隔行合并、未闭合
    /// 围栏续渲都在最后一块内完成）
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

// MARK: - 块切分

/// 块切分：MarkdownParser 块序列 → 流式块序列。
/// 只做结构映射与规范源重构，不新造解析规则；
/// 半截口径全随解析层既有定版（未闭合围栏续渲
/// 成代码块、半截表格不成表、行内未闭合标记字
/// 面——都落在尾块内，不影响已闭合块）
public enum StreamingBlockSegmenter {
    public static func blocks(
        for text: String
    ) -> [StreamingBlock] {
        guard !text.isEmpty else { return [] }
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
    /// （块间分隔的源形态）——呈现侧以此串走落定
    /// 同路渲染（MarkdownText），再解析回同一块
    /// 序列（往返一致由单测钉住代表样本）。无闭
    /// 合块时为空串
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

// MARK: - 块产物身份（复用包 2 产物通道）

/// 块 → 产物通道身份：块内容派生确定性条目 id，
/// 使块产物直接走 LayoutProductService／Layout-
/// ProductStore（键＝派生 id×内容哈希×宽×样式
/// 键，与条目产物四元组同构），不另立第二套缓存
/// 与量测池。派生只作缓存键因子（与 LayoutPro-
/// ductKey 的哈希定位相同：内容寻址、不作任何
/// 正确性判定）——相同内容的块跨拍、跨条目、跨
/// 线程同键命中，这正是「已闭合块冻结」的落点：
/// 闭合块内容不变 → 键不变 → 产物恒命中，单拍
/// 新增量测只剩内容仍在变的尾块
public enum StreamingBlockIdentity {
    /// 确定性派生 id：内容哈希 8 字节＋字节数 8
    /// 字节拼 16 字节 UUID（字节序固定、无随机
    /// 成分；同内容恒同 id、异内容碰撞面与 FNV
    /// 键同级，由字节数第二因子合围）
    public static func entryID(
        for block: StreamingBlock
    ) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        var hash = block.contentHash
        for index in 0..<8 {
            bytes[index] = UInt8(hash & 0xff)
            hash >>= 8
        }
        var count = UInt64(
            bitPattern: Int64(block.contentByteCount)
        )
        for index in 8..<16 {
            bytes[index] = UInt8(count & 0xff)
            count >>= 8
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// 块的产物键（与条目产物键同一构造口）
    public static func productKey(
        for block: StreamingBlock,
        width: Double,
        style: LayoutStyleKey
    ) -> LayoutProductKey {
        LayoutProductKey(
            entryID: entryID(for: block),
            content: block.sourceText,
            width: width,
            style: style
        )
    }
}

// MARK: - 组合账（喂 ChatRowHeightModel 的输入面）

/// 流式行高组合账：与落定条目同一组合口（Chat-
/// RowHeightModel 的 textTotalHeight／textSeg-
/// mentCount／structuralSegmentCount 三因子同
/// 义）——流式行与落定行走同一高度模型，落定前
/// 后估算口径不跳变。products 与 blocks 同序对
/// 位（nil＝该块产物未就绪）；文本块缺产物时整
/// 行不给组合值（宁可整行走暂定估算，不许拿缺
/// 尾块的半截总高冒充——缺的恰是正在长的部分）
public struct StreamingHeightTotals: Equatable, Sendable {
    /// 全部文本块产物齐备时的文本总高；任一文本
    /// 块缺产物为 nil
    public var textTotalHeight: Double?
    public var textSegmentCount: Int
    public var structuralSegmentCount: Int
    public var unmeasuredTextualCount: Int

    public init(
        textTotalHeight: Double?,
        textSegmentCount: Int,
        structuralSegmentCount: Int,
        unmeasuredTextualCount: Int
    ) {
        self.textTotalHeight = textTotalHeight
        self.textSegmentCount = textSegmentCount
        self.structuralSegmentCount = structuralSegmentCount
        self.unmeasuredTextualCount = unmeasuredTextualCount
    }
}

public enum StreamingComposition {
    public static func totals(
        blocks: [StreamingBlock],
        products: [LayoutProduct?]
    ) -> StreamingHeightTotals {
        var textTotal = 0.0
        var textSegments = 0
        var structural = 0
        var unmeasured = 0
        var allTextualMeasured = true
        for (index, block) in blocks.enumerated() {
            let product = index < products.count
                ? products[index] : nil
            if let product {
                textTotal += product.textTotalHeight
                textSegments += product.segments.count
                structural += product.structuralSegmentCount
            } else if block.isTextual {
                unmeasured += 1
                allTextualMeasured = false
            } else {
                structural += 1
            }
        }
        return StreamingHeightTotals(
            textTotalHeight: allTextualMeasured
                ? textTotal : nil,
            textSegmentCount: textSegments,
            structuralSegmentCount: structural,
            unmeasuredTextualCount: unmeasured
        )
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
