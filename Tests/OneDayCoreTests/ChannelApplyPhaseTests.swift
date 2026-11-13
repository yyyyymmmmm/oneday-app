import XCTest
@testable import OneDayCore

/// 频道凭据保存后的生效相位判定（频道文案小包）：
/// 回执 applyTriggered/applyError 与 status 的合
/// 成口径——触发成功显「正在生效」、触发失败如实
/// 回退等待＋原因、未触发落等待重启；status 翻终
/// 态后流程态退场
final class ChannelApplyPhaseTests: XCTestCase {

    /// 触发成功＋网关记录还没翻：正在生效
    func testTriggeredWhilePendingShowsApplying() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: nil,
                statusState: "pending_restart"
            ),
            .applying
        )
    }

    /// 触发成功＋status 已连上：相位退场、归 status 收口
    func testTriggeredYieldsToConnected() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: nil,
                statusState: "connected"
            ),
            .none
        )
    }

    /// 触发成功但网关报连接错误：错误带优先于进行时
    func testTriggeredYieldsToError() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: nil,
                statusState: "error"
            ),
            .none
        )
    }

    /// 触发失败＋桥回了原因：如实回退，原因原样带出
    func testApplyErrorFallsBackWithReason() {
        let reason = "即时生效没触发成功，将在网关下次重启时生效"
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: false, applyError: reason,
                statusState: "pending_restart"
            ),
            .applyFailed(reason: reason)
        )
    }

    /// 原因非空优先于触发标记：字段自相矛盾时按更
    /// 保守（不假报正在生效）的一侧判
    func testApplyErrorWinsOverTriggeredFlag() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: true, applyError: "触发失败",
                statusState: "pending_restart"
            ),
            .applyFailed(reason: "触发失败")
        )
    }

    /// 未触发且无原因（桥没有即时通道）：等下次重启
    func testNotTriggeredWithoutErrorAwaitsRestart() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: false, applyError: nil,
                statusState: "pending_restart"
            ),
            .awaitingRestart
        )
    }

    /// 空字符串原因视同没有原因，不进失败带
    func testNotTriggeredEmptyErrorAwaitsRestart() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: false, applyError: "",
                statusState: "pending_restart"
            ),
            .awaitingRestart
        )
    }

    /// 旧版伴生回执没有这两字段：完全回落 status
    func testLegacyReceiptFallsBackToNone() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: nil, applyError: nil,
                statusState: "pending_restart"
            ),
            .none
        )
    }

    /// 还没保存过（无回执）：无流程态
    func testNoReceiptIsNone() {
        XCTAssertEqual(
            ChannelApplyPhase.resolve(
                applyTriggered: nil, applyError: nil,
                statusState: nil
            ),
            .none
        )
    }
}
