import OneDayCore
import XCTest

/// 连接状态单源钉测（总表 156，DESIGN §394）：状态机
/// 转移全矩阵＋阶段词/细目文案逐字——阶段、第几次尝
/// 试、人话原因只许出自 ConnectionStatus 一处
final class ConnectionStatusTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    func testInitialStateIsNotConnected() {
        let status = ConnectionStatus()
        XCTAssertEqual(status.phase, .notConnected)
        XCTAssertEqual(status.attempt, 0)
        XCTAssertNil(status.reason)
        XCTAssertEqual(status.phaseWord, "未连接")
        XCTAssertNil(status.detailText)
    }

    func testProbeSuccessFromScratchGoesOnline() {
        var status = ConnectionStatus()
        status.beginProbe(at: t0)
        XCTAssertEqual(status.phase, .probing)
        XCTAssertEqual(status.phaseWord, "连接中")
        XCTAssertNil(status.detailText)
        status.probeSucceeded(at: t1)
        XCTAssertEqual(status.phase, .online)
        XCTAssertEqual(status.attempt, 0)
        XCTAssertNil(status.reason)
        XCTAssertEqual(status.phaseWord, "已连接")
        XCTAssertNil(status.detailText)
        XCTAssertEqual(status.updatedAt, t1)
    }

    func testFailureBeforeVerdictIsRetryingWithAttemptAndReason() {
        var status = ConnectionStatus()
        status.beginProbe(at: t0)
        status.probeFailed(
            attempt: 1, reason: "连不上服务器",
            settledOffline: false, at: t0
        )
        XCTAssertEqual(status.phase, .retrying)
        XCTAssertEqual(status.phaseWord, "重连中")
        XCTAssertEqual(
            status.detailText, "第 1 次尝试，连不上服务器"
        )
        status.probeFailed(
            attempt: 2, reason: "连不上服务器",
            settledOffline: false, at: t1
        )
        XCTAssertEqual(status.phase, .retrying)
        XCTAssertEqual(status.attempt, 2)
        XCTAssertEqual(
            status.detailText, "第 2 次尝试，连不上服务器"
        )
    }

    func testSettledFailureIsOfflineWithReasonAndAttemptCount() {
        var status = ConnectionStatus()
        status.beginProbe(at: t0)
        status.probeFailed(
            attempt: 3, reason: "密钥被服务器拒绝",
            settledOffline: true, at: t1
        )
        XCTAssertEqual(status.phase, .offline)
        XCTAssertEqual(status.phaseWord, "联系不上")
        XCTAssertEqual(
            status.detailText, "密钥被服务器拒绝，共 3 次尝试"
        )
    }

    func testRecoveryFromOfflineProbesThenOnline() {
        var status = ConnectionStatus()
        status.probeFailed(
            attempt: 3, reason: "连不上服务器",
            settledOffline: true, at: t0
        )
        XCTAssertEqual(status.phase, .offline)
        status.beginProbe(at: t1)
        XCTAssertEqual(status.phase, .probing)
        XCTAssertEqual(status.attempt, 0)
        status.probeSucceeded(at: t1)
        XCTAssertEqual(status.phase, .online)
        XCTAssertNil(status.reason)
    }

    func testSteadyStateProbeWhileOnlineDoesNotFlashPhase() {
        var status = ConnectionStatus()
        status.probeSucceeded(at: t0)
        status.beginProbe(at: t1)
        XCTAssertEqual(status.phase, .online)
        XCTAssertEqual(status.phaseWord, "已连接")
    }

    func testFailureWhileOnlineEntersRetryingNotOffline() {
        // 迟滞静默期：已连接时单次失败只进重探中——定版
        // 离线只认喂入方的 settledOffline 结论
        var status = ConnectionStatus()
        status.probeSucceeded(at: t0)
        status.beginProbe(at: t1)
        status.probeFailed(
            attempt: 1, reason: "连不上服务器",
            settledOffline: false, at: t1
        )
        XCTAssertEqual(status.phase, .retrying)
    }

    func testMarkNotConnectedResetsEverything() {
        var status = ConnectionStatus()
        status.probeFailed(
            attempt: 2, reason: "连不上服务器",
            settledOffline: false, at: t0
        )
        status.markNotConnected(at: t1)
        XCTAssertEqual(status.phase, .notConnected)
        XCTAssertEqual(status.attempt, 0)
        XCTAssertNil(status.reason)
        XCTAssertEqual(status.phaseWord, "未连接")
        XCTAssertNil(status.detailText)
    }

    func testAttemptIsClampedToAtLeastOne() {
        var status = ConnectionStatus()
        status.probeFailed(
            attempt: 0, reason: "连不上服务器",
            settledOffline: false, at: t0
        )
        XCTAssertEqual(status.attempt, 1)
    }
}
