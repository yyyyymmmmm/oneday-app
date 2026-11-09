import OneDayCore
import XCTest

/// 底栏符号名对定版（0.3.1 立，0.3.8 收口，0.4.0 续）：
/// 0.4.0 底栏回原生 TabView（审计 §3.2），本表降为原生
/// Tab 的 Label 符号源（系统直渲）；§22.5 立宪禁 .fill
/// 后 selected 恒等于 normal。本组测试钉全表＋禁 fill。
/// 0.6.0 五格 IA：聊天／活动／点子／目标／应用（蓝图 §4
/// 一期）；旧总览/文件/设置符号退为应用格内入口符号源，
/// 不再占底栏格（all 只含五格）。
final class TabBarSymbolsTests: XCTestCase {
    /// 五条目名对全表钉死（id／标题／未选／选中、顺序）
    func testTabSymbolPairsArePinned() {
        XCTAssertEqual(TabBarSymbols.all, [
            TabSymbolPair(
                id: "chat", title: "聊天",
                normal: "message",
                selected: "message"
            ),
            TabSymbolPair(
                id: "activity", title: "活动",
                normal: "list.bullet",
                selected: "list.bullet"
            ),
            TabSymbolPair(
                id: "ideas", title: "点子",
                normal: "lightbulb",
                selected: "lightbulb"
            ),
            TabSymbolPair(
                id: "goals", title: "目标",
                normal: "checklist",
                selected: "checklist"
            ),
            TabSymbolPair(
                id: "apps", title: "应用",
                normal: "circle.grid.2x2",
                selected: "circle.grid.2x2"
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
