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

/// 枢纽根页左缘右滑退出判读（0.36.27 §97 件五整
/// 桥退役后）：桥时代的 handler 仲裁/跟手钳制/松手
/// 裁决表（速度＋比值）已随 HubEdgeSwipeBridge 删
/// 除退役；现只钉阈值单源与「左缘起手＋横向过线」
/// 一条纯判读——视图层照此执行，不许另写数。
final class HubEdgeSwipeTests: XCTestCase {

    func testThresholdConstantsAreSingleSourced() {
        XCTAssertEqual(HubEdgeSwipe.edgeWidth, 28)
        // 起滑线与聊天右滑引用同值（同族构造口径）
        XCTAssertEqual(HubEdgeSwipe.minimumDistance, 30)
        XCTAssertEqual(HubEdgeSwipe.triggerTranslation, 60)
    }

    func testEdgeStartInsideBand() {
        XCTAssertTrue(HubEdgeSwipe.isEdgeStart(globalX: 0))
        XCTAssertTrue(HubEdgeSwipe.isEdgeStart(globalX: 14))
        // 带边界恰 28 算带内
        XCTAssertTrue(HubEdgeSwipe.isEdgeStart(globalX: 28))
    }

    func testEdgeStartOutsideBand() {
        XCTAssertFalse(HubEdgeSwipe.isEdgeStart(globalX: 29))
        XCTAssertFalse(HubEdgeSwipe.isEdgeStart(globalX: 120))
    }

    func testTriggerRequiresEdgeStart() {
        XCTAssertTrue(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 10, translationX: 61)
        )
        // 起点不在左缘带内：位移再大也不触发（页面中
        // 央起手的横拖不是返回意图）
        XCTAssertFalse(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 100, translationX: 61)
        )
        XCTAssertFalse(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 100, translationX: 200)
        )
    }

    func testTriggerIsStrictlyGreaterAndRightwardOnly() {
        // 恰在线上不触发（严格大于，与聊天右滑引用
        // shouldTrigger 同义）
        XCTAssertFalse(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 10, translationX: 60)
        )
        XCTAssertTrue(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 10, translationX: 61)
        )
        // 左向/零位移不触发（纵滚横向分量≈0 同理）
        XCTAssertFalse(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 10, translationX: -80)
        )
        XCTAssertFalse(
            HubEdgeSwipe.shouldTrigger(startGlobalX: 10, translationX: 0)
        )
    }
}
