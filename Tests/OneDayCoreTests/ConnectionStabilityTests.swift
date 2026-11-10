import OneDayCore
import XCTest

/// 连接稳固纯策略（0.36.20，§86）：在线判定迟滞
/// （连失计数/阈值翻转/成功清零/抖动不翻）与退避重
/// 试口径（全抖动公式/尝试上限）。App 层只执行、判
/// 定全在此钉死——治审计 R1「一次探活失败即翻联系
/// 不上」与 R2「链接步零重试」
final class ConnectionStabilityTests: XCTestCase {

    // MARK: - 在线判定：单次/两次失败不翻脸

    func testSingleFailureNeverFlipsOffline() {
        var liveness = ConnectionLiveness()
        XCTAssertNil(liveness.isUp)
        // 冷启首探失败：无旧结论可守、也不许直接判离线
        XCTAssertNil(liveness.recordFailure())
        XCTAssertEqual(liveness.consecutiveFailures, 1)
        XCTAssertTrue(liveness.isSuspect)
    }

    func testFailuresBelowThresholdKeepPreviousVerdict() {
        var liveness = ConnectionLiveness()
        liveness.recordSuccess()
        XCTAssertEqual(liveness.isUp, true)
        // 已有「在线」结论时连失 1、2 次都只累积不翻
        XCTAssertEqual(liveness.recordFailure(), true)
        XCTAssertEqual(liveness.recordFailure(), true)
        XCTAssertEqual(liveness.consecutiveFailures, 2)
    }

    func testThirdConsecutiveFailureFlipsOffline() {
        var liveness = ConnectionLiveness()
        liveness.recordSuccess()
        liveness.recordFailure()
        liveness.recordFailure()
        XCTAssertEqual(liveness.recordFailure(), false)
        XCTAssertEqual(liveness.isUp, false)
        // 定版离线后继续失败保持离线、计数继续累积
        XCTAssertEqual(liveness.recordFailure(), false)
        XCTAssertEqual(liveness.consecutiveFailures, 4)
    }

    func testSuccessClearsCounterAndRestoresImmediately() {
        var liveness = ConnectionLiveness()
        // 累到定版离线后，一次成功立即回在线＋清零
        liveness.recordFailure()
        liveness.recordFailure()
        liveness.recordFailure()
        XCTAssertEqual(liveness.isUp, false)
        XCTAssertEqual(liveness.recordSuccess(), true)
        XCTAssertEqual(liveness.consecutiveFailures, 0)
        XCTAssertFalse(liveness.isSuspect)
        // 清零后重新计数：一次失败又回到静默期、不翻
        XCTAssertEqual(liveness.recordFailure(), true)
        XCTAssertTrue(liveness.isSuspect)
    }

    func testJitterPatternDoesNotFlip() {
        // 抖动形态（失/成交替）：计数永不达阈、永不翻脸
        var liveness = ConnectionLiveness()
        liveness.recordSuccess()
        for _ in 0..<10 {
            XCTAssertEqual(liveness.recordFailure(), true)
            XCTAssertEqual(liveness.recordSuccess(), true)
        }
        XCTAssertEqual(liveness.isUp, true)
        XCTAssertEqual(liveness.consecutiveFailures, 0)
    }

    func testSuspectOnlyWhileAccumulating() {
        var liveness = ConnectionLiveness()
        XCTAssertFalse(liveness.isSuspect)
        liveness.recordSuccess()
        XCTAssertFalse(liveness.isSuspect)
        liveness.recordFailure()
        XCTAssertTrue(liveness.isSuspect)
        liveness.recordFailure()
        liveness.recordFailure()
        // 定版离线后不再是「静默期」——该出文案了
        XCTAssertFalse(liveness.isSuspect)
    }

    // MARK: - 退避：全抖动公式（jitterUnit 注入钉死）

    func testBackoffFullJitterFormula() {
        // jitterUnit=1 → 取满帽值：base 1.2 起翻倍
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 1, jitterUnit: 1),
            1.2, accuracy: 0.001
        )
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 2, jitterUnit: 1),
            2.4, accuracy: 0.001
        )
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 3, jitterUnit: 1),
            4.8, accuracy: 0.001
        )
        // 第 4 次帽值 9.6 超 cap 5 → 钳到 5
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 4, jitterUnit: 1),
            5.0, accuracy: 0.001
        )
        // jitterUnit=0 → 不等（全抖动的下界）
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 2, jitterUnit: 0),
            0, accuracy: 0.001
        )
        // 中值按比例
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 2, jitterUnit: 0.5),
            1.2, accuracy: 0.001
        )
        // failure＜1 不等待
        XCTAssertEqual(
            RetryBackoff.delay(afterFailure: 0, jitterUnit: 1),
            0, accuracy: 0.001
        )
    }

    func testBackoffCustomBaseAndCap() {
        // 探活轮内重探口径（base 1.0/cap 4.0）
        XCTAssertEqual(
            RetryBackoff.delay(
                afterFailure: 1, base: 1.0, cap: 4.0, jitterUnit: 1
            ),
            1.0, accuracy: 0.001
        )
        XCTAssertEqual(
            RetryBackoff.delay(
                afterFailure: 3, base: 1.0, cap: 4.0, jitterUnit: 1
            ),
            4.0, accuracy: 0.001
        )
    }

    func testShouldRetryMatchesSubmitMagnitude() {
        // 首发（1 次）后、2 次后仍许重试；3 次用尽停
        // （与提交步「首发＋同 key 重试至多 2 次」同量级）
        XCTAssertTrue(RetryBackoff.shouldRetry(afterAttempts: 1))
        XCTAssertTrue(RetryBackoff.shouldRetry(afterAttempts: 2))
        XCTAssertFalse(RetryBackoff.shouldRetry(afterAttempts: 3))
        XCTAssertFalse(RetryBackoff.shouldRetry(afterAttempts: 0))
        XCTAssertEqual(RetryBackoff.maxAttempts, 3)
    }
}
