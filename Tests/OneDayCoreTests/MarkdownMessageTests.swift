import OneDayCore
import XCTest

/// §161 消息级段落装配钉测：连续散文块合并成一段
/// prose（同一文本存储的前提），结构性块（引用／代
/// 码／表格／任务清单／分割线）各自独立成段且顺序
/// 不动。呈现（字体／标记／制表位）在 App 层，不在
/// 此测
final class MarkdownMessageTests: XCTestCase {

    // MARK: - 合并

    func testConsecutiveParagraphsMergeIntoOneProse() {
        let segments = MarkdownMessageAssembler.segments(
            for: "第一段\n\n第二段"
        )
        XCTAssertEqual(segments.count, 1)
        guard case .prose(let paragraphs) = segments[0] else {
            return XCTFail("应为 prose 段")
        }
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs.map(\.kind), [.body, .body])
        // 段落整形会在尾字间插 WORD JOINER（§149 既
        // 有口径、复制时剥除），比对前先剥
        XCTAssertEqual(
            paragraphs.map {
                $0.runs.map(\.text).joined()
                    .replacingOccurrences(of: "\u{2060}", with: "")
            },
            ["第一段", "第二段"]
        )
    }

    func testHeadingMergesWithSurroundingParagraphs() {
        let segments = MarkdownMessageAssembler.segments(
            for: "前文\n\n## 小节标题\n\n后文"
        )
        XCTAssertEqual(segments.count, 1)
        guard case .prose(let paragraphs) = segments[0] else {
            return XCTFail("应为 prose 段")
        }
        XCTAssertEqual(
            paragraphs.map(\.kind),
            [.body, .heading(level: 2), .body]
        )
    }

    func testPlainListMergesIntoProseWithTightSpacing() {
        let segments = MarkdownMessageAssembler.segments(
            for: "说明：\n\n- 甲\n- 乙\n  - 嵌套\n1. 第一"
        )
        XCTAssertEqual(segments.count, 1)
        guard case .prose(let paragraphs) = segments[0] else {
            return XCTFail("应为 prose 段")
        }
        XCTAssertEqual(paragraphs.count, 5)
        XCTAssertEqual(paragraphs[0].kind, .body)
        XCTAssertEqual(
            paragraphs[1].kind,
            .listItem(level: 0, marker: .bullet)
        )
        XCTAssertEqual(
            paragraphs[3].kind,
            .listItem(level: 1, marker: .bullet)
        )
        XCTAssertEqual(
            paragraphs[4].kind,
            .listItem(level: 0, marker: .ordered(number: 1))
        )
        // 项间紧凑、列表收尾回块间档
        XCTAssertTrue(paragraphs[1].tightAfter)
        XCTAssertTrue(paragraphs[2].tightAfter)
        XCTAssertTrue(paragraphs[3].tightAfter)
        XCTAssertFalse(paragraphs[4].tightAfter)
    }

    func testInlineMarksSurviveAssembly() {
        let segments = MarkdownMessageAssembler.segments(
            for: "这段有 **重点** 和 `代码` 片段"
        )
        guard case .prose(let paragraphs) = segments.first,
              paragraphs.count == 1
        else { return XCTFail("应为单段 prose") }
        let runs = paragraphs[0].runs
        XCTAssertTrue(runs.contains { $0.strong && $0.text == "重点" })
        XCTAssertTrue(runs.contains { $0.code && $0.text == "代码" })
    }

    // MARK: - 分流

    func testTaskListDivertsToOwnSegment() {
        let segments = MarkdownMessageAssembler.segments(
            for: "前文\n\n- [ ] 待办一\n- [x] 已办二\n\n后文"
        )
        XCTAssertEqual(segments.count, 3)
        guard case .prose = segments[0],
              case .taskList(let items) = segments[1],
              case .prose = segments[2]
        else { return XCTFail("任务清单应独立成段、两侧散文各一段") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].marker, .task(checked: false))
        XCTAssertEqual(items[1].marker, .task(checked: true))
    }

    func testMixedTaskAndBulletListDivertsWholly() {
        // 一块里只要有一项是任务项，整块分流（呈现
        // 形态整块一致，不许半块两种渲染）
        let segments = MarkdownMessageAssembler.segments(
            for: "- 普通项\n- [ ] 任务项"
        )
        XCTAssertEqual(segments.count, 1)
        guard case .taskList(let items) = segments[0] else {
            return XCTFail("含任务项的列表应整块分流")
        }
        XCTAssertEqual(items.count, 2)
    }

    func testQuoteCodeTableDividerSplitProse() {
        let segments = MarkdownMessageAssembler.segments(
            for: """
            前段

            > 引用一行

            ```
            let x = 1
            ```

            | 列一 | 列二 |
            | --- | --- |
            | 甲 | 乙 |

            ---

            后段
            """
        )
        XCTAssertEqual(segments.count, 6)
        guard case .prose = segments[0],
              case .quote(let lines) = segments[1],
              case .code(let code, _) = segments[2],
              case .table(let header, _, let rows) = segments[3],
              case .divider = segments[4],
              case .prose = segments[5]
        else { return XCTFail("结构块应逐个独立成段、顺序不变") }
        XCTAssertEqual(lines.map(\.text), ["引用一行"])
        XCTAssertEqual(code, "let x = 1")
        XCTAssertEqual(header, ["列一", "列二"])
        XCTAssertEqual(rows, [["甲", "乙"]])
    }

    func testEmptyContentProducesNoSegments() {
        XCTAssertEqual(
            MarkdownMessageAssembler.segments(for: ""), []
        )
        XCTAssertEqual(
            MarkdownMessageAssembler.segments(from: []), []
        )
    }

    func testParagraphAfterListStartsSameProseSegment() {
        // 列表后紧跟段落仍同属一段 prose（跨「列表→
        // 段落」界的选择正是本包要恢复的能力）
        let segments = MarkdownMessageAssembler.segments(
            for: "- 只有一项\n\n紧随段落"
        )
        XCTAssertEqual(segments.count, 1)
        guard case .prose(let paragraphs) = segments[0] else {
            return XCTFail("应为 prose 段")
        }
        XCTAssertEqual(
            paragraphs.map(\.kind),
            [.listItem(level: 0, marker: .bullet), .body]
        )
    }
}
