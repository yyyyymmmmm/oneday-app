import Foundation
import XCTest
@testable import OneDayCore

/// 大小回读重试口径（§127，D1）：次数封顶、间隔递
/// 增、冷却判定。钉死形状防宿主各写一套重试。
final class FileBackfillPolicyTests: XCTestCase {
    func testDelayProgressionAndExhaustion() {
        XCTAssertEqual(
            FileBackfillPolicy.delay(afterFailedAttempt: 1), 1.5
        )
        XCTAssertEqual(
            FileBackfillPolicy.delay(afterFailedAttempt: 2), 4
        )
        XCTAssertNil(FileBackfillPolicy.delay(afterFailedAttempt: 3))
        XCTAssertNil(FileBackfillPolicy.delay(afterFailedAttempt: 9))
    }

    func testMaxAttemptsCoversDelays() {
        // 有等待值的失败次数 + 首试 = maxAttempts：
        // 第 maxAttempts 次失败后 delay 必须为 nil
        XCTAssertNil(
            FileBackfillPolicy.delay(
                afterFailedAttempt: FileBackfillPolicy.maxAttempts
            )
        )
    }

    func testCooldownWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(
            FileBackfillPolicy.isCoolingDown(lastFailureAt: nil, now: now)
        )
        XCTAssertTrue(
            FileBackfillPolicy.isCoolingDown(
                lastFailureAt: now.addingTimeInterval(-1), now: now
            )
        )
        XCTAssertFalse(
            FileBackfillPolicy.isCoolingDown(
                lastFailureAt: now.addingTimeInterval(
                    -FileBackfillPolicy.failureCooldown - 1
                ),
                now: now
            )
        )
    }
}
