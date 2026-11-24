import XCTest
@testable import OneDayApp
import OneDayCore

/// §383 包一结构钉测：改名写口迁直连的形态把
/// 守——①身份桥客户端的改名写口（setName 与其
/// 端点路径）在代码行零残留、App 侧无桥改名调
/// 用；②直连写链在场：AppState 的 writeAgent
/// NameDirect、Core 的校验/手术、OneDayBridge
/// Client 的留痕自报口
final class BridgeConvergenceStructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    /// 代码行视图：剔除整行注释（/// 与 //）——
    /// 历史 prose 提及旧写口不在禁列，禁的是代
    /// 码本体回潮
    private func codeLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(
                    in: .whitespaces
                )
                return !t.hasPrefix("///") && !t.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    func testIdentityBridgeHasNoNameWritePort() throws {
        let identity = try codeLines(source(
            "Sources/OneDayApp/IdentityBridgeClient.swift"
        ))
        XCTAssertFalse(
            identity.contains("setName"),
            "身份桥改名写口回潮"
        )
        XCTAssertFalse(
            identity.contains("/identity/name"),
            "身份桥改名端点回潮"
        )
        let appState = try codeLines(source(
            "Sources/OneDayApp/AppState.swift"
        ))
        XCTAssertFalse(
            appState.contains(".setName("),
            "App 侧仍有桥改名调用"
        )
    }

    func testDirectNameWritePathPresent() throws {
        let appState = try codeLines(source(
            "Sources/OneDayApp/AppState.swift"
        ))
        XCTAssertTrue(appState.contains("writeAgentNameDirect"))
        XCTAssertTrue(
            appState.contains("recordTrace"),
            "改名留痕自报未接"
        )
        let core = try codeLines(source(
            "Sources/OneDayCore/AgentIdentity.swift"
        ))
        XCTAssertTrue(core.contains("validatedNewName"))
        XCTAssertTrue(core.contains("applyingNewName"))
        let bridge = try codeLines(source(
            "Sources/OneDayApp/OneDayBridgeClient.swift"
        ))
        XCTAssertTrue(bridge.contains("func recordTrace"))
    }
}
