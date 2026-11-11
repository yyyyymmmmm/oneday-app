import OneDayCore
import XCTest

/// §167（2026-11-11）解析记忆化验收：代理指标＝
/// MarkdownParseMetrics 命中／未命中计数——同文重复
/// 求值时未命中只许在首次出现、其后全命中，证明聊
/// 天页滚动／流式期行视图的重复求值已从「全量重解
/// 析」变「查表」；同时断言记忆化前后输出逐字相等
/// （纯函数同文同果）。诊断见 chat-scroll-
/// diagnosis-20261111.md 病因 A
final class MarkdownParseMemoTests: XCTestCase {

    /// 块解析：同一正文解析两次，第二次必命中、未命
    /// 中总增量恰为 1，两次结果逐字相等
    func testBlockParseMemoizedOnSecondCall() {
        let content = "# §167 探针标题\n\n探针正文一段，带 **粗体** 与 `代码`。\n\n- 探针甲\n- 探针乙"
        let before = MarkdownParseMetrics.snapshot()
        let first = MarkdownParser.parse(content)
        let second = MarkdownParser.parse(content)
        let after = MarkdownParseMetrics.snapshot()

        XCTAssertEqual(first, second)
        XCTAssertEqual(after.blockMisses - before.blockMisses, 1)
        XCTAssertGreaterThanOrEqual(after.blockHits - before.blockHits, 1)
    }

    /// 行内 runs：内含 AttributedString(markdown:) 全
    /// 量解析、最贵的一处——同文第二次必命中
    func testInlineRunsMemoizedOnSecondCall() {
        let text = "§167 runs 探针 **加粗探针** 与 [链接](https://example.com/probe157)"
        let before = MarkdownParseMetrics.snapshot()
        let first = InlineRunBuilder.runs(for: text)
        let second = InlineRunBuilder.runs(for: text)
        let after = MarkdownParseMetrics.snapshot()

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(after.runMisses - before.runMisses, 1)
        XCTAssertGreaterThanOrEqual(after.runHits - before.runHits, 1)
    }

    /// 代码高亮词法：同代码同语言第二次必命中
    func testCodeTokensMemoizedOnSecondCall() {
        let code = "let probe157 = \"§167 token 探针\"\nprint(probe157)"
        let before = MarkdownParseMetrics.snapshot()
        let first = CodeHighlight.tokens(code: code, language: "swift")
        let second = CodeHighlight.tokens(code: code, language: "swift")
        let after = MarkdownParseMetrics.snapshot()

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(after.tokenMisses - before.tokenMisses, 1)
        XCTAssertGreaterThanOrEqual(after.tokenHits - before.tokenHits, 1)
    }

    /// 记忆盒 LRU 本体：容量 2 时按最近使用淘汰——摸
    /// 过的 a 留、没摸的 b 被 c 挤出后须重算
    func testMemoBoxEvictsLeastRecentlyUsed() {
        let box = ParseMemoBox<Int>(capacity: 2)
        var computes: [String: Int] = [:]
        func fetch(_ key: String) -> Int {
            box.value(for: key) {
                computes[key, default: 0] += 1
                return computes[key] ?? 0
            }
        }

        _ = fetch("a")
        _ = fetch("b")
        _ = fetch("a")  // 命中，a 成最近使用
        _ = fetch("c")  // 未命中，挤出最久未用的 b
        XCTAssertEqual(box.count, 2)
        _ = fetch("b")  // 已被挤出，须重算

        XCTAssertEqual(computes["a"], 1)
        XCTAssertEqual(computes["b"], 2)
        XCTAssertEqual(computes["c"], 1)
        let metrics = box.metrics()
        XCTAssertEqual(metrics.misses, 4)
        XCTAssertEqual(metrics.hits, 1)
    }

    /// 记忆化不改语义：已知样本的结构与旧口径逐项对
    /// 齐（标题层级、段落、列表项数）
    func testMemoizedParseKeepsStructure() {
        let content = "# 标题一\n\n正文一段\n\n- 甲\n- 乙\n"
        let blocks = MarkdownParser.parse(content)
        XCTAssertEqual(blocks.first, .heading(text: "标题一", level: 1))
        XCTAssertTrue(blocks.contains(.paragraph("正文一段")))
        let listItems = blocks.compactMap { block -> [MarkdownListItem]? in
            if case .list(let items) = block { return items }
            return nil
        }
        XCTAssertEqual(listItems.first?.count, 2)
    }
}
