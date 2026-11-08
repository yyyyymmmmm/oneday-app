import OneDayCore
import XCTest

/// 图标变体令牌（0.3.7，DESIGN-V4 §22.5）：框架图标
/// outline＋regular、禁 fill；底栏符号源恒取线条体
/// 一侧（TabBarSymbols.normal），与令牌同口径把守。
final class IconTokensTests: XCTestCase {
    func testFrameworkIconToken() {
        XCTAssertEqual(FrameworkIcon.weightGrade, 400)
        XCTAssertFalse(FrameworkIcon.fillVariantAllowed)
        XCTAssertTrue(FrameworkIcon.glyphSizeRange.contains(21))
        XCTAssertTrue(FrameworkIcon.glyphSizeRange.contains(22))
    }

    /// 底栏四符号的线条体名都不带 .fill（.fill 只许
    /// 存在于 selected 历史字段，UI 恒取 normal）
    func testTabBarNormalSymbolsAreOutline() {
        for pair in TabBarSymbols.all {
            XCTAssertFalse(
                pair.normal.hasSuffix(".fill"),
                "\(pair.id) 的线条体名不许是 .fill 变体"
            )
        }
    }
}
