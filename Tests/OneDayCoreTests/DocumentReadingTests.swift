import Foundation
import XCTest
@testable import OneDayCore

/// 文档阅读页块模型（0.36.31）：文本类判定、Markdown
/// 直通 Core 解析、纯文本空行分段、CSV 成表归一、结
/// 构化文本代码块。
final class DocumentReadingTests: XCTestCase {

    func testKindMapping() {
        XCTAssertEqual(
            DocumentTextKind.kind(forFileName: "a.md"), .markdown
        )
        XCTAssertEqual(
            DocumentTextKind.kind(forFileName: "a.markdown"),
            .markdown
        )
        XCTAssertEqual(
            DocumentTextKind.kind(forFileName: "a.csv"), .csv
        )
        XCTAssertEqual(
            DocumentTextKind.kind(forFileName: "a.json"),
            .structured
        )
        XCTAssertEqual(
            DocumentTextKind.kind(forFileName: "a.txt"), .plain
        )
        XCTAssertEqual(
            DocumentTextKind.kind(forFileName: "a.log"), .plain
        )
        XCTAssertNil(DocumentTextKind.kind(forFileName: "a.html"))
        XCTAssertNil(DocumentTextKind.kind(forFileName: "a.docx"))
        XCTAssertNil(DocumentTextKind.kind(forFileName: "a.pdf"))
    }

    func testMarkdownGoesThroughParser() {
        let blocks = DocumentReading.blocks(
            for: "# 题\n\n正文", kind: .markdown
        )
        XCTAssertEqual(blocks.first, .heading(text: "题", level: 1))
        XCTAssertEqual(blocks.last, .paragraph("正文"))
    }

    func testPlainSplitsOnBlankLines() {
        let blocks = DocumentReading.blocks(
            for: "第一段\n同段续行\n\n第二段\n\n\n第三段",
            kind: .plain
        )
        XCTAssertEqual(
            blocks,
            [
                .paragraph("第一段\n同段续行"),
                .paragraph("第二段"),
                .paragraph("第三段"),
            ]
        )
    }

    func testPlainBlankTextReturnsEmpty() {
        XCTAssertEqual(
            DocumentReading.blocks(for: "  \n\n ", kind: .plain),
            []
        )
    }

    func testCSVBecomesTableWithNormalizedRows() {
        let blocks = DocumentReading.blocks(
            for: "名,量\n甲,1\n乙,2,多余\n丙",
            kind: .csv
        )
        XCTAssertEqual(
            blocks,
            [
                .table(
                    header: ["名", "量"],
                    alignments: [.left, .left],
                    rows: [["甲", "1"], ["乙", "2"], ["丙", ""]]
                ),
            ]
        )
    }

    func testCSVEmptyReturnsEmpty() {
        XCTAssertEqual(
            DocumentReading.blocks(for: "\n\n", kind: .csv), []
        )
    }

    func testStructuredBecomesCodeBlock() {
        XCTAssertEqual(
            DocumentReading.blocks(
                for: "{\"a\":1}", kind: .structured
            ),
            [.code(code: "{\"a\":1}", language: nil)]
        )
    }
}
