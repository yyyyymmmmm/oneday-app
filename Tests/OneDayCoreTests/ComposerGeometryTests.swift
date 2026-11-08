import OneDayCore
import XCTest

/// 发送舱几何同源（0.3.3，DESIGN-V4 §18；真机第 4/5
/// 条：光标逃逸、换行不对齐）：视图经 ComposerText-
/// Metrics.makeTextView 工厂以显式 TextKit-1 栈构造、
/// 与量测栈同类同参后，断言——
/// ①「规划」二字（真机原案）的插入点光标落在第一行、
///    且 x 在文字左原点之后（不在下方行首、不出界）；
/// ②空/单行/满行三态下文末光标矩形都落在视图帧界内；
/// ③长句缠绕各行 lineFragment usedRect 的 x 原点全等
///    textOriginX（换行左齐的直接证据）；
/// ④视图侧 fragment 行数与量测侧 lineCount 同源相等。
final class ComposerGeometryTests: XCTestCase {
    /// 与布局同源的文本宽：容器 402 的单行窄宽 270
    private var width: CGFloat {
        ComposerLayout.textWidth(forContainerWidth: 402)
    }

    private func makeLaidOutView(_ text: String) -> UITextView {
        let view = ComposerTextMetrics.makeTextView()
        view.frame = CGRect(
            x: 0, y: 0, width: width,
            height: ComposerLayout.cappedTextHeight(
                measured: ComposerTextMetrics.textHeight(
                    for: text, width: width
                )
            )
        )
        view.text = text
        // 模拟 UITextView 布局时对容器尺寸的管理（宽＝
        // 视图宽、高不封顶——封顶的是帧高、不是排版高，
        // 超限靠内滚，与生产 shouldScroll 同理）
        view.textContainer.size = CGSize(
            width: width, height: .greatestFiniteMagnitude
        )
        view.layoutManager.ensureLayout(for: view.textContainer)
        return view
    }

    /// 几何常数账：inset/padding 均为 0、左原点为 0，
    /// 且工厂确实把这套几何施加到了视图上
    func testGeometryConstantsAndFactory() {
        XCTAssertEqual(ComposerTextMetrics.textContainerInset, .zero)
        XCTAssertEqual(ComposerTextMetrics.lineFragmentPadding, 0)
        XCTAssertEqual(ComposerTextMetrics.textOriginX, 0)
        let view = ComposerTextMetrics.makeTextView()
        XCTAssertEqual(view.textContainerInset, .zero)
        XCTAssertEqual(view.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(
            view.font?.pointSize,
            ComposerTextMetrics.bodyFont.pointSize
        )
    }

    /// 真机原案：「规划」输入后光标应在第一行文字之后，
    /// 不许掉到下方行首（逃逸形态）或帧外
    func testCaretForShortTextStaysOnFirstLine() {
        let view = makeLaidOutView("规划")
        let end = view.endOfDocument
        let caret = view.caretRect(for: end)
        XCTAssertFalse(caret.isNull)
        XCTAssertLessThan(
            caret.minY, ComposerLayout.lineHeight,
            "光标 y \(caret.minY) 应在第一行内（行高 \(ComposerLayout.lineHeight)）"
        )
        XCTAssertGreaterThan(
            caret.minX, ComposerTextMetrics.textOriginX,
            "光标应在文字之后，而非行首原点"
        )
        // 光标高 20.0 是 16pt 字体的光标度量（比行高
        // 19.17 多 0.83、顶偏 −1，CI 实测）——容差 1.5
        // 覆盖这组字体度量差，不掩盖行级逃逸（≥19.17）
        XCTAssertLessThanOrEqual(caret.maxY, view.bounds.height + 1.5)
    }

    /// 三态：空/单行下文末光标矩形落在帧界内；满行
    /// （超 6 行封顶）下光标落在最后一个文字行上——
    /// 封顶的是帧高、光标的家在可滚内容区里，断言口径
    /// 是「在文字行带内、不逃到文本块之下」
    func testCaretInsideBoundsForAllStates() {
        let samples = [
            "",
            "规划",
            String(repeating: "量测满行文字排版", count: 40),
        ]
        for text in samples {
            let view = makeLaidOutView(text)
            let caret = view.caretRect(for: view.endOfDocument)
            let lines = ComposerTextMetrics.lineCount(
                for: text, width: width
            )
            XCTAssertFalse(caret.isNull, "文本长度 \(text.count) 光标矩形为空")
            XCTAssertGreaterThanOrEqual(caret.minX, -0.6)
            XCTAssertGreaterThanOrEqual(caret.minY, -1.5)
            XCTAssertLessThanOrEqual(
                caret.maxX, view.bounds.width + 0.6,
                "文本长度 \(text.count) 光标右界 \(caret.maxX) 出帧宽 \(view.bounds.width)"
            )
            // 光标顶须落在第 lines 行的行带内（逃逸形态
            // 是掉到文本块下方一行，即 ≥ lines×行高）
            XCTAssertLessThan(
                caret.minY, CGFloat(lines) * ComposerLayout.lineHeight,
                "文本长度 \(text.count) 光标顶 \(caret.minY) 逃出 \(lines) 行文本块"
            )
            if !ComposerLayout.shouldScroll(
                measured: ComposerTextMetrics.textHeight(
                    for: text, width: width
                )
            ) {
                XCTAssertLessThanOrEqual(
                    caret.maxY, view.bounds.height + 1.5,
                    "文本长度 \(text.count) 光标底 \(caret.maxY) 出帧高 \(view.bounds.height)"
                )
            }
        }
    }

    /// 换行左齐：长句缠绕 ≥3 行，各行 fragment 的
    /// usedRect.minX 全等 textOriginX（±0.6 排版容差）
    func testWrappedLinesShareLeftOrigin() {
        let text = "量测长句缠绕排版验证文字自然增长四季轮换工作日程安排与提醒事项同步完成存档"
        let view = makeLaidOutView(text)
        let lm = view.layoutManager
        var origins: [CGFloat] = []
        lm.enumerateLineFragments(
            forGlyphRange: NSRange(
                location: 0, length: lm.numberOfGlyphs
            )
        ) { _, usedRect, _, _, _ in
            origins.append(usedRect.minX)
        }
        XCTAssertGreaterThanOrEqual(origins.count, 3)
        for x in origins {
            XCTAssertEqual(
                x, ComposerTextMetrics.textOriginX, accuracy: 0.6,
                "行原点 \(x) 与 textOriginX \(ComposerTextMetrics.textOriginX) 不齐"
            )
        }
    }

    /// 同源断言：视图侧 fragment 行数 == 量测侧 lineCount
    /// （同文本同宽同字体，两栈给出同一行数）
    func testViewAndMetricsAgreeOnLineCount() {
        let samples = [
            "规划",
            "量测两行甲班\n量测两行乙班",
            "量测长句缠绕排版验证文字自然增长四季轮换工作日程安排与提醒事项同步完成存档",
        ]
        for text in samples {
            let view = makeLaidOutView(text)
            let lm = view.layoutManager
            var fragments = 0
            lm.enumerateLineFragments(
                forGlyphRange: NSRange(
                    location: 0, length: lm.numberOfGlyphs
                )
            ) { _, _, _, _, _ in fragments += 1 }
            XCTAssertEqual(
                fragments,
                ComposerTextMetrics.lineCount(for: text, width: width),
                "文本「\(text.prefix(8))…」视图行数 \(fragments) 与量测不一致"
            )
        }
    }
}
