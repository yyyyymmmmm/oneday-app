import OneDayCore
import XCTest

/// 工具卡卡级呈现（0.36.10，诊断 D2/D3）：状态只看
/// 本卡结果、无意义输出判定、一行状态语、组头摘要、
/// 旧落盘卡解码兼容。事故样本即 2026-11-10 20:44
/// 实拍：terminal 结果原文 "---" 被当正文、回答完了
/// 整片卡还挂「进行中」。
final class ToolCardPresentationTests: XCTestCase {

    private func card(
        result: String?, failed: Bool = false,
        category: ToolCardCategory = .terminal
    ) -> ToolCard {
        ToolCard(
            id: "c1", toolName: "terminal", category: category,
            title: "运行命令", summary: "", result: result,
            resultFailed: failed
        )
    }

    // MARK: - 卡级状态（D2）

    func testStateIsPerCardNotPerTurn() {
        XCTAssertEqual(
            ToolCardPresentation.state(of: card(result: nil)),
            .running
        )
        XCTAssertEqual(
            ToolCardPresentation.state(of: card(result: "done")),
            .succeeded
        )
        XCTAssertEqual(
            ToolCardPresentation.state(
                of: card(result: "boom", failed: true)
            ),
            .failed
        )
        // 结果已回的卡就是落定——与整轮是否落定无关
        XCTAssertNotEqual(
            ToolCardPresentation.state(of: card(result: "---")),
            .running
        )
    }

    // MARK: - 无意义输出（D3-7）

    func testMeaninglessOutputDetection() {
        XCTAssertTrue(ToolResultUnwrap.isMeaningless(""))
        XCTAssertTrue(ToolResultUnwrap.isMeaningless("  \n "))
        XCTAssertTrue(ToolResultUnwrap.isMeaningless("---"))
        XCTAssertTrue(ToolResultUnwrap.isMeaningless("=== ***"))
        XCTAssertFalse(ToolResultUnwrap.isMeaningless("done"))
        XCTAssertFalse(ToolResultUnwrap.isMeaningless("- item"))
        XCTAssertFalse(ToolResultUnwrap.isMeaningless("exit 1"))
    }

    // MARK: - 一行状态语

    func testStatusLine() {
        XCTAssertEqual(
            ToolCardPresentation.statusLine(of: card(result: nil)),
            "进行中"
        )
        // 成功无输出：呈「（无输出）」，不画符号
        XCTAssertEqual(
            ToolCardPresentation.statusLine(of: card(result: "---")),
            "（无输出）"
        )
        // 成功有输出：首行净化
        XCTAssertEqual(
            ToolCardPresentation.statusLine(
                of: card(result: "done\n第二行")
            ),
            "done"
        )
        // 失败带原因首行（D3-9）
        XCTAssertEqual(
            ToolCardPresentation.statusLine(
                of: card(result: "command not found", failed: true)
            ),
            "失败 · command not found"
        )
        // 失败且结果无意义：只剩「失败」
        XCTAssertEqual(
            ToolCardPresentation.statusLine(
                of: card(result: "---", failed: true)
            ),
            "失败"
        )
        // 浏览器 Page 首行：只出 URL
        XCTAssertEqual(
            ToolCardPresentation.statusLine(
                of: card(
                    result: "Page: Example Domain (https://example.com/)",
                    category: .browser
                )
            ),
            "https://example.com/"
        )
    }

    // MARK: - 组头摘要（D3-8）

    func testGroupHeader() {
        let done = card(result: "ok")
        let failed = card(result: "boom", failed: true)
        let running = card(result: nil)
        XCTAssertEqual(
            ToolCardPresentation.groupHeader(cards: [done, done]),
            "调用了 2 个工具 · 全部完成"
        )
        XCTAssertEqual(
            ToolCardPresentation.groupHeader(
                cards: [done, failed, done]
            ),
            "调用了 3 个工具 · 1 个失败"
        )
        XCTAssertEqual(
            ToolCardPresentation.groupHeader(
                cards: [running, failed, done]
            ),
            "调用了 3 个工具 · 1 个进行中 · 1 个失败"
        )
        XCTAssertEqual(
            ToolCardPresentation.groupHeader(cards: [running, done]),
            "调用了 2 个工具 · 1 个进行中"
        )
    }

    // MARK: - 未知工具成卡的中文回落（D3-3）

    func testAccumulatorUnknownToolUsesChineseFallback() {
        var accumulator = ToolCallStreamAccumulator()
        let frag = ChatStreamChunk.ToolCallFragment(
            index: 0, id: "call_z",
            function: .init(
                name: "mcp__foo__do_thing", arguments: "{}"
            )
        )
        _ = accumulator.ingest([frag])
        let cards = accumulator.flush()
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.title, "工具调用")
        XCTAssertEqual(cards.first?.category, .other)
    }

    // MARK: - 旧落盘卡解码兼容（arguments 缺键）

    func testLegacyCardJSONDecodesWithoutArguments() throws {
        let json = """
        {"id": "x", "toolName": "terminal", "category": "terminal",
         "title": "运行命令", "summary": "ls", "result": null,
         "resultFailed": false}
        """
        let decoded = try JSONDecoder().decode(
            ToolCard.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.toolName, "terminal")
        XCTAssertNil(decoded.arguments)
        XCTAssertNil(decoded.result)
    }

    /// 新卡 arguments 落盘往返不丢
    func testCardArgumentsRoundTrip() throws {
        let original = ToolCard(
            id: "y", toolName: "terminal", category: .terminal,
            title: "运行命令", summary: "ls", result: "ok",
            resultFailed: false,
            arguments: #"{"command": "ls"}"#
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ToolCard.self, from: data
        )
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.arguments, #"{"command": "ls"}"#)
    }
}
