import Foundation

/// §245（2026-11-14）排版产物层·键与产物（换代包 2）
///
/// 出处：native-list-migration-blueprint-20261113.md
/// §1.3＋§2 包 2。现行承载的行高来自一台全进程共享
/// 的离屏量测视图（App SelectableTextView 的
/// measuringView），在 SwiftUI 布局期于主线程串行量
/// 测——量测与承载同台同线是旧承载的既定形态，本包
/// 不动它，只在其旁立起「产物层」：按条目预先在后
/// 台产出不可变的排版产物（分段属性串＋各段实测高
/// ＋总高），高度供应先以影子模式运行（算但不消费、
/// 与现量测值对拍计数，见 App LayoutShadowLedger），
/// 消费端切换归包 3 的新承载。
///
/// 本文件只管值与策略（键、产物、计划分类、缓存与
/// 计数），量测引擎（TextKit 实例池）在 App 层——
/// Core 不持 UIKit 量测栈的先例同 ComposerText-
/// Metrics（其量测为纯函数逐次新建、本层池化在
/// App）。

// MARK: - 样式键

/// 样式键：影响排版的全部样式因子。蓝图 §1.3 口径
/// ——字号档（Dynamic Type）入键、**深浅色剔除**
/// （颜色不影响行高；产物里的属性串是量测工件，
/// 呈现拼装仍走 §168 既有缓存按当前环境解析颜色，
/// 包 3 消费高度时不直接贴产物串上屏）；字体映射
/// 与段落映射的口径版本入键——映射代码改版时版本
/// +1，旧产物按新键自然淘汰，不设显式失效路
public struct LayoutStyleKey: Hashable, Sendable {
    /// UIFont.TextStyle.rawValue（App 侧映射传入，
    /// Core 不引 UIKit 枚举）
    public var textStyle: String
    /// UIContentSizeCategory.rawValue（App 侧映射）
    public var sizeCategory: String
    /// 粗体文本（无障碍）开关：开时基字重升档、
    /// 行高随之变，须入键
    public var boldText: Bool
    /// 字体映射版本（InlineTextFonts 口径）
    public var fontVersion: Int
    /// 段落映射版本（MarkdownText 段落映射口径：
    /// 段后距/标题字阶/列表标记几何）
    public var paragraphVersion: Int

    public static let currentFontVersion = 1
    public static let currentParagraphVersion = 1

    public init(
        textStyle: String,
        sizeCategory: String,
        boldText: Bool,
        fontVersion: Int = LayoutStyleKey.currentFontVersion,
        paragraphVersion: Int =
            LayoutStyleKey.currentParagraphVersion
    ) {
        self.textStyle = textStyle
        self.sizeCategory = sizeCategory
        self.boldText = boldText
        self.fontVersion = fontVersion
        self.paragraphVersion = paragraphVersion
    }

    /// 缓存键因子串（稳定、无随机成分）
    public var fingerprint: String {
        "\(textStyle)|\(sizeCategory)|\(boldText ? "b" : "r")"
            + "|f\(fontVersion)|p\(paragraphVersion)"
    }
}

// MARK: - 产物键（四元组）

/// 产物键＝蓝图 §1.3 四元组：条目 id × 内容哈希 ×
/// 宽度 × 样式键。失效只有三路且全在键内：内容变
/// （哈希/字节数变）、宽度变、样式键变——键不变即
/// 产物不变，不设显式失效通道
public struct LayoutProductKey: Hashable, Sendable {
    public var entryID: UUID
    /// 渲染文本（喂呈现层的最终文本：助手＝摘标记
    /// 后文本、用户＝原文）的 FNV-1a 64 位哈希，
    /// 与 EntryScanMemo 同算法同源
    public var contentHash: UInt64
    /// 渲染文本 UTF-8 字节数（哈希的第二因子，与
    /// EntryScanMemo 键口径一致）
    public var contentByteCount: Int
    /// 量测宽（pt，量化到 0.01——布局提议宽的浮点
    /// 抖动不许把同一宽度打成两个键）
    public var width: Double
    public var style: LayoutStyleKey

    public init(
        entryID: UUID,
        content: String,
        width: Double,
        style: LayoutStyleKey
    ) {
        self.entryID = entryID
        self.contentHash = LayoutProductKey.fnv1a(content)
        self.contentByteCount = content.utf8.count
        self.width = LayoutProductKey.quantizedWidth(width)
        self.style = style
    }

    public static func quantizedWidth(_ width: Double) -> Double {
        (width * 100).rounded() / 100
    }

    /// 缓存键串（NSCache 用）
    public var cacheKey: String {
        "lp|\(entryID.uuidString)|\(contentHash)"
            + "|\(contentByteCount)|\(width)|\(style.fingerprint)"
    }

    /// FNV-1a 64 位（确定性、无随机种子）：只作缓
    /// 存键因子——与条目 id、字节数三重合围，不作
    /// 任何安全/正确性判定用途（同 EntryScanMemo）
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}

// MARK: - 产物

/// 一段的排版产物：属性串（量测工件）＋实测高
/// @unchecked Sendable 依据：NSAttributedString 组
/// 装后不可变、跨线只读——与 §149 InlineTextRender-
/// Cache 同口径
public struct LayoutSegmentProduct: @unchecked Sendable {
    public enum Kind: String, Sendable {
        case prose
        case quote
        case plain
    }

    /// 在条目全部呈现段（MarkdownMessageSegment
    /// 序列）中的下标——结构段不在产物内、下标留
    /// 真位，包 3 按下标对回呈现段
    public var segmentIndex: Int
    public var kind: Kind
    public var attributed: NSAttributedString
    public var height: Double

    public init(
        segmentIndex: Int,
        kind: Kind,
        attributed: NSAttributedString,
        height: Double
    ) {
        self.segmentIndex = segmentIndex
        self.kind = kind
        self.attributed = attributed
        self.height = height
    }
}

/// 一条条目的排版产物（不可变）。范围记账（包 2
/// 分流，如实）：只含**文本段**（合并散文/引用/用
/// 户纯文本）——它们在现行承载里有 TextKit 量测路
/// 径、可对拍；结构段（代码/表格/任务清单/分割
/// 线）的高度由承载形态（块内边距、Grid、标记
/// 列）决定、现行路径无 TextKit 量测值可对拍，强
/// 造数字违反实测口径，故只记其计数、高由包 3 承
/// 载侧定。textTotalHeight 是文本段总高、不是整
/// 条行高——消费方（包 3）须与结构段高合成，禁
/// 直接当行高用
public struct LayoutProduct: @unchecked Sendable {
    public var key: LayoutProductKey
    public var segments: [LayoutSegmentProduct]
    /// 文本段实测高之和
    public var textTotalHeight: Double
    /// 结构段计数（代码/表格/任务清单/分割线）
    public var structuralSegmentCount: Int

    public init(
        key: LayoutProductKey,
        segments: [LayoutSegmentProduct],
        structuralSegmentCount: Int
    ) {
        self.key = key
        self.segments = segments
        self.textTotalHeight = segments.reduce(0) { $0 + $1.height }
        self.structuralSegmentCount = structuralSegmentCount
    }
}

// MARK: - 渲染计划接线

/// 条目渲染计划（包 1 扫描/解析层 → 产物层的接线
/// API）：把呈现段序列分类为「可量测文本段」与
/// 「结构段」，文本段连同其在全段序列中的下标交
/// 产物层。分类口径与 MarkdownMessageAssembler 的
/// 分流一一对应，不新造段型
public enum LayoutProductPlan {
    public enum TextSegment: Equatable {
        case prose(index: Int, paragraphs: [MarkdownProseParagraph])
        case quote(index: Int, lines: [MarkdownQuoteLine])

        public var index: Int {
            switch self {
            case .prose(let index, _): return index
            case .quote(let index, _): return index
            }
        }
    }

    public struct Plan: Equatable {
        public var textSegments: [TextSegment]
        public var structuralSegmentCount: Int
    }

    /// 助手条目：渲染文本 → 呈现段 → 分类
    public static func plan(forAssistantText text: String) -> Plan {
        let segments = MarkdownMessageAssembler.segments(for: text)
        var textSegments: [TextSegment] = []
        var structural = 0
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .prose(let paragraphs):
                textSegments.append(
                    .prose(index: index, paragraphs: paragraphs)
                )
            case .quote(let lines):
                textSegments.append(
                    .quote(index: index, lines: lines)
                )
            case .code, .table, .taskList, .divider:
                structural += 1
            }
        }
        return Plan(
            textSegments: textSegments,
            structuralSegmentCount: structural
        )
    }
}

// MARK: - 产物缓存

/// 产物缓存：NSCache 条数＋成本双限（成本＝属性
/// 串总字符数），命中/未命中计数常开（蓝图 §1.3
/// 「先计数后切消费端」纪律，与 MarkdownParse-
/// Metrics/EntryScanMemo 同口径）。内存警告全清
/// 由 App 层订阅通知后调 clear()
public final class LayoutProductCache: @unchecked Sendable {
    private final class Box {
        let product: LayoutProduct
        init(_ product: LayoutProduct) { self.product = product }
    }

    private let cache = NSCache<NSString, Box>()
    private let lock = NSLock()
    private var hitTotal = 0
    private var missTotal = 0

    public init(countLimit: Int = 384, totalCostLimit: Int = 2_000_000) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    public func product(for key: LayoutProductKey) -> LayoutProduct? {
        let found = cache.object(forKey: key.cacheKey as NSString)
        lock.lock()
        if found != nil { hitTotal += 1 } else { missTotal += 1 }
        lock.unlock()
        return found?.product
    }

    /// 只查不记账（预热跳过判定用，不污染命中率账）
    public func contains(_ key: LayoutProductKey) -> Bool {
        cache.object(forKey: key.cacheKey as NSString) != nil
    }

    public func store(_ product: LayoutProduct) {
        let cost = product.segments.reduce(0) {
            $0 + $1.attributed.length
        }
        cache.setObject(
            Box(product),
            forKey: product.key.cacheKey as NSString,
            cost: cost
        )
    }

    public func clear() {
        cache.removeAllObjects()
    }

    public struct Metrics: Equatable {
        public var hits: Int
        public var misses: Int
        /// 命中率（无样本时为 0）
        public var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0
        }
    }

    public func metrics() -> Metrics {
        lock.lock()
        defer { lock.unlock() }
        return Metrics(hits: hitTotal, misses: missTotal)
    }

    public func resetMetrics() {
        lock.lock()
        hitTotal = 0
        missTotal = 0
        lock.unlock()
    }
}

/// 产物缓存单例与验收读面（与 MarkdownParseMetrics
/// 同形态）
public enum LayoutProductStore {
    public static let cache = LayoutProductCache()

    public static func metrics() -> LayoutProductCache.Metrics {
        cache.metrics()
    }

    public static func resetMetrics() {
        cache.resetMetrics()
    }
}
