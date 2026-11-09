import OneDayCore
import XCTest

/// 流失败归因分型（0.20.0）：同是瞬断错误，经历过
/// 后台与否决定它是生命周期中断（对账恢复、不报网络
/// 错）还是前台瞬断（重试＋中性文案）；非瞬断错误
/// 恒真失败、与后台无关。
final class StreamRecoveryTests: XCTestCase {

    func testTransientAfterBackgroundIsLifecycleInterruption() {
        XCTAssertEqual(
            StreamFailure.kind(
                error: .transientNetwork, wasBackgrounded: true
            ),
            .lifecycleInterrupted
        )
    }

    func testTransientInForegroundIsTransient() {
        XCTAssertEqual(
            StreamFailure.kind(
                error: .transientNetwork, wasBackgrounded: false
            ),
            .transient
        )
    }

    func testNonTransientIsFatalRegardlessOfBackground() {
        XCTAssertEqual(
            StreamFailure.kind(
                error: .apiKeyRejected, wasBackgrounded: true
            ),
            .fatal
        )
        XCTAssertEqual(
            StreamFailure.kind(
                error: .sessionExpired, wasBackgrounded: false
            ),
            .fatal
        )
        XCTAssertEqual(
            StreamFailure.kind(
                error: .unreachable("无法建立连接"),
                wasBackgrounded: true
            ),
            .fatal
        )
    }
}
