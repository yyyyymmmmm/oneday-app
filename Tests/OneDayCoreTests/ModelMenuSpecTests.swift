import OneDayCore
import XCTest

/// 模型菜单对号槽钉（0.36.4，用户 18:48 点名）：
/// 槽宽恒定、与有无对号无关——未选行靠留空槽与
/// 选中行同列。若有人把槽改回「有勾才占位」，名
/// 字列立刻漂移，先在此红。
final class ModelMenuSpecTests: XCTestCase {

    func testCheckmarkSlotIsFixedWidth() {
        XCTAssertEqual(ModelMenuSpec.checkmarkSlotWidth, 18)
        XCTAssertEqual(ModelMenuSpec.checkmarkSlotSpacing, 6)
        // 槽宽须容得下 checkmark 字形（body 档 ≈15）
        // 又不许宽到把名字列推得肉眼可辨地右移
        XCTAssertGreaterThanOrEqual(
            ModelMenuSpec.checkmarkSlotWidth, 15
        )
        XCTAssertLessThanOrEqual(
            ModelMenuSpec.checkmarkSlotWidth, 22
        )
    }
}
