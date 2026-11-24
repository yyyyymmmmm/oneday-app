import XCTest
@testable import OneDayCore

/// §494（2026-11-24）流式块级切分重建钉测：切
/// 块分类／规范源确定性／尾块与闭合前缀／**追
/// 加生长下闭合块冻结**／闭合前缀重解析往返／
/// 表格尾部重分类只动尾块／开关缺省／落定映射
/// 首占规则。§247 原套件（§409 步 D 随簇退役）
/// 按现行树解析核复原：解析源已换 Markdown-
/// Parser.parse（§417），断言口径逐项同原版；
/// 块产物身份/组合账两节随产物通道退役不复原
final class StreamingBlockProductTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StreamingBlockSegmenter.resetCachesForTesting()
    }

    private func kinds(_ text: String) -> [StreamingBlockKind] {
        StreamingBlockSegmenter.blocks(for: text).map(\.kind)
    }

    // MARK: - 切块分类

    func testSegmentationClassifiesBlockKinds() {
        XCTAssertEqual(kinds("你好世界"), [.paragraph])
        XCTAssertEqual(
            kinds("# 标题\n\n正文段"), [.heading, .paragraph])
        XCTAssertEqual(
            kinds("- 甲\n- 乙\n\n段落"), [.list, .paragraph])
        XCTAssertEqual(
            kinds("1. 一\n2. 二"), [.list])
        XCTAssertEqual(
            kinds("- [ ] 待办\n- [x] 已办"), [.taskList])
        XCTAssertEqual(kinds("> 引用一\n> 引用二"), [.blockquote])
        XCTAssertEqual(
            kinds("```swift\nlet a = 1\n```\n\n后文"),
            [.code, .paragraph])
        XCTAssertEqual(
            kinds("| 名 | 量 |\n| :--- | ---: |\n| 米 | 3 |"),
            [.table])
        XCTAssertEqual(
            kinds("前文\n\n---\n\n后文"),
            [.paragraph, .divider, .paragraph])
        // 未闭合围栏：尾块即代码块（解析层半截口径）
        XCTAssertEqual(
            kinds("引子\n\n```\nlet x"), [.paragraph, .code])
        XCTAssertTrue(
            StreamingBlockSegmenter.blocks(for: "").isEmpty)
    }

    func testCanonicalSourcesAreDeterministic() {
        let blocks = StreamingBlockSegmenter.blocks(
            for: "## 小标题\n\n> 引一\n> 引二\n\n| 名 | 量 |\n| :--- | ---: |\n| 米 | 3 |")
        XCTAssertEqual(blocks[0].sourceText, "## 小标题")
        XCTAssertEqual(blocks[1].sourceText, "> 引一\n> 引二")
        XCTAssertEqual(
            blocks[2].sourceText,
            "| 名 | 量 |\n| :--- | ---: |\n| 米 | 3 |")
        let code = StreamingBlockSegmenter.blocks(
            for: "```swift\nlet a = 1\n```")
        // 身份形态不带闭合围栏：围栏闭合的那一拍
        // 块内容不变（冻结性的一部分）
        XCTAssertEqual(code[0].sourceText, "```swift\nlet a = 1")
        let tasks = StreamingBlockSegmenter.blocks(
            for: "- [ ] 待办\n- [x] 已办")
        XCTAssertEqual(
            tasks[0].sourceText, "- [ ] 待办\n- [x] 已办")
    }

    // MARK: - 尾块与闭合前缀

    func testTailAndClosedPrefix() {
        let blocks = StreamingBlockSegmenter.blocks(
            for: "甲段\n\n- 乙\n\n丙段")
        XCTAssertEqual(blocks.map(\.isTail), [false, false, true])
        XCTAssertEqual(
            StreamingBlockSegmenter.closedPrefix(of: blocks),
            "甲段\n\n- 乙")
        XCTAssertEqual(
            StreamingBlockSegmenter.tailSource(of: blocks), "丙段")
        // 单块：无闭合前缀
        let single = StreamingBlockSegmenter.blocks(for: "独段")
        XCTAssertEqual(
            StreamingBlockSegmenter.closedPrefix(of: single), "")
        // 代码块拼进前缀须补闭合围栏（防吞后续块）
        let withCode = StreamingBlockSegmenter.blocks(
            for: "```\na\n```\n\n尾段")
        XCTAssertEqual(
            StreamingBlockSegmenter.closedPrefix(of: withCode),
            "```\na\n```")
    }

    // MARK: - 冻结性（追加生长下闭合块不变）

    func testClosedBlocksFreezeUnderAppendingGrowth() {
        // 模拟发布门驱动的追加式增长：每步只在末
        // 尾追加，既有闭合块的（kind, sourceText）
        // 逐步核对恒不变
        let steps = [
            "第一段开始",
            "第一段开始继续生长",
            "第一段开始继续生长\n\n## 小标题",
            "第一段开始继续生长\n\n## 小标题\n\n- 甲\n- 乙",
            "第一段开始继续生长\n\n## 小标题\n\n- 甲\n- 乙"
                + "\n\n```swift\nlet a = 1",
            "第一段开始继续生长\n\n## 小标题\n\n- 甲\n- 乙"
                + "\n\n```swift\nlet a = 1\n```",
            "第一段开始继续生长\n\n## 小标题\n\n- 甲\n- 乙"
                + "\n\n```swift\nlet a = 1\n```\n\n收尾段",
            "第一段开始继续生长\n\n## 小标题\n\n- 甲\n- 乙"
                + "\n\n```swift\nlet a = 1\n```\n\n收尾段加长",
        ]
        var frozen: [(StreamingBlockKind, String)] = []
        for text in steps {
            let blocks = StreamingBlockSegmenter.blocks(for: text)
            let closed = blocks.filter { !$0.isTail }
            XCTAssertGreaterThanOrEqual(
                closed.count, frozen.count,
                "闭合块数目不许回退")
            for (index, record) in frozen.enumerated() {
                XCTAssertEqual(closed[index].kind, record.0)
                XCTAssertEqual(closed[index].sourceText, record.1)
            }
            frozen = closed.map { ($0.kind, $0.sourceText) }
        }
    }

    /// 表格在尾部成形（段落行＋分隔行到达才成
    /// 表）：重分类只许发生在尾块，闭合块不动
    func testTableFormationOnlyReclassifiesTail() {
        let before = StreamingBlockSegmenter.blocks(
            for: "引子\n\n| 名 | 量 |")
        XCTAssertEqual(before.map(\.kind), [.paragraph, .paragraph])
        let after = StreamingBlockSegmenter.blocks(
            for: "引子\n\n| 名 | 量 |\n| --- | --- |\n| 米 | 3 |")
        XCTAssertEqual(after.map(\.kind), [.paragraph, .table])
        XCTAssertEqual(after[0].sourceText, "引子")
    }

    // MARK: - 闭合前缀往返

    func testClosedPrefixReparsesToSameClosedBlocks() {
        let samples = [
            "甲段\n\n- 乙\n\n丙段",
            "## 题\n\n> 引用\n\n```swift\nlet a = 1\n```\n\n尾段",
            "一段\n\n| 名 | 量 |\n| :--- | ---: |\n| 米 | 3 |\n\n尾段",
            "前文\n\n---\n\n后文\n\n尾段",
        ]
        for sample in samples {
            let blocks = StreamingBlockSegmenter.blocks(for: sample)
            let closed = blocks.filter { !$0.isTail }
            let prefix = StreamingBlockSegmenter
                .closedPrefix(of: blocks)
            let reparsed = StreamingBlockSegmenter.blocks(
                for: prefix + "\n\n尾")
            let reparsedClosed = reparsed.filter { !$0.isTail }
            XCTAssertEqual(
                reparsedClosed.map(\.kind), closed.map(\.kind),
                "往返块类不一致：\(sample)")
            XCTAssertEqual(
                reparsedClosed.map(\.sourceText),
                closed.map(\.sourceText),
                "往返规范源不一致：\(sample)")
        }
    }

    /// 备忘与强制全量两路逐块恒等（差分把守）
    func testMemoizedMatchesForcedFullEvaluation() {
        let samples = [
            "你好世界",
            "# 标题\n\n正文\n\n- 甲\n- 乙\n\n```\ncode",
            "| 名 | 量 |\n| :--- | ---: |\n| 米 | 3 |",
        ]
        for sample in samples {
            XCTAssertEqual(
                StreamingBlockSegmenter.blocks(for: sample),
                StreamingBlockSegmenter
                    .blocksForcingFullEvaluation(for: sample))
        }
    }

    // MARK: - 开关与落定映射（存量件回归）

    func testStreamingFeatureDefaultsToIncremental() {
        let defaults = UserDefaults(
            suiteName: "test-streaming-485-\(UUID().uuidString)")!
        XCTAssertTrue(
            ChatStreamingFeature.isIncrementalEnabled(
                defaults: defaults))
        defaults.set(false, forKey: ChatStreamingFeature.defaultsKey)
        XCTAssertFalse(
            ChatStreamingFeature.isIncrementalEnabled(
                defaults: defaults))
    }

    func testSettleMapFirstClaimantWins() {
        var map = StreamingSettleMap()
        let first = UUID()
        let second = UUID()
        XCTAssertTrue(map.record(
            entryID: first, streamRowKey: "stream-u1"))
        XCTAssertFalse(map.record(
            entryID: second, streamRowKey: "stream-u1"))
        XCTAssertEqual(map.rowKey(for: first), "stream-u1")
        XCTAssertNil(map.rowKey(for: second))
    }

    func testEntrancePlanHonorsFirstBatchAndReduceMotion() {
        XCTAssertEqual(
            StreamingEntrance.plan(
                typewriterEnabled: true, reduceMotion: false,
                isFirstBatchOfGeneration: true),
            .instant)
        XCTAssertEqual(
            StreamingEntrance.plan(
                typewriterEnabled: true, reduceMotion: true,
                isFirstBatchOfGeneration: false),
            .instant)
        XCTAssertEqual(
            StreamingEntrance.plan(
                typewriterEnabled: false, reduceMotion: false,
                isFirstBatchOfGeneration: false),
            .instant)
        XCTAssertEqual(
            StreamingEntrance.plan(
                typewriterEnabled: true, reduceMotion: false,
                isFirstBatchOfGeneration: false),
            .batchFade)
    }
}
