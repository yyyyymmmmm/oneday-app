import XCTest
@testable import OneDayCore

/// 智能体本地档案（0.36.22）：显示名多来源仲裁、编
/// 辑输入净化、分享域名提取（名片红线）、预置头像
/// 目录完整性——全是纯逻辑，视图层只许消费不许另判。
final class AgentProfileTests: XCTestCase {

    // MARK: - 显示名仲裁：覆盖 → soul → Hermes

    func testDisplayNameOverrideWins() {
        XCTAssertEqual(
            AgentDisplayName.resolve(override: "小助手", soulName: "三狗"),
            "小助手"
        )
    }

    func testDisplayNameFallsToSoulThenFallback() {
        XCTAssertEqual(
            AgentDisplayName.resolve(override: nil, soulName: "三狗"),
            "三狗"
        )
        XCTAssertEqual(
            AgentDisplayName.resolve(override: nil, soulName: nil),
            "Hermes"
        )
    }

    func testDisplayNameEmptyStringsCountAsUnset() {
        XCTAssertEqual(
            AgentDisplayName.resolve(override: "", soulName: "三狗"),
            "三狗"
        )
        XCTAssertEqual(
            AgentDisplayName.resolve(override: nil, soulName: ""),
            "Hermes"
        )
    }

    // MARK: - 编辑输入净化

    func testSanitizedOverrideCollapsesWhitespace() {
        XCTAssertEqual(
            AgentDisplayName.sanitizedOverride("  小  助手 \n"),
            "小 助手"
        )
    }

    func testSanitizedOverrideRejectsBlankAndOverlong() {
        XCTAssertNil(AgentDisplayName.sanitizedOverride("   "))
        XCTAssertNil(AgentDisplayName.sanitizedOverride(""))
        XCTAssertNil(
            AgentDisplayName.sanitizedOverride(String(repeating: "名", count: 21))
        )
        XCTAssertEqual(
            AgentDisplayName.sanitizedOverride(String(repeating: "名", count: 20)),
            String(repeating: "名", count: 20)
        )
    }

    // MARK: - 分享域名：只出 host（红线）

    func testHostExtractionStripsEverythingButHost() {
        XCTAssertEqual(
            AgentServerHost.extract(
                from: "https://user:secret@hermes.didichou.site:8443/v1?key=abc"
            ),
            "hermes.didichou.site"
        )
        XCTAssertEqual(
            AgentServerHost.extract(from: "https://hermes.didichou.site"),
            "hermes.didichou.site"
        )
        XCTAssertEqual(
            AgentServerHost.extract(from: "http://118.24.41.52:8642"),
            "118.24.41.52"
        )
    }

    func testHostExtractionSchemelessAndGarbage() {
        XCTAssertEqual(
            AgentServerHost.extract(from: "hermes.didichou.site"),
            "hermes.didichou.site"
        )
        XCTAssertNil(AgentServerHost.extract(from: nil))
        XCTAssertNil(AgentServerHost.extract(from: ""))
        XCTAssertNil(AgentServerHost.extract(from: "   "))
    }

    // MARK: - 分享名片文本

    func testShareCardTextShape() {
        XCTAssertEqual(
            AgentShareCardText.make(name: "三狗", host: "hermes.didichou.site"),
            "三狗 · hermes.didichou.site"
        )
        XCTAssertEqual(
            AgentShareCardText.make(name: "三狗", host: nil),
            "三狗"
        )
        XCTAssertEqual(
            AgentShareCardText.make(name: "三狗", host: ""),
            "三狗"
        )
    }

    // MARK: - 预置头像目录

    func testPresetCatalogIntegrity() {
        let ids = AgentAvatarPreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "预置 id 不许重复")
        XCTAssertTrue(ids.contains(AgentAvatarPreset.defaultID))
        for preset in AgentAvatarPreset.all {
            // 每款必须二选一有图源：资产或符号
            XCTAssertTrue(
                (preset.assetName == nil) != (preset.symbolName == nil),
                "预置 \(preset.id) 的图源必须恰有其一"
            )
            XCTAssertFalse(preset.displayName.isEmpty)
        }
    }

    func testPresetResolveFallsBackToDefault() {
        XCTAssertEqual(
            AgentAvatarPreset.resolve(id: "paw").id, "paw"
        )
        XCTAssertEqual(
            AgentAvatarPreset.resolve(id: "不存在的 id").id,
            AgentAvatarPreset.defaultID
        )
        XCTAssertEqual(
            AgentAvatarSelection.default,
            .preset(id: AgentAvatarPreset.defaultID)
        )
    }
}

/// 枢纽边缘右滑仲裁（0.36.22 立、0.36.24 改判）：生
/// 死关无方向判据（速度门已退役——begin 时刻量未累
/// 积恒假死，P-15 同病复发），方向改 handler 内按
/// translation 仲裁、跟手钳制、松手裁决表——桥层只
/// 许照表执行，不许在 UIKit 侧另写比值。
final class HubEdgeSwipeTests: XCTestCase {

    func testArbitrationStaysUndecidedBelowDecisionFloor() {
        // 主导轴未过决定下限：方向读数还是噪声，不表态
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 0, translationY: 0),
            .undecided
        )
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 7, translationY: 0),
            .undecided
        )
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 0, translationY: -7),
            .undecided
        )
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 5, translationY: 5),
            .undecided
        )
    }

    func testArbitrationFollowsClearRightwardDrag() {
        // 纯横向右滑
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 30, translationY: 0),
            .follow
        )
        // 横向主导（比值 1.5 内）跟手，上下偏都认
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 30, translationY: 19),
            .follow
        )
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 30, translationY: -19),
            .follow
        )
        // 比值边界（30 = 20 × 1.5）恰过线也跟手
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 30, translationY: 20),
            .follow
        )
        // 决定下限边界：主导轴恰 8 且纯横向
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 8, translationY: 0),
            .follow
        )
    }

    func testArbitrationYieldsEverythingElseToScroll() {
        // 纵向主导（列表滚动形态）让位
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 5, translationY: 30),
            .yieldToScroll
        )
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 0, translationY: -40),
            .yieldToScroll
        )
        // 左向让位（本手势只认右滑返回）
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: -30, translationY: 2),
            .yieldToScroll
        )
        // 斜向不明确（过不了 1.5 比值）让位：退出的代
        // 价高于滚动，含糊一律判给滚动
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 20, translationY: 20),
            .yieldToScroll
        )
        XCTAssertEqual(
            HubEdgeSwipe.arbitration(translationX: 29, translationY: 20),
            .yieldToScroll
        )
    }

    func testFollowedOffsetClamps() {
        XCTAssertEqual(HubEdgeSwipe.followedOffset(translationX: -20), 0)
        XCTAssertEqual(HubEdgeSwipe.followedOffset(translationX: 120), 120)
        XCTAssertEqual(
            HubEdgeSwipe.followedOffset(translationX: 9999),
            HubEdgeSwipe.maxFollowOffset
        )
    }

    func testShouldDismissTable() {
        // 位移直达线
        XCTAssertTrue(HubEdgeSwipe.shouldDismiss(translationX: 90, velocityX: 0))
        XCTAssertFalse(HubEdgeSwipe.shouldDismiss(translationX: 89, velocityX: 0))
        // 半线＋快甩
        XCTAssertTrue(HubEdgeSwipe.shouldDismiss(translationX: 40, velocityX: 500))
        XCTAssertFalse(HubEdgeSwipe.shouldDismiss(translationX: 40, velocityX: 499))
        XCTAssertFalse(HubEdgeSwipe.shouldDismiss(translationX: 39, velocityX: 900))
        // 反向速度不救
        XCTAssertFalse(HubEdgeSwipe.shouldDismiss(translationX: 60, velocityX: -800))
    }
}
