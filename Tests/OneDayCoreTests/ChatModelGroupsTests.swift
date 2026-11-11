import OneDayCore
import XCTest

/// 顶栏全量分组清单＋本会话选择解析（§153，模型重构
/// ·顶栏包 B1/B2/B4）。options 回执样本按 2026-11-11
/// 生产定型逐字复刻（键名与层级实证，数值示例化）。
final class ChatModelGroupsTests: XCTestCase {

    /// 生产定型回执：默认在 Ailey（is_current 行），
    /// 网关行（custom）含 gpt-5.6 等全目录，另有一行
    /// 注册表外内置服务商（deepseek）
    private func productionRoot() -> JSONValue {
        .object([
            "model": .string("gpt-5.6"),
            "provider": .string("custom:ailey"),
            "providers": .array([
                .object([
                    "slug": .string("custom"),
                    "is_current": .bool(false),
                    "models": .array([
                        .string("gpt-5.6"),
                        .string("deepseek-flash"),
                        .string("hermes-agent"),
                    ]),
                ]),
                .object([
                    "slug": .string("Ailey"),
                    "is_current": .bool(true),
                    "models": .array([
                        .string("gpt-5.6"),
                        .string("gpt-5.5"),
                    ]),
                ]),
                .object([
                    "slug": .string("deepseek"),
                    "is_current": .bool(false),
                    "models": .array([.string("deepseek-flash")]),
                ]),
            ]),
        ])
    }

    private func providers() -> [ProviderRegistry.Entry] {
        [
            ProviderRegistry.Entry(
                name: "Ailey",
                baseURL: "https://aikey.didichou.site/v1",
                keyEnv: "ONEDAY_PROVIDER_AILEY_KEY",
                models: ["gpt-5.6", "gpt-5.5", "ailey-only"]
            ),
            ProviderRegistry.Entry(
                name: "Gateway",
                baseURL: "http://172.18.0.1:3000/v1",
                keyEnv: "ONEDAY_PROVIDER_GATEWAY_KEY",
                models: ["reg-only-model"]
            ),
        ]
    }

    private func build(
        root: JSONValue? = nil, candidates: [String] = []
    ) -> [ChatModelGroup] {
        ChatModelGroups.build(
            optionsRoot: root ?? productionRoot(),
            providers: providers(),
            gatewayCandidates: candidates,
            defaultModel: "gpt-5.6",
            gatewayAliases: ["hermes-agent"]
        )
    }

    /// B1 本体：分组齐全——网关组在前、具名组随后、
    /// 注册表外行成组置后；Gateway 条目并网关组
    func testGroupsCoverAllProviders() {
        let groups = build()
        XCTAssertEqual(
            groups.map(\.title), ["默认服务商", "Ailey", "deepseek"]
        )
        let gateway = groups[0]
        // 回执 custom 行＋Gateway 注册表补项，别名剔除
        XCTAssertEqual(
            gateway.choices.map(\.model),
            ["gpt-5.6", "deepseek-flash", "reg-only-model"]
        )
        XCTAssertTrue(
            gateway.choices.allSatisfy { $0.providerField == "custom" }
        )
        let ailey = groups[1]
        XCTAssertEqual(
            ailey.choices.map(\.model),
            ["gpt-5.6", "gpt-5.5", "ailey-only"]
        )
        XCTAssertTrue(ailey.choices.allSatisfy {
            $0.providerField == "custom:ailey"
        })
        // 注册表外行：不带逐请求 provider（服务端自理）
        XCTAssertNil(groups[2].choices[0].providerField)
    }

    /// 默认标记只落在「默认模型×默认所在行」一处：
    /// 网关组同名 gpt-5.6 不许冒充默认（它的路不是
    /// 默认的路）
    func testDefaultMarkOnlyOnCurrentRow() {
        let groups = build()
        let marked = groups.flatMap { group in
            group.choices.filter(\.isDefault).map {
                "\(group.title)|\($0.model)"
            }
        }
        XCTAssertEqual(marked, ["Ailey|gpt-5.6"])
    }

    /// 回执缺席时回落：网关组用扁平候选、具名组仍在
    func testFallbackWithoutOptionsRoot() {
        // 回执缺席：注册表 Gateway 条目清单仍是网关组
        // 真源（与回执同级、同源同批取数），扁平候选
        // 只在两源皆缺时兜底
        let groups = ChatModelGroups.build(
            optionsRoot: nil,
            providers: providers(),
            gatewayCandidates: ["deepseek-flash", "deepseek-v4-pro"],
            defaultModel: nil,
            gatewayAliases: ["hermes-agent"]
        )
        XCTAssertEqual(groups.map(\.title), ["默认服务商", "Ailey"])
        XCTAssertEqual(groups[0].choices.map(\.model), ["reg-only-model"])

        // 两源皆缺：网关组回落扁平候选清单
        let bare = ChatModelGroups.build(
            optionsRoot: nil,
            providers: [ProviderRegistry.Entry(
                name: "Ailey",
                baseURL: "https://aikey.didichou.site/v1",
                keyEnv: "ONEDAY_PROVIDER_AILEY_KEY",
                models: ["gpt-5.6"]
            )],
            gatewayCandidates: ["deepseek-flash", "deepseek-v4-pro"],
            defaultModel: nil,
            gatewayAliases: ["hermes-agent"]
        )
        XCTAssertEqual(
            bare[0].choices.map(\.model),
            ["deepseek-flash", "deepseek-v4-pro"]
        )
    }

    /// 搜索：跨组按模型名过滤、组名命中整组保留
    func testSearchFilter() {
        let groups = build()
        let byModel = ChatModelGroups.filtered(groups, query: "5.5")
        XCTAssertEqual(byModel.map(\.title), ["Ailey"])
        XCTAssertEqual(byModel[0].choices.map(\.model), ["gpt-5.5"])
        let byGroup = ChatModelGroups.filtered(groups, query: "ailey")
        XCTAssertEqual(byGroup.count, 1)
        XCTAssertEqual(byGroup[0].choices.count, 3)
        XCTAssertEqual(
            ChatModelGroups.filtered(groups, query: "  ").count, 3
        )
    }

    /// B2 解析：会话自选（须仍在清单）＞服务端默认
    /// 播种＞分组首项；自选已下线则回落播种
    func testSessionResolutionOrder() {
        let groups = build()
        let picked = groups[0].choices[1]  // 网关组 deepseek-flash
        XCTAssertEqual(
            SessionModelResolution.resolve(
                stored: picked, groups: groups, serverDefault: nil
            ),
            picked
        )
        let seeded = SessionModelResolution.serverDefaultChoice(
            in: groups, defaultModel: "gpt-5.6"
        )
        XCTAssertEqual(seeded?.model, "gpt-5.6")
        XCTAssertEqual(seeded?.providerField, "custom:ailey")
        XCTAssertEqual(
            SessionModelResolution.resolve(
                stored: nil, groups: groups, serverDefault: seeded
            ),
            seeded
        )
        let stale = ChatModelChoice(
            model: "gone-model", providerField: "custom"
        )
        XCTAssertEqual(
            SessionModelResolution.resolve(
                stored: stale, groups: groups, serverDefault: seeded
            ),
            seeded
        )
        XCTAssertEqual(
            SessionModelResolution.resolve(
                stored: nil, groups: groups, serverDefault: nil
            ),
            groups[0].choices[0]
        )
    }

    /// B4 别名收一：别名归一到规范名、触发器短名走
    /// 单源——「Flash」与「deepseek-flash」同物同名
    func testAliasCanonicalization() {
        XCTAssertEqual(
            ModelDisplayNames.canonicalID(for: "deepseek-chat"),
            "deepseek-flash"
        )
        XCTAssertEqual(
            ModelDisplayNames.canonicalID(for: "gpt-5.6"), "gpt-5.6"
        )
        XCTAssertEqual(
            ModelDisplayNames.triggerLabel(for: "deepseek-chat"),
            "Flash"
        )
        XCTAssertEqual(
            ModelDisplayNames.triggerLabel(for: "deepseek-flash"),
            "Flash"
        )
        XCTAssertEqual(
            ModelDisplayNames.triggerLabel(for: "deepseek-v4-pro"),
            "V4 Pro"
        )
        // 清单外模型：无短名口径、回落模型名原文
        XCTAssertEqual(
            ModelDisplayNames.triggerLabel(for: "gpt-5.6"), "gpt-5.6"
        )
    }

    /// 选择的来源标注：网关/直连/不标注三分（与设置
    /// 页 AnnotatedModel 口径同源）
    func testChoiceSourceLabels() {
        let groups = build()
        XCTAssertEqual(groups[0].choices[0].sourceLabel, "经网关")
        XCTAssertEqual(groups[1].choices[0].sourceLabel, "直连 · ailey")
        XCTAssertNil(groups[2].choices[0].sourceLabel)
    }
}
