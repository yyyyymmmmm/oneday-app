import OneDayCore
import XCTest

/// 发送舱多行纯逻辑定案（0.2.9，DESIGN-V4 §13）：行数
/// 由 ComposerTextMetrics 以 TextKit 在与实际布局相同
/// 的字体与宽度（容器 402 − 横向 chrome 132 ＝ 270，
/// 与 ChatView 几何逐项对应）下数出，胶囊高只由
/// ComposerLayout 纯函数决定。核心断言：给定 2 行、
/// 4 行定长串，胶囊高＝单行基数＋(n−1)×行高，±1pt
/// （单行基数 46 由键侧 30 主导、与文本侧差 0.83 在
/// 容差内，见 ComposerLayout 注）。
final class ComposerTextMetricsTests: XCTestCase {
    /// 与真机同宽的容器口径（402pt 机型）
    private var textWidth: CGFloat {
        ComposerLayout.textWidth(forContainerWidth: 402)
    }

    /// 宽度同源：402 容器 → 文本宽 270（chrome 132 逐项
    /// 对应 ChatView：边距 24＋16、键 60、间距 16、字段
    /// 边距 16）
    func testTextWidthDerivation() {
        XCTAssertEqual(ComposerLayout.horizontalChrome, 132)
        XCTAssertEqual(textWidth, 270, accuracy: 0.001)
    }

    /// 行高常数与字体同源：ComposerLayout.lineHeight 须
    /// 等于正文字体（单一来源 bodyFont）的真实行高
    func testLineHeightMatchesFont() {
        XCTAssertEqual(
            ComposerTextMetrics.bodyFont.lineHeight,
            ComposerLayout.lineHeight, accuracy: 0.5,
            "字体行高 \(ComposerTextMetrics.bodyFont.lineHeight) 与常数 \(ComposerLayout.lineHeight) 脱钩"
        )
    }

    /// 2 行定长串：行数 == 2，胶囊 == 基数＋1×行高（±1）
    func testTwoLineCapsule() {
        let two = "量测两行甲班\n量测两行乙班"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: two, width: textWidth), 2
        )
        let base = ComposerTextMetrics.capsuleHeight(
            for: "量测两行甲班", width: textWidth
        )
        XCTAssertEqual(base, 46, accuracy: 0.001)
        let capsule = ComposerTextMetrics.capsuleHeight(
            for: two, width: textWidth
        )
        XCTAssertEqual(
            capsule, base + ComposerLayout.lineHeight, accuracy: 1,
            "2 行胶囊 \(capsule)，应为基数 \(base)＋行高 \(ComposerLayout.lineHeight)（±1）"
        )
    }

    /// 4 行定长串：行数 == 4，胶囊 == 基数＋3×行高（±1）
    func testFourLineCapsule() {
        let four = "量测四行甲班\n量测四行乙班\n量测四行丙班\n量测四行丁班"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: four, width: textWidth), 4
        )
        let base = ComposerTextMetrics.capsuleHeight(
            for: "量测四行甲班", width: textWidth
        )
        let capsule = ComposerTextMetrics.capsuleHeight(
            for: four, width: textWidth
        )
        XCTAssertEqual(
            capsule, base + 3 * ComposerLayout.lineHeight, accuracy: 1,
            "4 行胶囊 \(capsule)，应为基数 \(base)＋3×行高（±1）"
        )
    }

    /// 缠绕行数：37 字单行长句在文本宽 270 下恰缠 3 行
    /// （宽度路径的行数证据——宽度错则行数错）
    func testWrapCountsThreeLines() {
        let wrap = "量测长句缠绕排版验证文字自然增长四季轮换工作日程安排与提醒事项同步完成存档"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: wrap, width: textWidth), 3
        )
    }

    /// 空文本：1 行、胶囊＝单行基数 46
    func testEmptyIsSingleLine() {
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "", width: textWidth), 1
        )
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(for: "", width: textWidth),
            46, accuracy: 0.001
        )
    }
}
