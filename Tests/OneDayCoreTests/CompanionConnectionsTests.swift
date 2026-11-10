import XCTest
@testable import OneDayCore

/// 伴生连接与网关渠道（0.37.0 模型包）：连接记录解码
/// （front 实形）、状态词表派生、凭据载荷字段对齐、
/// 配置串拆分、验活状态机转移、渠道状态人话与空态口径。
final class CompanionConnectionsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - 连接记录解码（2026-11-11 生产实形）

    func testConnectionDecodesFrontShape() throws {
        let conn = try decode(CompanionConnection.self, """
        {
          "id": "box", "kind": "cloud_computer",
          "provider": "simular_box", "name": "Simular Box",
          "configured": true,
          "lastVerify": {"at": "2026-11-11T01:02:03+08:00", "ok": true,
                         "detail": "云电脑已连上"},
          "effective": "已生效", "note": ""
        }
        """)
        XCTAssertTrue(conn.isCloudComputer)
        XCTAssertEqual(conn.configured, true)
        XCTAssertEqual(conn.lastVerify?.ok, true)
        XCTAssertEqual(conn.providerWording, "托管云电脑")
    }

    func testConnectionDecodesNulls() throws {
        let conn = try decode(CompanionConnection.self, """
        {
          "id": "hermes-mcp", "kind": "mcp_registration",
          "provider": "hermes_mcp", "name": "Hermes 侧连接登记",
          "configured": null, "lastVerify": null,
          "effective": "", "note": ""
        }
        """)
        XCTAssertNil(conn.configured)
        XCTAssertNil(conn.lastVerify)
    }

    // MARK: - 状态词表

    private func conn(
        configured: Bool? = nil, effective: String? = nil,
        verify: CompanionConnection.VerifyRecord? = nil
    ) -> CompanionConnection {
        CompanionConnection(
            id: "x", kind: "cloud_computer", provider: "vps_agent",
            name: "测试机", configured: configured,
            lastVerify: verify, effective: effective, note: nil
        )
    }

    func testStatusWordingEffectiveWins() {
        let pending = ConnectionStatusWording.evaluate(
            conn(configured: true, effective: "已配置 · 待生效")
        )
        XCTAssertEqual(pending.text, "已配置 · 待生效")
        XCTAssertEqual(pending.tone, .pending)
        let live = ConnectionStatusWording.evaluate(
            conn(configured: true, effective: "已生效")
        )
        XCTAssertEqual(live.tone, .ok)
    }

    func testStatusWordingDerived() {
        XCTAssertEqual(
            ConnectionStatusWording.evaluate(conn(configured: true)).text,
            "已连接"
        )
        XCTAssertEqual(
            ConnectionStatusWording.evaluate(conn(configured: false)).text,
            "未配置"
        )
        let failed = ConnectionStatusWording.evaluate(conn(
            configured: false,
            verify: .init(at: "t", ok: false, detail: "对方返回 401")
        ))
        XCTAssertEqual(failed.tone, .bad)
        let dropped = ConnectionStatusWording.evaluate(conn(
            configured: false,
            verify: .init(at: "t", ok: false, detail: "已断开")
        ))
        XCTAssertEqual(dropped.text, "已断开")
        XCTAssertEqual(
            ConnectionStatusWording.evaluate(conn()).text, "状态未知"
        )
    }

    // MARK: - 载荷

    func testPayloadsMatchFrontContract() {
        XCTAssertEqual(
            ConnectionPayloads.create(provider: "vps_agent", name: "我的机"),
            [
                "kind": .string("cloud_computer"),
                "provider": .string("vps_agent"),
                "name": .string("我的机"),
            ]
        )
        XCTAssertEqual(
            ConnectionPayloads.simularCredential(apiKey: "k"),
            ["apiKey": .string("k")]
        )
        XCTAssertEqual(
            ConnectionPayloads.vpsCredential(endpointUrl: "https://x/mcp", token: "t"),
            ["endpointUrl": .string("https://x/mcp"), "token": .string("t")]
        )
    }

    // MARK: - 配置串拆分

    func testParseConfigStringForms() {
        let json = ConnectionPayloads.parseConfigString(
            #"{"endpointUrl": "https://h:8811/mcp", "token": "abc"}"#
        )
        XCTAssertEqual(json?.endpointUrl, "https://h:8811/mcp")
        XCTAssertEqual(json?.token, "abc")
        let lines = ConnectionPayloads.parseConfigString(
            "https://h:8811/mcp\nabc123"
        )
        XCTAssertEqual(lines?.token, "abc123")
        let spaced = ConnectionPayloads.parseConfigString(
            "https://h:8811/mcp abc123"
        )
        XCTAssertEqual(spaced?.endpointUrl, "https://h:8811/mcp")
        XCTAssertNil(ConnectionPayloads.parseConfigString("就一个词"))
        XCTAssertNil(ConnectionPayloads.parseConfigString("ftp://x token"))
        XCTAssertNil(ConnectionPayloads.parseConfigString("   "))
    }

    func testEndpointPlausibility() {
        XCTAssertTrue(ConnectionPayloads.isPlausibleEndpoint("https://h/mcp"))
        XCTAssertTrue(ConnectionPayloads.isPlausibleEndpoint("http://10.0.0.2:8811"))
        XCTAssertFalse(ConnectionPayloads.isPlausibleEndpoint("h/mcp"))
    }

    // MARK: - 验活状态机

    func testCredentialFlowTransitions() {
        XCTAssertEqual(
            CredentialFlowPhase.next(from: .idle, submitted: true),
            .submitting
        )
        XCTAssertEqual(
            CredentialFlowPhase.next(
                from: .submitting, receipt: (ok: true, detail: "连上了")
            ),
            .verified(detail: "连上了")
        )
        XCTAssertEqual(
            CredentialFlowPhase.next(
                from: .submitting, receipt: (ok: false, detail: "没过，已撤回")
            ),
            .failed(detail: "没过，已撤回")
        )
        // 乱序回执不许带偏 idle
        XCTAssertEqual(
            CredentialFlowPhase.next(
                from: .idle, receipt: (ok: true, detail: "x")
            ),
            .idle
        )
        // 重复提交不叠态
        XCTAssertEqual(
            CredentialFlowPhase.next(from: .submitting, submitted: true),
            .submitting
        )
        // 终态可再提交
        XCTAssertEqual(
            CredentialFlowPhase.next(
                from: .failed(detail: "x"), submitted: true
            ),
            .submitting
        )
    }

    // MARK: - 网关渠道

    func testGatewayChannelWording() {
        func channel(status: String) -> GatewayChannel {
            GatewayChannel(
                id: "14", name: "DeepSeek 官方", status: status,
                models: ["deepseek-flash", "deepseek-v4-pro"],
                priority: 10, weight: nil, group: "default"
            )
        }
        XCTAssertEqual(channel(status: "enabled").statusWording, "使用中")
        XCTAssertEqual(channel(status: "disabled").statusWording, "已停用")
        XCTAssertEqual(
            channel(status: "auto_disabled").statusWording, "出错后自动停用"
        )
        XCTAssertEqual(channel(status: "???").statusWording, "状态未知")
        XCTAssertEqual(
            channel(status: "enabled").detailLine,
            "可用模型 2 个 · 优先级 10 · 分组 default"
        )
    }

    func testGatewayChannelsResponseDecodes() throws {
        let resp = try decode(GatewayChannelsResponse.self, """
        {"channels": [
          {"id": "14", "name": "DeepSeek 官方", "status": "enabled",
           "models": ["deepseek-flash"], "priority": 10,
           "weight": null, "group": "default"}
        ]}
        """)
        XCTAssertEqual(resp.channels.count, 1)
        XCTAssertEqual(resp.channels[0].name, "DeepSeek 官方")
    }

    func testGatewayFacePlaceholderTexts() {
        XCTAssertNotNil(GatewayChannelsFace.faceMissing.placeholderText)
        XCTAssertTrue(
            GatewayChannelsFace.faceMissing.placeholderText?
                .contains("还没开通") ?? false
        )
        XCTAssertNil(GatewayChannelsFace.ready([
            GatewayChannel(
                id: "1", name: "x", status: "enabled", models: [],
                priority: nil, weight: nil, group: nil
            ),
        ]).placeholderText)
        XCTAssertNotNil(GatewayChannelsFace.ready([]).placeholderText)
    }
}
