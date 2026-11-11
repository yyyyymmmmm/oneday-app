import OneDayCore
import XCTest

/// 抽屉弹簧 UIKit 换算口（§156）：与 MotionTokens
/// .drawerSpring 的定版值（response 0.34、ζ 0.86）
/// 等价关系逐项钉死——UIKit 容器归位动画与旧
/// SwiftUI 壳层弹簧同手感只认这组回算
final class DrawerSpringTimingTests: XCTestCase {

    func testTimingConstantsMatchDrawerSpring() {
        XCTAssertEqual(DrawerSpringTiming.response, 0.34, accuracy: 0.0001)
        XCTAssertEqual(DrawerSpringTiming.dampingFraction, 0.86, accuracy: 0.0001)
        XCTAssertGreaterThan(DrawerSpringTiming.settleProjectionInterval, 0)
    }

    func testStiffnessBackComputesToResponse() {
        // k＝(2π/0.34)²≈341.5；由 k 回算 response 恒等
        XCTAssertEqual(DrawerSpringTiming.stiffness, 341.5, accuracy: 0.5)
        let response = 2 * CGFloat.pi / sqrt(DrawerSpringTiming.stiffness)
        XCTAssertEqual(response, DrawerSpringTiming.response, accuracy: 0.0001)
    }

    func testDampingBackComputesToDampingFraction() {
        // c＝2×0.86×(2π/0.34)≈31.8；由 c、k 回算 ζ 恒等
        XCTAssertEqual(DrawerSpringTiming.damping, 31.8, accuracy: 0.2)
        let zeta = DrawerSpringTiming.damping
            / (2 * sqrt(DrawerSpringTiming.stiffness))
        XCTAssertEqual(zeta, DrawerSpringTiming.dampingFraction, accuracy: 0.0001)
        // ζ<1 欠阻尼但近临界：与 interactiveSpring
        // 0.86「无可见回弹」的定版取向一致（不许改成
        // 过阻尼把跟手感拖死）
        XCTAssertLessThan(zeta, 1)
        XCTAssertGreaterThan(zeta, 0.8)
    }
}
