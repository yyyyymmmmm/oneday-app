import OneDayCore
import XCTest

/// 发送舱多行纯逻辑定案（0.2.9，DESIGN-V4 §13）：
/// 行数由 ComposerTextMetrics 以 TextKit 在与实际布局
/// 相同的字体与宽度下数出，胶囊高只由 ComposerLayout
/// 纯函数决定。0.3.3 上文下钮口径：capsuleHeight 入参
/// 改容器宽，内部窄宽（402−132＝270）判形态、全宽
/// （402−56＝346）量多行高；多行胶囊＝全宽文本高＋60
/// （文本纵向边距 10＋按钮行距 4＋按钮行 30＋行纵向
/// 边距 16）——2 行 98.34、4 行 136.68（±1）。
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

    /// 2 行定长串：窄宽行数 == 2（形态判据），全宽仍
    /// 2 行，胶囊 ＝38.34＋60＝98.34（±1）；单行基数 46
    func testTwoLineCapsule() {
        let two = "量测两行甲班\n量测两行乙班"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: two, width: textWidth), 2
        )
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(
                for: "量测两行甲班", containerWidth: 402
            ),
            46, accuracy: 0.001
        )
        let capsule = ComposerTextMetrics.capsuleHeight(
            for: two, containerWidth: 402
        )
        XCTAssertEqual(
            capsule, 98.34, accuracy: 1,
            "2 行胶囊 \(capsule)，应为全宽 2 行高 38.34＋60（±1）"
        )
    }

    /// 4 行定长串：行数 == 4，胶囊 ＝76.68＋60＝136.68（±1）
    func testFourLineCapsule() {
        let four = "量测四行甲班\n量测四行乙班\n量测四行丙班\n量测四行丁班"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: four, width: textWidth), 4
        )
        let capsule = ComposerTextMetrics.capsuleHeight(
            for: four, containerWidth: 402
        )
        XCTAssertEqual(
            capsule, 136.68, accuracy: 1,
            "4 行胶囊 \(capsule)，应为全宽 4 行高 76.68＋60（±1）"
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
            ComposerTextMetrics.capsuleHeight(for: "", containerWidth: 402),
            46, accuracy: 0.001
        )
    }
}
