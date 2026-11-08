import OneDayCore
import XCTest

/// 字重阶梯定版（0.3.3 立账，0.3.7 按 §22.6 字重映射
/// 令牌改版）：regular 400 承载正文与全部行位角色，
/// bold 700 只许标题位（胶囊标题/Markdown 标题）与
/// Markdown 行内粗体；semibold 600/medium 500 退出
/// 账本——档距断言：正文→粗体差 300（CSS 单位）、
/// 粗体不越上限、正文侧五角色同为 400（值/副标题/
/// 行标题/分区题不许偷偷加粗）。
final class TextRoleWeightsTests: XCTestCase {
    func testBodyRolesAreRegular() {
        XCTAssertEqual(TextRoleWeights.body, 400)
        XCTAssertEqual(TextRoleWeights.rowValue, 400)
        XCTAssertEqual(TextRoleWeights.rowSubtitle, 400)
        XCTAssertEqual(TextRoleWeights.rowTitle, 400)
        XCTAssertEqual(TextRoleWeights.sectionTitle, 400)
    }

    func testBoldRoles() {
        XCTAssertEqual(TextRoleWeights.capsuleTitle, 700)
        XCTAssertEqual(TextRoleWeights.markdownStrong, 700)
        XCTAssertEqual(TextRoleWeights.heading, 700)
    }

    func testLadderSpacing() {
        // 粗体与正文恰拉开一档（300 CSS 单位），且不越上限
        XCTAssertEqual(
            TextRoleWeights.markdownStrong - TextRoleWeights.body, 300
        )
        XCTAssertLessThanOrEqual(
            TextRoleWeights.markdownStrong, TextRoleWeights.boldCeiling
        )
        XCTAssertEqual(TextRoleWeights.boldCeiling, 700)
    }

    /// 600/500 退出账本：全部角色只许 400 或 700 两值
    func testNoSemiboldOrMediumGradesRemain() {
        let all = [
            TextRoleWeights.body, TextRoleWeights.rowValue,
            TextRoleWeights.rowSubtitle, TextRoleWeights.rowTitle,
            TextRoleWeights.sectionTitle, TextRoleWeights.capsuleTitle,
            TextRoleWeights.markdownStrong, TextRoleWeights.heading,
            TextRoleWeights.boldCeiling,
        ]
        for grade in all {
            XCTAssertTrue(
                grade == 400 || grade == 700,
                "字重账本只许 400/700，实得 \(grade)"
            )
        }
    }
}
