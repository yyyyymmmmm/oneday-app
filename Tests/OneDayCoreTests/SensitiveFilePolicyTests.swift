import Foundation
import XCTest
@testable import OneDayCore

/// 敏感文件边界（0.36.31，规格 §4.6）：凭据类文件在
/// 系统文件浏览器里禁预览/下载/删除。钉：受保护名
/// 单、.env 变体、凭据词元、私钥扩展；同时钉不误伤
/// ——含 key 子串的正常词（monkey/keyboard）不算敏感。
final class SensitiveFilePolicyTests: XCTestCase {

    func testProtectedNamesAreSensitive() {
        for name in [
            "auth.json", ".env", "config.yaml",
            "SOUL.md", "AGENTS.md", "MEMORY.md",
        ] {
            XCTAssertTrue(
                SensitiveFilePolicy.isSensitive(fileName: name),
                name
            )
        }
    }

    func testEnvVariantsAreSensitive() {
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: ".env.local")
        )
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: ".env.production")
        )
    }

    func testCredentialWordsAreSensitive() {
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: "api_key.txt")
        )
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: "mytoken.txt")
        )
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(
                fileName: "client-secret.json"
            )
        )
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: "credentials.md")
        )
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: "password.txt")
        )
    }

    func testKeyMaterialExtensionsAreSensitive() {
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: "server.pem")
        )
        XCTAssertTrue(
            SensitiveFilePolicy.isSensitive(fileName: "id.key")
        )
    }

    func testOrdinaryFilesAreNotSensitive() {
        for name in [
            "monkey.txt", "keyboard.md", "hockey.pdf",
            "报告.docx", "笔记.md", "photo.png", "data.csv",
        ] {
            XCTAssertFalse(
                SensitiveFilePolicy.isSensitive(fileName: name),
                name
            )
        }
    }

    func testProtectedNamesMatchDeliverablesDenyBaseline() {
        // 与交付物面既有 deny 名单同集（0.36.28 前的 8 名
        // 单）——合并维护后不许漂移丢名
        XCTAssertEqual(
            SensitiveFilePolicy.protectedNames,
            [
                "config.yaml", ".env", "auth.json",
                "SOUL.md", "AGENTS.md", "USER.md",
                "MEMORY.md", "IDENTITY.md",
            ]
        )
    }
}
