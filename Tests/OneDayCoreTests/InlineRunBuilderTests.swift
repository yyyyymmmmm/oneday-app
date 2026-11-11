import OneDayCore
import XCTest

/// 行内 run 拼装（§146，DESIGN-V4 §146.3 第 1 条）：
/// 气泡正文改走 UITextView 后，markdown 的读法全
/// 在本拼装——逐项钉死与旧 SwiftUI 读法同口径：
/// strong 只认 ** 且代码段除外、emphasis 独立成
/// 标、链接带 URL、删除线经 MarkdownInline 分段
/// 叠加；降级口径（未闭合字面保留、解析失败不丢
/// 字）与 plainRuns 的不解析纪律一并钉
final class InlineRunBuilderTests: XCTestCase {

    private func visibleText(_ runs: [InlineRun]) -> String {
        runs.map(\.text).joined()
    }

    func testPlainTextSingleRun() {
        let runs = InlineRunBuilder.runs(for: "今天天气不错")
        XCTAssertEqual(runs, [InlineRun(text: "今天天气不错")])
    }

    func testStrongSegment() {
        let runs = InlineRunBuilder.runs(for: "这是**重点**部分")
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0], InlineRun(text: "这是"))
        XCTAssertEqual(runs[1], InlineRun(text: "重点", strong: true))
        XCTAssertEqual(runs[2], InlineRun(text: "部分"))
        XCTAssertEqual(visibleText(runs), "这是重点部分")
    }

    func testEmphasisOnlyIsNotStrong() {
        let runs = InlineRunBuilder.runs(for: "这是*斜体*部分")
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[1].text, "斜体")
        XCTAssertTrue(runs[1].emphasis)
        XCTAssertFalse(runs[1].strong)
    }

    func testStrongPlusEmphasis() {
        let runs = InlineRunBuilder.runs(for: "***粗斜***")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].text, "粗斜")
        XCTAssertTrue(runs[0].strong)
        XCTAssertTrue(runs[0].emphasis)
    }

    func testInlineCodeNotStrong() {
        let runs = InlineRunBuilder.runs(for: "运行 `**not bold**` 命令")
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[1].text, "**not bold**")
        XCTAssertTrue(runs[1].code)
        XCTAssertFalse(runs[1].strong)
        XCTAssertFalse(runs[1].emphasis)
        XCTAssertEqual(visibleText(runs), "运行 **not bold** 命令")
    }

    func testLinkRunCarriesURL() {
        let runs = InlineRunBuilder.runs(
            for: "看[文档](https://example.com/a)这里"
        )
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[1].text, "文档")
        XCTAssertEqual(
            runs[1].link, URL(string: "https://example.com/a")
        )
        XCTAssertEqual(visibleText(runs), "看文档这里")
    }

    func testStrikethroughSegmentAndInnerStrong() {
        let runs = InlineRunBuilder.runs(for: "~~删掉**这段**~~保留")
        XCTAssertEqual(visibleText(runs), "删掉这段保留")
        let struck = runs.filter(\.strikethrough)
        XCTAssertEqual(struck.map(\.text).joined(), "删掉这段")
        XCTAssertTrue(
            struck.contains { $0.text == "这段" && $0.strong }
        )
        XCTAssertFalse(runs.last?.strikethrough ?? true)
    }

    func testUnclosedStrongStaysLiteral() {
        let runs = InlineRunBuilder.runs(for: "这是**没闭合")
        XCTAssertEqual(visibleText(runs), "这是**没闭合")
        XCTAssertFalse(runs.contains { $0.strong })
    }

    func testMixedRunsJoinToVisibleText() {
        let source = "先**加粗**再`code`和[链接](https://a.b/c)最后*斜*"
        let runs = InlineRunBuilder.runs(for: source)
        XCTAssertEqual(
            visibleText(runs), "先加粗再code和链接最后斜"
        )
        XCTAssertEqual(
            runs.filter(\.strong).map(\.text), ["加粗"]
        )
        XCTAssertEqual(runs.filter(\.code).map(\.text), ["code"])
        XCTAssertEqual(
            runs.filter { $0.link != nil }.map(\.text), ["链接"]
        )
        XCTAssertEqual(
            runs.filter(\.emphasis).map(\.text), ["斜"]
        )
    }

    func testAdjacentSameFlagRunsMerge() {
        // 相邻同标记段应合一（拼装层 run 数收敛）：
        // 两段同址链接在解析层是两个 run、拼装层合一
        let runs = InlineRunBuilder.runs(
            for: "[甲](https://a.b)[乙](https://a.b)"
        )
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(
            runs[0],
            InlineRun(text: "甲乙", link: URL(string: "https://a.b"))
        )
    }

    func testPlainRunsNeverParses() {
        let runs = InlineRunBuilder.plainRuns("**原文**与~~符号~~")
        XCTAssertEqual(runs, [InlineRun(text: "**原文**与~~符号~~")])
    }

    func testPlainRunsEmpty() {
        XCTAssertEqual(InlineRunBuilder.plainRuns(""), [])
    }

    func testEmptyInput() {
        XCTAssertEqual(InlineRunBuilder.runs(for: ""), [])
    }
}
