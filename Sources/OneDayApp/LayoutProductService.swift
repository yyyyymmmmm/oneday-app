import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// §251（2026-11-14）排版产物服务（换代包 2）
///
/// 产物层（蓝图 §1.3）的 App 侧门面：按键查 Core
/// 产物缓存 → 未命中按呈现同源映射拼装段落属性串
/// → 后台量测池逐段量高 → 组产物回存。高度先以
/// 影子模式运行：本服务与 LayoutShadowLedger 只算
/// 只记账，**没有任何呈现消费方**——行高来源仍是
/// §168 现量测视图，消费切换归包 3。
///
/// §335（台账 190 留账②）消费切换落地：产物自此
/// 是三方单源——呈现（条目行段串直贴，Markdown-
/// Text 产物注入）、预计算（量测未就绪时段高代
/// 量测，见合成器 precomputedEntryHeight）、行高
/// 估算（流式/承载既有读口）。入串色改 trait 动
/// 态色（呈现级工件，见 assemble 注）；§168 拼装
/// 缓存退为产物未就绪时的回落与非条目面的单源。
///
/// 拼装同源纪律：段落映射只用 MarkdownText 的单
/// 源静态映射（proseParagraphs/quoteParagraphs）＋
/// SelectableInlineText.build 本体——产物层不另拼
/// 一套，否则影子对拍比的是两套拼装、毫无意义。
/// 颜色以 trait 动态色入串（§335；颜色不入样式
/// 键、不影响高，见 Core LayoutStyleKey）

// MARK: - 样式上下文

/// 样式快照：视图环境（字号档/粗体开关）在调用点
/// 摘出、显式贯穿产物链（同 ComposerTextMetrics
/// A11Y-D1 的贯穿口径——量测档必须与排版档同源）
struct LayoutStyleContext: Equatable {
    var sizeCategory: UIContentSizeCategory
    var boldText: Bool

    /// 聊天正文统一字阶（§152/§168 定单源；§263 升
    /// .body：.callout 是次级字阶、不配作主阅读文本，
    /// 用户泡与助手泡同档一起升、不拆两套）
    var coreKey: LayoutStyleKey {
        LayoutStyleKey(
            textStyle: UIFont.TextStyle.body.rawValue,
            sizeCategory: sizeCategory.rawValue,
            boldText: boldText
        )
    }

    static func current(
        boldText: Bool
    ) -> LayoutStyleContext {
        LayoutStyleContext(
            sizeCategory: UITraitCollection.current
                .preferredContentSizeCategory,
            boldText: boldText
        )
    }
}

// MARK: - 产物服务

final class LayoutProductService: @unchecked Sendable {
    static let shared = LayoutProductService()

    private let pool = LayoutMeasurePool.shared

    private init() {
        // 蓝图 §1.3：内存警告全清——订阅在服务首
        // 次被触及时装上（聊天打开必经预热口）
        NotificationCenter.default.addObserver(
            forName: UIApplication
                .didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { _ in
            LayoutProductStore.cache.clear()
        }
    }

    /// 取一条条目的排版产物：缓存命中直返、未命中
    /// 后台现产。renderedText＝喂呈现层的最终文本
    /// （助手＝摘标记后文本、用户＝原文），与呈现
    /// 同源是键的内容因子
    func product(
        entryID: UUID,
        renderedText: String,
        isUser: Bool,
        width: CGFloat,
        style: LayoutStyleContext
    ) async -> LayoutProduct? {
        guard !renderedText.isEmpty, width > 0 else { return nil }
        let key = LayoutProductKey(
            entryID: entryID,
            content: renderedText,
            width: Double(width),
            style: style.coreKey
        )
        if let cached = LayoutProductStore.cache.product(for: key) {
            return cached
        }
        let built = await build(
            key: key, renderedText: renderedText,
            isUser: isUser, width: width, style: style
        )
        LayoutProductStore.cache.store(built)
        return built
    }

    /// 同步取产物（台账 190③）：量测台工单在后
    /// 台队列量完整行高后顺产排版产物入同一缓存
    /// ——「量测产物」自此不止行高：段属性串＋各
    /// 段高一次算完存账，呈现/估算侧只取成品（学
    /// 微信 CellLayout 的预排版全件）。拼装与异
    /// 步口逐字同源（assembleWorks），量测走池
    /// 同步口——**调用方须已在后台线程**（同步
    /// 口主线程禁用，见 LayoutMeasurePool 注）；
    /// 主线程调用方（就地量测路）应改走异步
    /// product(...) 补产
    func productSynchronously(
        entryID: UUID,
        renderedText: String,
        isUser: Bool,
        width: CGFloat,
        style: LayoutStyleContext
    ) -> LayoutProduct? {
        guard !renderedText.isEmpty, width > 0
        else { return nil }
        let key = LayoutProductKey(
            entryID: entryID,
            content: renderedText,
            width: Double(width),
            style: style.coreKey
        )
        if let cached = LayoutProductStore.cache
            .product(for: key) {
            return cached
        }
        let (works, structuralCount) = assembleWorks(
            renderedText: renderedText,
            isUser: isUser, width: width, style: style
        )
        var segments: [LayoutSegmentProduct] = []
        for work in works {
            let height = pool.measureSizeSynchronously(
                work.attributed, width: work.measureWidth
            ).height
            segments.append(LayoutSegmentProduct(
                segmentIndex: work.index, kind: work.kind,
                attributed: work.attributed,
                height: Double(height)
            ))
        }
        let built = LayoutProduct(
            key: key, segments: segments,
            structuralSegmentCount: structuralCount
        )
        LayoutProductStore.cache.store(built)
        return built
    }

    /// 预热入口（蓝图 §1.3：开线程时按可见区±一屏
    /// 预热的本期落法——线程打开时对其全部已载条
    /// 目在后台预产；LazyVStack 的物化范围≈可见区
    /// ±一屏，逐条预产的产物按键待查、多产无害、
    /// 少产在消费时补）。不阻塞调用方、不回主线
    /// 程，条目上限防超长线程一次打满量测池
    struct PreheatEntry {
        var entryID: UUID
        var renderedText: String
        var isUser: Bool
    }

    /// 条目文本列宽单源（§263）：预热与承载行高估算
    /// （ChatView.carrierRowEstimate 的缓存直读）共用
    /// 本处，两处同键同宽、不许各算一份。用户泡沿旧
    /// 账（屏宽−气泡内边距×2−侧让位，宽度口径不动）；
    /// 助手正文＝屏宽×文宽占屏比（与气泡布局封顶同
    /// 值，assistantBubble 消费 assistantTextWidth-
    /// Fraction）
    static func textWidth(
        isUser: Bool, screenWidth: CGFloat
    ) -> CGFloat {
        isUser
            ? screenWidth
                - OneDayMetrics.bubblePaddingH * 2
                - OneDayMetrics.bubbleSideInset
            : OneDayMetrics.assistantTextWidth(screenWidth: screenWidth)
    }

    func preheat(
        entries: [PreheatEntry],
        screenWidth: CGFloat,
        style: LayoutStyleContext
    ) {
        let capped = Array(entries.prefix(200))
        guard !capped.isEmpty, screenWidth > 0 else { return }
        Task.detached(priority: .utility) { [self] in
            for entry in capped {
                let width = Self.textWidth(
                    isUser: entry.isUser, screenWidth: screenWidth
                )
                let key = LayoutProductKey(
                    entryID: entry.entryID,
                    content: entry.renderedText,
                    width: Double(width),
                    style: style.coreKey
                )
                if LayoutProductStore.cache.contains(key) {
                    continue
                }
                _ = await product(
                    entryID: entry.entryID,
                    renderedText: entry.renderedText,
                    isUser: entry.isUser,
                    width: width, style: style
                )
            }
        }
    }

    // MARK: - 拼装＋量测

    private func build(
        key: LayoutProductKey,
        renderedText: String,
        isUser: Bool,
        width: CGFloat,
        style: LayoutStyleContext
    ) async -> LayoutProduct {
        let (works, structuralCount) = assembleWorks(
            renderedText: renderedText,
            isUser: isUser, width: width, style: style
        )
        var segments: [LayoutSegmentProduct] = []
        for work in works {
            let height = await pool.measure(
                work.attributed, width: work.measureWidth
            )
            segments.append(LayoutSegmentProduct(
                segmentIndex: work.index, kind: work.kind,
                attributed: work.attributed,
                height: Double(height)
            ))
        }
        return LayoutProduct(
            key: key,
            segments: segments,
            structuralSegmentCount: structuralCount
        )
    }

    /// 段拼装工件（量测前）：段序／段型／属性串／
    /// 该段量测宽——异步 build 与同步 product-
    /// Synchronously 共用本拼装（拼装单源纪律：
    /// 两路只差量测口、不差拼装口）
    private struct SegmentWork {
        var index: Int
        var kind: LayoutSegmentProduct.Kind
        var attributed: NSAttributedString
        var measureWidth: CGFloat
    }

    private func assembleWorks(
        renderedText: String,
        isUser: Bool,
        width: CGFloat,
        style: LayoutStyleContext
    ) -> (works: [SegmentWork], structuralCount: Int) {
        let baseFont = InlineTextFonts.baseFont(
            textStyle: .body,
            category: style.sizeCategory,
            boldText: style.boldText
        )
        func assemble(
            _ paragraphs: [InlineTextParagraph],
            foreground: Color
        ) -> NSAttributedString {
            SelectableInlineText.build(
                paragraphs: paragraphs,
                baseFont: baseFont,
                overrideFont: { textStyle in
                    InlineTextFonts.baseFont(
                        textStyle: textStyle,
                        category: style.sizeCategory,
                        boldText: style.boldText
                    )
                },
                // §335：入串色改 trait 动态色——产
                // 物串自此是呈现级工件（呈现直贴消
                // 费，见 MarkdownText 产物注入），显
                // 示时按承载视图 trait 解析（系统明
                // 暗＋应用内外观覆盖同拍）；旧静态
                // 解析色按构建拍 trait 定格、外观一
                // 变即串色过期，是呈现不敢消费产物
                // 串的根由。量测不读色、零影响
                textColor: Self.dynamicColor(foreground),
                dimmedColor: Self.dynamicColor(
                    Palette.inkSecondaryOnFill
                )
            )
        }

        var works: [SegmentWork] = []
        var structuralCount = 0
        if isUser {
            let attributed = assemble(
                // §271：与呈现侧（ChatView 用户气泡）
                // 同一 run 层整形，量测与呈现不分家
                [InlineTextParagraph(
                    runs: TextShaping.shapeRuns(
                        InlineRunBuilder.plainRuns(renderedText)
                    )
                )],
                foreground: Palette.userBubbleText
            )
            works.append(SegmentWork(
                index: 0, kind: .plain,
                attributed: attributed, measureWidth: width
            ))
        } else {
            let plan = LayoutProductPlan.plan(
                forAssistantText: renderedText
            )
            structuralCount = plan.structuralSegmentCount
            for segment in plan.textSegments {
                switch segment {
                case .prose(let index, let paragraphs):
                    works.append(SegmentWork(
                        index: index, kind: .prose,
                        attributed: assemble(
                            MarkdownText.proseParagraphs(paragraphs),
                            foreground: Palette.bodyInk
                        ),
                        measureWidth: width
                    ))
                case .quote(let index, let lines):
                    // 引用文本可用宽＝气泡文本宽−（竖
                    // 条 3＋HStack 间距 spacingS）——
                    // 与 blockquoteView 的几何同值
                    let quoteWidth = width
                        - (3 + OneDayMetrics.spacingS)
                    works.append(SegmentWork(
                        index: index, kind: .quote,
                        attributed: assemble(
                            MarkdownText.quoteParagraphs(lines),
                            foreground: Palette
                                .inkSecondaryOnFill
                        ),
                        measureWidth: quoteWidth
                    ))
                }
            }
        }
        return (works, structuralCount)
    }

    /// trait 动态色（§335）：按承载视图 trait 的
    /// 明暗档逐拍解析（解析式与视图内 resolve 同
    /// 值——环境构造与旧 resolved 同式、只是延后
    /// 到显示拍按 trait 求值）；产物串跨明暗/外
    /// 观覆盖恒同串可用，颜色仍不入样式键、不影
    /// 响高（Core LayoutStyleKey 纪律不变）
    private static func dynamicColor(
        _ color: Color
    ) -> UIColor {
        UIColor { trait in
            var environment = EnvironmentValues()
            environment.colorScheme =
                trait.userInterfaceStyle == .dark
                    ? .dark : .light
            return UIColor(
                cgColor: color.resolve(in: environment)
                    .cgColor
            )
        }
    }
}

// MARK: - 影子对拍账本

/// 影子对拍（蓝图 §2 包 2 验收门）：现量测的每
/// 一次 sizeThatFits 都把（属性串、宽、现值高）
/// 记一笔账，后台量测池复量同串同宽、逐笔比对。
/// 只记账、不消费——现量测仍是行高唯一来源。
///
/// 纪律：
/// - 去重节流：同（文本哈希×宽）只记首笔，滚动
///   重排的成千上万次重复量测不灌满量测池；账面
///   覆盖的是「不同文本×不同宽」的全集；
/// - 一致口径：|池高 − 现值| ≤ 1.0pt 记一致（现
///   量测经 UITextView.sizeThatFits 有其自身的取
///   整/边界口径，亚点级差属同值）；超差样本留
///   前 8 条（文本前缀＋双值）供逐条解释；
/// - 空串豁免：空文本池口径返 0、现量测回字体行
///   高，两口径定义不同——记豁免计数、不记不一
///   致（报告 §四逐条说明）
final class LayoutShadowLedger: @unchecked Sendable {
    static let shared = LayoutShadowLedger()

    struct Mismatch: Sendable {
        var textPrefix: String
        var width: Double
        var referenceHeight: Double
        var pooledHeight: Double
        var delta: Double { abs(pooledHeight - referenceHeight) }
    }

    struct Snapshot: Sendable {
        var compared = 0
        var consistent = 0
        var inconsistent = 0
        var exemptedEmpty = 0
        var maxDelta = 0.0
        var samples: [Mismatch] = []
    }

    private let lock = NSLock()
    private var seen: Set<String> = []
    private var state = Snapshot()

    /// 一致判定阈值（pt）
    static let tolerance = 1.0

    func record(
        attributed: NSAttributedString,
        width: CGFloat,
        referenceHeight: CGFloat
    ) {
        guard width > 0 else { return }
        if attributed.length == 0 {
            lock.lock()
            state.exemptedEmpty += 1
            lock.unlock()
            return
        }
        let dedupeKey = "\(LayoutProductKey.fnv1a(attributed.string))"
            + "|\(attributed.length)"
            + "|\(LayoutProductKey.quantizedWidth(Double(width)))"
        lock.lock()
        if seen.contains(dedupeKey) {
            lock.unlock()
            return
        }
        seen.insert(dedupeKey)
        if seen.count > 4096 {
            // 去重集有界：超限整体重置（账面覆盖目
            // 的已达，不许影子设施自带无界内存）
            seen = [dedupeKey]
        }
        lock.unlock()

        let prefix = String(attributed.string.prefix(80))
        // NSAttributedString 非 Sendable：装箱过
        // detached 边界——串组装后不可变、跨线只
        // 读，与 §149 拼装缓存的 @unchecked 口径同
        let boxed = LayoutAttributedBox(attributed)
        Task.detached(priority: .utility) { [self, boxed] in
            let pooled = await LayoutMeasurePool.shared.measure(
                boxed.value, width: width
            )
            applyResult(
                pooled: Double(pooled),
                reference: Double(referenceHeight),
                width: Double(width),
                textPrefix: prefix
            )
        }
    }

    /// 对拍结果落账（同步函数内持锁——锁不跨挂起
    /// 点，async 上下文不直接碰 NSLock 的 Swift 6
    /// 口径）
    private func applyResult(
        pooled: Double, reference: Double,
        width: Double, textPrefix: String
    ) {
        let delta = abs(pooled - reference)
        lock.lock()
        state.compared += 1
        state.maxDelta = max(state.maxDelta, delta)
        if delta <= Self.tolerance {
            state.consistent += 1
        } else {
            state.inconsistent += 1
            if state.samples.count < 8 {
                state.samples.append(Mismatch(
                    textPrefix: textPrefix,
                    width: width,
                    referenceHeight: reference,
                    pooledHeight: pooled
                ))
            }
        }
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func reset() {
        lock.lock()
        seen = []
        state = Snapshot()
        lock.unlock()
    }
}
