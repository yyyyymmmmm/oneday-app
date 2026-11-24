import OneDayCore
import OneDayDesign
import XCTest

/// 抽屉弹簧定版单源（§313 立单源；§322 速度重定
/// 版；§351 再换代）：DrawerSpringTiming 是唯一
/// 事实源——定版值（response 0.27、ζ 0.90；
/// 2026-11-22 Muse 真机视频轨迹拟合；§322 档
/// 0.35/0.85 转沿革）逐项钉死、刚度/阻尼回算恒
/// 等；MotionTokens.drawerSpring 只以同字面值镜
/// 像、两处对钉（§313 前的双口径换算层已退役）。
/// 旧值 1.4/ζ 1.2（第 78 条 D3 慢阻尼档）经同录屏
/// 对照证伪作废——本档断言方向随之反转：ζ<1 欠阻
/// 尼、带微过冲才是 Muse 性状
final class DrawerSpringTimingTests: XCTestCase {

    func testTimingConstantsAreFastSpec() {
        XCTAssertEqual(DrawerSpringTiming.response, 0.27, accuracy: 0.0001)
        XCTAssertEqual(DrawerSpringTiming.dampingFraction, 0.90, accuracy: 0.0001)
        // 动量投影随弹簧动量吸收率 ζω 反比缩放：
        // §322 重算 0.22 → 0.08、§351 再缩放 → 0.06
        // （推导见单源头注）
        XCTAssertEqual(
            DrawerSpringTiming.settleProjectionInterval, 0.06, accuracy: 0.0001
        )
    }

    /// SwiftUI 镜像同值对钉：DesignTokens 的字面值与
    /// Core 定版逐项相等（改一处、另一处不对钉即红）
    func testMotionTokenMirrorMatchesSpec() {
        XCTAssertEqual(
            MotionTokens.drawerSpring,
            .interactiveSpring(
                response: DrawerSpringTiming.response,
                dampingFraction: DrawerSpringTiming.dampingFraction
            )
        )
    }

    func testStiffnessBackComputesToResponse() {
        // k＝(2π/0.27)²≈541.5；由 k 回算 response 恒等
        XCTAssertEqual(DrawerSpringTiming.stiffness, 541.5, accuracy: 0.5)
        let response = 2 * CGFloat.pi / sqrt(DrawerSpringTiming.stiffness)
        XCTAssertEqual(response, DrawerSpringTiming.response, accuracy: 0.0001)
    }

    func testDampingBackComputesToDampingFraction() {
        // c＝2×0.90×(2π/0.27)≈41.9；由 c、k 回算 ζ 恒等
        XCTAssertEqual(DrawerSpringTiming.damping, 41.9, accuracy: 0.2)
        let zeta = DrawerSpringTiming.damping
            / (2 * sqrt(DrawerSpringTiming.stiffness))
        XCTAssertEqual(zeta, DrawerSpringTiming.dampingFraction, accuracy: 0.0001)
        // ζ<1 欠阻尼：Muse 录屏实测带 +4–5px 微过
        // 冲（≈0.8% 行程、诊断报告 §5.2）——不许改
        // 回 ζ>1 过阻尼慢档（1.4/1.2 已证伪作废）
        XCTAssertLessThan(zeta, 1)
    }

    /// 模型预言对 Muse 实测量级（闭式解数值核
    /// 算，**是模型预言、不是真机证据**；真机速度门
    /// ——落定 ≤0.35s、打开 ≤0.6s、关闭 ≤0.35s、
    /// 过冲 ≤1.5% 行程——见 §322 真机清单）：全程
    /// v0＝0 释放的过冲占比与永久落定（|x|≤2px 后
    /// 不再越界）时长、余量 200px 释放的落定时长，
    /// 须与 2026-11-22 视频量测同带（过冲 ≈0.15%
    /// 近无回摆、开合总时长约 0.27–0.3s）；§322 带
    /// （过冲 0.70–0.87%、全程 0.43–0.47s）是旧视
    /// 频旧档口径、随 §351 换代
    func testModelPredictionsMatchClaudeMeasurements() {
        // 过冲占比只由 ζ 定：exp(−πζ/√(1−ζ²))
        let zeta = Double(DrawerSpringTiming.dampingFraction)
        let overshootFraction = exp(
            -Double.pi * zeta / (1 - zeta * zeta).squareRoot()
        )
        XCTAssertEqual(overshootFraction, 0.0015, accuracy: 0.0005)
        XCTAssertLessThanOrEqual(overshootFraction, 0.015)

        let fullTravelSettle = permanentSettleTime(x0: 540)
        XCTAssertGreaterThan(fullTravelSettle, 0.20)
        XCTAssertLessThanOrEqual(fullTravelSettle, 0.30)
        let remainderSettle = permanentSettleTime(x0: 200)
        XCTAssertLessThanOrEqual(remainderSettle, 0.28)
    }

    /// 闭式解（v0＝0）数值扫描：返回 |x| 最后一次
    /// 越过 2px 阈的时刻（其后永久留在阈内）
    private func permanentSettleTime(x0: Double) -> Double {
        let response = Double(DrawerSpringTiming.response)
        let zeta = Double(DrawerSpringTiming.dampingFraction)
        let omega = 2 * Double.pi / response
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        var lastBeyond = 0.0
        var t = 0.0
        while t <= 1.5 {
            let x = exp(-zeta * omega * t)
                * (x0 * cos(omegaD * t)
                    + (zeta * omega * x0 / omegaD) * sin(omegaD * t))
            if abs(x) > 2 { lastBeyond = t }
            t += 0.0005
        }
        return lastBeyond
    }
}
