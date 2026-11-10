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

    /// 输入序列（0.3.5，§20.1）：复刻真机录屏路径
    /// 「测试」→ 回车成行 → 组合输入续打——胶囊高全程
    /// 单调不减（形态只向前跨、不回跳）；同文本重复量
    /// 测逐次相等（量测是纯函数：无状态、无迟滞）。
    /// 切换路径的视图身份建立在此之上：几何只由文本
    /// 决定，文本视图全程同一实例、只改 frame，marked
    /// 段与光标无从被「换视图」丢掉
    func testTypingSequenceModeIsMonotonicAndPure() {
        let steps = ["", "测", "测试", "测试\n", "测试\nh", "测试\n好"]
        let heights = steps.map {
            ComposerTextMetrics.capsuleHeight(
                for: $0, containerWidth: 402
            )
        }
        XCTAssertEqual(heights[0], 46, accuracy: 0.001)
        XCTAssertEqual(heights[2], 46, accuracy: 0.001)
        for i in 1..<heights.count {
            XCTAssertGreaterThanOrEqual(
                heights[i], heights[i - 1],
                "第 \(i) 步胶囊高 \(heights[i]) 小于前步 \(heights[i - 1])（形态回跳）"
            )
        }
        // 第 4 步「测试\n」等值收紧（0.36.12）：尾部 \n
        // 的光标行恒计入后，该步须与下一步「测试\nh」
        // 逐值相等——旧版只断言单调不减、放行了漏数
        XCTAssertEqual(heights[3], 98.34, accuracy: 1)
        XCTAssertEqual(heights[3], heights[4], accuracy: 0.001)
        XCTAssertEqual(heights[4], 98.34, accuracy: 1)
        XCTAssertEqual(heights[5], heights[4], accuracy: 0.001)
        for s in steps {
            XCTAssertEqual(
                ComposerTextMetrics.capsuleHeight(
                    for: s, containerWidth: 402
                ),
                ComposerTextMetrics.capsuleHeight(
                    for: s, containerWidth: 402
                ),
                accuracy: 0.001
            )
        }
    }

    /// 尾部换行光标行（0.36.12，用户真机录屏定案，
    /// 诊断档 composer-newline-diagnosis-20261110）：
    /// 以 \n 结尾时光标所在的空行是 TextKit 的
    /// extraLineFragment、不在字形枚举内，旧量测漏
    /// 数——「测试\n」数成 1 行、胶囊不动，键入新字
    /// 才跳高。口径：尾 \n 的光标行恒计入
    func testTrailingNewlineCountsCursorLine() {
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "测试\n", width: textWidth), 2
        )
        XCTAssertEqual(
            ComposerTextMetrics.textHeight(for: "测试\n", width: textWidth),
            2 * ComposerLayout.lineHeight, accuracy: 0.01
        )
        // 回车当场就该到两行高：与续打一字的「测试\nh」
        // 逐值相等
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(
                for: "测试\n", containerWidth: 402
            ),
            ComposerTextMetrics.capsuleHeight(
                for: "测试\nh", containerWidth: 402
            ),
            accuracy: 0.001
        )
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(
                for: "测试\n", containerWidth: 402
            ),
            98.34, accuracy: 1
        )
    }

    /// 连续尾部换行与纯换行：每多一个尾 \n 多一行
    /// 光标行（「a\n\n」枚举 2＋补 1＝3；「\n」枚举
    /// 1＋补 1＝2）
    func testMultipleTrailingNewlines() {
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "测试\n\n", width: textWidth), 3
        )
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "\n", width: textWidth), 2
        )
    }

    /// 中间＋尾部混合（防双补/漏补）与无尾 \n 的回
    /// 归护栏
    func testMiddleAndTrailingNewline() {
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "测试\nh\n", width: textWidth), 3
        )
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "测试", width: textWidth), 1
        )
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: "测试\nh", width: textWidth), 2
        )
    }

    /// 封顶边界：5 行正文＋尾 \n 数得 6 行、实测高
    /// 恰达封顶、胶囊为 6 行多行总高（115.02＋60＝
    /// 175.02）；6 行正文＋尾 \n 数得 7 行、未封顶
    /// 实测高过封顶使内滚触发（光标行可经滚动到
    /// 达），胶囊仍封顶
    func testTrailingNewlineAtCapBoundary() {
        let five = "量测五行甲班\n量测五行乙班\n量测五行丙班\n量测五行丁班\n量测五行戊班\n"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: five, width: textWidth), 6
        )
        XCTAssertEqual(
            ComposerTextMetrics.textHeight(for: five, width: textWidth),
            ComposerLayout.maxTextHeight, accuracy: 0.01
        )
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(for: five, containerWidth: 402),
            175.02, accuracy: 1
        )
        let six = "量测六行甲班\n量测六行乙班\n量测六行丙班\n量测六行丁班\n量测六行戊班\n量测六行己班\n"
        XCTAssertEqual(
            ComposerTextMetrics.lineCount(for: six, width: textWidth), 7
        )
        let measured = ComposerTextMetrics.textHeight(
            for: six, width: textWidth
        )
        XCTAssertEqual(
            measured, 7 * ComposerLayout.lineHeight, accuracy: 0.01
        )
        XCTAssertTrue(ComposerLayout.shouldScroll(measured: measured))
        XCTAssertEqual(
            ComposerTextMetrics.capsuleHeight(for: six, containerWidth: 402),
            175.02, accuracy: 1
        )
    }
}
