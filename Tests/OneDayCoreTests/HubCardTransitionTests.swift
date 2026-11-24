import XCTest
@testable import OneDayCore

/// §502 中枢卡片转场数学钉测：判据全部取量测正本
/// （hub-card-presentation-spec-20261124 §2/§7）的
/// 死值——缩放映射、圆角、投影判定（含 §2.6 两回
/// 合对照）、方向锁、降级裁决。
final class HubCardTransitionTests: XCTestCase {

    // MARK: - 缩放映射（§7.2 死值）

    func testScaleAtRestIsOne() {
        XCTAssertEqual(HubCardTransition.scale(forDeltaX: 0), 1, accuracy: 0.0001)
    }

    func testScaleAt100ptMatchesMeasurement() {
        // Δx＝100pt → 0.79 ± 0.03
        XCTAssertEqual(HubCardTransition.scale(forDeltaX: 100), 0.79, accuracy: 0.03)
    }

    func testScaleAt170ptMatchesMeasurement() {
        // Δx＝170pt → 0.64 ± 0.04
        XCTAssertEqual(HubCardTransition.scale(forDeltaX: 170), 0.64, accuracy: 0.04)
    }

    func testScaleIgnoresLeftwardDrag() {
        // 左向（非关闭方向）不驱动缩放
        XCTAssertEqual(HubCardTransition.scale(forDeltaX: -120), 1, accuracy: 0.0001)
    }

    func testScaleClampsAtMinimum() {
        XCTAssertEqual(
            HubCardTransition.scale(forDeltaX: 1000),
            HubCardTransition.minScale, accuracy: 0.0001)
    }

    // MARK: - 圆角（§7.3 死值）

    func testCornerRadiusZeroAtRest() {
        XCTAssertEqual(HubCardTransition.cornerRadius(forDeltaX: 0), 0, accuracy: 0.0001)
    }

    func testCornerRadiusFullInDragState() {
        // 拖动态（Δx ≥ 33pt，量测 §2.4 取样点）圆角 57 ± 4
        XCTAssertEqual(HubCardTransition.cornerRadius(forDeltaX: 33), 57, accuracy: 4)
        XCTAssertEqual(HubCardTransition.cornerRadius(forDeltaX: 170), 57, accuracy: 4)
    }

    // MARK: - 松手投影判定（§2.6 回合对照，屏宽 402pt）

    func testProjectionRound1SlowShortDragCancels() {
        // 回合一：Δx＝112pt、末速 ≈0 → 取消弹回
        XCTAssertFalse(HubCardTransition.shouldFinish(
            predictedEndX: 112, screenWidth: 402))
    }

    func testProjectionRound4SlowLongDragCancels() {
        // 回合四：Δx＝171pt、末速 ≈0 → 投影 42.5%＜50% 取消
        XCTAssertFalse(HubCardTransition.shouldFinish(
            predictedEndX: 171, screenWidth: 402))
    }

    func testProjectionRound5FastDragFinishes() {
        // 回合五：Δx＝174pt、末速 ≈525pt/s → 投影
        // ≈174＋525×0.25 ≈ 305pt（76%）→ 完成关闭
        XCTAssertTrue(HubCardTransition.shouldFinish(
            predictedEndX: 305, screenWidth: 402))
    }

    func testProjectionPastHalfWidthFinishes() {
        // §7.4 上界验证：慢拖至 57% 屏宽（230pt）→ 关闭
        XCTAssertTrue(HubCardTransition.shouldFinish(
            predictedEndX: 230, screenWidth: 402))
    }

    func testProjectionZeroWidthNeverFinishes() {
        XCTAssertFalse(HubCardTransition.shouldFinish(
            predictedEndX: 300, screenWidth: 0))
    }

    // MARK: - 方向锁（§2.8 仲裁）

    func testDirectionUndecidedBelowThreshold() {
        let d = HubCardTransition.classifyDrag(
            translation: CGSize(width: 6, height: 4), current: .undecided)
        XCTAssertEqual(d, .undecided)
    }

    func testDirectionHorizontalDominant() {
        let d = HubCardTransition.classifyDrag(
            translation: CGSize(width: 30, height: 12), current: .undecided)
        XCTAssertEqual(d, .horizontal)
    }

    func testDirectionVerticalDominant() {
        let d = HubCardTransition.classifyDrag(
            translation: CGSize(width: 8, height: 40), current: .undecided)
        XCTAssertEqual(d, .vertical)
    }

    func testDirectionLockIsSticky() {
        let d = HubCardTransition.classifyDrag(
            translation: CGSize(width: 4, height: 90), current: .horizontal)
        XCTAssertEqual(d, .horizontal)
    }

    // MARK: - 底层强度

    func testUnderlayStrengthZeroAtRestScale() {
        XCTAssertEqual(HubCardTransition.underlayStrength(forScale: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(HubCardTransition.underlayDimOpacity(forScale: 1), 0, accuracy: 0.0001)
    }

    func testUnderlayStrengthFullAtEntryScale() {
        // 入场起始缩放 0.75 → 强度满格、压暗 0.20（亮度 ≈0.80×，§2.5 带内）
        XCTAssertEqual(HubCardTransition.underlayStrength(forScale: 0.75), 1, accuracy: 0.0001)
        XCTAssertEqual(HubCardTransition.underlayDimOpacity(forScale: 0.75), 0.20, accuracy: 0.001)
    }

    // MARK: - 底层本体处理（灰底根治）

    func testUnderlayBlurRadiusZeroAtRest() {
        XCTAssertEqual(
            HubCardTransition.underlayBlurRadius(forStrength: 0),
            0, accuracy: 0.0001)
    }

    func testUnderlayBlurRadiusFullAtMaxStrength() {
        // 满强度达上限，上限本身在施工图 §6 口径带内
        XCTAssertEqual(
            HubCardTransition.underlayBlurRadius(forStrength: 1),
            HubCardTransition.underlayMaxBlurRadius,
            accuracy: 0.0001)
        XCTAssertTrue(
            (12...16).contains(
                HubCardTransition.underlayMaxBlurRadius))
    }

    func testUnderlayBrightnessDeltaFollowsDimSource() {
        XCTAssertEqual(
            HubCardTransition.underlayBrightnessDelta(
                forStrength: 0),
            0, accuracy: 0.0001)
        // 满强度 −0.20 ≈ 亮度 ×0.80（§2.5 带内、与
        // underlayMaxDimOpacity 同源同值）
        XCTAssertEqual(
            HubCardTransition.underlayBrightnessDelta(
                forStrength: 1),
            -0.20, accuracy: 0.001)
    }

    func testUnderlayBlurDegradeSwitchKeepsDimOnly() {
        // 降级档（真机帧率留档开关）：关模糊、只压暗；
        // 出厂常量默认开（全量形态），翻档改常量重编
        XCTAssertTrue(HubCardTransition.underlayBlurEnabled)
        XCTAssertEqual(
            HubCardTransition.underlayBlurRadius(
                forStrength: 1, blurEnabled: false),
            0, accuracy: 0.0001)
        XCTAssertEqual(
            HubCardTransition.underlayBrightnessDelta(
                forStrength: 1),
            -0.20, accuracy: 0.001)
    }

    // MARK: - 降级裁决

    func testPolicyReduceMotionDegradesToStandard() {
        XCTAssertEqual(HubCardPolicy.decide(reduceMotion: true), .standard)
        XCTAssertEqual(HubCardPolicy.decide(reduceMotion: false), .card)
    }
}
