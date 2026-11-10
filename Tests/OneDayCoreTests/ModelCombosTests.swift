import XCTest
@testable import OneDayCore

/// 模型组合（0.37.0 模型包·分配层）：激活拼装纯函数
/// （只改点名键、其余原样）、现行值读取、起始示例只收
/// 非默认槽位、文档编解码往返。
final class ModelCombosTests: XCTestCase {

    private func baseConfig() -> [String: JSONValue] {
        [
            "model": .string("deepseek-flash"),
            "auxiliary": .object([
                "vision": .object([
                    "provider": .string("main"),
                    "model": .string("deepseek-flash"),
                    "timeout": .number(30),
                ]),
                "title_generation": .object([
                    "provider": .string("auto"),
                    "model": .string(""),
                ]),
            ]),
            "delegation": .object([
                "provider": .string(""),
                "model": .string(""),
            ]),
            "fallback_providers": .array([]),
            "unknown_future_key": .object(["keep": .bool(true)]),
        ]
    }

    private func combo(
        mainModel: String? = nil,
        aux: [String: SlotChoice] = [:],
        delegation: SlotChoice? = nil,
        fallback: [SlotChoice] = [],
        includesFallback: Bool = false
    ) -> ModelCombo {
        ModelCombo(
            id: "c1", name: "测试组合", mainModel: mainModel,
            aux: aux, delegation: delegation, fallback: fallback,
            includesFallback: includesFallback, updatedAt: 100
        )
    }

    // MARK: - 激活拼装

    func testApplyMainModelOnly() {
        let out = ComboActivation.apply(
            combo(mainModel: "deepseek-v4-pro"), to: baseConfig()
        )
        XCTAssertEqual(out["model"]?.stringValue, "deepseek-v4-pro")
        XCTAssertEqual(out["auxiliary"], baseConfig()["auxiliary"])
        XCTAssertEqual(out["unknown_future_key"], baseConfig()["unknown_future_key"])
    }

    func testApplyNilMainModelLeavesConfigModel() {
        let out = ComboActivation.apply(combo(), to: baseConfig())
        XCTAssertEqual(out["model"]?.stringValue, "deepseek-flash")
    }

    func testApplyAuxPreservesSiblingKeys() {
        let out = ComboActivation.apply(
            combo(aux: ["vision": SlotChoice(provider: "main", model: "other")]),
            to: baseConfig()
        )
        guard case .object(let aux) = out["auxiliary"] ?? .null,
              case .object(let vision) = aux["vision"] ?? .null else {
            return XCTFail("auxiliary/vision 形状不对")
        }
        XCTAssertEqual(vision["model"]?.stringValue, "other")
        XCTAssertEqual(vision["timeout"], .number(30)) // 同槽位其余键保留
        // 没点名的槽位不动
        guard case .object(let title) = aux["title_generation"] ?? .null else {
            return XCTFail("title_generation 缺失")
        }
        XCTAssertEqual(title["provider"]?.stringValue, "auto")
    }

    func testApplyAuxCreatesMissingSlotObject() {
        var config = baseConfig()
        config["auxiliary"] = .object([:])
        let out = ComboActivation.apply(
            combo(aux: ["monitor": SlotChoice(provider: "main", model: "m")]),
            to: config
        )
        guard case .object(let aux) = out["auxiliary"] ?? .null,
              case .object(let monitor) = aux["monitor"] ?? .null else {
            return XCTFail("monitor 槽位没建出来")
        }
        XCTAssertEqual(monitor["model"]?.stringValue, "m")
    }

    func testApplyDelegation() {
        let out = ComboActivation.apply(
            combo(delegation: SlotChoice(provider: "main", model: "cheap")),
            to: baseConfig()
        )
        guard case .object(let delegation) = out["delegation"] ?? .null else {
            return XCTFail("delegation 缺失")
        }
        XCTAssertEqual(delegation["model"]?.stringValue, "cheap")
    }

    func testApplyFallbackOnlyWhenIncluded() {
        let chain = [SlotChoice(provider: "main", model: "deepseek-v4-pro")]
        let untouched = ComboActivation.apply(
            combo(fallback: chain, includesFallback: false), to: baseConfig()
        )
        XCTAssertEqual(untouched["fallback_providers"], .array([]))
        let applied = ComboActivation.apply(
            combo(fallback: chain, includesFallback: true), to: baseConfig()
        )
        XCTAssertEqual(applied["fallback_providers"], .array([
            .object([
                "provider": .string("main"),
                "model": .string("deepseek-v4-pro"),
            ]),
        ]))
        // 显式清空：includesFallback=true 且空链 → 写空表
        let cleared = ComboActivation.apply(
            combo(fallback: [], includesFallback: true), to: baseConfig()
        )
        XCTAssertEqual(cleared["fallback_providers"], .array([]))
    }

    // MARK: - 现行值读取

    func testCurrentValuesRead() {
        let config = baseConfig()
        XCTAssertEqual(
            ComboCurrentValues.auxChoice(in: config, slot: "vision"),
            SlotChoice(provider: "main", model: "deepseek-flash")
        )
        XCTAssertEqual(
            ComboCurrentValues.auxChoice(in: config, slot: "不存在"),
            .auto
        )
        XCTAssertNil(ComboCurrentValues.delegationChoice(in: config))
        XCTAssertEqual(ComboCurrentValues.fallbackChain(in: config), [])
    }

    // MARK: - 起始示例

    func testStarterCapturesOnlyNonDefaultSlots() {
        let starter = ComboStarter.fromCurrentConfig(
            baseConfig(), id: "s1", name: "当前配置", updatedAt: 5
        )
        XCTAssertEqual(starter.mainModel, "deepseek-flash")
        XCTAssertEqual(starter.aux, [
            "vision": SlotChoice(provider: "main", model: "deepseek-flash"),
        ]) // title_generation 是 auto，不收
        XCTAssertNil(starter.delegation)
        XCTAssertFalse(starter.includesFallback)
    }

    // MARK: - 文档往返与摘要

    func testDocumentCodableRoundTrip() throws {
        let doc = ModelComboDocument(
            combos: [combo(mainModel: "deepseek-flash")],
            activeComboID: "c1"
        )
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(ModelComboDocument.self, from: data)
        XCTAssertEqual(back, doc)
    }

    func testComboSummaryLine() {
        XCTAssertEqual(
            combo().summaryLine(locale: Locale(identifier: "zh-Hans")), "还没有设置任何槽位"
        )
        XCTAssertEqual(
            combo(
                mainModel: "deepseek-flash",
                aux: ["vision": .auto],
                fallback: [SlotChoice(provider: "main", model: "x")],
                includesFallback: true
            ).summaryLine(locale: Locale(identifier: "zh-Hans")),
            "主模型 deepseek-flash · 1 个辅助槽位 · 备用链 1 级"
        )
    }

    func testActivationNoticeMentionsScope() {
        let notice = ComboActivation.activationNotice(
            for: combo(mainModel: "deepseek-v4-pro", aux: ["vision": .auto])
        , locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(notice.contains("已有会话不受影响"))
        XCTAssertTrue(notice.contains("所有会话共用"))
        let empty = ComboActivation.activationNotice(for: combo(), locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(empty.contains("不会改动"))
    }

    func testSlotCatalogChoices() {
        XCTAssertEqual(
            AuxSlotCatalog.providerChoices(namedProviders: ["甲厂"]),
            ["auto", "main", "甲厂"]
        )
        XCTAssertEqual(AuxSlotCatalog.title(forKey: "vision", locale: Locale(identifier: "zh-Hans")), "看图")
        XCTAssertEqual(AuxSlotCatalog.title(forKey: "未知键", locale: Locale(identifier: "zh-Hans")), "未知键")
    }
}
