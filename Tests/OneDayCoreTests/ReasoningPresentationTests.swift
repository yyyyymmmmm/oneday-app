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

    // 0.20.0 硬规格（用户 23:36）：相位默认展开态——
    // 只有纯思考期默认展开；正文起流即默认收起；落盘
    // ／历史载入（finished）恒默认收起（截图里旧会话
    // 满屏思考原文即此条钉死的形态，不许回归）
    func testPhaseDefaultExpandedOnlyWhilePureThinking() {
        XCTAssertTrue(
            ReasoningPresentation.defaultExpanded(phase: .streaming)
        )
        XCTAssertFalse(
            ReasoningPresentation.defaultExpanded(phase: .contentStarted)
        )
        XCTAssertFalse(
            ReasoningPresentation.defaultExpanded(phase: .finished)
        )
    }

    // 思考正文区限高：钉 240pt，且不许超过主流视高
    // 三分之一的保守界（730/3≈243）
    func testReasoningBodyHeightCap() {
        XCTAssertEqual(ReasoningPresentation.maxBodyHeight, 240)
        XCTAssertLessThanOrEqual(
            ReasoningPresentation.maxBodyHeight, 730.0 / 3.0
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
