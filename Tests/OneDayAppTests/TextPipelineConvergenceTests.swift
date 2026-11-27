import XCTest
import SwiftUI
@testable import OneDayApp
import OneDayCore

/// §392 钉测：文本管线归属收敛——
/// ①语义等价：表格格呈现映射 `MarkdownText
/// .cellAttributed` 改走 Core InlineRunBuilder
/// 单源后，逐 run 的文字/intent/strong 字体/删线
/// /链接与旧 App 自带系统解析读法逐项同口径；
/// ②结构钉：App 层零行内解析（禁词回潮即红）、
/// 删除线分段不许 App 直调、B 类分页装配调用点
/// 恰一处（私抄防回潮）
final class TextPipelineConvergenceTests: XCTestCase {

    private let strongFont = Font.callout.weight(.bold)

    private func characters(
        of attributed: AttributedString
    ) -> String {
        String(attributed.characters)
    }

    // MARK: - 语义等价

    func testPlainCellTextStaysUnstyled() {
        let attributed = MarkdownText.cellAttributed(
            "普通文本一格", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "普通文本一格")
        for run in attributed.runs {
            let piece = attributed[run.range]
            XCTAssertNil(piece.font)
            XCTAssertNil(run.inlinePresentationIntent)
            XCTAssertNil(piece.strikethroughStyle)
            XCTAssertNil(piece.link)
        }
    }

    func testStrongRunMapsToStrongFont() {
        let attributed = MarkdownText.cellAttributed(
            "**粗体**与正文", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "粗体与正文")
        let runs = Array(attributed.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(
            runs[0].inlinePresentationIntent, [.stronglyEmphasized]
        )
        XCTAssertEqual(
            attributed[runs[0].range].font, strongFont
        )
        XCTAssertNil(runs[1].inlinePresentationIntent)
        XCTAssertNil(attributed[runs[1].range].font)
    }

    func testStrongEmphasisRunGetsItalicStrongFont() {
        let attributed = MarkdownText.cellAttributed(
            "***粗斜***", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "粗斜")
        let runs = Array(attributed.runs)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(
            runs[0].inlinePresentationIntent,
            [.stronglyEmphasized, .emphasized]
        )
        XCTAssertEqual(
            attributed[runs[0].range].font, strongFont.italic()
        )
    }

    func testEmphasisOnlyRunKeepsBaseFont() {
        let attributed = MarkdownText.cellAttributed(
            "*斜体*", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "斜体")
        let runs = Array(attributed.runs)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(
            runs[0].inlinePresentationIntent, [.emphasized]
        )
        XCTAssertNil(attributed[runs[0].range].font)
    }

    func testInlineCodeStaysLiteralAndUnstruck() {
        let code = MarkdownText.cellAttributed(
            "`**码**`", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: code), "**码**")
        for run in code.runs {
            XCTAssertEqual(run.inlinePresentationIntent, [.code])
            XCTAssertNil(code[run.range].font)
        }
        // 删除线段内的代码不许被划（旧口径同）
        let struck = MarkdownText.cellAttributed(
            "~~`删码`~~", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: struck), "删码")
        for run in struck.runs {
            XCTAssertEqual(run.inlinePresentationIntent, [.code])
            XCTAssertNil(
                struck[run.range].strikethroughStyle,
                "代码段不许被删线划过"
            )
        }
    }

    func testStrikethroughRunIsStruck() {
        let attributed = MarkdownText.cellAttributed(
            "~~删除~~", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "删除")
        let runs = Array(attributed.runs)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(
            attributed[runs[0].range].strikethroughStyle, .single
        )
    }

    func testLinkRunCarriesURL() {
        let attributed = MarkdownText.cellAttributed(
            "[文档](https://example.com/a)",
            strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "文档")
        let runs = Array(attributed.runs)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(
            attributed[runs[0].range].link,
            URL(string: "https://example.com/a")
        )
    }

    func testUnclosedDelimiterStaysLiteral() {
        let attributed = MarkdownText.cellAttributed(
            "**未闭合", strongFont: strongFont
        )
        XCTAssertEqual(characters(of: attributed), "**未闭合")
        for run in attributed.runs {
            XCTAssertNil(attributed[run.range].font)
            XCTAssertNil(run.inlinePresentationIntent)
        }
    }

    // MARK: - 结构钉

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftSources(
        under relative: String
    ) throws -> [(path: String, text: String)] {
        let root = repoRoot().appendingPathComponent(relative)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            )
        )
        var result: [(String, String)] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift" {
            result.append((
                url.lastPathComponent,
                try String(contentsOf: url, encoding: .utf8)
            ))
        }
        return result
    }

    func testAppLayerHasNoInlineMarkdownParsing() throws {
        let sources = try swiftSources(under: "Sources/OneDayApp")
        XCTAssertFalse(sources.isEmpty)
        for (name, text) in sources {
            XCTAssertFalse(
                text.contains("AttributedString(markdown"),
                "§392：App 层不许再自带系统行内解析（\(name)）"
            )
            XCTAssertFalse(
                text.contains("MarkdownParsingOptions"),
                "§392：App 层不许再自带系统行内解析（\(name)）"
            )
            XCTAssertFalse(
                text.contains("MarkdownInline.segments"),
                "§392：删除线分段只许 Core 内消费（\(name)）"
            )
        }
    }

    func testSessionPageCallHasSingleOwner() throws {
        var hits: [String] = []
        for dir in ["Sources/OneDayApp", "Sources/OneDayCore"] {
            for (name, text) in try swiftSources(under: dir) {
                if text.contains(".serverSessionsPage(") {
                    hits.append(name)
                }
            }
        }
        XCTAssertEqual(
            hits, ["SessionLedger.swift"],
            "§392/B 类防回潮：分页装配调用点全仓恰一处且归账本，实测 \(hits)"
        )
    }
}
