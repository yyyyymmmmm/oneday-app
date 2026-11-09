import XCTest
@testable import OneDayCore

/// P10 管理面模型测试（0.16.0）：MCP 与会话搜索的
/// fixture 是 2026-11-09 主代理只读联调的生产实样
/// （服务器内存 49% 时取样、逐字收录）；技能商店因本
/// 部署端点超时无实样，fixture 按 identifier 官方语
/// 义构造、专钉多形宽容解码不回归。
final class ManagementModelsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - MCP（生产实样）

    func testMCPServerListProductionFixture() throws {
        let json = """
        {"servers":[{"name":"box","transport":"http","url":"https://mcp.box.simular.ai/mcp","command":null,"args":[],"env":{},"auth":"header","enabled":true,"tools":null,"source":"plugin","plugin":"box"}]}
        """
        let response = try decode(MCPServersResponse.self, json)
        XCTAssertEqual(response.servers.count, 1)
        let box = response.servers[0]
        XCTAssertEqual(box.name, "box")
        XCTAssertEqual(box.transport, "http")
        XCTAssertEqual(box.url, "https://mcp.box.simular.ai/mcp")
        XCTAssertNil(box.command)
        XCTAssertTrue(box.enabled)
        XCTAssertTrue(box.isPluginProvided)
        XCTAssertEqual(box.originLabel, "插件预置 · box")
        XCTAssertEqual(box.endpointLine, "https://mcp.box.simular.ai/mcp")
    }

    func testMCPServerManualConfigDefaults() throws {
        let json = """
        [{"name":"local-tools","transport":"stdio","command":"npx -y demo","enabled":false}]
        """
        let response = try decode(MCPServersResponse.self, json)
        let item = response.servers[0]
        XCTAssertFalse(item.isPluginProvided)
        XCTAssertEqual(item.originLabel, "手动配置")
        XCTAssertEqual(item.endpointLine, "npx -y demo")
        XCTAssertFalse(item.enabled)
    }

    func testMCPTestResultSignals() throws {
        let ok = try decode(MCPTestResult.self, #"{"ok":true,"message":"连接正常"}"#)
        XCTAssertTrue(ok.succeeded)
        XCTAssertEqual(ok.displayMessage, "连接正常")

        let status = try decode(MCPTestResult.self, #"{"status":"connected","tools":[1,2,3]}"#)
        XCTAssertTrue(status.succeeded)
        XCTAssertEqual(status.toolCount, 3)

        let failed = try decode(MCPTestResult.self, #"{"ok":false,"error":"连接超时"}"#)
        XCTAssertFalse(failed.succeeded)
        XCTAssertEqual(failed.displayMessage, "连接超时")

        // 无任何显式信号不判成功（与盒终端口径一致）
        let silent = try decode(MCPTestResult.self, #"{"detail":"done"}"#)
        XCTAssertFalse(silent.succeeded)
        XCTAssertNil(silent.displayMessage)
    }

    // MARK: - 会话搜索（生产实样）

    func testSessionSearchProductionFixture() throws {
        let json = """
        {"results":[{"snippet":"蓝鲸42","role":"assistant","source":"api_server","model":"deepseek-flash","session_started":1794189744.987208,"last_active":1794189754.778247,"session_id":"api-10bbb01cdf42b4a5","lineage_root":"api-10bbb01cdf42b4a5","profile":"default","is_default_profile":true,"id":"api-10bbb01cdf42b4a5","title":"记住暗号蓝鲸42","started_at":1794189744.987208,"ended_at":null,"is_active":false,"message_count":7,"tool_call_count":1,"input_tokens":500,"output_tokens":380,"preview":"[R1TEST-1109] 受控实测第一条。请记住暗号：蓝鲸42。只回复：已记住。","parent_session_id":null,"archived":false}]}
        """
        let response = try decode(SessionSearchResponse.self, json)
        XCTAssertEqual(response.results.count, 1)
        let hit = response.results[0]
        XCTAssertEqual(hit.sessionID, "api-10bbb01cdf42b4a5")
        XCTAssertEqual(hit.title, "记住暗号蓝鲸42")
        XCTAssertEqual(hit.snippet, "蓝鲸42")
        XCTAssertEqual(hit.roleLabel, "助手消息")
        XCTAssertEqual(hit.messageCount, 7)
        XCTAssertEqual(
            hit.startedDate,
            Date(timeIntervalSince1970: 1794189744.987208)
        )
        XCTAssertEqual(hit.displayTitle, "记住暗号蓝鲸42")
    }

    func testSessionSearchHitFallbacks() throws {
        let hit = SessionSearchHit(
            sessionID: "s1", preview: "只有预览的会话"
        )
        XCTAssertEqual(hit.displayTitle, "只有预览的会话")
        let bare = SessionSearchHit(sessionID: "s2")
        XCTAssertEqual(bare.displayTitle, "未命名会话")
        XCTAssertNil(bare.roleLabel)
    }

    // MARK: - 技能商店（多形宽容）

    func testHubSearchResultsKeyForm() throws {
        let json = """
        {"results":[
          {"identifier":"official/security/1password","name":"1Password","description":"保险库集成","source":"official","version":"1.2.0"},
          {"identifier":"skills-sh/vercel-labs/agent-skills/vercel-react-best-practices","description":"React 最佳实践","source":"skills-sh"}
        ]}
        """
        let response = try decode(HubSearchResponse.self, json)
        XCTAssertEqual(response.results.count, 2)
        let first = response.results[0]
        XCTAssertEqual(first.displayName, "1Password")
        XCTAssertEqual(first.installedName, "1password")
        XCTAssertEqual(first.sourceLabel, "official")
        let second = response.results[1]
        XCTAssertEqual(second.displayName, "vercel-react-best-practices")
        XCTAssertEqual(second.installedName, "vercel-react-best-practices")
        XCTAssertTrue(second.isInstalled(installedNames: ["vercel-react-best-practices"]))
        XCTAssertFalse(second.isInstalled(installedNames: ["other"]))
    }

    func testHubSearchBareArrayAndSkillsKeyForms() throws {
        let bare = try decode(
            HubSearchResponse.self,
            #"[{"identifier":"official/media/pdf-tools"}]"#
        )
        XCTAssertEqual(bare.results.count, 1)
        XCTAssertEqual(bare.results[0].installedName, "pdf-tools")

        let skillsKey = try decode(
            HubSearchResponse.self,
            #"{"skills":[{"id":"clawhub/demo/skill-x","name":"Skill X"}]}"#
        )
        XCTAssertEqual(skillsKey.results.count, 1)
        XCTAssertEqual(skillsKey.results[0].identifier, "clawhub/demo/skill-x")
        XCTAssertEqual(skillsKey.results[0].sourceLabel, "clawhub")
    }

    func testHubSourcesForms() throws {
        let keyed = try decode(
            HubSourcesResponse.self,
            #"{"sources":[{"name":"official","label":"官方","skill_count":59},{"name":"skills-sh"}]}"#
        )
        XCTAssertEqual(keyed.sources.count, 2)
        XCTAssertEqual(keyed.sources[0].displayLabel, "官方")
        XCTAssertEqual(keyed.sources[0].skillCount, 59)
        XCTAssertEqual(keyed.sources[1].displayLabel, "skills-sh")

        let bare = try decode(
            HubSourcesResponse.self,
            #"[{"id":"well-known","count":3}]"#
        )
        XCTAssertEqual(bare.sources[0].name, "well-known")
        XCTAssertEqual(bare.sources[0].skillCount, 3)
    }

    func testHubPreviewContentKeyVariants() throws {
        let content = try decode(
            HubPreview.self,
            ##"{"identifier":"official/a/b","content":"# 正文","files":["SKILL.md","refs/x.md"]}"##
        )
        XCTAssertTrue(content.hasContent)
        XCTAssertEqual(content.files, ["SKILL.md", "refs/x.md"])

        let skillMD = try decode(
            HubPreview.self,
            ##"{"skill_md":"# 另一键名","files":[{"path":"SKILL.md"},{"name":"extra.md"}]}"##
        )
        XCTAssertEqual(skillMD.content, "# 另一键名")
        XCTAssertEqual(skillMD.files, ["SKILL.md", "extra.md"])

        let empty = try decode(HubPreview.self, #"{"identifier":"official/a/c"}"#)
        XCTAssertFalse(empty.hasContent)
        XCTAssertEqual(empty.files, [])
    }

    // MARK: - 档案导出回执

    func testProfileExportReferenceVariants() throws {
        let path = try decode(
            ProfileExportResult.self, #"{"path":"/opt/data/exports/a.tar.gz"}"#
        )
        XCTAssertEqual(path.archiveReference, "/opt/data/exports/a.tar.gz")
        let output = try decode(
            ProfileExportResult.self, #"{"output":"/tmp/b.tar.gz"}"#
        )
        XCTAssertEqual(output.archiveReference, "/tmp/b.tar.gz")
        let silent = try decode(ProfileExportResult.self, #"{"ok":true}"#)
        XCTAssertNil(silent.archiveReference)
    }

    // MARK: - 审批已决派生

    func testDecisionRecordLabels() throws {
        let json = """
        {"decisions":[
          {"id":"d1","subsystem":"memory","action":"append","summary":"写入一条巡检结论","origin":"background_review","created_at":"2026-11-09T09:00:00+00:00","decided_at":"2026-11-09T09:05:00+00:00","decision":"approved"},
          {"id":"d2","subsystem":"skills","action":"edit","summary":"改技能口径","origin":"oneday_app","created_at":"2026-11-09T09:10:00+00:00","decided_at":"2026-11-09T09:12:00+00:00","decision":"rejected"}
        ]}
        """
        let response = try decode(WriteGateDecisionsResponse.self, json)
        XCTAssertEqual(response.decisions.count, 2)
        XCTAssertEqual(response.decisions[0].decisionLabel, "已批准")
        XCTAssertEqual(response.decisions[1].decisionLabel, "已驳回")
        XCTAssertNotNil(response.decisions[0].decidedAt)
        XCTAssertFalse(response.decisions[0].originText.isEmpty)
    }
}
