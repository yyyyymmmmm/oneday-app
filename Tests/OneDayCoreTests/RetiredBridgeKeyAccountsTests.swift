import XCTest
@testable import OneDayCore

/// 退役桥钥残项清单（0.33.1）：0.32.1 五分项钥退役后，
/// 启动清理只许删 bridge.key.* 这组本 App 自己写过的
/// 键——清单内容与挑选逻辑在此钉死，防误删登录凭据。
final class RetiredBridgeKeyAccountsTests: XCTestCase {

    func testCanonicalListIsExactlyTheFiveRetiredAccounts() {
        XCTAssertEqual(
            RetiredBridgeKeyAccounts.accounts,
            [
                "bridge.key.overview",
                "bridge.key.oneday",
                "bridge.key.writegate",
                "bridge.key.box",
                "bridge.key.device",
            ]
        )
    }

    func testAllAccountsCarryBridgeKeyPrefix() {
        for account in RetiredBridgeKeyAccounts.accounts {
            XCTAssertTrue(
                account.hasPrefix("bridge.key."),
                "\(account) 必须带 bridge.key. 前缀"
            )
        }
    }

    func testAccountsAreUnique() {
        XCTAssertEqual(
            Set(RetiredBridgeKeyAccounts.accounts).count,
            RetiredBridgeKeyAccounts.accounts.count
        )
    }

    func testPurgeReturnsAllFiveWhenAllPresent() {
        let existing = RetiredBridgeKeyAccounts.accounts + ["api.key"]
        XCTAssertEqual(
            RetiredBridgeKeyAccounts.accountsToPurge(
                existingAccounts: existing
            ),
            RetiredBridgeKeyAccounts.accounts
        )
    }

    func testPurgeNeverIncludesLiveCredentialAccounts() {
        // 登录凭据与旧共用钥即使存在也不许被启动清理带走
        let existing = [
            "api.key", "auth.username", "auth.password",
            "server.baseURL", "writegate.key", "bridge.key.box",
        ]
        XCTAssertEqual(
            RetiredBridgeKeyAccounts.accountsToPurge(
                existingAccounts: existing
            ),
            ["bridge.key.box"]
        )
    }

    func testPurgePreservesCanonicalOrderAndHandlesEmpty() {
        XCTAssertEqual(
            RetiredBridgeKeyAccounts.accountsToPurge(
                existingAccounts: []
            ),
            []
        )
        XCTAssertEqual(
            RetiredBridgeKeyAccounts.accountsToPurge(
                existingAccounts: [
                    "bridge.key.device", "bridge.key.overview",
                ]
            ),
            ["bridge.key.overview", "bridge.key.device"]
        )
    }
}
