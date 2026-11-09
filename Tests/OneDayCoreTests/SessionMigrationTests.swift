import XCTest
@testable import OneDayCore

/// 存量迁移规划与折叠（0.18.0，立项档 A.3）：本地
/// 标题覆盖表与服务端归档键一次性回写服务端——规
/// 划顺序钉死、成功退役、失败留痕保留，两件都必须
/// 可复现，不许静默吞失败。
final class SessionMigrationTests: XCTestCase {
    func testPlanOrdersRenamesThenArchivesAndSkipsLocalKeys() {
        let plan = SessionMigration.plan(
            titleOverrides: ["sess-b": "名字乙", "sess-a": "名字甲"],
            archivedKeys: [
                "server:sess-d", "server:sess-c",
                "local:00000000-0000-0000-0000-000000000001",
            ]
        )
        XCTAssertEqual(
            plan,
            [
                SessionMigration.Item(
                    sessionID: "sess-a", kind: .rename(title: "名字甲")
                ),
                SessionMigration.Item(
                    sessionID: "sess-b", kind: .rename(title: "名字乙")
                ),
                SessionMigration.Item(sessionID: "sess-c", kind: .archive),
                SessionMigration.Item(sessionID: "sess-d", kind: .archive),
            ]
        )
    }

    func testPlanSkipsBlankOverrideTitles() {
        let plan = SessionMigration.plan(
            titleOverrides: ["sess-a": "   ", "sess-b": "有效名"],
            archivedKeys: []
        )
        XCTAssertEqual(
            plan,
            [SessionMigration.Item(
                sessionID: "sess-b", kind: .rename(title: "有效名")
            )]
        )
    }

    func testPlanEmptyWhenNothingToMigrate() {
        XCTAssertTrue(
            SessionMigration.plan(titleOverrides: [:], archivedKeys: []).isEmpty
        )
        XCTAssertTrue(
            SessionMigration.plan(
                titleOverrides: [:],
                archivedKeys: ["local:00000000-0000-0000-0000-000000000001"]
            ).isEmpty
        )
    }

    func testFoldRetiresSuccessesAndKeepsFailuresWithReasons() {
        let overrides = ["sess-a": "名字甲", "sess-b": "名字乙"]
        let keys: Set<String> = [
            "server:sess-c", "server:sess-d",
            "local:00000000-0000-0000-0000-000000000001",
        ]
        let plan = SessionMigration.plan(
            titleOverrides: overrides, archivedKeys: keys
        )
        let failedRename = SessionMigration.Item(
            sessionID: "sess-b", kind: .rename(title: "名字乙")
        )
        let outcome = SessionMigration.fold(
            plan: plan,
            failureReasons: [failedRename: "回读对账不一致"],
            titleOverrides: overrides,
            archivedKeys: keys
        )
        // sess-a 改名落定退役、sess-b 失败保留原值
        XCTAssertEqual(outcome.remainingTitleOverrides, ["sess-b": "名字乙"])
        // 两个服务端归档键都落定退役，本地线程键不动
        XCTAssertEqual(
            outcome.remainingArchivedKeys,
            ["local:00000000-0000-0000-0000-000000000001"]
        )
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.item, failedRename)
        XCTAssertEqual(outcome.failures.first?.reason, "回读对账不一致")
    }

    func testFoldAllSuccessClearsServerState() {
        let overrides = ["sess-a": "名字甲"]
        let keys: Set<String> = ["server:sess-c"]
        let plan = SessionMigration.plan(
            titleOverrides: overrides, archivedKeys: keys
        )
        let outcome = SessionMigration.fold(
            plan: plan, failureReasons: [:],
            titleOverrides: overrides, archivedKeys: keys
        )
        XCTAssertTrue(outcome.remainingTitleOverrides.isEmpty)
        XCTAssertTrue(outcome.remainingArchivedKeys.isEmpty)
        XCTAssertTrue(outcome.failures.isEmpty)
    }
}
