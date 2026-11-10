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

    func testTrailingStateStreamingWinsOverCanSend() {
        XCTAssertEqual(
            ComposerTrailingState.resolve(isStreaming: true, canSend: true),
            .stop
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
