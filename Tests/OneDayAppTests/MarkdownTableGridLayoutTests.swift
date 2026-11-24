import OneDayCore
import UIKit
import XCTest
@testable import OneDayApp

/// §396 钉测（总表 139）：表格 Grid 列宽单源——
/// 逐列自然宽封顶 Core maxColumnWidth、呈现与
/// 量测共用同一列宽；拼装 strong 段字体映射与
/// 合成器旧拼装同口径
@MainActor
final class MarkdownTableGridLayoutTests: XCTestCase {

    private let cap = CGFloat(
        MarkdownTablePresentation.maxColumnWidth
    )

    func testShortColumnsKeepNaturalWidths() {
        let widths = MarkdownTableGridLayout
            .columnWidths(
                header: ["项目", "状态"],
                rows: [["构建", "通过"], ["真机", "待验"]],
                category: .large, boldText: false
            )
        XCTAssertEqual(widths.count, 2)
        for width in widths {
            XCTAssertGreaterThan(width, 0)
            XCTAssertLessThan(width, cap)
        }
    }

    func testLongColumnIsCappedAtMaxColumnWidth() {
        let longCell =
            "这是一段明显超过一百六十八点自然宽的长备注"
            + "用来验证列宽封顶后单元格在列内折行呈现"
        let widths = MarkdownTableGridLayout
            .columnWidths(
                header: ["项目", "备注"],
                rows: [["构建", longCell]],
                category: .large, boldText: false
            )
        XCTAssertEqual(widths.count, 2)
        XCTAssertLessThan(widths[0], cap)
        XCTAssertEqual(widths[1], cap, accuracy: 0.5)
    }

    func testColumnWidthsArePerColumnIndependent() {
        // 第一列长、第二列短：封顶只落长列，短列
        // 保留自然宽（逐列独立取最大后封顶）
        let widths = MarkdownTableGridLayout
            .columnWidths(
                header: ["长标题列的内容继续变长直到超过封顶", "短"],
                rows: [["甲", "乙"]],
                category: .large, boldText: false
            )
        XCTAssertEqual(widths[0], cap, accuracy: 0.5)
        XCTAssertLessThan(widths[1], cap)
        XCTAssertGreaterThan(widths[1], 0)
    }

    func testCellAttributedMapsStrongToBoldFont() {
        let attributed = MarkdownTableGridLayout
            .cellAttributed(
                "正文**加粗**收尾",
                category: .large, boldText: false
            )
        var sawBold = false
        var sawRegular = false
        attributed.enumerateAttribute(
            .font,
            in: NSRange(
                location: 0, length: attributed.length
            )
        ) { value, _, _ in
            guard let font = value as? UIFont
            else { return }
            if font.fontDescriptor.symbolicTraits
                .contains(.traitBold) {
                sawBold = true
            } else {
                sawRegular = true
            }
        }
        XCTAssertTrue(
            sawBold,
            "strong 段须映射 bold 字体（与合成器旧拼装同口径）"
        )
        XCTAssertTrue(
            sawRegular, "正文段须映射常规字体"
        )
    }

}
