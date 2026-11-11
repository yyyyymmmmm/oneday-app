import OneDayCore
import XCTest

/// 听写改判落稿面（0.36.17，用户 2026-11-10 23:48
/// 改判）：录音条照 Muse——录时零文字、停/发送两
/// 钮、停后整段落字。落稿路径（意图×有无识别字）、
/// 录音条三钮相位政策是纯逻辑，钉在此处；引擎/呈
/// 现是真机面。停后落字钟已随复杂度清理退役（审
/// 计第 8 项），其测已整段删除、不在此列
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

}
