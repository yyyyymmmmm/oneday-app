import OneDayCore
import XCTest

/// 思考折叠单元呈现判定（0.5.1，§32）：展开口径与
/// 标题文案（流式计时/落盘秒数/无数据不编数）。
final class ReasoningPresentationTests: XCTestCase {

    func testShowsTextOnlyWhenStreamingOrExpanded() {
        XCTAssertTrue(
            ReasoningPresentation.showsText(isStreaming: true, expanded: false)
        )
        XCTAssertTrue(
            ReasoningPresentation.showsText(isStreaming: false, expanded: true)
        )
        XCTAssertFalse(
            ReasoningPresentation.showsText(isStreaming: false, expanded: false)
        )
    }

    func testStreamingHeaderWithoutElapsed() {
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: true, seconds: nil, elapsed: nil),
            "思考中"
        )
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: true, seconds: nil, elapsed: 0.4),
            "思考中"
        )
    }

    func testStreamingHeaderWithElapsed() {
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: true, seconds: nil, elapsed: 7.9),
            "思考中 · 7 秒"
        )
    }

    func testFinishedHeaderVariants() {
        // 无落盘数据（历史导入等）：只显「已思考」不编数
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: false, seconds: nil, elapsed: nil),
            "已思考"
        )
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: false, seconds: 0.4, elapsed: nil),
            "已思考 · 不到 1 秒"
        )
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: false, seconds: 12.3, elapsed: nil),
            "已思考 · 约 12 秒"
        )
        XCTAssertEqual(
            ReasoningPresentation.header(isStreaming: false, seconds: 12.6, elapsed: nil),
            "已思考 · 约 13 秒"
        )
    }
}
