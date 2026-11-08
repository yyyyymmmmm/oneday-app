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
}
