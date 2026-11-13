import OneDayCore
import XCTest

/// 手感 A 档（2026-11-13，用户点名手感两题三路调研
/// 合成后授权施工）：回底滚动弹簧化＋显隐判定加固
/// （复核序列＋事实校准）——本组钉死三件纯逻辑：
/// 弹簧响应按距缩放、事实信号与几何冲突时的取值、
/// 复核序列每检的裁决与运动落定判据；以及协调者
/// 复贴解挂的新契约
final class BottomFeelTierATests: XCTestCase {

    // MARK: - 回底弹簧（BottomScrollSpring）

    func testSpringDampingIsCriticallyDamped() {
        // WWDC18-803 直接操纵口径：ζ＝1.0 无过冲
        XCTAssertEqual(BottomScrollSpring.dampingFraction, 1.0)
    }

    func testSpringResponseAtZeroAndNegativeDistanceIsMinimum() {
        XCTAssertEqual(
            BottomScrollSpring.response(forDistance: 0),
            BottomScrollSpring.minimumResponse
        )
        XCTAssertEqual(
            BottomScrollSpring.response(forDistance: -40),
            BottomScrollSpring.minimumResponse
        )
    }

    func testSpringResponseScalesWithDistance() {
        // 1000pt → 0.30 + 1000 × 0.00012 = 0.42
        XCTAssertEqual(
            BottomScrollSpring.response(forDistance: 1000),
            0.42, accuracy: 1e-9
        )
        XCTAssertEqual(
            BottomScrollSpring.response(forDistance: 500),
            0.36, accuracy: 1e-9
        )
    }

    func testSpringResponseIsMonotonicAndCapped() {
        var previous = BottomScrollSpring.response(forDistance: 0)
        for distance: CGFloat in stride(
            from: 100, through: 20000, by: 100
        ) {
            let response = BottomScrollSpring.response(
                forDistance: distance
            )
            XCTAssertGreaterThanOrEqual(response, previous)
            XCTAssertLessThanOrEqual(
                response, BottomScrollSpring.maximumResponse
            )
            previous = response
        }
        XCTAssertEqual(
            BottomScrollSpring.response(forDistance: 20000),
            BottomScrollSpring.maximumResponse
        )
    }

    // MARK: - 事实校准（BottomFactCalibration）

    func testCalibrationFactOverridesGeometricAway() {
        // 冲突取值：几何报离底（估算驻留迟滞带）而内
        // 容末端完整可见——以事实为准判在底，钮消失
        XCTAssertTrue(
            BottomFactCalibration.isNearBottom(
                geometric: false, contentEndVisible: true
            )
        )
    }

    func testCalibrationFactNeverProvesAway() {
        // 单向口径：末端不可见不反证离底，几何在底
        // 时原样保留
        XCTAssertTrue(
            BottomFactCalibration.isNearBottom(
                geometric: true, contentEndVisible: false
            )
        )
        XCTAssertFalse(
            BottomFactCalibration.isNearBottom(
                geometric: false, contentEndVisible: false
            )
        )
    }

    // MARK: - 复核序列·运动落定（BottomSettleRecheck.motionSettled）

    func testMotionSettledUnanimatedIsAlwaysSettled() {
        XCTAssertTrue(
            BottomSettleRecheck.motionSettled(
                wasAnimated: false, distance: 300,
                previousDistance: nil
            )
        )
        XCTAssertTrue(
            BottomSettleRecheck.motionSettled(
                wasAnimated: false, distance: 300,
                previousDistance: 900
            )
        )
    }

    func testMotionSettledAnimatedNeedsStableSamples() {
        // 首检无前值：弹簧途中，恒判未落定
        XCTAssertFalse(
            BottomSettleRecheck.motionSettled(
                wasAnimated: true, distance: 300,
                previousDistance: nil
            )
        )
        // 相邻两检读数差 ≤ epsilon（1pt）→ 已落定
        XCTAssertTrue(
            BottomSettleRecheck.motionSettled(
                wasAnimated: true, distance: 300,
                previousDistance: 300.5
            )
        )
        XCTAssertTrue(
            BottomSettleRecheck.motionSettled(
                wasAnimated: true, distance: 300,
                previousDistance: 301
            )
        )
        // 仍在大幅变化 → 未落定
        XCTAssertFalse(
            BottomSettleRecheck.motionSettled(
                wasAnimated: true, distance: 300,
                previousDistance: 380
            )
        )
    }

    // MARK: - 复核序列·裁决（BottomSettleRecheck.decision）

    func testRecheckSettledWhenWithinRestickThreshold() {
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: BottomSettle.restickThreshold,
                motionSettled: false,
                contentEndVisible: false,
                isLastCheck: false
            ),
            .settled
        )
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 0,
                motionSettled: false,
                contentEndVisible: false,
                isLastCheck: false
            ),
            .settled
        )
    }

    func testRecheckCalibratedWhenContentEndVisible() {
        // 距底读数驻留迟滞带（96–176）而末端事实可见
        // → 校准收官、不复贴
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 120,
                motionSettled: false,
                contentEndVisible: true,
                isLastCheck: false
            ),
            .calibrated
        )
        // 事实优先于离底放弃：读数再大，末端可见即
        // 以事实为准
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 400,
                motionSettled: true,
                contentEndVisible: true,
                isLastCheck: false
            ),
            .calibrated
        )
    }

    func testRecheckRestickWhenSettledShortOfBottom() {
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 57,
                motionSettled: true,
                contentEndVisible: false,
                isLastCheck: false
            ),
            .restick
        )
    }

    func testRecheckNeverResticksWhenUserWentAway() {
        // 距底 ≥ 退出阈值（点钮后反悔上滑等）：运动
        // 再「落定」也不许把用户拽回——整序放弃
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: BottomProximity.exitDistance,
                motionSettled: true,
                contentEndVisible: false,
                isLastCheck: false
            ),
            .exhausted
        )
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 900,
                motionSettled: true,
                contentEndVisible: false,
                isLastCheck: false
            ),
            .exhausted
        )
    }

    func testRecheckWaitsWhileMotionInFlight() {
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 120,
                motionSettled: false,
                contentEndVisible: false,
                isLastCheck: false
            ),
            .wait
        )
        // 末检仍在动 → 放弃（派生链逐帧自理，不留尾巴）
        XCTAssertEqual(
            BottomSettleRecheck.decision(
                distance: 120,
                motionSettled: false,
                contentEndVisible: false,
                isLastCheck: true
            ),
            .exhausted
        )
    }

    func testRecheckScheduleAlignsWithLegacyFirstCheck() {
        // 首检沿 0.36.13 量实时点、四检短窗收官
        XCTAssertEqual(
            BottomSettleRecheck.checkDelaysMilliseconds,
            [120, 320, 640, 1100]
        )
        XCTAssertEqual(
            BottomSettleRecheck.checkDelaysMilliseconds.first ?? -1,
            BottomStickCoordinator.restickDelayMilliseconds
        )
    }

    // MARK: - 协调者复贴解挂（disarmRestick）

    func testDisarmRestickByGeneration() {
        var coordinator = BottomStickCoordinator()
        guard case .perform(let generation) =
            coordinator.requestStick(at: 100)
        else {
            return XCTFail("首请求应执行即时贴")
        }
        coordinator.disarmRestick(generation: generation)
        XCTAssertFalse(
            coordinator.consumeRestick(generation: generation)
        )
    }

    func testDisarmWithStaleGenerationKeepsArmedRestick() {
        var coordinator = BottomStickCoordinator()
        guard case .perform(let generation) =
            coordinator.requestStick(at: 100)
        else {
            return XCTFail("首请求应执行即时贴")
        }
        coordinator.disarmRestick(generation: generation + 99)
        XCTAssertTrue(
            coordinator.consumeRestick(generation: generation)
        )
    }
}
