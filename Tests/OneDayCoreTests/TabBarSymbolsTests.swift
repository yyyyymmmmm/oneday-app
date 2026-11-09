import OneDayCore
import XCTest

/// 底栏符号名对定版（0.3.1 立，0.3.8 收口）：0.3.8 起
/// 底栏自绘、符号仍系统直渲；§22.5 立宪禁 .fill 后，
/// 0.3.7 遗留在账本里的 chat/files 两个 .fill 名本轮
/// 清账——四格 selected 恒等于 normal，选中只靠浅灰
/// 胶囊垫（FloatingTabBar）。本组测试钉全表＋禁 fill。
final class TabBarSymbolsTests: XCTestCase {
    /// 四条目名对全表钉死（id／标题／未选／选中、顺序）
    func testTabSymbolPairsArePinned() {
        XCTAssertEqual(TabBarSymbols.all, [
            TabSymbolPair(
                id: "chat", title: "聊天",
                normal: "bubble.left.and.bubble.right",
                selected: "bubble.left.and.bubble.right"
            ),
            TabSymbolPair(
                id: "overview", title: "总览",
                normal: "chart.line.uptrend.xyaxis",
                selected: "chart.line.uptrend.xyaxis"
            ),
            TabSymbolPair(
                id: "files", title: "文件",
                normal: "folder",
                selected: "folder"
            ),
            TabSymbolPair(
                id: "settings", title: "设置",
                normal: "slider.horizontal.3",
                selected: "slider.horizontal.3"
            ),
        ])
    }

    /// §22.5 变体纪律（0.3.8）：全表不许出现 .fill，
    /// 两态恒同名——选中信号只由胶囊垫承载
    func testNoFillVariantsAnywhere() {
        for pair in TabBarSymbols.all {
            XCTAssertEqual(pair.selected, pair.normal, "\(pair.id) 两态须同名")
            XCTAssertFalse(
                pair.normal.contains(".fill") || pair.selected.contains(".fill"),
                "\(pair.id) 不许 .fill 变体"
            )
        }
    }

    /// 按态取名：两态同名（0.3.8 口径）
    func testNameIsStableAcrossSelection() {
        for pair in TabBarSymbols.all {
            XCTAssertEqual(
                pair.name(isSelected: true), pair.name(isSelected: false)
            )
        }
    }
}

/// 自绘底栏几何（0.3.8 第 2 条）：垫宽由构造决定、
/// 栏占位带与既有 tabBarZone 同值口径
final class TabBarLayoutTests: XCTestCase {
    func testPadWidthAddsBothInsets() {
        // 22pt 字形点宽约 24–28 → 垫宽约 50–54，远小于
        // 原生栏的约 1/4 栏宽（393 屏约 98）
        XCTAssertEqual(TabBarLayout.padWidth(glyphWidth: 26), 52)
        XCTAssertLessThan(
            TabBarLayout.padWidth(glyphWidth: 28), 393.0 / 4
        )
    }

    func testZoneHeightMatchesLegacyZone() {
        XCTAssertEqual(TabBarLayout.zoneHeight, 76)
        XCTAssertEqual(TabBarLayout.barHeight, 58)
        XCTAssertEqual(TabBarLayout.glyphSize, 22)
    }
}
