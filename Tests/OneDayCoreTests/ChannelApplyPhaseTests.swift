import XCTest
@testable import OneDayCore

/// 生效相位判定（频道二期，2026-11-13；与
/// channel-apply-copy 包同形态）：回执三值×status
/// 终态的组合逐格钉死——相位只在「刚保存、status
/// 还没翻」时出头，status 一旦给出终态（connected
/// /error）呈现完全归 status；旧版伴生无回执字段
/// 时相位恒 .none，与旧行为同形。
final class ChannelApplyPhaseTests: XCTestCase {

    func testTriggeredWithoutErrorIsApplying() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: nil,
                statusState: "pending_restart"),
            .applying)
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: "",
                statusState: "not_configured"),
            .applying)
    }

    func testTriggerFailureCarriesReason() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: false, applyError: "没能即时生效",
                statusState: "pending_restart"),
            .applyFailed(reason: "没能即时生效"))
    }

    func testSavedWithoutTriggerAwaitsRestart() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: false, applyError: nil,
                statusState: "pending_restart"),
            .awaitingRestart)
    }

    func testTerminalStatusRetiresPhase() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: nil,
                statusState: "connected"),
            .none)
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: false, applyError: "没能即时生效",
                statusState: "error"),
            .none)
    }

    func testMissingReceiptIsNone() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: nil, applyError: nil,
                statusState: "pending_restart"),
            .none)
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: nil, applyError: nil,
                statusState: nil),
            .none)
    }
}
