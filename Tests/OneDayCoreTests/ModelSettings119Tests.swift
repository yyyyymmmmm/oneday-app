import XCTest
@testable import OneDayCore

/// 模型设置简化（§119）：辅助用途注册表（19 活槽/
/// 死槽排除/11＋8 分层/MoA 显隐）、分配读写换算、
/// 清单刷新差异、测连接三态、未配模型判定、预设
/// 快照往返。
final class ModelSettings119Tests: XCTestCase {

    private let zh = Locale(identifier: "zh-Hans")

    // MARK: - 注册表

    func testCatalogHas19LiveSlots() {
        XCTAssertEqual(AuxSlotCatalog.all.count, 19)
        XCTAssertEqual(
            Set(AuxSlotCatalog.all.map(\.key)).count, 19, "键不许重"
        )
    }

    func testCatalogExcludesDeadSlots() {
        for dead in ["web_extract", "session_search", "skills_hub"] {
            XCTAssertTrue(AuxSlotCatalog.isDead(dead))
            XCTAssertNil(AuxSlotCatalog.slot(forKey: dead))
            XCTAssertFalse(
                AuxSlotCatalog.all.contains { $0.key == dead }
            )
        }
    }

    func testCatalogLayerSplit() {
        XCTAssertEqual(AuxSlotCatalog.common.count, 11)
        XCTAssertEqual(AuxSlotCatalog.more.count, 8)
        // 拍板调和线：review 在折叠层、mcp 在常用层
        XCTAssertEqual(
            AuxSlotCatalog.slot(forKey: "review")?.layer, .more
        )
        XCTAssertEqual(
            AuxSlotCatalog.slot(forKey: "mcp")?.layer, .common
        )
        XCTAssertEqual(
            AuxSlotCatalog.title(forKey: "vision", locale: zh), "看图"
        )
    }

    func testCatalogEnabledSwitchSlots() {
        let withSwitch = AuxSlotCatalog.all
            .filter { $0.hasEnabledSwitch }.map(\.key)
        XCTAssertEqual(
            Set(withSwitch), ["title_generation", "background_review"]
        )
    }

    // MARK: - MoA 显隐

    func testMoAHiddenByDefault() {
        let sections = AuxSlotCatalog.sections(
            assignments: [:], activePresetUsesMoA: false
        )
        XCTAssertEqual(sections.common.count, 11)
        XCTAssertEqual(sections.more.count, 6)
        XCTAssertFalse(
            sections.more.contains { $0.key == "moa_reference" }
        )
    }

    func testMoAShownWhenAssigned() {
        let sections = AuxSlotCatalog.sections(
            assignments: [
                "moa_aggregator": .use(.mainEndpoint, model: "deepseek-flash"),
            ],
            activePresetUsesMoA: false
        )
        XCTAssertEqual(sections.more.count, 8)
    }

    func testMoAShownWhenActivePresetUsesMoA() {
        let sections = AuxSlotCatalog.sections(
            assignments: [:], activePresetUsesMoA: true
        )
        XCTAssertEqual(sections.more.count, 8)
    }

    // MARK: - 分配换算与读写

    private func config(
        aux: [String: JSONValue]
    ) -> [String: JSONValue] {
        ["model": .string("deepseek-flash"), "auxiliary": .object(aux)]
    }

    func testAssignmentFollowWhenMissing() {
        XCTAssertEqual(
            AuxAssignments.assignment(
                in: config(aux: [:]), slot: "vision",
                namedProviders: []
            ),
            .follow
        )
    }

    func testAssignmentMainEndpointForms() {
        // 生产写形 custom 与旧写形 main 都归一为主端点
        for raw in ["custom", "main"] {
            let read = AuxAssignments.assignment(
                in: config(aux: [
                    "vision": .object([
                        "provider": .string(raw),
                        "model": .string("deepseek-flash"),
                    ]),
                ]),
                slot: "vision", namedProviders: []
            )
            XCTAssertEqual(
                read, .use(.mainEndpoint, model: "deepseek-flash")
            )
        }
        // 写形恒为 custom（与生产 vision 现行写形一致）
        XCTAssertEqual(
            AuxAssignment.use(.mainEndpoint, model: "m").slotChoice,
            SlotChoice(provider: "custom", model: "m")
        )
    }

    func testAssignmentAutoWithModelNormalizesToMain() {
        let read = AuxAssignments.assignment(
            in: config(aux: [
                "vision": .object([
                    "provider": .string("auto"),
                    "model": .string("deepseek-flash"),
                ]),
            ]),
            slot: "vision", namedProviders: []
        )
        XCTAssertEqual(read, .use(.mainEndpoint, model: "deepseek-flash"))
    }

    func testAssignmentNamedAndUnknownPreserved() {
        let named = AuxAssignments.assignment(
            in: config(aux: [
                "vision": .object([
                    "provider": .string("甲厂"),
                    "model": .string("m1"),
                ]),
            ]),
            slot: "vision", namedProviders: ["甲厂"]
        )
        XCTAssertEqual(named, .use(.named("甲厂"), model: "m1"))
        // 不在册的 provider 原样保真、不吞
        let unknown = AuxAssignments.assignment(
            in: config(aux: [
                "vision": .object([
                    "provider": .string("openrouter"),
                    "model": .string("m2"),
                ]),
            ]),
            slot: "vision", namedProviders: ["甲厂"]
        )
        XCTAssertEqual(unknown, .use(.other("openrouter"), model: "m2"))
        XCTAssertEqual(
            unknown.slotChoice,
            SlotChoice(provider: "openrouter", model: "m2")
        )
    }

    func testApplyPreservesSiblingKeysAndEnabled() {
        let base = config(aux: [
            "vision": .object([
                "provider": .string("auto"),
                "model": .string(""),
                "timeout": .number(120),
            ]),
        ])
        let out = AuxAssignments.applying(
            .use(.named("甲厂"), model: "m1"), enabled: nil,
            slot: "vision", to: base
        )
        guard case .object(let aux) = out["auxiliary"] ?? .null,
              case .object(let vision) = aux["vision"] ?? .null
        else { return XCTFail("形状不对") }
        XCTAssertEqual(vision["provider"]?.stringValue, "甲厂")
        XCTAssertEqual(vision["model"]?.stringValue, "m1")
        XCTAssertEqual(vision["timeout"], .number(120))

        let out2 = AuxAssignments.applying(
            .follow, enabled: false, slot: "title_generation",
            to: base
        )
        guard case .object(let aux2) = out2["auxiliary"] ?? .null,
              case .object(let title) = aux2["title_generation"] ?? .null
        else { return XCTFail("形状不对") }
        XCTAssertEqual(title["provider"]?.stringValue, "auto")
        XCTAssertEqual(title["enabled"]?.boolValue, false)
        XCTAssertTrue(
            AuxAssignments.enabled(in: base, slot: "title_generation"),
            "enabled 缺失按开"
        )
        XCTAssertFalse(AuxAssignments.enabled(in: out2, slot: "title_generation"))
    }

    func testAssignmentValueLabels() {
        XCTAssertEqual(
            AuxAssignment.follow.valueLabel(locale: zh), "跟随主模型"
        )
        XCTAssertEqual(
            AuxAssignment.use(.mainEndpoint, model: "deepseek-flash")
                .valueLabel(locale: zh),
            "默认服务商 · deepseek-flash"
        )
        XCTAssertEqual(
            AuxAssignment.use(.named("甲厂"), model: "")
                .valueLabel(locale: zh),
            "甲厂"
        )
    }

    // MARK: - 清单刷新差异

    func testModelListDiff() {
        let diff = ModelListDiff.between(
            old: ["a", "b", "c"], new: ["b", "d", "a"]
        )
        XCTAssertEqual(diff.removed, ["c"])
        XCTAssertEqual(diff.added, ["d"])
        XCTAssertFalse(diff.isUnchanged)
        XCTAssertTrue(
            ModelListDiff.between(old: ["a"], new: ["a"]).isUnchanged
        )
        let emptied = ModelListDiff.between(old: ["a"], new: [])
        XCTAssertEqual(emptied.removed, ["a"])
        XCTAssertEqual(emptied.added, [])
    }

    // MARK: - 测连接三态

    func testProbeOutcomeWording() {
        XCTAssertEqual(
            ProviderConnectionOutcome.connected(modelCount: 3)
                .headline(locale: zh),
            "连通，发现 3 个模型"
        )
        XCTAssertNil(
            ProviderConnectionOutcome.connected(modelCount: 3)
                .advice(locale: zh)
        )
        let noCatalog = ProviderConnectionOutcome.connectedNoCatalog
        XCTAssertEqual(
            noCatalog.headline(locale: zh), "接口通了，但没返回模型目录"
        )
        XCTAssertTrue(noCatalog.canSaveAnyway)
        let failed = ProviderConnectionOutcome.failed(message: "没连上")
        XCTAssertEqual(failed.headline(locale: zh), "没连上")
        XCTAssertTrue(failed.canSaveAnyway)
        XCTAssertFalse(
            ProviderConnectionOutcome.connected(modelCount: 1)
                .canSaveAnyway
        )
    }

    // MARK: - 未配模型判定（四例＋未知不报）

    func testNeedsSetup() {
        // (a) 无服务商＋无网关模型 → 引导
        XCTAssertTrue(ModelSetupGuidance.needsSetup(
            gatewayModels: [], providerModelTotal: 0
        ))
        // (b) 网关有模型 → 不引导（生产现行形态）
        XCTAssertFalse(ModelSetupGuidance.needsSetup(
            gatewayModels: ["deepseek-flash"], providerModelTotal: 0
        ))
        // (c) 服务商有模型 → 不引导
        XCTAssertFalse(ModelSetupGuidance.needsSetup(
            gatewayModels: [], providerModelTotal: 2
        ))
        // (d) 服务商在册但无模型＋无网关 → 引导
        XCTAssertTrue(ModelSetupGuidance.needsSetup(
            gatewayModels: [], providerModelTotal: 0
        ))
        // 配置还没读到 → 不误报
        XCTAssertFalse(ModelSetupGuidance.needsSetup(
            gatewayModels: [], providerModelTotal: nil
        ))
    }

    // MARK: - 预设快照往返

    func testPresetSnapshotRoundTrip() {
        let named = ["甲厂"]
        let source = config(aux: [
            "vision": .object([
                "provider": .string("custom"),
                "model": .string("deepseek-flash"),
                "timeout": .number(120),
            ]),
            "approval": .object([
                "provider": .string("甲厂"),
                "model": .string("cheap-1"),
            ]),
            "moa_reference": .object([
                "provider": .string("custom"),
                "model": .string("deepseek-v4-pro"),
            ]),
        ])
        let preset = PresetSnapshot.capture(
            config: source, namedProviders: named,
            id: "p1", name: "测试预设", updatedAt: 1
        )
        XCTAssertEqual(preset.mainModel, "deepseek-flash")
        XCTAssertEqual(preset.aux.count, 19, "整套快照含跟随项")
        XCTAssertTrue(PresetSnapshot.usesMoA(preset))

        // 启用到另一份配置上 → 逐用途读回应与源一致
        var other = config(aux: [
            "vision": .object([
                "provider": .string("auto"), "model": .string(""),
            ]),
        ])
        other["model"] = .string("something-else")
        let applied = ComboActivation.apply(preset, to: other)
        XCTAssertEqual(applied["model"]?.stringValue, "deepseek-flash")
        for slot in AuxSlotCatalog.all {
            XCTAssertEqual(
                AuxAssignments.assignment(
                    in: applied, slot: slot.key, namedProviders: named
                ),
                AuxAssignments.assignment(
                    in: source, slot: slot.key, namedProviders: named
                ),
                "用途 \(slot.key) 快照往返不一致"
            )
        }
    }

    func testPresetUsesMoAFalseWhenAllFollow() {
        let preset = PresetSnapshot.capture(
            config: config(aux: [:]), namedProviders: [],
            id: "p2", name: "空预设", updatedAt: 1
        )
        XCTAssertFalse(PresetSnapshot.usesMoA(preset))
        XCTAssertEqual(preset.specifiedAuxCount, 0)
    }

    // MARK: - 编辑校验（§119 扩）

    func testValidateEditDraft() {
        XCTAssertNil(ProviderRegistry.validateEditDraft(
            baseURL: "https://api.example.com/v1",
            apiKey: "", models: ["m"]
        ), "编辑态密钥留空＝不改，应放行")
        XCTAssertEqual(
            ProviderRegistry.validateEditDraft(
                baseURL: "ftp://x", apiKey: "", models: ["m"]
            ),
            .badBaseURL
        )
        XCTAssertEqual(
            ProviderRegistry.validateEditDraft(
                baseURL: "https://api.example.com/v1",
                apiKey: "", models: []
            ),
            .noModels
        )
        XCTAssertNil(ProviderRegistry.validateEditDraft(
            baseURL: "https://api.example.com/v1",
            apiKey: "", models: [], allowNoModels: true
        ), "「仍然保存」只绕过无模型一闸")
    }
}

/// §150 清单治理（B5）：折叠阈值、搜索过滤、展开全量
final class ModelListGovernanceTests: XCTestCase {

    private func models(_ count: Int) -> [String] {
        (1...count).map { "model-\($0)" }
    }

    func testUnderThresholdShowsAll() {
        let p = ModelListGovernance.presentation(
            models: models(40), query: "", expanded: false
        )
        XCTAssertEqual(p.shown.count, 40)
        XCTAssertEqual(p.hiddenCount, 0)
        XCTAssertFalse(p.isFiltering)
    }

    func testOverThresholdFoldsAtForty() {
        let p = ModelListGovernance.presentation(
            models: models(132), query: "", expanded: false
        )
        XCTAssertEqual(p.shown.count, 40)
        XCTAssertEqual(p.hiddenCount, 92)
        XCTAssertEqual(p.matchCount, 132)
    }

    func testExpandedShowsAll() {
        let p = ModelListGovernance.presentation(
            models: models(132), query: "", expanded: true
        )
        XCTAssertEqual(p.shown.count, 132)
        XCTAssertEqual(p.hiddenCount, 0)
    }

    func testSearchIgnoresFoldAndIsCaseInsensitive() {
        let p = ModelListGovernance.presentation(
            models: ["DeepSeek-Flash", "gpt-5", "deepseek-pro"],
            query: "DEEPSEEK", expanded: false
        )
        XCTAssertTrue(p.isFiltering)
        XCTAssertEqual(p.shown, ["DeepSeek-Flash", "deepseek-pro"])
        XCTAssertEqual(p.hiddenCount, 0)
    }

    func testSearchNoMatch() {
        let p = ModelListGovernance.presentation(
            models: models(10), query: "zzz", expanded: false
        )
        XCTAssertTrue(p.isFiltering)
        XCTAssertEqual(p.matchCount, 0)
        XCTAssertTrue(p.shown.isEmpty)
    }

    func testBlankQueryIsNotFiltering() {
        let p = ModelListGovernance.presentation(
            models: models(3), query: "   ", expanded: false
        )
        XCTAssertFalse(p.isFiltering)
        XCTAssertEqual(p.shown.count, 3)
    }
}
