import OneDayCore
import XCTest

/// 字重阶梯定版（0.3.3，DESIGN-V4 §18）：正文 400、
/// 半粗位（行标题/胶囊标题/分区题/Markdown 粗体/标
/// 题）600、bold 上限 700 仅标题角色——档距断言：
/// 正文→粗体恰差一档（200 CSS 单位）、粗体不越上限、
/// 正文侧三角色同为 400（值/副标题不许偷偷加粗）
final class TextRoleWeightsTests: XCTestCase {
    func testBodyRolesAreRegular() {
        XCTAssertEqual(TextRoleWeights.body, 400)
        XCTAssertEqual(TextRoleWeights.rowValue, 400)
        XCTAssertEqual(TextRoleWeights.rowSubtitle, 400)
    }

    func testSemiboldRoles() {
        XCTAssertEqual(TextRoleWeights.rowTitle, 600)
        XCTAssertEqual(TextRoleWeights.capsuleTitle, 600)
        XCTAssertEqual(TextRoleWeights.sectionTitle, 600)
        XCTAssertEqual(TextRoleWeights.markdownStrong, 600)
        XCTAssertEqual(TextRoleWeights.heading, 600)
    }

    func testLadderSpacing() {
        // 粗体与正文恰拉开一档，且严守上限之下
        XCTAssertEqual(
            TextRoleWeights.markdownStrong - TextRoleWeights.body, 200
        )
        XCTAssertLessThan(
            TextRoleWeights.markdownStrong, TextRoleWeights.boldCeiling
        )
        XCTAssertEqual(TextRoleWeights.boldCeiling, 700)
    }
}
