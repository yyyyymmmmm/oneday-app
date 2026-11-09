import OneDayCore
import XCTest

final class SSEParserTests: XCTestCase {
    private var parser = SSEParser()

    func testDeltaLine() {
        let line = #"data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}"#
        XCTAssertEqual(parser.consume(line: line), .delta("你好"))
    }

    func testDoneLine() {
        XCTAssertEqual(parser.consume(line: "data: [DONE]"), .done)
    }

    func testRoleOnlyChunkIgnored() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}"#
        XCTAssertNil(parser.consume(line: line))
    }

    func testEmptyDeltaIgnored() {
        let line = #"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#
        XCTAssertNil(parser.consume(line: line))
    }

    func testNonDataLinesIgnored() {
        XCTAssertNil(parser.consume(line: ""))
        XCTAssertNil(parser.consume(line: "event: message"))
        XCTAssertNil(parser.consume(line: ": keep-alive"))
        XCTAssertNil(parser.consume(line: "id: 42"))
    }

    func testMalformedJSONIgnored() {
        XCTAssertNil(parser.consume(line: "data: {not-json"))
    }

    func testNoSpaceAfterColon() {
        let line = #"data:{"choices":[{"delta":{"content":"x"}}]}"#
        XCTAssertEqual(parser.consume(line: line), .delta("x"))
    }

    // MARK: - 思考通道（0.5.1，§32：delta.reasoning_content 独立字段）

    func testReasoningLine() {
        let line = #"data: {"choices":[{"delta":{"reasoning_content":"先想想"},"finish_reason":null}]}"#
        XCTAssertEqual(parser.consume(line: line), .reasoning("先想想"))
    }

    func testReasoningWithEmptyContent() {
        // DeepSeek 思考期形态：同帧 content 为空串、思考有值
        let line = #"data: {"choices":[{"delta":{"content":"","reasoning_content":"嗯"},"finish_reason":null}]}"#
        XCTAssertEqual(parser.consume(line: line), .reasoning("嗯"))
    }

    func testContentWinsWhenBothPresent() {
        // 分帧下发为常态；同帧并存时正文优先、思考让位，
        // 保证正文永不丢字（SSEParser 文件头口径）
        let line = #"data: {"choices":[{"delta":{"content":"答","reasoning_content":"想"},"finish_reason":null}]}"#
        XCTAssertEqual(parser.consume(line: line), .delta("答"))
    }

    func testEmptyReasoningIgnored() {
        let line = #"data: {"choices":[{"delta":{"reasoning_content":""},"finish_reason":null}]}"#
        XCTAssertNil(parser.consume(line: line))
    }
}
