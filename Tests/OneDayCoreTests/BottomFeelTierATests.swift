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

    // MARK: - 落定评估（BottomSettleEvaluation，R4 事件化）

    func testSettleEvaluationSettledWithinThreshold() {
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: BottomSettle.restickThreshold,
                contentEndVisible: false,
                previousDistance: nil,
                restickArmed: false
            ),
            .settled
        )
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 0,
                contentEndVisible: false,
                previousDistance: 400,
                restickArmed: true
            ),
            .settled
        )
        // 达标优先于事实：两者同真取 settled
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 3,
                contentEndVisible: true,
                previousDistance: nil,
                restickArmed: false
            ),
            .settled
        )
    }

    func testSettleEvaluationCalibratedWhenContentEndVisible() {
        // 距底驻留中段而末端事实可见 → 校准收官
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 120,
                contentEndVisible: true,
                previousDistance: nil,
                restickArmed: false
            ),
            .calibrated
        )
        // 事实优先于离底放弃：读数再大，末端可见即
        // 以事实为准
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 400,
                contentEndVisible: true,
                previousDistance: 400,
                restickArmed: true
            ),
            .calibrated
        )
    }

    func testSettleEvaluationRestickWhenMotionStopped() {
        // 相邻两事件读数差 ≤ epsilon（1pt）且挂账
        // 在位 → 唯一一次复贴
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 57,
                contentEndVisible: false,
                previousDistance: 57.5,
                restickArmed: true
            ),
            .restick
        )
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 57,
                contentEndVisible: false,
                previousDistance: 58,
                restickArmed: true
            ),
            .restick
        )
    }

    func testSettleEvaluationWaitsWhileMotionInFlight() {
        // 读数仍在大幅变化 → 等下一事件
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 120,
                contentEndVisible: false,
                previousDistance: 300,
                restickArmed: true
            ),
            .wait
        )
        // 首个事件无前值可比 → 等（动画贴底的弹簧
        // 不被首读误截）
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 120,
                contentEndVisible: false,
                previousDistance: nil,
                restickArmed: true
            ),
            .wait
        )
    }

    func testSettleEvaluationWaitsWhenRestickNotArmed() {
        // 运动已停但放行门未开（动画贴底尚未观测到
        // 运动在途／挂账已被顶替）→ 只等、不复贴
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 57,
                contentEndVisible: false,
                previousDistance: 57,
                restickArmed: false
            ),
            .wait
        )
    }

    func testSettleEvaluationNeverResticksWhenUserWentAway() {
        // 距底 ≥ 退出阈值：读数再稳也不许把用户拽
        // 回——离底收官优先于复贴
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: BottomProximity.exitDistance,
                contentEndVisible: false,
                previousDistance:
                    BottomProximity.exitDistance,
                restickArmed: true
            ),
            .exhausted
        )
        XCTAssertEqual(
            BottomSettleEvaluation.decision(
                distance: 900,
                contentEndVisible: false,
                previousDistance: 900,
                restickArmed: true
            ),
            .exhausted
        )
    }

    func testRestickArmedPeekDoesNotConsume() {
        var coordinator = BottomStickCoordinator()
        guard case .perform(let generation) =
            coordinator.requestStick(at: 100)
        else {
            return XCTFail("首请求应执行即时贴")
        }
        XCTAssertTrue(
            coordinator.isRestickArmed(
                generation: generation
            )
        )
        // 窥视不消费：再窥仍在位、消费后才落空
        XCTAssertTrue(
            coordinator.isRestickArmed(
                generation: generation
            )
        )
        XCTAssertTrue(
            coordinator.consumeRestick(
                generation: generation
            )
        )
        XCTAssertFalse(
            coordinator.isRestickArmed(
                generation: generation
            )
        )
        // 过期代号恒不在位
        XCTAssertFalse(
            coordinator.isRestickArmed(
                generation: generation + 99
            )
        )
    }

    // MARK: - 落定状态机（BottomSettleMachine，R4）

    func testMachineSettlesOnFirstEventWithinThreshold() {
        var machine = BottomSettleMachine()
        machine.begin(animated: false)
        XCTAssertEqual(
            machine.step(
                distance: 3, contentEndVisible: false,
                restickArmed: true
            ),
            .settled
        )
        XCTAssertFalse(machine.isWatching)
        // 收官后步进惰性：恒 continue、不再裁决
        XCTAssertEqual(
            machine.step(
                distance: 90, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
    }

    func testMachineAnimatedWaitsForMotionThenResticks() {
        var machine = BottomSettleMachine()
        machine.begin(animated: true)
        // 首事件无前值：等
        XCTAssertEqual(
            machine.step(
                distance: 300, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
        // 大幅变化＝运动在途、仍在动：等
        XCTAssertEqual(
            machine.step(
                distance: 120, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
        XCTAssertEqual(
            machine.step(
                distance: 60, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
        // 读数连稳且运动已观测：复贴收官
        XCTAssertEqual(
            machine.step(
                distance: 60.5, contentEndVisible: false,
                restickArmed: true
            ),
            .restick
        )
        XCTAssertFalse(machine.isWatching)
    }

    func testMachineUnanimatedNeedsTwoStableReadings() {
        var machine = BottomSettleMachine()
        machine.begin(animated: false)
        // 无动画贴底：首事件无前值不可判稳——等
        XCTAssertEqual(
            machine.step(
                distance: 60, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
        // 第二事件读数不变＝已落定未达标：复贴
        XCTAssertEqual(
            machine.step(
                distance: 60, contentEndVisible: false,
                restickArmed: true
            ),
            .restick
        )
    }

    func testMachineAnimatedLateEventsFallbackByStableStreak() {
        // 迟到事件：弹簧已近落定才来首事件、全程未
        // 见大幅变化——连稳两拍后兜底放行
        var machine = BottomSettleMachine()
        machine.begin(animated: true)
        _ = machine.step(
            distance: 60, contentEndVisible: false,
            restickArmed: true
        )
        _ = machine.step(
            distance: 60.4, contentEndVisible: false,
            restickArmed: true
        )
        XCTAssertEqual(
            machine.step(
                distance: 60.2, contentEndVisible: false,
                restickArmed: true
            ),
            .restick
        )
    }

    func testMachineExhaustedWhenUserWentAway() {
        var machine = BottomSettleMachine()
        machine.begin(animated: false)
        XCTAssertEqual(
            machine.step(
                distance: 240, contentEndVisible: false,
                restickArmed: true
            ),
            .exhausted
        )
        XCTAssertFalse(machine.isWatching)
    }

    func testMachineCalibratedByFact() {
        var machine = BottomSettleMachine()
        machine.begin(animated: true)
        XCTAssertEqual(
            machine.step(
                distance: 130, contentEndVisible: true,
                restickArmed: true
            ),
            .calibrated
        )
    }

    func testMachineRespectsRestickArmedGate() {
        var machine = BottomSettleMachine()
        machine.begin(animated: false)
        _ = machine.step(
            distance: 60, contentEndVisible: false,
            restickArmed: false
        )
        // 读数已稳但协调者挂账不在位：不复贴、继续
        XCTAssertEqual(
            machine.step(
                distance: 60, contentEndVisible: false,
                restickArmed: false
            ),
            .continue
        )
        XCTAssertTrue(machine.isWatching)
    }

    func testMachineCancelAndRebegin() {
        var machine = BottomSettleMachine()
        machine.begin(animated: true)
        machine.cancel()
        XCTAssertFalse(machine.isWatching)
        XCTAssertEqual(
            machine.step(
                distance: 3, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
        // 顶替：begin 全量重置——新观察的首事件不
        // 得吃上一笔的 previousDistance
        machine.begin(animated: false)
        _ = machine.step(
            distance: 500, contentEndVisible: false,
            restickArmed: true
        )
        machine.begin(animated: false)
        XCTAssertEqual(
            machine.step(
                distance: 500, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
        )
    }

    func testMachineTimeoutStepForcesVerdict() {
        // 零事件兜底：stepTimeout 以「无事件即静止」
        // 喂回同一判定——动画观察也一评收官
        var machine = BottomSettleMachine()
        machine.begin(animated: true)
        XCTAssertEqual(
            machine.stepTimeout(
                distance: 48, contentEndVisible: false,
                restickArmed: true
            ),
            .restick
        )
        var settled = BottomSettleMachine()
        settled.begin(animated: true)
        XCTAssertEqual(
            settled.stepTimeout(
                distance: 2, contentEndVisible: false,
                restickArmed: true
            ),
            .settled
        )
        // 未观察态喂兜底：惰性
        var idle = BottomSettleMachine()
        XCTAssertEqual(
            idle.stepTimeout(
                distance: 48, contentEndVisible: false,
                restickArmed: true
            ),
            .continue
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
