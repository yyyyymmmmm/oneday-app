import OneDayCore
import XCTest

/// 盒终端契约测试（P9，0.15.0）：fixture 按
/// box-shell-contract-20261109.md 冻结形状落字。
/// 红线：成败以 exitCode 为第一口径（盖过 ok）、
/// 两信号皆缺不许猜成功、空输出给占位不许冒充
/// 执行过、命令规范化只去首尾空白一字不改。
final class BoxShellTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testShellResponseFullDecode() throws {
        let json = """
        {"ok": true, "output": "Linux box 6.8 x86_64\\n",
         "exitCode": 0, "truncated": false}
        """
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(response.outputText, "Linux box 6.8 x86_64\n")
        XCTAssertFalse(response.wasTruncated)
    }

    func testShellExitCodeOverridesOk() throws {
        // ok 写 true 但退出码非 0：以退出码为准判失败
        let json = """
        {"ok": true, "output": "ls: /nonexistent: No such file",
         "exitCode": 2}
        """
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.exitCode, 2)
    }

    func testShellFallbackToOkWhenNoExitCode() throws {
        let json = #"{"ok": false, "output": "boom"}"#
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.outputText, "boom")
    }

    func testShellNoSignalsIsNotSuccess() throws {
        // ok 与 exitCode 皆缺：不许猜成功
        let json = #"{"output": "something"}"#
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertFalse(response.succeeded)
    }

    func testShellEmptyOutputPlaceholder() throws {
        let json = #"{"ok": true, "output": "", "exitCode": 0}"#
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(response.outputText, "（无输出）")
    }

    func testShellMissingOutputDecodesAsEmpty() throws {
        let json = #"{"ok": true, "exitCode": 0}"#
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.outputText, "（无输出）")
    }

    func testShellTruncatedFlag() throws {
        let json = """
        {"ok": true, "output": "long...", "exitCode": 0,
         "truncated": true}
        """
        let response = try decoder.decode(
            BoxShellResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(response.wasTruncated)
    }

    func testShellRequestEncoding() throws {
        let data = try encoder.encode(
            BoxShellRequest(command: "uname -a")
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["command"] as? String, "uname -a")
        XCTAssertEqual(object.count, 1)
    }

    func testShellCommandNormalize() {
        XCTAssertEqual(
            BoxShellCommandText.normalize("  ls -la \n"), "ls -la"
        )
        // 命令本体一字不改：内部多空格原样保留
        XCTAssertEqual(
            BoxShellCommandText.normalize("echo a  b"), "echo a  b"
        )
        XCTAssertNil(BoxShellCommandText.normalize(""))
        XCTAssertNil(BoxShellCommandText.normalize("   \n "))
    }
}
