import OneDayCore
import XCTest

/// 样本 JSON 均为 2026-11-08 服务端实测返回的节选（见 docs/API-SURFACE.md）。
final class ModelsDecodeTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testHealth() throws {
        let json = #"{"status": "ok", "platform": "hermes-agent", "version": "0.23.0"}"#
        let health = try decoder.decode(HealthResponse.self, from: Data(json.utf8))
        XCTAssertTrue(health.isOK)
        XCTAssertEqual(health.version, "0.23.0")
    }

    func testStatus() throws {
        let json = """
        {"version": "0.23.0", "release_date": "2026.9.24", "config_version": 52,
         "gateway_running": true, "gateway_state": "running",
         "gateway_platforms": {"api_server": {"state": "connected", "error_code": null,
         "error_message": null, "updated_at": "2026-11-08T12:39:11.167Z"}}}
        """
        let status = try decoder.decode(ServerStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.version, "0.23.0")
        XCTAssertEqual(status.gatewayRunning, true)
        XCTAssertEqual(status.platforms["api_server"]?.state, "connected")
    }

    func testStatusMissingFieldsTolerated() throws {
        let status = try decoder.decode(ServerStatus.self, from: Data("{}".utf8))
        XCTAssertNil(status.version)
        XCTAssertTrue(status.platforms.isEmpty)
    }

    func testConfigSummary() throws {
        let json = """
        {"model": "anthropic/claude-opus-4.6", "providers": {"openai-api": {"base_url": "x"}},
         "fallback_providers": [], "toolsets": ["hermes-cli"],
         "database": {"journal_mode": "wal"}}
        """
        let summary = try decoder.decode(ServerConfigSummary.self, from: Data(json.utf8))
        XCTAssertEqual(summary.model, "anthropic/claude-opus-4.6")
        XCTAssertEqual(summary.providerNames, ["openai-api"])
        XCTAssertEqual(summary.toolsets, ["hermes-cli"])
    }

    func testModels() throws {
        let json = #"{"object": "list", "data": [{"id": "hermes-agent", "object": "model"}]}"#
        let models = try decoder.decode(ModelsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(models.ids, ["hermes-agent"])
    }

    func testStreamChunk() throws {
        let json = #"{"choices": [{"delta": {"content": "在的"}, "finish_reason": null}]}"#
        let chunk = try decoder.decode(ChatStreamChunk.self, from: Data(json.utf8))
        XCTAssertEqual(chunk.deltaText, "在的")
    }
}
