import XCTest
@testable import OneDayCore

/// 提供商名册与来源标注（0.37.0 模型包·接入/清单层）：
/// 条目解码/拼装往返、env 引用名派生、表单校验五闸、
/// /models 解析三形态、来源标注（别名硬排除＋同名双路）。
final class ProviderRegistryTests: XCTestCase {

    // MARK: - 条目解码与拼装

    func testEntriesDecodeFromConfigProviders() {
        let value: JSONValue = .object([
            "甲厂": .object([
                "base_url": .string("https://api.a.com/v1"),
                "key_env": .string("ONEDAY_PROVIDER__KEY"),
                "models": .array([.string("m1"), .string("m2")]),
            ]),
            "乙厂": .object(["base_url": .string("https://api.b.com/v1")]),
            "坏条目": .string("not-an-object"),
        ])
        let entries = ProviderRegistry.entries(from: value)
        XCTAssertEqual(entries.map(\.name), ["乙厂", "甲厂"]) // 名序
        let a = entries.first { $0.name == "甲厂" }
        XCTAssertEqual(a?.baseURL, "https://api.a.com/v1")
        XCTAssertEqual(a?.keyEnv, "ONEDAY_PROVIDER__KEY")
        XCTAssertEqual(a?.models, ["m1", "m2"])
        let b = entries.first { $0.name == "乙厂" }
        XCTAssertEqual(b?.models, [])
        XCTAssertNil(b?.keyEnv)
    }

    func testEntriesEmptyForNonObject() {
        XCTAssertEqual(ProviderRegistry.entries(from: nil), [])
        XCTAssertEqual(ProviderRegistry.entries(from: .array([])), [])
    }

    func testConfigValueRoundTrip() {
        let entry = ProviderRegistry.Entry(
            name: "甲厂", baseURL: "https://api.a.com/v1",
            keyEnv: "ONEDAY_PROVIDER__KEY", models: ["m1"]
        )
        let decoded = ProviderRegistry.entries(
            from: .object(["甲厂": ProviderRegistry.configValue(for: entry)])
        )
        XCTAssertEqual(decoded, [entry])
    }

    func testConfigValueOmitsEmptyFields() {
        let entry = ProviderRegistry.Entry(
            name: "裸条目", baseURL: nil, keyEnv: nil, models: []
        )
        guard case .object(let fields) =
            ProviderRegistry.configValue(for: entry) else {
            return XCTFail("应为对象")
        }
        XCTAssertTrue(fields.isEmpty)
    }

    // MARK: - env 引用名

    func testEnvKeyDerivation() {
        XCTAssertEqual(
            ProviderRegistry.envKey(forProviderName: "DeepSeek 直连"),
            "ONEDAY_PROVIDER_DEEPSEEK_KEY"
        )
        XCTAssertEqual(
            ProviderRegistry.envKey(forProviderName: "my-provider 2"),
            "ONEDAY_PROVIDER_MY_PROVIDER_2_KEY"
        )
        XCTAssertEqual(
            ProviderRegistry.envKey(forProviderName: "甲厂"),
            "ONEDAY_PROVIDER_PROVIDER_KEY"
        )
    }

    func testValidateDraftEnvKeyCollision() {
        XCTAssertEqual(ProviderRegistry.validateDraft(
            name: "乙厂", baseURL: "https://api.x.com/v1", apiKey: "k",
            models: ["m"], existingNames: ["甲厂"],
            existingEnvKeys: ["ONEDAY_PROVIDER_PROVIDER_KEY"]
        ), .envKeyCollision)
    }

    // MARK: - 表单校验

    func testValidateDraftPasses() {
        XCTAssertNil(ProviderRegistry.validateDraft(
            name: "新厂", baseURL: "https://api.x.com/v1",
            apiKey: "sk-123", models: ["m1"], existingNames: ["旧厂"]
        ))
    }

    func testValidateDraftOrder() {
        XCTAssertEqual(ProviderRegistry.validateDraft(
            name: "  ", baseURL: "bad", apiKey: "", models: [],
            existingNames: []
        ), .emptyName)
        XCTAssertEqual(ProviderRegistry.validateDraft(
            name: "旧厂", baseURL: "bad", apiKey: "", models: [],
            existingNames: ["旧厂"]
        ), .duplicateName)
        XCTAssertEqual(ProviderRegistry.validateDraft(
            name: "新厂", baseURL: "api.x.com", apiKey: "k",
            models: ["m"], existingNames: []
        ), .badBaseURL)
        XCTAssertEqual(ProviderRegistry.validateDraft(
            name: "新厂", baseURL: "https://api.x.com/v1", apiKey: " ",
            models: ["m"], existingNames: []
        ), .emptyKey)
        XCTAssertEqual(ProviderRegistry.validateDraft(
            name: "新厂", baseURL: "https://api.x.com/v1", apiKey: "k",
            models: ["", " "], existingNames: []
        ), .noModels)
    }

    // MARK: - /models 解析

    func testParseModelListOpenAIShape() {
        let root: JSONValue = .object([
            "data": .array([
                .object(["id": .string("gpt-x")]),
                .object(["id": .string("gpt-y")]),
                .object(["id": .string("gpt-x")]),
                .object(["id": .string("")]),
            ]),
        ])
        XCTAssertEqual(
            ProviderRegistry.parseModelList(from: root), ["gpt-x", "gpt-y"]
        )
    }

    func testParseModelListModelsKeyAndBareArray() {
        let byKey: JSONValue = .object([
            "models": .array([.string("a"), .string("b")]),
        ])
        XCTAssertEqual(ProviderRegistry.parseModelList(from: byKey), ["a", "b"])
        let bare: JSONValue = .array([
            .object(["name": .string("n1")]), .string("n2"),
        ])
        XCTAssertEqual(ProviderRegistry.parseModelList(from: bare), ["n1", "n2"])
    }

    // MARK: - 来源标注

    func testAnnotateGatewayFirstThenDirect() {
        let providers = [
            ProviderRegistry.Entry(
                name: "甲厂", baseURL: nil, keyEnv: nil,
                models: ["m-direct", "deepseek-flash"]
            ),
        ]
        let annotated = ModelSourceAnnotation.annotate(
            gatewayCandidates: ["deepseek-flash", "deepseek-v4-pro"],
            providers: providers,
            gatewayAliases: ["hermes-agent"]
        )
        XCTAssertEqual(annotated.map(\.id), [
            "gw::deepseek-flash",
            "gw::deepseek-v4-pro",
            "direct::甲厂::m-direct",
            "direct::甲厂::deepseek-flash", // 同名双路并存（选路即选来源）
        ])
    }

    func testAnnotateExcludesGatewayAliasEverywhere() {
        let providers = [
            ProviderRegistry.Entry(
                name: "甲厂", baseURL: nil, keyEnv: nil,
                models: ["hermes-agent", "ok-model"]
            ),
        ]
        let annotated = ModelSourceAnnotation.annotate(
            gatewayCandidates: ["hermes-agent", "ok-model"],
            providers: providers,
            gatewayAliases: ["hermes-agent"]
        )
        XCTAssertEqual(annotated.map(\.model), ["ok-model", "ok-model"])
        XCTAssertFalse(annotated.contains { $0.model == "hermes-agent" })
    }

    func testAnnotateDedupesWithinSameSource() {
        let providers = [
            ProviderRegistry.Entry(
                name: "甲厂", baseURL: nil, keyEnv: nil, models: ["m", "m"]
            ),
        ]
        let annotated = ModelSourceAnnotation.annotate(
            gatewayCandidates: ["m", "m"], providers: providers,
            gatewayAliases: []
        )
        XCTAssertEqual(annotated.count, 2) // 网关一条＋直连一条
    }
}
