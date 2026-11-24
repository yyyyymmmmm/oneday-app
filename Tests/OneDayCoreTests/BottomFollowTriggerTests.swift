import XCTest
@testable import OneDayCore

/// 台账 149（贴底四触发源验收清单）：四源清单本
/// 体钉住——源增减必须先改清单再改行为；四源的装
/// 配层行为用例在 App 侧 ChatNativeFollowSource-
/// Tests 逐源成对（在底保持/离底不拽）
final class BottomFollowTriggerTests: XCTestCase {
    func testFourSourcesPinned() {
        XCTAssertEqual(
            BottomFollowTrigger.allCases,
            [.dataChange, .itemLayout, .footerLayout, .layout]
        )
    }
}
