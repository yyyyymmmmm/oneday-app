import OneDayCore
import XCTest

/// 模型菜单带勾判定（0.36.13）：菜单改系统 Picker
/// 承载后勾由系统画，本组钉的是勾的语义口径——
/// 「哪行该带勾」恒由 ModelMenuSelection.checkedID
/// 单点决定：清单内选中值有且仅有一勾、清单外零
/// 勾、切换后勾逐次随动。渲染通道（Menu→UIKit 提
/// 取时 .opacity 被剥掉、双勾同显的旧病）单测钉不
/// 住，验收靠真机展开菜单看一勾（DESIGN-V4 §78）；
/// 0.36.4 的对号槽常数钉测（ModelMenuSpecTests）随
/// opacity 形态退役，由本组替代。
final class ModelMenuSelectionTests: XCTestCase {

    private let itemIDs = ["deepseek-flash", "deepseek-v4-pro"]

    /// 一组：双模型各选其一，勾恒为所选那行、且总
    /// 数恒一——checkedID 至多返回一个 id 是构造上
    /// 的保证，此处把两向都钉死防判定被改成多选
    func testCheckedIDFollowsEachSingleSelection() {
        XCTAssertEqual(
            ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: "deepseek-flash"
            ),
            "deepseek-flash"
        )
        XCTAssertEqual(
            ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: "deepseek-v4-pro"
            ),
            "deepseek-v4-pro"
        )
        // 任一选中态下带勾行数恒为 1（不多不少）
        for selected in itemIDs {
            let checked = ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: selected
            )
            XCTAssertEqual([checked].compactMap { $0 }.count, 1)
        }
    }

    /// 二组：已下线/未知 id、空串、nil 一律零勾——
    /// 本地存量选中值指向已退役模型时，菜单不许把
    /// 勾错挂到任何一行上
    func testCheckedIDIsNilForUnknownSelection() {
        XCTAssertNil(
            ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: "qwen3-30b-retired"
            )
        )
        XCTAssertNil(
            ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: ""
            )
        )
        XCTAssertNil(
            ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: nil
            )
        )
        XCTAssertNil(
            ModelMenuSelection.checkedID(
                itemIDs: [], selected: "deepseek-flash"
            )
        )
    }

    /// 三组：切换序列 flash→pro→flash，勾逐次随
    /// 动、任一时刻计数恒为 1 且等于当刻选中值
    func testCheckedIDTracksSwitchSequence() {
        let sequence = [
            "deepseek-flash", "deepseek-v4-pro", "deepseek-flash",
        ]
        for selected in sequence {
            let checked = ModelMenuSelection.checkedID(
                itemIDs: itemIDs, selected: selected
            )
            XCTAssertEqual(checked, selected)
            XCTAssertEqual([checked].compactMap { $0 }.count, 1)
        }
    }
}
