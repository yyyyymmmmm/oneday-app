import XCTest
@testable import OneDayCore

/// 服务端文案安全门（§232 件八）：过门才许上屏、
/// 不过门落通用人话＋原文进诊断留痕——本组钉住门
/// 的判定矩阵：人话放行、技术原文一律拦下
final class ServerErrorTextTests: XCTestCase {

    // MARK: - 放行（自家服务端人话）

    func testPlainChineseServerMessagePasses() {
        XCTAssertEqual(
            ServerErrorText.userSafe("连接失败，服务器繁忙，请稍后再试。"),
            "连接失败，服务器繁忙，请稍后再试。"
        )
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(
            ServerErrorText.userSafe("  标题已被占用  \n"),
            "标题已被占用"
        )
    }

    func testShortAsciiTokensInsideChinesePass() {
        // 状态码/短英文词混在中文人话里不拦（真实回执形态）
        XCTAssertEqual(
            ServerErrorText.userSafe("网络异常（code 500），请稍后再试"),
            "网络异常（code 500），请稍后再试"
        )
    }

    func testExactlyEightyCharactersPasses() {
        let text = String(repeating: "错", count: 80)
        XCTAssertEqual(ServerErrorText.userSafe(text), text)
    }

    // MARK: - 拦截（技术原文/异常形态）

    func testEnglishTechnicalMessageRejected() {
        XCTAssertNil(
            ServerErrorText.userSafe("Connection refused (errno 61)")
        )
    }

    func testStackTraceRejected() {
        XCTAssertNil(
            ServerErrorText.userSafe("Traceback: boom")
        )
    }

    func testURLRejected() {
        XCTAssertNil(
            ServerErrorText.userSafe("请求失败 https://example.com/x")
        )
    }

    func testJSONShapedRejected() {
        XCTAssertNil(
            ServerErrorText.userSafe("{\"error\":\"x\"}")
        )
    }

    func testLongAsciiTokenRejected() {
        // 中文外壳里夹超长纯 ASCII token（令牌/哈希形态）
        let text = "服务器返回 " + String(repeating: "a", count: 30) + " 请重试"
        XCTAssertNil(ServerErrorText.userSafe(text))
    }

    func testOverEightyCharactersRejected() {
        let text = String(repeating: "错", count: 81)
        XCTAssertNil(ServerErrorText.userSafe(text))
    }

    func testEmptyAndWhitespaceRejected() {
        XCTAssertNil(ServerErrorText.userSafe(""))
        XCTAssertNil(ServerErrorText.userSafe("   \n  "))
    }

    func testMultilineRejected() {
        XCTAssertNil(ServerErrorText.userSafe("第一行\n第二行错误"))
    }

    func testHexAddressRejected() {
        XCTAssertNil(
            ServerErrorText.userSafe("崩溃于 0x00007fff 处，请重试")
        )
    }

    func testIsUserSafeMirrorsUserSafe() {
        XCTAssertTrue(ServerErrorText.isUserSafe("标题已被占用"))
        XCTAssertFalse(ServerErrorText.isUserSafe("undefined is not an object"))
    }
}
