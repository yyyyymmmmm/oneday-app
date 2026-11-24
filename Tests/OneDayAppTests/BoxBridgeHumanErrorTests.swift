import XCTest
import OneDayCore
@testable import OneDayApp

/// 云电脑工具错误人话出口钉测（§344，中枢四欠账·
/// 失败给人话）：BoxBridgeClient.humanToolErrorText
/// 是 status/screenshot/act 三路 .failed 的单源出
/// 口——MCP 工具错误原文先过 §233 用户安全门，过
/// 门原样、不过门落通用句。旧版 act 路把厂商原文
/// （上限 400 字、英文技术串）直塞 .failed 上屏
/// （actNote），本组钉死收口后的口径
final class BoxBridgeHumanErrorTests: XCTestCase {

    private func makeResult(text: String?) throws -> MCPResult {
        let content: String
        if let text {
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            content = "[{\"type\": \"text\", \"text\": \"\(escaped)\"}]"
        } else {
            content = "[]"
        }
        let json = "{\"content\": \(content), \"isError\": true}"
        return try JSONDecoder().decode(
            MCPResult.self, from: Data(json.utf8)
        )
    }

    func testHumanVendorTextPassesThrough() throws {
        let result = try makeResult(text: "余额不足，请先充值后再试")
        XCTAssertEqual(
            BoxBridgeClient.humanToolErrorText(result),
            "余额不足，请先充值后再试"
        )
    }

    func testEnglishTechnicalTextFallsBackToGeneric() throws {
        let result = try makeResult(
            text: "Tool execution failed: HTTP 502 Bad Gateway"
        )
        XCTAssertEqual(
            BoxBridgeClient.humanToolErrorText(result),
            "云电脑那边出了点问题，请稍后再试。"
        )
    }

    func testOverlongTextFallsBackToGeneric() throws {
        let result = try makeResult(
            text: String(repeating: "错", count: 90)
        )
        XCTAssertEqual(
            BoxBridgeClient.humanToolErrorText(result),
            "云电脑那边出了点问题，请稍后再试。"
        )
    }

    func testEmptyContentFallsBackToGeneric() throws {
        // 无文本块时 mcpErrorText 的兜底是英文 "tool
        // error"——旧版会原样上屏，新门必须拦下落通
        // 用句（本条即该泄漏形态的钉测）
        let result = try makeResult(text: nil)
        XCTAssertEqual(
            BoxBridgeClient.humanToolErrorText(result),
            "云电脑那边出了点问题，请稍后再试。"
        )
    }
}
