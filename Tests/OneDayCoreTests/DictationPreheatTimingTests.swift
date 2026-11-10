import OneDayCore
import XCTest

/// 起步时序钟＋预热状态机（0.36.15，语音延迟修复
/// 包）：首结果迟到的量尺与「点麦克风前备齐分析
/// 器」的驱动政策全是纯逻辑，钉在此处；引擎/资产
/// 等系统面不在此测（真机面）
final class DictationPreheatTimingTests: XCTestCase {

    // MARK: - 时序钟：相对毫秒换算

    func testTimingOffsetsAreRelativeToBegin() {
        var timing = DictationStartTiming()
        timing.begin(atUptime: 100.0)
        timing.mark(.engineStarted, atUptime: 100.085)
        timing.mark(.analyzerStarted, atUptime: 100.210)
        timing.mark(.firstResult, atUptime: 110.234)
        XCTAssertEqual(timing.offsetMs(.engineStarted), 85)
        XCTAssertEqual(timing.offsetMs(.analyzerStarted), 210)
        XCTAssertEqual(timing.firstResultMs, 10234)
    }

    func testTimingMarkBeforeBeginIsIgnored() {
        var timing = DictationStartTiming()
        timing.mark(.firstResult, atUptime: 50.0)
        XCTAssertNil(timing.firstResultMs)
        XCTAssertEqual(timing.diagnosticSegment, "")
    }

    func testTimingFirstMarkWins() {
        var timing = DictationStartTiming()
        timing.begin(atUptime: 0)
        timing.mark(.firstResult, atUptime: 1.5)
        // 迟到的重复打点不许改写第一次到达
        timing.mark(.firstResult, atUptime: 9.9)
        XCTAssertEqual(timing.firstResultMs, 1500)
    }

    func testTimingBeginClearsPreviousRound() {
        var timing = DictationStartTiming()
        timing.begin(atUptime: 0)
        timing.mark(.firstResult, atUptime: 3.0)
        timing.begin(atUptime: 20.0)
        XCTAssertNil(timing.firstResultMs)
        timing.mark(.engineStarted, atUptime: 20.05)
        XCTAssertEqual(timing.offsetMs(.engineStarted), 50)
    }

    func testTimingNegativeDeltaClampsToZero() {
        var timing = DictationStartTiming()
        timing.begin(atUptime: 10.0)
        timing.mark(.engineStarted, atUptime: 9.0)
        XCTAssertEqual(timing.offsetMs(.engineStarted), 0)
    }

    func testTimingResetClearsEverything() {
        var timing = DictationStartTiming()
        timing.begin(atUptime: 0)
        timing.mark(.firstResult, atUptime: 1.0)
        timing.reset()
        XCTAssertNil(timing.originUptime)
        XCTAssertNil(timing.firstResultMs)
        // reset 后迟到 mark 无零点可依，忽略
        timing.mark(.firstResult, atUptime: 2.0)
        XCTAssertNil(timing.firstResultMs)
    }

    func testTimingDiagnosticSegmentOrdersPointsAndOmitsMissing() {
        var timing = DictationStartTiming()
        timing.begin(atUptime: 0)
        XCTAssertEqual(timing.diagnosticSegment, "")
        // 乱序到达也按 eng→ana→首结果 的时序拼
        timing.mark(.firstResult, atUptime: 10.234)
        timing.mark(.engineStarted, atUptime: 0.085)
        XCTAssertEqual(
            timing.diagnosticSegment, "eng+85ms 首结果+10234ms")
        timing.mark(.analyzerStarted, atUptime: 0.210)
        XCTAssertEqual(
            timing.diagnosticSegment, "eng+85ms ana+210ms 首结果+10234ms")
    }

    // MARK: - 预热状态机：转移全表

    func testPreheatHappyPathAndConsumeCycle() {
        var state = DictationPreheatState.cold
        state = DictationPreheatPolicy.transition(
            from: state, event: .beginWarm)
        XCTAssertEqual(state, .warming)
        state = DictationPreheatPolicy.transition(
            from: state, event: .warmSucceeded)
        XCTAssertEqual(state, .ready)
        // 消费即回冷（单次使用制），等控制器录后重备
        state = DictationPreheatPolicy.transition(
            from: state, event: .consume)
        XCTAssertEqual(state, .cold)
    }

    func testPreheatFailureRetriesFromFailed() {
        var state = DictationPreheatState.warming
        state = DictationPreheatPolicy.transition(
            from: state, event: .warmFailed)
        XCTAssertEqual(state, .failed)
        // 失败不锁死：下一轮可再备
        XCTAssertTrue(DictationPreheatPolicy.canBeginWarm(state))
        state = DictationPreheatPolicy.transition(
            from: state, event: .beginWarm)
        XCTAssertEqual(state, .warming)
    }

    func testPreheatInvalidateReturnsToColdFromAnyArmedState() {
        for from in [DictationPreheatState.warming,
                     DictationPreheatState.ready,
                     DictationPreheatState.failed] {
            XCTAssertEqual(
                DictationPreheatPolicy.transition(
                    from: from, event: .invalidate),
                .cold, "from=\(from)")
        }
    }

    func testPreheatOffTableEventsKeepState() {
        // 已备时重复发起：不起第二轮
        XCTAssertEqual(
            DictationPreheatPolicy.transition(
                from: .ready, event: .beginWarm), .ready)
        XCTAssertFalse(DictationPreheatPolicy.canBeginWarm(.ready))
        XCTAssertFalse(DictationPreheatPolicy.canBeginWarm(.warming))
        // 冷态收到迟到的成功/消费事件：保持冷态
        XCTAssertEqual(
            DictationPreheatPolicy.transition(
                from: .cold, event: .warmSucceeded), .cold)
        XCTAssertEqual(
            DictationPreheatPolicy.transition(
                from: .cold, event: .consume), .cold)
        // 弃置后迟到的失败回执（任务取消的尾巴）不许
        // 把冷态拽成失败态
        XCTAssertEqual(
            DictationPreheatPolicy.transition(
                from: .cold, event: .warmFailed), .cold)
    }
}
