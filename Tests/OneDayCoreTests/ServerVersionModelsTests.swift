import OneDayCore
import XCTest

/// 台账 36「版本与更新」只读感知面契约（DESIGN §360）：
/// update/check 的 managed 分支与一般形态、receipt
/// 在位样本、ServerStatus 版本扩键、呈现合成口径。
/// 样本按探活报告 blueprint-phase1-recon-20261122
/// §4.1 的源码定形与 2026-11-22 生产实测（/api/status
/// can_update_hermes=false、config 52/52）构造；联调
/// 时以会话实测替换（§360 未验项）。
final class ServerVersionModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decodeStatus(_ json: String) throws -> ServerStatus {
        try decoder.decode(ServerStatus.self, from: Data(json.utf8))
    }

    private func decodeCheck(_ json: String) throws -> UpdateCheckResponse {
        try decoder.decode(UpdateCheckResponse.self, from: Data(json.utf8))
    }

    // MARK: - update/check 解码

    /// 本部署恒走的 managed 分支（§4.1 字面形态）
    func testUpdateCheckManagedBranchDecodes() throws {
        let json = """
        {"install_method": "managed-runtime", "current_version": "0.23.0",
         "behind": null, "update_available": false, "can_apply": false,
         "update_command": "",
         "message": "Hermes updates are managed outside this dashboard in containerized environments."}
        """
        let check = try decodeCheck(json)
        XCTAssertEqual(check.installMethod, "managed-runtime")
        XCTAssertEqual(check.currentVersion, "0.23.0")
        XCTAssertNil(check.behind)
        XCTAssertEqual(check.updateAvailable, false)
        XCTAssertEqual(check.canApply, false)
        XCTAssertEqual(check.updateCommand, "")
        XCTAssertTrue(check.isManagedRuntime)
    }

    /// 一般形态（非托管部署）：behind/可应用等键齐全
    func testUpdateCheckGeneralBranchDecodes() throws {
        let json = """
        {"install_method": "git", "current_version": "0.22.0",
         "behind": 3, "update_available": true, "can_apply": true,
         "update_command": "hermes update", "message": "3 commits behind"}
        """
        let check = try decodeCheck(json)
        XCTAssertEqual(check.behind, 3)
        XCTAssertEqual(check.updateAvailable, true)
        XCTAssertEqual(check.canApply, true)
        XCTAssertFalse(check.isManagedRuntime)
    }

    /// 字段全缺不许打死解码（服务端小版本增减口径）
    func testUpdateCheckEmptyObjectTolerated() throws {
        let check = try decodeCheck("{}")
        XCTAssertNil(check.installMethod)
        XCTAssertNil(check.currentVersion)
        XCTAssertFalse(check.isManagedRuntime)
    }

    // MARK: - ServerStatus 版本扩键

    func testStatusVersionKeysDecode() throws {
        let json = """
        {"version": "0.23.0", "release_date": "2026.9.24",
         "config_version": 52, "latest_config_version": 52,
         "can_update_hermes": false,
         "gateway_running": true, "gateway_state": "running",
         "gateway_platforms": {}}
        """
        let status = try decodeStatus(json)
        XCTAssertEqual(status.configVersion, 52)
        XCTAssertEqual(status.latestConfigVersion, 52)
        XCTAssertEqual(status.canUpdateHermes, false)
    }

    func testStatusVersionKeysAbsentTolerated() throws {
        let status = try decodeStatus(#"{"version": "0.23.0"}"#)
        XCTAssertNil(status.latestConfigVersion)
        XCTAssertNil(status.canUpdateHermes)
    }

    // MARK: - receipt 解码

    func testReceiptPresentDecodes() throws {
        let json = """
        {"receipt": {"outcome": "success", "steps": [], "skips": []},
         "summary": "Updated to 0.24.0"}
        """
        let response = try decoder.decode(
            UpdateReceiptResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.summary, "Updated to 0.24.0")
        XCTAssertEqual(response.receipt?.outcome, "success")
        XCTAssertEqual(response.displayText, "Updated to 0.24.0")
    }

    /// 摘要缺席时回落结果键；再缺只报「有更新记录」
    func testReceiptDisplayTextFallbacks() throws {
        let outcomeOnly = try decoder.decode(
            UpdateReceiptResponse.self,
            from: Data(#"{"receipt": {"outcome": "failed"}}"#.utf8)
        )
        XCTAssertEqual(outcomeOnly.displayText, "failed")
        let bare = try decoder.decode(
            UpdateReceiptResponse.self,
            from: Data(#"{"receipt": {}}"#.utf8)
        )
        XCTAssertEqual(bare.displayText, "有更新记录")
    }

    // MARK: - 呈现合成（ServerVersionBuilder）

    /// 生产实测形态：版本/日期/配置 52∶52＋托管说明
    func testBuilderProductionShape() throws {
        let status = try decodeStatus("""
        {"version": "0.23.0", "release_date": "2026.9.24",
         "config_version": 52, "latest_config_version": 52,
         "can_update_hermes": false, "gateway_platforms": {}}
        """)
        let facts = ServerVersionBuilder.facts(status: status, check: nil)
        XCTAssertEqual(facts.versionText, "0.23.0")
        XCTAssertEqual(facts.releaseDateText, "2026.9.24")
        XCTAssertEqual(facts.configVersionText, "52 / 52")
        XCTAssertEqual(facts.managedNote, ServerVersionBuilder.managedNoteText)
    }

    /// 配置版本落后：对照原样呈现两数，不加工结论
    func testBuilderConfigBehindShowsPair() throws {
        let status = try decodeStatus("""
        {"config_version": 52, "latest_config_version": 55,
         "can_update_hermes": false, "gateway_platforms": {}}
        """)
        let facts = ServerVersionBuilder.facts(status: status, check: nil)
        XCTAssertEqual(facts.configVersionText, "52 / 55")
    }

    /// 配置对照缺一半：整行「未记录」，不拿单边冒充对照
    func testBuilderConfigHalfMissingShowsMissing() throws {
        let status = try decodeStatus("""
        {"config_version": 52, "gateway_platforms": {}}
        """)
        let facts = ServerVersionBuilder.facts(status: status, check: nil)
        XCTAssertEqual(facts.configVersionText, ServerVersionBuilder.missingText)
    }

    /// 状态面缺席：版本以检查面 current_version 回落，
    /// 托管以 install_method 旁证坐实
    func testBuilderFallsBackToCheck() throws {
        let check = try decodeCheck("""
        {"install_method": "managed-runtime", "current_version": "0.23.0",
         "behind": null, "update_available": false, "can_apply": false,
         "update_command": ""}
        """)
        let facts = ServerVersionBuilder.facts(status: nil, check: check)
        XCTAssertEqual(facts.versionText, "0.23.0")
        XCTAssertEqual(facts.releaseDateText, ServerVersionBuilder.missingText)
        XCTAssertEqual(facts.managedNote, ServerVersionBuilder.managedNoteText)
    }

    /// 两路皆空：三行全「未记录」、无托管说明（不编造）
    func testBuilderAllMissing() {
        let facts = ServerVersionBuilder.facts(status: nil, check: nil)
        XCTAssertEqual(facts.versionText, ServerVersionBuilder.missingText)
        XCTAssertEqual(facts.releaseDateText, ServerVersionBuilder.missingText)
        XCTAssertEqual(facts.configVersionText, ServerVersionBuilder.missingText)
        XCTAssertNil(facts.managedNote)
    }

    /// 非托管部署：说明只转述服务端原话；无原话则不出
    func testBuilderNonManagedUsesServerMessage() throws {
        let status = try decodeStatus("""
        {"can_update_hermes": true, "gateway_platforms": {}}
        """)
        let check = try decodeCheck("""
        {"install_method": "git", "current_version": "0.23.0",
         "message": "3 commits behind"}
        """)
        let facts = ServerVersionBuilder.facts(status: status, check: check)
        XCTAssertEqual(facts.managedNote, "3 commits behind")
        let silent = ServerVersionBuilder.facts(status: status, check: nil)
        XCTAssertNil(silent.managedNote)
    }
}
