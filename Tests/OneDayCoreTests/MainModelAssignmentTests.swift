import OneDayCore
import XCTest

/// 全局默认归属回读解析（§141）：用例形状全部照
/// 2026-11-11 生产实测的 /api/model/options 回执——
/// 注册 Gateway 前（裸 custom 行 is_current）与注册
/// 后（Gateway 行 is_current、顶层仍 custom）两种
/// 真形态都在内，不拿想象形状喂。
final class MainModelAssignmentTests: XCTestCase {

    private func root(
        provider: String?, model: String?,
        rows: [(slug: String, current: Bool)]
    ) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        if let provider { fields["provider"] = .string(provider) }
        if let model { fields["model"] = .string(model) }
        fields["providers"] = .array(rows.map { row in
            .object([
                "slug": .string(row.slug),
                "is_current": .bool(row.current),
                "models": .array([]),
            ])
        })
        return .object(fields)
    }

    func testBareCustomRowCurrentIsGateway() {
        // 注册前生产形态：custom 行 is_current
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "custom", model: "deepseek-flash",
                rows: [("custom", true), ("Ailey", false)]
            ),
            providerNames: ["Ailey"]
        )
        XCTAssertEqual(parsed.owner, .gateway)
        XCTAssertEqual(parsed.model, "deepseek-flash")
    }

    func testGatewayRowCurrentIsGatewayNotNamed() {
        // 注册后生产形态：Gateway 行取代 custom 行
        // is_current——它在注册表里也不能判成具名卡
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "custom", model: "deepseek-flash",
                rows: [("Gateway", true), ("Ailey", false)]
            ),
            providerNames: ["Ailey", "Gateway"]
        )
        XCTAssertEqual(parsed.owner, .gateway)
        XCTAssertEqual(parsed.model, "deepseek-flash")
    }

    func testNamedRowCurrentIsNamed() {
        // 设 Ailey 为默认后：Ailey 行 is_current、
        // 顶层 provider 落盘为 custom:ailey
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "custom:ailey", model: "gpt-5.5",
                rows: [("Gateway", false), ("Ailey", true)]
            ),
            providerNames: ["Ailey", "Gateway"]
        )
        XCTAssertEqual(parsed.owner, .named("Ailey"))
        XCTAssertEqual(parsed.model, "gpt-5.5")
    }

    func testTopLevelFallbackWhenNoCurrentRow() {
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "custom:ailey", model: "gpt-5.5",
                rows: [("Gateway", false), ("Ailey", false)]
            ),
            providerNames: ["Ailey", "Gateway"]
        )
        XCTAssertEqual(parsed.owner, .named("Ailey"))
    }

    func testSlugNormalizationMatchesHermes() {
        // 注册键带空格/大写：slug 按服务端规则归一后命中
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "custom:my-provider", model: "m1",
                rows: []
            ),
            providerNames: ["My Provider"]
        )
        XCTAssertEqual(parsed.owner, .named("My Provider"))
        XCTAssertEqual(
            MainModelAssignment.slug(forProviderName: "My Provider"),
            "my-provider"
        )
    }

    func testUnknownBuiltinSlugIsOther() {
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "openrouter", model: "some/model",
                rows: [("openrouter", true)]
            ),
            providerNames: ["Ailey"]
        )
        XCTAssertEqual(parsed.owner, .other("openrouter"))
        XCTAssertEqual(parsed.model, "some/model")
    }

    func testUnregisteredCustomSlugIsOther() {
        // custom:<名> 但注册表读面里没有这家（读面
        // 竞态）：不冒充网关、也不冒充已知具名
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: "custom:ghost", model: "m1", rows: []
            ),
            providerNames: ["Ailey"]
        )
        XCTAssertEqual(parsed.owner, .other("ghost"))
    }

    func testGarbageRootIsUnknown() {
        let parsed = MainModelAssignment.parse(
            optionsRoot: .array([]), providerNames: ["Ailey"]
        )
        XCTAssertEqual(parsed.owner, .unknown)
        XCTAssertNil(parsed.model)
    }

    func testEmptySlugIsUnknownButModelKept() {
        let parsed = MainModelAssignment.parse(
            optionsRoot: root(
                provider: nil, model: "deepseek-flash", rows: []
            ),
            providerNames: []
        )
        XCTAssertEqual(parsed.owner, .unknown)
        XCTAssertEqual(parsed.model, "deepseek-flash")
    }

    func testGatewayIdentityPredicate() {
        XCTAssertTrue(MainModelAssignment.isGatewayIdentity("Gateway"))
        XCTAssertTrue(MainModelAssignment.isGatewayIdentity(" gateway "))
        XCTAssertFalse(MainModelAssignment.isGatewayIdentity("Ailey"))
    }
}
