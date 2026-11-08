import OneDayCore
import XCTest

/// 顶栏钮规格（0.3.3，DESIGN-V4 §18；真机第 2 条）：
/// 左右两钮共用一份规格——直径/字号钉死、字形比落在
/// Muse 截图量测的校准带内（≈0.48，带 0.45–0.55）
final class HeaderButtonSpecTests: XCTestCase {
    func testSpecValues() {
        XCTAssertEqual(HeaderButtonSpec.diameter, 40)
        XCTAssertEqual(HeaderButtonSpec.glyphPointSize, 20)
    }

    func testGlyphRatioInCalibratedBand() {
        XCTAssertEqual(HeaderButtonSpec.glyphRatio, 0.5, accuracy: 0.001)
        XCTAssertTrue(
            (0.45...0.55).contains(HeaderButtonSpec.glyphRatio),
            "字形/圆比 \(HeaderButtonSpec.glyphRatio) 出校准带"
        )
    }
}
