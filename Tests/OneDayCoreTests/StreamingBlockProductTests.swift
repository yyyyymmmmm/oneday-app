import XCTest
@testable import OneDayCore

/// §247（包 4）流式块级增量产物 Core 单测：
/// 切块分类／尾块与闭合前缀／**追加生长下闭合
/// 块冻结**／**单拍成本可验设计**（每拍新身份
/// 数有界、闭合身份只增不改——单拍成本不随已
/// 落定长度增长的纯函数代偿证据）／表格尾部重
/// 分类只动尾块／闭合前缀重解析往返／组合账／
/// 开关缺省／落定映射首占规则
final class StreamingBlockProductTests: XCTestCase {

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
        // 模拟发布闸驱动的追加式增长：每步只在末
        // 尾追加，既有闭合块的（kind, sourceText,
        // 派生 id）逐步核对恒不变
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
        var frozen: [(StreamingBlockKind, String, UUID)] = []
        for text in steps {
            let blocks = StreamingBlockSegmenter.blocks(for: text)
            let closed = blocks.filter { !$0.isTail }
            // 已冻结集合必须是当前闭合集合的前缀
            XCTAssertEqual(
                closed.count >= frozen.count, true,
                "闭合块数目不许回退")
            for (index, record) in frozen.enumerated() {
                XCTAssertEqual(closed[index].kind, record.0)
                XCTAssertEqual(closed[index].sourceText, record.1)
                XCTAssertEqual(
                    StreamingBlockIdentity.entryID(
                        for: closed[index]),
                    record.2)
            }
            frozen = closed.map {
                ($0.kind, $0.sourceText,
                 StreamingBlockIdentity.entryID(for: $0))
            }
        }
        XCTAssertEqual(frozen.count, 4)
    }

    // MARK: - 单拍成本可验设计

    func testPerPublishIdentityChurnIsBounded() {
        // 以发布拍序列模拟流式生长：每拍新出现身
        // 份数 ≤2（尾块换代＋至多一回块界跨越），
        // 且任一身份一旦所在块闭合便永不消失——
        // 即单拍需要新量测的块数与已落定长度无关，
        // 只与本拍新增内容有关
        var text = ""
        var previous: [UUID] = []
        var closedIdentities = Set<UUID>()
        let tokens = [
            "长", "回", "复", "正", "文", "逐", "字", "生",
            "长", "中", "\n\n", "##", " 节", "点", "\n\n",
            "- ", "其", "一", "\n", "- ", "其", "二", "\n\n",
            "```", "\n", "le", "t ", "x", "\n", "```",
            "\n\n", "尾", "段", "继", "续",
        ]
        for token in tokens {
            text += token
            let blocks = StreamingBlockSegmenter.blocks(for: text)
            let identities = blocks.map {
                StreamingBlockIdentity.entryID(for: $0)
            }
            let fresh = identities.filter {
                !previous.contains($0)
            }
            XCTAssertLessThanOrEqual(
                fresh.count, 2,
                "一拍新身份数越界（文本：\(text.suffix(20))）")
            // 已闭合身份集合只增不减
            for id in closedIdentities {
                XCTAssertTrue(
                    identities.contains(id),
                    "闭合块身份消失（文本：\(text.suffix(20))）")
            }
            for (block, id) in zip(blocks, identities)
            where !block.isTail {
                closedIdentities.insert(id)
            }
            previous = identities
        }
    }

    // MARK: - 表格尾部重分类只动尾块

    func testTableReclassificationStaysInTail() {
        let before = StreamingBlockSegmenter.blocks(
            for: "引言段\n\n| 名 | 量 |")
        XCTAssertEqual(before.map(\.kind), [.paragraph, .paragraph])
        let closedID = StreamingBlockIdentity.entryID(
            for: before[0])
        let after = StreamingBlockSegmenter.blocks(
            for: "引言段\n\n| 名 | 量 |\n| --- | --- |")
        XCTAssertEqual(after.map(\.kind), [.paragraph, .table])
        // 重分类只发生在尾块：闭合段身份不变
        XCTAssertFalse(after[0].isTail)
        XCTAssertEqual(
            StreamingBlockIdentity.entryID(for: after[0]), closedID)
        XCTAssertTrue(after[1].isTail)
    }

    // MARK: - 闭合前缀往返

    func testClosedPrefixReparseRoundTrip() {
        let full = "## 标题\n\n正文一段\n\n- 甲\n- 乙\n\n"
            + "> 引用行\n\n```swift\nlet a = 1\n```\n\n"
            + "| 名 | 量 |\n| :--- | ---: |\n| 米 | 3 |\n\n"
            + "---\n\n尾段还在长"
        let blocks = StreamingBlockSegmenter.blocks(for: full)
        let prefix = StreamingBlockSegmenter.closedPrefix(
            of: blocks)
        let reparsed = StreamingBlockSegmenter.blocks(for: prefix)
        let closed = blocks.filter { !$0.isTail }
        XCTAssertEqual(
            reparsed.map(\.kind), closed.map(\.kind))
        XCTAssertEqual(
            reparsed.map(\.sourceText), closed.map(\.sourceText))
    }

    // MARK: - 组合账

    func testCompositionTotals() {
        let blocks = StreamingBlockSegmenter.blocks(
            for: "段一\n\n段二\n\n---")
        func product(_ text: String, _ height: Double)
            -> LayoutProduct {
            LayoutProduct(
                key: LayoutProductKey(
                    entryID: UUID(), content: text, width: 300,
                    style: LayoutStyleKey(
                        fontSize: 16.5, lineSpacing: 0,
                        fontWeight: 400, theme: "light")),
                segments: [LayoutSegmentProduct(
                    segmentIndex: 0, kind: .prose,
                    attributed: NSAttributedString(string: text),
                    height: height)],
                structuralSegmentCount: 0)
        }
        // 文本块产物未齐：整行不给组合总高
        let partial = StreamingComposition.totals(
            blocks: blocks,
            products: [product("段一", 40), nil, nil])
        XCTAssertNil(partial.textTotalHeight)
        XCTAssertEqual(partial.unmeasuredTextualCount, 1)
        XCTAssertEqual(partial.structuralSegmentCount, 1)
        // 齐备：总高＝文本段高和；结构计数含分割线
        let full = StreamingComposition.totals(
            blocks: blocks,
            products: [product("段一", 40), product("段二", 60),
                       nil])
        XCTAssertEqual(full.textTotalHeight, 100)
        XCTAssertEqual(full.textSegmentCount, 2)
        XCTAssertEqual(full.structuralSegmentCount, 1)
        XCTAssertEqual(full.unmeasuredTextualCount, 0)
    }

    // MARK: - 开关与身份

    func testStreamingFeatureDefaultsToIncremental() {
        let suite = "gen4-streaming-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(
            ChatStreamingFeature.isIncrementalEnabled(
                defaults: defaults))
        defaults.set(false, forKey: ChatStreamingFeature.defaultsKey)
        XCTAssertFalse(
            ChatStreamingFeature.isIncrementalEnabled(
                defaults: defaults))
        defaults.set(true, forKey: ChatStreamingFeature.defaultsKey)
        XCTAssertTrue(
            ChatStreamingFeature.isIncrementalEnabled(
                defaults: defaults))
    }

    func testBlockIdentityIsContentAddressed() {
        let first = StreamingBlockSegmenter.blocks(
            for: "同一段\n\n甲")
        let second = StreamingBlockSegmenter.blocks(
            for: "同一段\n\n乙")
        // 同内容的块跨文本同身份（缓存可跨条目命中）
        XCTAssertEqual(
            StreamingBlockIdentity.entryID(for: first[0]),
            StreamingBlockIdentity.entryID(for: second[0]))
        XCTAssertNotEqual(
            StreamingBlockIdentity.entryID(for: first[1]),
            StreamingBlockIdentity.entryID(for: second[1]))
    }

    func testSettleMapFirstClaimWins() {
        var map = StreamingSettleMap()
        let entryA = UUID()
        let entryB = UUID()
        let key = StreamingRowIdentity.streamRowKey(
            userEntryID: "user-1")
        XCTAssertEqual(key, "stream-user-1")
        XCTAssertTrue(map.record(entryID: entryA, streamRowKey: key))
        XCTAssertEqual(map.rowKey(for: entryA), key)
        // 同键第二认领被拒（重发轮降级本名建行）
        XCTAssertFalse(map.record(entryID: entryB, streamRowKey: key))
        XCTAssertNil(map.rowKey(for: entryB))
        XCTAssertEqual(
            StreamingRowIdentity.fallbackStreamRowKey(
                threadID: UUID(uuidString:
                    "00000000-0000-0000-0000-000000000001")!),
            "stream-thread-00000000-0000-0000-0000-000000000001")
    }
}
