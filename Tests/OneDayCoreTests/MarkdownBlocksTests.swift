import OneDayCore
import XCTest

/// 渲染补全包（0.36.25）的解析层钉测：Core
/// MarkdownParser 块级结构、MarkdownInline 删除线分
/// 段、CodeHighlight 词法五类。视图呈现不在此测——
/// 结构对了呈现才有据（与 MessageActionsTests 同分工）
final class MarkdownBlocksTests: XCTestCase {

    // MARK: - 段落与标题

    func testPlainParagraph() {
        XCTAssertEqual(
            MarkdownParser.parse("你好，世界"),
            [.paragraph("你好，世界")]
        )
    }

    func testMultilineParagraphJoinsWithNewline() {
        XCTAssertEqual(
            MarkdownParser.parse("第一行\n第二行"),
            [.paragraph("第一行\n第二行")]
        )
    }

    func testAllSixHeadingLevels() {
        let blocks = MarkdownParser.parse(
            "# 一\n## 二\n### 三\n#### 四\n##### 五\n###### 六"
        )
        XCTAssertEqual(blocks, [
            .heading(text: "一", level: 1),
            .heading(text: "二", level: 2),
            .heading(text: "三", level: 3),
            .heading(text: "四", level: 4),
            .heading(text: "五", level: 5),
            .heading(text: "六", level: 6),
        ])
    }

    func testHeadingRequiresSpaceAfterHashes() {
        XCTAssertEqual(
            MarkdownParser.parse("#话题不是标题"),
            [.paragraph("#话题不是标题")]
        )
    }

    func testSevenHashesIsNotHeading() {
        XCTAssertEqual(
            MarkdownParser.parse("####### 太深了"),
            [.paragraph("####### 太深了")]
        )
    }

    func testHeadingClosingHashesStripped() {
        XCTAssertEqual(
            MarkdownParser.parse("## 标题 ##"),
            [.heading(text: "标题", level: 2)]
        )
    }

    // MARK: - 代码块

    func testCodeFenceCapturesLanguage() {
        XCTAssertEqual(
            MarkdownParser.parse("```python\nprint(1)\n```"),
            [.code(code: "print(1)", language: "python")]
        )
    }

    func testCodeFenceWithoutLanguage() {
        XCTAssertEqual(
            MarkdownParser.parse("```\nplain\n```"),
            [.code(code: "plain", language: nil)]
        )
    }

    func testUnclosedFenceBecomesCodeToEnd() {
        // 流式半截口径：未闭合围栏按已开围栏续渲
        XCTAssertEqual(
            MarkdownParser.parse("前文\n```swift\nlet a = 1"),
            [
                .paragraph("前文"),
                .code(code: "let a = 1", language: "swift"),
            ]
        )
    }

    func testCodeContentIsVerbatim() {
        XCTAssertEqual(
            MarkdownParser.parse("```\n# 不是标题\n- 不是列表\n```"),
            [.code(code: "# 不是标题\n- 不是列表", language: nil)]
        )
    }

    // MARK: - 引用块

    func testBlockquoteMergesLines() {
        XCTAssertEqual(
            MarkdownParser.parse("> 第一句\n> 第二句"),
            [.blockquote(lines: [
                MarkdownQuoteLine(depth: 1, text: "第一句"),
                MarkdownQuoteLine(depth: 1, text: "第二句"),
            ])]
        )
    }

    func testBlockquoteNestedDepth() {
        XCTAssertEqual(
            MarkdownParser.parse("> 外层\n>> 内层"),
            [.blockquote(lines: [
                MarkdownQuoteLine(depth: 1, text: "外层"),
                MarkdownQuoteLine(depth: 2, text: "内层"),
            ])]
        )
    }

    func testBlockquoteSplitByBlankLine() {
        let blocks = MarkdownParser.parse("> 甲\n\n> 乙")
        XCTAssertEqual(blocks.count, 2)
    }

    // MARK: - 列表

    func testBulletList() {
        XCTAssertEqual(
            MarkdownParser.parse("- 苹果\n- 香蕉"),
            [.list(items: [
                MarkdownListItem(level: 0, marker: .bullet, text: "苹果"),
                MarkdownListItem(level: 0, marker: .bullet, text: "香蕉"),
            ])]
        )
    }

    func testOrderedListKeepsNumbers() {
        XCTAssertEqual(
            MarkdownParser.parse("1. 第一\n2. 第二"),
            [.list(items: [
                MarkdownListItem(
                    level: 0, marker: .ordered(number: 1), text: "第一"
                ),
                MarkdownListItem(
                    level: 0, marker: .ordered(number: 2), text: "第二"
                ),
            ])]
        )
    }

    func testNestedListLevels() {
        let blocks = MarkdownParser.parse("- 父\n  - 子\n    - 孙")
        guard case .list(let items) = blocks.first, blocks.count == 1
        else {
            return XCTFail("应为单个列表块，实际 \(blocks)")
        }
        XCTAssertEqual(items.map(\.level), [0, 1, 2])
    }

    func testTaskListMarkers() {
        XCTAssertEqual(
            MarkdownParser.parse("- [ ] 没做\n- [x] 做了"),
            [.list(items: [
                MarkdownListItem(
                    level: 0, marker: .task(checked: false), text: "没做"
                ),
                MarkdownListItem(
                    level: 0, marker: .task(checked: true), text: "做了"
                ),
            ])]
        )
    }

    func testListContinuationLineJoinsItem() {
        XCTAssertEqual(
            MarkdownParser.parse("- 第一项\n  续行内容"),
            [.list(items: [
                MarkdownListItem(
                    level: 0, marker: .bullet, text: "第一项 续行内容"
                ),
            ])]
        )
    }

    func testLooseListAcrossBlankLineStaysOneBlock() {
        let blocks = MarkdownParser.parse("- 甲\n\n- 乙")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items) = blocks.first else {
            return XCTFail("应为列表块")
        }
        XCTAssertEqual(items.count, 2)
    }

    func testOrderedListDoesNotInterruptParagraphUnlessOne() {
        // 「2024. 是…」是正文，不许被抢成列表
        XCTAssertEqual(
            MarkdownParser.parse("回顾一下\n2024. 是重要的一年"),
            [.paragraph("回顾一下\n2024. 是重要的一年")]
        )
        XCTAssertEqual(
            MarkdownParser.parse("步骤如下\n1. 先做这个"),
            [
                .paragraph("步骤如下"),
                .list(items: [
                    MarkdownListItem(
                        level: 0, marker: .ordered(number: 1),
                        text: "先做这个"
                    ),
                ]),
            ]
        )
    }

    // MARK: - 分割线

    func testHorizontalRules() {
        for source in ["---", "***", "___", "- - -"] {
            XCTAssertEqual(
                MarkdownParser.parse(source), [.divider], source
            )
        }
    }

    func testTwoDashesIsNotRule() {
        XCTAssertEqual(
            MarkdownParser.parse("--"), [.paragraph("--")]
        )
    }

    // MARK: - 表格

    func testBasicTable() {
        let source = """
        | 名称 | 数量 |
        | --- | ---: |
        | 苹果 | 3 |
        | 香蕉 | 5 |
        """
        XCTAssertEqual(
            MarkdownParser.parse(source),
            [.table(
                header: ["名称", "数量"],
                alignments: [.left, .right],
                rows: [["苹果", "3"], ["香蕉", "5"]]
            )]
        )
    }

    func testTableAlignments() {
        let source = "| A | B | C |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |"
        guard case .table(_, let alignments, _) =
                MarkdownParser.parse(source).first
        else { return XCTFail("应为表格块") }
        XCTAssertEqual(alignments, [.left, .center, .right])
    }

    func testTableWithoutOuterPipes() {
        let source = "A | B\n--- | ---\n1 | 2"
        XCTAssertEqual(
            MarkdownParser.parse(source),
            [.table(
                header: ["A", "B"],
                alignments: [.left, .left],
                rows: [["1", "2"]]
            )]
        )
    }

    func testTableRowPaddedAndTruncated() {
        let source = "| A | B |\n| --- | --- |\n| 1 |\n| 1 | 2 | 3 |"
        guard case .table(_, _, let rows) =
                MarkdownParser.parse(source).first
        else { return XCTFail("应为表格块") }
        XCTAssertEqual(rows, [["1", ""], ["1", "2"]])
    }

    func testHalfTableFallsBackToParagraph() {
        // 流式半截口径：分隔行没写完（第二列还没落笔）
        // 不成表，按原文降级；写完下一帧才成表
        XCTAssertEqual(
            MarkdownParser.parse("| 名称 | 数量 |\n| --- |"),
            [.paragraph("| 名称 | 数量 |\n| --- |")]
        )
    }

    func testTableColumnCountMismatchIsNotTable() {
        XCTAssertEqual(
            MarkdownParser.parse("| A | B |\n| --- |"),
            [.paragraph("| A | B |\n| --- |")]
        )
    }

    func testEscapedPipeInsideCell() {
        let source = "| A |\n| --- |\n| a \\| b |"
        guard case .table(_, _, let rows) =
                MarkdownParser.parse(source).first
        else { return XCTFail("应为表格块") }
        XCTAssertEqual(rows, [["a | b"]])
    }

    // MARK: - 块间关系（一锅烩样本）

    func testMixedDocument() {
        let source = """
        # 标题
        正文一段。

        - 列表项

        > 引用

        ---
        """
        let blocks = MarkdownParser.parse(source)
        XCTAssertEqual(blocks, [
            .heading(text: "标题", level: 1),
            .paragraph("正文一段。"),
            .list(items: [
                MarkdownListItem(
                    level: 0, marker: .bullet, text: "列表项"
                ),
            ]),
            .blockquote(lines: [
                MarkdownQuoteLine(depth: 1, text: "引用"),
            ]),
            .divider,
        ])
    }

    // MARK: - 删除线分段

    func testStrikethroughSegments() {
        XCTAssertEqual(
            MarkdownInline.segments("前面~~删掉~~后面"),
            [
                MarkdownInline.Segment(
                    text: "前面", strikethrough: false
                ),
                MarkdownInline.Segment(
                    text: "删掉", strikethrough: true
                ),
                MarkdownInline.Segment(
                    text: "后面", strikethrough: false
                ),
            ]
        )
    }

    func testUnclosedStrikeStaysLiteral() {
        // 流式半截口径：未闭合 ~~ 不成段、字面呈现
        XCTAssertEqual(
            MarkdownInline.segments("半截~~还没写完"),
            [MarkdownInline.Segment(
                text: "半截~~还没写完", strikethrough: false
            )]
        )
    }

    func testStrikeInsideCodeSpanDoesNotTrigger() {
        let segments = MarkdownInline.segments("`~~代码~~` 和 ~~正文~~")
        XCTAssertEqual(segments, [
            MarkdownInline.Segment(
                text: "`~~代码~~` 和 ", strikethrough: false
            ),
            MarkdownInline.Segment(
                text: "正文", strikethrough: true
            ),
        ])
    }

    func testSingleTildeIsLiteral() {
        XCTAssertEqual(
            MarkdownInline.segments("大约 ~5 个"),
            [MarkdownInline.Segment(
                text: "大约 ~5 个", strikethrough: false
            )]
        )
    }

    // MARK: - 代码高亮

    func testHighlightSwiftKeywordsStringCommentNumber() {
        let tokens = CodeHighlight.tokens(
            code: "let name = \"值\" // 注释\nlet n = 42",
            language: "swift"
        )
        XCTAssertEqual(
            tokens.map(\.text).joined(),
            "let name = \"值\" // 注释\nlet n = 42"
        )
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.comment))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertEqual(
            tokens.first(where: { $0.kind == .keyword })?.text, "let"
        )
        XCTAssertEqual(
            tokens.first(where: { $0.kind == .string })?.text, "\"值\""
        )
    }

    func testHighlightPythonHashCommentAndAlias() {
        let tokens = CodeHighlight.tokens(
            code: "def f(): # 说明\n    return True",
            language: "py"
        )
        XCTAssertEqual(
            tokens.map(\.text).joined(),
            "def f(): # 说明\n    return True"
        )
        XCTAssertEqual(
            tokens.first(where: { $0.kind == .comment })?.text,
            "# 说明"
        )
        XCTAssertTrue(
            tokens.contains(where: {
                $0.kind == .keyword && $0.text == "def"
            })
        )
    }

    func testHighlightNeverDropsCharacters() {
        // 不变式：任意语言任意代码，token 拼回恒等于原文
        let samples: [(String, String?)] = [
            ("if (x) { return \"a//b\" }", "javascript"),
            ("/* 未闭合注释", "c"),
            ("s = '半截字符串", "python"),
            ("let s = \"转义\\\"引号\"", "swift"),
            ("平凡代码没有标记", nil),
            ("{\"k\": 1}", "json"),
        ]
        for (code, language) in samples {
            XCTAssertEqual(
                CodeHighlight.tokens(
                    code: code, language: language
                ).map(\.text).joined(),
                code,
                "language=\(language ?? "nil")"
            )
        }
    }

    func testHighlightUnknownLanguageHasNoKeywords() {
        let tokens = CodeHighlight.tokens(
            code: "return value", language: "brainfuck"
        )
        XCTAssertFalse(
            tokens.contains(where: { $0.kind == .keyword })
        )
    }

    func testNormalizeLanguageAliases() {
        XCTAssertEqual(CodeHighlight.normalizeLanguage("py"), "python")
        XCTAssertEqual(CodeHighlight.normalizeLanguage("JS"), "javascript")
        XCTAssertEqual(CodeHighlight.normalizeLanguage("C++"), "cpp")
        XCTAssertNil(CodeHighlight.normalizeLanguage(""))
        XCTAssertNil(CodeHighlight.normalizeLanguage(nil))
    }
}
