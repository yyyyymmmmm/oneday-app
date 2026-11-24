import SwiftUI
import XCTest
@testable import OneDayApp

/// 点子详情 sheet 双档钉（§470，2026-11-24 用户
/// 裁：默认半屏打开、可上拖到大档）：档位集恰
/// {.medium, .large}、默认档恒 .medium。呈现层
/// （IdeasView）只引 IdeaDetailSheet 单源，本组钉
/// 单源本体；上拖手感与落点归真机 verdict
final class IdeaDetailSheetDetentsTests: XCTestCase {

    func testDetentsAreMediumAndLarge() {
        XCTAssertEqual(
            IdeaDetailSheet.detents, [.medium, .large],
            "§470：点子详情 sheet 须双档（半屏＋大档）"
        )
    }

    func testDefaultDetentIsMediumAndInSet() {
        XCTAssertEqual(
            IdeaDetailSheet.defaultDetent, .medium,
            "§470：默认半屏打开"
        )
        XCTAssertTrue(
            IdeaDetailSheet.detents.contains(
                IdeaDetailSheet.defaultDetent
            ),
            "默认档必须在档位集内（selection 初始值合法）"
        )
    }
}
