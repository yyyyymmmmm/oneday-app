import XCTest
@testable import OneDayCore

/// 智能体身份（§245 收敛后）：呈现名只剩「缓存→回
/// 落」一级链；改名校验与服务端同口径；升级迁移的
/// 最后一判（旧覆盖/双槽头像按退役前末写胜语义折
/// 算成缓存＋待推标记）——全是纯逻辑，视图层与存储
/// 层只许消费不许另判。
final class AgentProfileTests: XCTestCase {

    // MARK: - 显示名：缓存 → Hermes（§245 一级链）

    func testDisplayNameFromCache() {
        XCTAssertEqual(
            AgentDisplayName.resolve(cachedName: "三狗"), "三狗"
        )
    }

    func testDisplayNameFallsBackWhenCacheEmpty() {
        XCTAssertEqual(
            AgentDisplayName.resolve(cachedName: nil), "Hermes"
        )
        XCTAssertEqual(
            AgentDisplayName.resolve(cachedName: ""), "Hermes"
        )
        XCTAssertEqual(
            AgentDisplayName.resolve(cachedName: "   "), "Hermes"
        )
    }

    // MARK: - 改名校验（与桥 _validate_new_name 同口径）

    func testSanitizedRenameCollapsesWhitespace() {
        XCTAssertEqual(
            AgentNameEdit.sanitizedRename("  小  助手 \n"), "小 助手"
        )
    }

    func testSanitizedRenameRejectsBlankAndOverlong() {
        XCTAssertNil(AgentNameEdit.sanitizedRename("   "))
        XCTAssertNil(AgentNameEdit.sanitizedRename(""))
        XCTAssertNil(
            AgentNameEdit.sanitizedRename(
                String(repeating: "名", count: 21)
            )
        )
        XCTAssertEqual(
            AgentNameEdit.sanitizedRename(
                String(repeating: "名", count: 20)
            ),
            String(repeating: "名", count: 20)
        )
    }

    /// 句读与结构词：服务端会拒的客户端先拒，不让用
    /// 户白跑一趟写穿才知道
    func testSanitizedRenameRejectsPunctuationAndStructuralWords() {
        XCTAssertNil(AgentNameEdit.sanitizedRename("三狗。"))
        XCTAssertNil(AgentNameEdit.sanitizedRename("三，狗"))
        XCTAssertNil(AgentNameEdit.sanitizedRename("三狗!"))
        XCTAssertNil(AgentNameEdit.sanitizedRename("# 三狗"))
        XCTAssertNil(AgentNameEdit.sanitizedRename("SOUL"))
        XCTAssertNil(AgentNameEdit.sanitizedRename("人设"))
        XCTAssertEqual(AgentNameEdit.sanitizedRename("三狗"), "三狗")
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

    // MARK: - 缓存编解码往返（落盘形态不许丢字段）

    func testNameCacheCodableRoundTrip() throws {
        let cache = IdentityNameCache(
            name: "三狗",
            serverUpdatedAt: Date(timeIntervalSince1970: 1_794_559_749),
            cachedAt: Date(timeIntervalSince1970: 1_794_559_800)
        )
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(
            IdentityNameCache.self, from: data
        )
        XCTAssertEqual(decoded, cache)
    }

    func testAvatarCacheCodableRoundTrip() throws {
        let cache = IdentityAvatarCache(
            selection: .image(itemID: "av_1"),
            itemID: "av_1",
            serverUpdatedAt: Date(timeIntervalSince1970: 1_794_559_749),
            cachedAt: Date(timeIntervalSince1970: 1_794_559_800)
        )
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(
            IdentityAvatarCache.self, from: data
        )
        XCTAssertEqual(decoded, cache)
    }

    // MARK: - 迁移·名字（§245 一次性：退役前末写胜最后一判）

    private static let migT0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let migT1 = Date(timeIntervalSince1970: 1_700_003_600)
    private static let migT2 = Date(timeIntervalSince1970: 1_700_007_200)

    /// 主案复刻：存量裸覆盖「测试」（无来源记录）压
    /// 服务器现行名「三狗」→ 迁移取服务器名、不待推
    func testMigrationBareOverrideLosesToSoulName() {
        let outcome = IdentityLegacyMigration.effectiveName(
            override: "测试", provenance: nil,
            soulName: "三狗", soulUpdatedAt: nil
        )
        XCTAssertEqual(outcome.name, "三狗")
        XCTAssertFalse(outcome.needsPush)
    }

    /// 无覆盖：直接播种服务器名
    func testMigrationNoOverrideSeedsSoulName() {
        let outcome = IdentityLegacyMigration.effectiveName(
            override: nil, provenance: nil,
            soulName: "三狗", soulUpdatedAt: Self.migT1
        )
        XCTAssertEqual(outcome.name, "三狗")
        XCTAssertFalse(outcome.needsPush)
    }

    /// 两边都无名：不播种（呈现继续回落 Hermes）
    func testMigrationNoNameAnywhereSeedsNothing() {
        let outcome = IdentityLegacyMigration.effectiveName(
            override: nil, provenance: nil,
            soulName: nil, soulUpdatedAt: nil
        )
        XCTAssertNil(outcome.name)
        XCTAssertFalse(outcome.needsPush)
    }

    /// 用户在现行名之下亲手定的名（来源对账成立、
    /// 时刻不齐）：本机胜出→播种该名并待推写穿
    func testMigrationProvenancedOverrideWinsAndNeedsPush() {
        let provenance = LegacyNameOverrideProvenance(
            writtenAt: Date(), soulNameAtWrite: "三狗"
        )
        let outcome = IdentityLegacyMigration.effectiveName(
            override: "狗子", provenance: provenance,
            soulName: "三狗", soulUpdatedAt: nil
        )
        XCTAssertEqual(outcome.name, "狗子")
        XCTAssertTrue(outcome.needsPush)
    }

    /// 时刻齐备、服务器更晚（含名绕一圈回到原点）：
    /// 只认时刻，旧覆盖退场
    func testMigrationNewerServerTimestampWins() {
        let provenance = LegacyNameOverrideProvenance(
            writtenAt: Self.migT0, soulNameAtWrite: "三狗"
        )
        let outcome = IdentityLegacyMigration.effectiveName(
            override: "狗子", provenance: provenance,
            soulName: "三狗", soulUpdatedAt: Self.migT2
        )
        XCTAssertEqual(outcome.name, "三狗")
        XCTAssertFalse(outcome.needsPush)
    }

    /// 时刻齐备、本机更晚（AI 改名之后用户又亲手
    /// 改）：末写胜不问写者，本机胜出并待推
    func testMigrationNewerOverrideTimestampWinsAndNeedsPush() {
        let provenance = LegacyNameOverrideProvenance(
            writtenAt: Self.migT2, soulNameAtWrite: "Hermes"
        )
        let outcome = IdentityLegacyMigration.effectiveName(
            override: "狗子", provenance: provenance,
            soulName: "三狗", soulUpdatedAt: Self.migT1
        )
        XCTAssertEqual(outcome.name, "狗子")
        XCTAssertTrue(outcome.needsPush)
    }

    // MARK: - 迁移·头像（§245 一次性：旧双槽最后一判）

    /// 2026-11-13 事故复刻：用户早先选过 paw，AI 其
    /// 后在服务器换上自生成图——迁移取 AI 图、不待推
    func testMigrationAILaterImageWins() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: nil, aiItemID: "av_new",
            aiUpdatedAt: Self.migT2,
            user: .preset(id: "paw"), userSelectedAt: Self.migT1,
            userEverSelected: true
        )
        XCTAssertEqual(outcome.selection, .custom)
        XCTAssertEqual(outcome.aiItemID, "av_new")
        XCTAssertFalse(outcome.userWon)
    }

    /// 用户后写：本机选择胜出→播种并待推上仓
    func testMigrationUserLaterPresetWinsAndNeedsPush() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: nil, aiItemID: "av_old",
            aiUpdatedAt: Self.migT0,
            user: .preset(id: "atom"), userSelectedAt: Self.migT1,
            userEverSelected: true
        )
        XCTAssertEqual(outcome.selection, .preset(id: "atom"))
        XCTAssertTrue(outcome.userWon)
    }

    /// 同刻取服务器（多端同源的退役口径原样）
    func testMigrationAvatarTieGoesToServer() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: "sparkles", aiItemID: "av_tie",
            aiUpdatedAt: Self.migT1,
            user: .preset(id: "paw"), userSelectedAt: Self.migT1,
            userEverSelected: true
        )
        XCTAssertEqual(outcome.selection, .preset(id: "sparkles"))
        XCTAssertFalse(outcome.userWon)
    }

    /// AI 档为空：用户选择胜出（仓从未有过当前时同理）
    func testMigrationNoAIUserSelectionWins() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: nil, aiItemID: nil, aiUpdatedAt: nil,
            user: .custom, userSelectedAt: Self.migT1,
            userEverSelected: true
        )
        XCTAssertEqual(outcome.selection, .custom)
        XCTAssertTrue(outcome.userWon)
    }

    /// 用户从未选过：AI 档胜（缺省档案不许挡住跟随）
    func testMigrationUserNeverSelectedAIWins() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: "paw", aiItemID: "av_9",
            aiUpdatedAt: Self.migT0,
            user: .default, userSelectedAt: nil,
            userEverSelected: false
        )
        XCTAssertEqual(outcome.selection, .preset(id: "paw"))
        XCTAssertFalse(outcome.userWon)
    }

    /// 两边皆空：不播种（呈现回落缺省、不假装选过）
    func testMigrationNeitherSideSeedsNothing() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: nil, aiItemID: nil, aiUpdatedAt: nil,
            user: .default, userSelectedAt: nil,
            userEverSelected: false
        )
        XCTAssertNil(outcome.selection)
        XCTAssertFalse(outcome.userWon)
    }

    /// 脏 id 收敛：仓里来的预置 id 不在目录内回落缺省款
    func testMigrationUnknownAIPresetResolvesToDefault() {
        let outcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: "no-such-preset", aiItemID: "av_x",
            aiUpdatedAt: Self.migT1,
            user: .preset(id: "atom"), userSelectedAt: Self.migT0,
            userEverSelected: true
        )
        XCTAssertEqual(
            outcome.selection,
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
