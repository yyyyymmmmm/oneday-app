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

/// 枢纽边缘右滑仲裁（0.36.22）：生死只认速度域（P-15
/// 续修口径）、跟手钳制、松手裁决表——桥层只许照表执
/// 行，不许在 UIKit 侧另写比值。
final class HubEdgeSwipeTests: XCTestCase {

    func testShouldBeginNeedsRightwardHorizontalDominantVelocity() {
        XCTAssertTrue(HubEdgeSwipe.shouldBegin(velocityX: 300, velocityY: 100))
        XCTAssertTrue(HubEdgeSwipe.shouldBegin(velocityX: 300, velocityY: -100))
        // 纵向主导（列表滚动形态）拒
        XCTAssertFalse(HubEdgeSwipe.shouldBegin(velocityX: 100, velocityY: 300))
        // 左向拒（本手势只认右滑返回）
        XCTAssertFalse(HubEdgeSwipe.shouldBegin(velocityX: -300, velocityY: 0))
        // 静止无速度拒
        XCTAssertFalse(HubEdgeSwipe.shouldBegin(velocityX: 0, velocityY: 0))
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
