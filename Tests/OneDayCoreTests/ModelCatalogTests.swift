import OneDayCore
import XCTest

/// 0.2.4 模型目录根治的回归网（2026-11-09 服务器实测口径）：
/// 网关 /v1/models 只返回别名 hermes-agent，它不是上游模型，
/// 写进默认配置会被上游 400——候选必须硬排除、写入必须拦截。
final class ModelCatalogTests: XCTestCase {
    private let gatewayAliases: Set<String> = ["hermes-agent"]

    /// 硬排除（回落路径）：用量里混着网关别名也不能进候选
    func testGatewayAliasExcludedFromFallbackCandidates() {
        let result = ModelCatalog.candidates(
            options: [],
            usage: ["deepseek-chat", "hermes-agent", "deepseek-flash"],
            current: "deepseek-flash",
            gatewayAliases: gatewayAliases
        )
        XCTAssertFalse(result.contains("hermes-agent"))
        XCTAssertEqual(result.first, "deepseek-flash")
        XCTAssertTrue(result.contains("deepseek-chat"))
    }

    /// 硬排除（正规端点路径）：options 非空即优先，且其中的
    /// 别名同样被剔除；用量不再参与
    func testOptionsPreferredAndAliasExcluded() {
        let result = ModelCatalog.candidates(
            options: ["deepseek-flash", "hermes-agent", "deepseek-v4-pro"],
            usage: ["deepseek-chat"],
            current: "deepseek-flash",
            gatewayAliases: gatewayAliases
        )
        XCTAssertEqual(result, ["deepseek-flash", "deepseek-v4-pro"])
    }

    /// 当前值若本身是网关别名（历史误写），回落路径也不许
    /// 把它放回候选
    func testAliasCurrentValueNotReadmitted() {
        let result = ModelCatalog.candidates(
            options: [],
            usage: ["deepseek-flash"],
            current: "hermes-agent",
            gatewayAliases: gatewayAliases
        )
        XCTAssertEqual(result, ["deepseek-flash"])
    }

    /// 写入校验：候选外的值（网关别名、未知模型）一律拦截
    func testIllegalWriteBlocked() {
        let candidates = ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat"]
        XCTAssertFalse(ModelCatalog.isWritable("hermes-agent", candidates: candidates))
        XCTAssertFalse(ModelCatalog.isWritable("gpt-5", candidates: candidates))
        XCTAssertTrue(ModelCatalog.isWritable("deepseek-flash", candidates: candidates))
        XCTAssertTrue(ModelCatalog.isWritable("deepseek-chat", candidates: candidates))
    }

    /// 别名映射口径与实测一致：老名字按 deepseek-flash 运行
    func testAliasRuntimeMatchesProbe() {
        XCTAssertEqual(ModelCatalog.aliasRuntime["deepseek-chat"], "deepseek-flash")
        XCTAssertEqual(ModelCatalog.aliasRuntime["deepseek-reasoner"], "deepseek-flash")
        XCTAssertNil(ModelCatalog.aliasRuntime["deepseek-flash"])
    }

    /// options 回执宽容提取：对象形 id 与字符串形都认，
    /// 嵌套层级不限，保序去重
    func testExtractModelIDsFromOptionsPayload() throws {
        let json = """
        {"providers": [
          {"id": "deepseek", "models": [
            {"id": "deepseek-flash"}, {"id": "deepseek-v4-pro"}
          ]},
          {"id": "backup", "models": ["deepseek-chat", "deepseek-flash"]}
        ]}
        """
        let root = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(
            ModelCatalog.extractModelIDs(from: root),
            ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat"]
        )
    }

    /// 提取的空与异常形状：无 models 键返回空列表（触发回落）
    func testExtractModelIDsEmptyWhenNoModelsKey() throws {
        let root = try JSONDecoder().decode(
            JSONValue.self, from: Data(#"{"providers": []}"#.utf8)
        )
        XCTAssertEqual(ModelCatalog.extractModelIDs(from: root), [])
    }
}
