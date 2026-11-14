import OneDayDesign
import XCTest

/// 分区外距落值钉（UI 台账余项批，2026-11-14）：
/// 组节奏定版（DESIGN-V2 §3.2「分区标题上 28 下
/// 8」）的 28 一侧——手搓页 SectionLabel 之上与
/// 页末组之下的同族留白。此值曾以字面量散写 38
/// 处（PM/UI 复盘点名的「组顶距 28 复发」），收
/// 编入 OneDayMetrics.sectionOuterSpacing 后以本
/// 钉守值：改值须先改组节奏定版、不许单边漂移；
/// 下 8 一侧即 spacingS、已在间距梯队内不另钉。
final class SectionOuterSpacingTests: XCTestCase {

    func testSectionOuterSpacingMatchesGroupRhythm() {
        XCTAssertEqual(OneDayMetrics.sectionOuterSpacing, 28)
    }

    func testSectionOuterSpacingExceedsSettingsGroupSpacing() {
        // 分区外距是页面级组节奏、恒大于设置页组距
        // （24）与一般组距 spacingL（24）——外距被
        // 压平到组距即组界消失，本关系钉住层级差
        XCTAssertGreaterThan(
            OneDayMetrics.sectionOuterSpacing,
            OneDayMetrics.settingsSectionSpacing
        )
        XCTAssertGreaterThan(
            OneDayMetrics.sectionOuterSpacing,
            OneDayMetrics.spacingL
        )
    }
}
