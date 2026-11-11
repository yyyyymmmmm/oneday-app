import XCTest
@testable import OneDayCore

/// 演示空态信号钉测（复杂化全清·第 4 项）：清单外接口
/// 的统一信号只有 HermesError.demoLimitReached 一处，
/// 文案三语键一条——此处钉 zh-Hans 源串（测试环境无
/// 目录宿主时 L10n 回落源串，与 CompanionProbeTests
/// 同口径）；信号不许被发送链当瞬断重试。
final class DemoLimitTests: XCTestCase {

    func testDemoLimitMessageIsTheUnifiedCopy() {
        XCTAssertEqual(
            HermesError.demoLimitReached.userMessage(
                locale: Locale(identifier: "zh-Hans")
            ),
            "演示模式到此为止，连接你的服务器后可用。"
        )
    }

    func testDemoLimitIsNotTransient() {
        XCTAssertFalse(HermesError.demoLimitReached.isTransient)
    }
}
