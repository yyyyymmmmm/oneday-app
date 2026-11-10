import OneDayCore
import XCTest

/// 听写改判落稿面（0.36.17，用户 2026-11-10 23:48
/// 改判）：录音条照 Muse——录时零文字、停/发送两
/// 钮、停后整段落字。落稿路径（意图×有无识别字）、
/// 录音条三钮相位政策、停后落字钟全是纯逻辑，钉
/// 在此处；引擎/呈现是真机面
final class DictationSettlePolicyTests: XCTestCase {

    // MARK: - 落稿路径：意图×有字

    func testSettleStopWithTextFillsComposer() {
        XCTAssertEqual(
            DictationSettlePolicy.route(
                intent: .commitToComposer, hasRecognizedText: true),
            .fillComposer)
    }

    func testSettleSendWithTextFillsAndSends() {
        XCTAssertEqual(
            DictationSettlePolicy.route(
                intent: .commitAndSend, hasRecognizedText: true),
            .fillAndSend)
    }

    // MARK: - 落稿路径：空稿两路都静默

    func testSettleStopWithNoTextIsSilent() {
        XCTAssertEqual(
            DictationSettlePolicy.route(
                intent: .commitToComposer, hasRecognizedText: false),
            .silentIdle)
    }

    func testSettleSendWithNoTextNeverSendsEmpty() {
        XCTAssertEqual(
            DictationSettlePolicy.route(
                intent: .commitAndSend, hasRecognizedText: false),
            .silentIdle)
    }

    // MARK: - 录音条三钮政策

    func testBarRecordingEnablesAllThreeButtons() {
        let controls = DictationBarPolicy.controls(for: .recording)
        XCTAssertTrue(controls.discardEnabled)
        XCTAssertTrue(controls.stopEnabled)
        XCTAssertTrue(controls.sendEnabled)
    }

    func testBarPreparingOnlyAllowsDiscard() {
        let controls = DictationBarPolicy.controls(for: .preparing)
        XCTAssertTrue(controls.discardEnabled)
        XCTAssertFalse(controls.stopEnabled)
        XCTAssertFalse(controls.sendEnabled)
    }

    func testBarFinishingDisablesAllButtons() {
        // 整理中：终稿未落定，三钮全禁——不许在落
        // 定前点出第二条路径（重复发送/废弃已落稿）
        let controls = DictationBarPolicy.controls(for: .finishing)
        XCTAssertFalse(controls.discardEnabled)
        XCTAssertFalse(controls.stopEnabled)
        XCTAssertFalse(controls.sendEnabled)
    }

    func testBarOffPhasesDisableAllButtons() {
        for phase in [DictationPhase.idle, .requestingPermission, .failed] {
            let controls = DictationBarPolicy.controls(for: phase)
            XCTAssertFalse(controls.discardEnabled, "\(phase)")
            XCTAssertFalse(controls.stopEnabled, "\(phase)")
            XCTAssertFalse(controls.sendEnabled, "\(phase)")
        }
    }

    // MARK: - 停后落字钟

    func testSettleLatencyMeasuresStopToApplied() {
        var latency = DictationSettleLatency()
        latency.begin(atUptime: 200.0)
        latency.complete(atUptime: 201.25)
        XCTAssertEqual(latency.lastMs, 1250)
        XCTAssertEqual(latency.diagnosticSegment, "落字+1250ms")
    }

    func testSettleLatencyCompleteBeforeBeginIsIgnored() {
        var latency = DictationSettleLatency()
        latency.complete(atUptime: 10.0)
        XCTAssertNil(latency.lastMs)
        XCTAssertEqual(latency.diagnosticSegment, "")
    }

    func testSettleLatencyFirstCompleteWins() {
        var latency = DictationSettleLatency()
        latency.begin(atUptime: 100.0)
        latency.complete(atUptime: 100.4)
        latency.complete(atUptime: 100.9)
        XCTAssertEqual(latency.lastMs, 400)
    }

    func testSettleLatencyBeginClearsPreviousReading() {
        var latency = DictationSettleLatency()
        latency.begin(atUptime: 100.0)
        latency.complete(atUptime: 101.0)
        XCTAssertEqual(latency.lastMs, 1000)
        // 新一轮按下：旧读数立即清，未落定前不出段
        latency.begin(atUptime: 200.0)
        XCTAssertNil(latency.lastMs)
        XCTAssertEqual(latency.diagnosticSegment, "")
        latency.complete(atUptime: 200.3)
        XCTAssertEqual(latency.lastMs, 300)
    }

    func testSettleLatencyRoundsAndClamps() {
        var latency = DictationSettleLatency()
        latency.begin(atUptime: 1000.0)
        // 84.9999… 的浮点表示不许截成 84（0.36.15
        // 时序钟 CI 首轮实测教训，同口径取最近值）
        latency.complete(atUptime: 1000.085)
        XCTAssertEqual(latency.lastMs, 85)
        // 时钟异常回拨钳到 0，不许出负数
        latency.begin(atUptime: 500.0)
        latency.complete(atUptime: 499.5)
        XCTAssertEqual(latency.lastMs, 0)
    }
}
