import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §263（第 81 条）气泡排版四值对齐验收：
/// 字号 .body／行高＝text style 规格 leading（苹果
/// HIG Dynamic Type 表：默认 Large 档 Body 17/22、
/// Callout 16/21）／段间额外距 16／助手文宽占屏比。
/// 旧管线双重不合：正文用次级字阶 .callout 当主阅
/// 读文本，且基字体只摘 pointSize 以 systemFont 重
/// 构、拿自然行高（实测 pitch 19.0）顶替规格行高
/// （连 Callout 的 21 都没到）。本组断言以量测池
/// （与产物同栈 TextKit 2）实量归因串总高反推
/// pitch 与段距，不认代码自报值
final class ChatTypeScaleAlignTests: XCTestCase {

    // MARK: - 拼装助手（与产物 builder 同源同参）

    private func assemble(
        _ paragraphs: [InlineTextParagraph],
        category: UIContentSizeCategory = .large
    ) -> NSAttributedString {
        SelectableInlineText.build(
            paragraphs: paragraphs,
            baseFont: InlineTextFonts.baseFont(
                textStyle: .body, category: category,
                boldText: false
            ),
            overrideFont: { style in
                InlineTextFonts.baseFont(
                    textStyle: style, category: category,
                    boldText: false
                )
            },
            textColor: .label,
            dimmedColor: .secondaryLabel
        )
    }

    /// 定行数样本：一段内以 \n 显式断行（plainRuns
    /// 单 run 保 \n、TextKit 按 \n 断行），行数确定
    /// 可反推 pitch
    private func linedParagraph(_ lines: Int) -> NSAttributedString {
        let text = Array(repeating: "测", count: lines)
            .joined(separator: "\n")
        return assemble([.plain(text)])
    }

    // MARK: - 字体链：规格 leading 由 TK2 布局同栈交付

    func testBodyFontCarriesSpecLeading() {
        let body = InlineTextFonts.baseFont(
            textStyle: .body, category: .large, boldText: false
        )
        XCTAssertEqual(body.pointSize, 17, accuracy: 0.1)
        // font.lineHeight 是字体自然行高（20.29）、
        // 不是规格值——首轮 CI 实测钉死，防后人拿它
        // 冒充规格 leading
        XCTAssertEqual(body.lineHeight, 20.29, accuracy: 0.5)
        // 苹果 HIG 表默认档 Body leading＝22，经
        // specLineHeight（与量测池同栈实量）读出
        XCTAssertEqual(
            InlineTextFonts.specLineHeight(
                textStyle: .body, category: .large, boldText: false
            ),
            22, accuracy: 0.5
        )
        // 粗体文本（semibold）只换字重、不丢规格行高
        let bold = InlineTextFonts.baseFont(
            textStyle: .body, category: .large, boldText: true
        )
        XCTAssertEqual(bold.pointSize, 17, accuracy: 0.1)
        XCTAssertEqual(
            InlineTextFonts.specLineHeight(
                textStyle: .body, category: .large, boldText: true
            ),
            22, accuracy: 0.5
        )
        // 对照：次级字阶 .callout 规格行高 21、自然
        // 行高 19.09——旧管线实测 pitch 19.0 正是拿
        // 自然行高顶替了规格，连自家字阶的 21 都没到
        let callout = InlineTextFonts.baseFont(
            textStyle: .callout, category: .large, boldText: false
        )
        XCTAssertEqual(callout.pointSize, 16, accuracy: 0.1)
        XCTAssertEqual(callout.lineHeight, 19.09, accuracy: 0.5)
        XCTAssertEqual(
            InlineTextFonts.specLineHeight(
                textStyle: .callout, category: .large,
                boldText: false
            ),
            21, accuracy: 0.5
        )
    }

    // MARK: - 实量 pitch：默认档 22

    func testMeasuredPitchEqualsSpecLeading() async {
        let pool = LayoutMeasurePool(workerCount: 1)
        let width: CGFloat = 309
        let h1 = await pool.measure(linedParagraph(1), width: width)
        let h2 = await pool.measure(linedParagraph(2), width: width)
        let h3 = await pool.measure(linedParagraph(3), width: width)
        // 单行高＝一个 pitch；行间差＝pitch 本体
        XCTAssertEqual(h1, 22, accuracy: 0.75)
        XCTAssertEqual(h2 - h1, 22, accuracy: 0.75)
        XCTAssertEqual(h3 - h2, 22, accuracy: 0.75)
        // 固定多行中文长文（自然换行）：总高须为
        // pitch 的整数倍（每行片段同高、无额外估算）
        let prose = assemble([.plain(
            String(
                repeating: "这是一段较长的中文正文，用来触发多行换行与逐行量测。",
                count: 12
            )
        )])
        let total = await pool.measure(prose, width: width)
        let lines = (total / 22).rounded()
        XCTAssertGreaterThan(lines, 3)
        XCTAssertEqual(total, lines * 22, accuracy: 1.5)
    }

    // MARK: - 段距：映射单源值 16＋实量闭合

    func testParagraphSpacingSixteen() async {
        let markdown = "甲段正文。\n\n乙段正文。"
        let segments = MarkdownMessageAssembler.segments(
            for: markdown
        )
        guard case .prose(let raw) = segments.first else {
            XCTFail("样本应装配出合并散文段")
            return
        }
        let paragraphs = MarkdownText.proseParagraphs(raw)
        XCTAssertEqual(paragraphs.count, 2)
        // 映射单源值：段间额外距 16、末段 0
        XCTAssertEqual(
            paragraphs[0].spaceAfter, 16, accuracy: 0.01
        )
        XCTAssertEqual(
            paragraphs[1].spaceAfter, 0, accuracy: 0.01
        )
        XCTAssertEqual(
            OneDayMetrics.paragraphSpacing, 16, accuracy: 0.01
        )
        // 实量：两段各一行宽（宽 309 下短段各占一行）
        // 总高＝22（段一）＋16（段距）＋22（段二）
        let pool = LayoutMeasurePool(workerCount: 1)
        let total = await pool.measure(
            assemble(paragraphs), width: 309
        )
        XCTAssertEqual(total, 60, accuracy: 1.0)
    }

    // MARK: - 随字号档按规格表缩放

    func testPitchScalesWithContentSizeCategory() async {
        let category = UIContentSizeCategory.extraExtraLarge
        // HIG 规格表 XXL 档成对值：Body 21pt／leading
        // 26（表值直钉＋链路读值双验）
        let spec = InlineTextFonts.specLineHeight(
            textStyle: .body, category: category, boldText: false
        )
        XCTAssertEqual(spec, 26, accuracy: 0.5)
        let font = InlineTextFonts.baseFont(
            textStyle: .body, category: category, boldText: false
        )
        XCTAssertEqual(font.pointSize, 21, accuracy: 0.1)
        // 实量 pitch 随档同涨
        let pool = LayoutMeasurePool(workerCount: 1)
        let scaled = assemble(
            [.plain("测\n测")], category: category
        )
        let single = assemble([.plain("测")], category: category)
        let double = await pool.measure(scaled, width: 309)
        let one = await pool.measure(single, width: 309)
        XCTAssertEqual(double - one, 26, accuracy: 0.75)
        XCTAssertEqual(double - one, spec, accuracy: 0.75)
    }

    // MARK: - 行高模型下限与呈现同值

    func testHeightModelFloorSameSource() async {
        // ChatView.carrierRowEstimate 的下限公式本体
        // （specLineHeight .body）与量测单行高同源、
        // 同钉 HIG 表默认档 22
        let floor = InlineTextFonts.specLineHeight(
            textStyle: .body, category: .large, boldText: false
        )
        XCTAssertEqual(floor, 22, accuracy: 0.5)
        let pool = LayoutMeasurePool(workerCount: 1)
        let oneLine = await pool.measure(
            linedParagraph(1), width: 309
        )
        XCTAssertEqual(oneLine, floor, accuracy: 0.75)
    }

    // MARK: - 文宽：助手按占屏比、用户旧账不动

    func testAssistantColumnGeometryValues() {
        // 402pt 屏：助手文宽 ≈309、左缘 ≈33
        XCTAssertEqual(
            LayoutProductService.textWidth(
                isUser: false, screenWidth: 402
            ),
            309, accuracy: 0.5
        )
        XCTAssertEqual(
            402 * OneDayMetrics.assistantTextLeadingFraction,
            33, accuracy: 0.5
        )
        // 用户泡宽度旧账逐值不变（402−16×2−44＝326）
        XCTAssertEqual(
            LayoutProductService.textWidth(
                isUser: true, screenWidth: 402
            ),
            326, accuracy: 0.01
        )
        // 比例落值非写死 402：换屏宽按比缩放
        XCTAssertEqual(
            LayoutProductService.textWidth(
                isUser: false, screenWidth: 430
            ),
            430 * 0.769, accuracy: 0.5
        )
    }
}
