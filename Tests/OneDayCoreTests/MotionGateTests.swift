import OneDayCore
import OneDayDesign
import SwiftUI
import XCTest

/// 0.25.0 交互与动效专包的机器闸：①令牌册 resolved
/// 出口——Reduce Motion 开启时全册动画必须归零（返
/// 回 nil＝瞬时切换），关闭时全数放行；②发送舱右端
/// 状态机三态判定（流式优先）钉死，视图层切换动画
/// 以它为动画值，判定漂移在此现形。
final class MotionGateTests: XCTestCase {

    // MARK: - Reduce Motion 出口

    func testResolvedDropsEveryTokenUnderReduceMotion() {
        let tokens: [Animation] = [
            MotionTokens.press,
            MotionTokens.swap,
            MotionTokens.sectionCollapse,
            MotionTokens.systemDefault,
            MotionTokens.liquidSpring,
            MotionTokens.entrance,
            MotionTokens.pageCrossfade,
            MotionTokens.streamIn,
            MotionTokens.dragSpring,
            MotionTokens.drawerSpring,
            MotionTokens.microSpring,
        ]
        for token in tokens {
            XCTAssertNil(
                MotionTokens.resolved(token, reduceMotion: true),
                "Reduce Motion 开启时令牌必须归零（瞬时）"
            )
            XCTAssertNotNil(
                MotionTokens.resolved(token, reduceMotion: false),
                "Reduce Motion 关闭时令牌必须放行"
            )
        }
    }

    // MARK: - 发送舱右端状态机

    /// §446 改判（用户 2026-11-24 亲裁，§419 双钮
    /// 作废）：单槽位按内容切换——有可发送内容恒
    /// 出发送（流式中点按走 §419 入队）；流式空输
    /// 入出停止。双钮态 .stopAndSend 退役：真机实
    /// 证双钮 62pt 溢出 30pt 槽位、发送钮被挤出屏
    /// 幕点不到（0.50.105 verdict，DESIGN §446）
    func testTrailingStateStreamingWithCanSendQueues() {
        XCTAssertEqual(
            ComposerTrailingState.resolve(isStreaming: true, canSend: true),
            .send
        )
        XCTAssertEqual(
            ComposerTrailingState.resolve(isStreaming: true, canSend: false),
            .stop
        )
    }

    func testTrailingStateSendAndMic() {
        XCTAssertEqual(
            ComposerTrailingState.resolve(isStreaming: false, canSend: true),
            .send
        )
        XCTAssertEqual(
            ComposerTrailingState.resolve(isStreaming: false, canSend: false),
            .mic
        )
    }

    func testTrailingStateDiscKeyMembership() {
        XCTAssertFalse(ComposerTrailingState.mic.isDiscKey)
        XCTAssertTrue(ComposerTrailingState.send.isDiscKey)
        XCTAssertTrue(ComposerTrailingState.stop.isDiscKey)
        XCTAssertEqual(ComposerTrailingState.allCases.count, 3)
    }
}
