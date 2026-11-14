import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// §245（2026-11-14）排版产物服务（换代包 2）
///
/// 产物层（蓝图 §1.3）的 App 侧门面：按键查 Core
/// 产物缓存 → 未命中按呈现同源映射拼装段落属性串
/// → 后台量测池逐段量高 → 组产物回存。高度先以
/// 影子模式运行：本服务与 LayoutShadowLedger 只算
/// 只记账，**没有任何呈现消费方**——行高来源仍是
/// §168 现量测视图，消费切换归包 3。
///
/// 拼装同源纪律：段落映射只用 MarkdownText 的单
/// 源静态映射（proseParagraphs/quoteParagraphs）＋
/// SelectableInlineText.build 本体——产物层不另拼
/// 一套，否则影子对拍比的是两套拼装、毫无意义。
/// 颜色按当前 trait 环境解析（量测工件用；颜色
/// 不入样式键、不影响高，见 Core LayoutStyleKey）

// MARK: - 样式上下文

/// 样式快照：视图环境（字号档/粗体开关）在调用点
/// 摘出、显式贯穿产物链（同 ComposerTextMetrics
/// A11Y-D1 的贯穿口径——量测档必须与排版档同源）
struct LayoutStyleContext: Equatable {
    var sizeCategory: UIContentSizeCategory
    var boldText: Bool

    /// 聊天正文统一字阶（§152/§168：气泡正文恒
    /// .callout，用户泡与助手泡同档）
    var coreKey: LayoutStyleKey {
        LayoutStyleKey(
            textStyle: UIFont.TextStyle.callout.rawValue,
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

    func preheat(
        entries: [PreheatEntry],
        width: CGFloat,
        style: LayoutStyleContext
    ) {
        let capped = Array(entries.prefix(200))
        guard !capped.isEmpty, width > 0 else { return }
        Task.detached(priority: .utility) { [self] in
            for entry in capped {
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
        let baseFont = InlineTextFonts.baseFont(
            textStyle: .callout,
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
                textColor: Self.resolved(foreground),
                dimmedColor: Self.resolved(
                    Palette.inkSecondaryOnFill
                )
            )
        }

        var segments: [LayoutSegmentProduct] = []
        var structuralCount = 0
        if isUser {
            let attributed = assemble(
                [.plain(
                    TextShaping.prettyWrapDocument(renderedText)
                )],
                foreground: Palette.userBubbleText
            )
            let height = await pool.measure(
                attributed, width: width
            )
            segments.append(LayoutSegmentProduct(
                segmentIndex: 0, kind: .plain,
                attributed: attributed, height: Double(height)
            ))
        } else {
            let plan = LayoutProductPlan.plan(
                forAssistantText: renderedText
            )
            structuralCount = plan.structuralSegmentCount
            for segment in plan.textSegments {
                switch segment {
                case .prose(let index, let paragraphs):
                    let attributed = assemble(
                        MarkdownText.proseParagraphs(paragraphs),
                        foreground: Palette.bodyInk
                    )
                    let height = await pool.measure(
                        attributed, width: width
                    )
                    segments.append(LayoutSegmentProduct(
                        segmentIndex: index, kind: .prose,
                        attributed: attributed,
                        height: Double(height)
                    ))
                case .quote(let index, let lines):
                    let attributed = assemble(
                        MarkdownText.quoteParagraphs(lines),
                        foreground: Palette.inkSecondaryOnFill
                    )
                    // 引用文本可用宽＝气泡文本宽−（竖
                    // 条 3＋HStack 间距 spacingS）——
                    // 与 blockquoteView 的几何同值
                    let quoteWidth = width
                        - (3 + OneDayMetrics.spacingS)
                    let height = await pool.measure(
                        attributed, width: quoteWidth
                    )
                    segments.append(LayoutSegmentProduct(
                        segmentIndex: index, kind: .quote,
                        attributed: attributed,
                        height: Double(height)
                    ))
                }
            }
        }
        return LayoutProduct(
            key: key,
            segments: segments,
            structuralSegmentCount: structuralCount
        )
    }

    /// 环境外解析颜色：按当前 trait 的明暗档构造
    /// 环境值解析（与视图内 resolve 同色值；仅作
    /// 量测工件的属性，不影响高）
    private static func resolved(_ color: Color) -> UIColor {
        var environment = EnvironmentValues()
        environment.colorScheme =
            UITraitCollection.current.userInterfaceStyle == .dark
                ? .dark : .light
        return UIColor(
            cgColor: color.resolve(in: environment).cgColor
        )
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
