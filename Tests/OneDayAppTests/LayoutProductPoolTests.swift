import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §251（换代包 2）排版产物层·App 验收：
/// 后台量测池与现量测（§168 离屏量测视图）的影子
/// 对拍一致率、池的并发与不阻塞主线程、产物服务
/// 的组装/缓存、影子账本记账
final class LayoutProductPoolTests: XCTestCase {

    /// 现量测本体属 MainActor（UIView 量测的真
    /// 实口径）：参考值统一经主线取、池值在后台
    /// ——两侧线程归属与生产一致。跨边界一律经
    /// LayoutAttributedBox 装箱（静态函数不捕获
    /// self——Swift 6 sending 口径，测试与生产同
    /// 一条过界路）
    @MainActor
    private static func referenceOnMain(
        _ box: LayoutAttributedBox, width: CGFloat
    ) -> CGFloat {
        SelectableTextRepresentable.referenceHeight(
            attributed: box.value, width: width
        )
    }

    // MARK: - 拼装助手（与产物 builder 同源同参）

    private func assemble(
        _ paragraphs: [InlineTextParagraph]
    ) -> NSAttributedString {
        let category = UIContentSizeCategory.large
        return SelectableInlineText.build(
            paragraphs: paragraphs,
            baseFont: InlineTextFonts.baseFont(
                textStyle: .callout, category: category,
                boldText: false
            ),
            overrideFont: { style in
                InlineTextFonts.baseFont(
                    textStyle: style, category: category,
                    boldText: false
                )
            },
            textColor: .label,
            dimmedColor: .secondaryLabel
        )
    }

    private func proseAttributed(
        _ markdown: String
    ) -> NSAttributedString {
        let segments = MarkdownMessageAssembler.segments(
            for: markdown
        )
        guard case .prose(let paragraphs) = segments.first else {
            XCTFail("样本应装配出合并散文段：\(markdown.prefix(30))")
            return NSAttributedString()
        }
        return assemble(MarkdownText.proseParagraphs(paragraphs))
    }

    /// 对拍语料：短/长/中英混排/标题列表/行内格式/
    /// emoji 与 CJK——覆盖聊天正文的真实形态面
    private var corpus: [NSAttributedString] {
        [
            assemble([.plain("你好，世界。")]),
            assemble([.plain(
                String(repeating: "这是一段较长的中文正文，用来触发多行换行与逐行量测。", count: 12)
            )]),
            assemble([.plain(
                "The quick brown fox jumps over the lazy dog. "
                    + "Pack my box with five dozen liquor jugs. "
                    + "How vexingly quick daft zebras jump!"
            )]),
            proseAttributed("""
                # 标题一则

                正文一段，含**粗体**与*斜体*、行内 `code` 与[链接](https://example.com)。

                - 列表项一
                - 列表项二，内容长一些用来换行继续排下去看看悬挂缩进
                1. 有序一项
                2. 有序二项
                """),
            assemble([.plain("混排 emoji 😀🎉 与 CJK 漢字、かな、한국어，以及数字 12345.678 的一段。")]),
            assemble(MarkdownText.quoteParagraphs([
                MarkdownQuoteLine(depth: 1, text: "引用第一行"),
                MarkdownQuoteLine(depth: 2, text: "引用第二行，稍长一点点"),
            ])),
        ]
    }

    // MARK: - 对拍（蓝图 §2 包 2 验收门）

    func testPoolMatchesReferenceAcrossCorpus() async {
        let pool = LayoutMeasurePool(workerCount: 2)
        for (index, attributed) in corpus.enumerated() {
            let box = LayoutAttributedBox(attributed)
            for width in [CGFloat(326), CGFloat(200), CGFloat(500)] {
                let pooled = await pool.measure(
                    box.value, width: width
                )
                let reference = await Self.referenceOnMain(
                    box, width: width
                )
                let delta = abs(pooled - reference)
                XCTAssertLessThanOrEqual(
                    delta, LayoutShadowLedger.tolerance,
                    "语料 \(index) 宽 \(width)：池 \(pooled) vs 现量测 \(reference)"
                )
            }
        }
    }

    func testPoolDeterministicAndConcurrentSafe() async {
        let pool = LayoutMeasurePool()
        let samples = corpus.map(LayoutAttributedBox.init)
        // 顺序基准
        var baseline: [CGFloat] = []
        for box in samples {
            baseline.append(
                await pool.measure(box.value, width: 326)
            )
        }
        // 并发 4 轮全语料：同串同宽结果须与顺序值
        // 逐位相等（量测是纯函数、栈按 worker 隔离）
        let results = await withTaskGroup(
            of: (Int, CGFloat).self
        ) { group in
            for round in 0..<4 {
                for (index, box) in samples.enumerated() {
                    group.addTask {
                        (round * samples.count + index,
                         await pool.measure(box.value, width: 326))
                    }
                }
            }
            var collected: [Int: CGFloat] = [:]
            for await (slot, height) in group {
                collected[slot] = height
            }
            return collected
        }
        XCTAssertEqual(results.count, 4 * samples.count)
        for (slot, height) in results {
            XCTAssertEqual(
                height, baseline[slot % samples.count],
                accuracy: 0.001,
                "并发槽 \(slot) 与顺序基准不一致"
            )
        }
    }

    /// 主线程面纪律：影子记账的同步入口（布局期在
    /// 主线程被 sizeThatFits 调用）只许做哈希＋投
    /// 递——以约 16 万字巨串计时，同步段须远低于
    /// 一次真量测的耗时；巨串本身随后在后台完成
    /// 对拍（兼作压力对拍样本）
    func testShadowRecordIsCheapOnCallerThread() async throws {
        let ledger = LayoutShadowLedger.shared
        ledger.reset()
        let huge = assemble([.plain(
            String(repeating: "长文本量测样本，", count: 16_000)
        )])
        let reference = await Self.referenceOnMain(
            LayoutAttributedBox(huge), width: 326
        )
        let start = CFAbsoluteTimeGetCurrent()
        ledger.record(
            attributed: huge, width: 326,
            referenceHeight: reference
        )
        let syncCost = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(
            syncCost, 0.1,
            "影子记账同步段耗时 \(syncCost)s——不许在布局期做真量测"
        )
        let deadline = Date().addingTimeInterval(15)
        while ledger.snapshot().compared < 1,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(ledger.snapshot().compared, 1)
        XCTAssertEqual(ledger.snapshot().inconsistent, 0)
    }

    /// 池内并发：三名 worker 各扛一份巨串，总时
    /// 长应显著低于串行三倍（栈隔离、无全局串行
    /// 瓶颈）
    func testWorkersRunConcurrently() async {
        let pool = LayoutMeasurePool(workerCount: 3)
        let huge = assemble([.plain(
            String(repeating: "并发量测样本。", count: 12_000)
        )])
        let box = LayoutAttributedBox(huge)
        let singleStart = CFAbsoluteTimeGetCurrent()
        _ = await pool.measure(box.value, width: 326)
        let single = CFAbsoluteTimeGetCurrent() - singleStart

        let tripleStart = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: CGFloat.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await pool.measure(box.value, width: 326)
                }
            }
        }
        let triple = CFAbsoluteTimeGetCurrent() - tripleStart
        XCTAssertLessThan(
            triple, single * 2.5,
            "三份并发 \(triple)s vs 单份 \(single)s——疑串行化"
        )
    }

    // MARK: - 产物服务

    func testServiceBuildsAndCachesProduct() async throws {
        LayoutProductStore.resetMetrics()
        let service = LayoutProductService.shared
        let style = LayoutStyleContext(
            sizeCategory: .large, boldText: false
        )
        let text = """
            第一段正文，含**粗体**。

            ```swift
            let a = 1
            ```

            > 引用一行
            """
        let entryID = UUID()
        let productOrNil = await service.product(
            entryID: entryID, renderedText: text,
            isUser: false, width: 326, style: style
        )
        let product = try XCTUnwrap(productOrNil)
        XCTAssertEqual(product.segments.count, 2)
        XCTAssertEqual(product.segments.first?.kind, .prose)
        XCTAssertEqual(product.segments.last?.kind, .quote)
        XCTAssertEqual(product.structuralSegmentCount, 1)
        XCTAssertGreaterThan(product.textTotalHeight, 0)
        // 文本段高与现量测逐段对拍（端到端：拼装→
        // 池量→产物，与 §168 量测本体同值）
        for segment in product.segments {
            let width: CGFloat = segment.kind == .quote
                ? 326 - (3 + OneDayMetrics.spacingS) : 326
            let reference = await Self.referenceOnMain(
                LayoutAttributedBox(segment.attributed),
                width: width
            )
            XCTAssertEqual(
                segment.height, Double(reference),
                accuracy: LayoutShadowLedger.tolerance
            )
        }

        let missesBefore = LayoutProductStore.metrics().misses
        let second = await service.product(
            entryID: entryID, renderedText: text,
            isUser: false, width: 326, style: style
        )
        XCTAssertEqual(second?.textTotalHeight, product.textTotalHeight)
        // 第二遍命中缓存：命中 +1、未命中不增长
        XCTAssertEqual(
            LayoutProductStore.metrics().misses, missesBefore
        )
        XCTAssertGreaterThanOrEqual(
            LayoutProductStore.metrics().hits, 1
        )
    }

    func testServiceUserPlainProduct() async {
        let service = LayoutProductService.shared
        let style = LayoutStyleContext(
            sizeCategory: .large, boldText: false
        )
        let product = await service.product(
            entryID: UUID(), renderedText: "用户的一句话",
            isUser: true, width: 326, style: style
        )
        XCTAssertEqual(product?.segments.count, 1)
        XCTAssertEqual(product?.segments.first?.kind, .plain)
        XCTAssertEqual(product?.structuralSegmentCount, 0)
    }

    // MARK: - 影子账本

    func testShadowLedgerRecordsConsistentPairs() async throws {
        let ledger = LayoutShadowLedger.shared
        ledger.reset()
        // 空串走豁免口径、不进对拍
        ledger.record(
            attributed: NSAttributedString(string: ""),
            width: 326, referenceHeight: 20
        )
        XCTAssertEqual(ledger.snapshot().exemptedEmpty, 1)
        XCTAssertEqual(ledger.snapshot().compared, 0)

        let samples = Array(corpus.prefix(3))
        for attributed in samples {
            ledger.record(
                attributed: attributed, width: 326,
                referenceHeight: await Self.referenceOnMain(
                    LayoutAttributedBox(attributed), width: 326
                )
            )
        }
        // 等后台复量落账（上限 10 秒轮询）
        let deadline = Date().addingTimeInterval(10)
        while ledger.snapshot().compared < samples.count,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let snapshot = ledger.snapshot()
        XCTAssertEqual(snapshot.compared, samples.count)
        XCTAssertEqual(snapshot.inconsistent, 0)
        XCTAssertEqual(snapshot.consistent, samples.count)
    }
}
