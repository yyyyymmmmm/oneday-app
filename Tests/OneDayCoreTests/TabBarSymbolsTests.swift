import OneDayCore
import XCTest

/// 底栏符号名对定版（0.3.1，DESIGN-V4 §16）：图标走
/// 礼记同款系统直渲（Label＋systemImage，零配置零预
/// 渲染），本组测试只钉符号名对清单——未选线条体与
/// 选中官方 .fill 对。0.2.9 的 alpha 量高与 0.3.1
/// 先行版的配置定标断言均已删除（两路线皆作废，定
/// 因与止损条款在 §16）。
final class TabBarSymbolsTests: XCTestCase {
    /// 四条目名对全表钉死（id／标题／未选／选中、顺序）
    func testTabSymbolPairsArePinned() {
        XCTAssertEqual(TabBarSymbols.all, [
            TabSymbolPair(
                id: "chat", title: "聊天",
                normal: "bubble.left.and.bubble.right",
                selected: "bubble.left.and.bubble.right.fill"
            ),
            TabSymbolPair(
                id: "overview", title: "总览",
                normal: "chart.line.uptrend.xyaxis",
                selected: "chart.line.uptrend.xyaxis"
            ),
            TabSymbolPair(
                id: "files", title: "文件",
                normal: "folder",
                selected: "folder.fill"
            ),
            TabSymbolPair(
                id: "settings", title: "设置",
                normal: "slider.horizontal.3",
                selected: "slider.horizontal.3"
            ),
        ])
    }

    /// 成对变体纪律：凡选中名与未选名不同者，必须是
    /// 官方 .fill 后缀对，不许自造变体名
    func testSelectedVariantsAreOfficialFillPairs() {
        for pair in TabBarSymbols.all where pair.selected != pair.normal {
            XCTAssertEqual(
                pair.selected, pair.normal + ".fill",
                "\(pair.id) 选中变体不是官方 .fill 对"
            )
        }
    }

    /// 按态取名：选中回 .fill 侧、未选回线条侧
    func testNameSwitchesBySelection() {
        XCTAssertEqual(
            TabBarSymbols.chat.name(isSelected: true),
            "bubble.left.and.bubble.right.fill"
        )
        XCTAssertEqual(
            TabBarSymbols.chat.name(isSelected: false),
            "bubble.left.and.bubble.right"
        )
        XCTAssertEqual(
            TabBarSymbols.settings.name(isSelected: true),
            TabBarSymbols.settings.name(isSelected: false),
            "无 .fill 对的条目两态同名"
        )
    }
}
