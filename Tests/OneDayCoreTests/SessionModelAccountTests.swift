import OneDayCore
import XCTest

/// 模型账合一（§227，诊断题三）：取键单派生（Session-
/// ModelAccount）与服务端报告值定性（SessionModel-
/// Truth）的纯口径验收。
final class SessionModelAccountTests: XCTestCase {

    private let threadID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111"
    )!
    private let otherThreadID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
    )!

    private func assertIDs(
        _ actual: (serverSessionID: String?, threadID: UUID?),
        _ expectedServer: String?, _ expectedThread: UUID?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.serverSessionID, expectedServer,
            "serverSessionID", file: file, line: line
        )
        XCTAssertEqual(
            actual.threadID, expectedThread,
            "threadID", file: file, line: line
        )
    }

    // MARK: - 派生矩阵（胶囊面通用派生）

    /// 线程已绑定 → 绑定为准，store 副本在场也不许抢
    func testBoundThreadWinsOverStoreCopy() {
        assertIDs(
            SessionModelAccount.accountIDs(
                threadServerSessionID: "oneday-main-adopted",
                threadID: threadID, isMainThread: true,
                mainServerSessionID: "oneday-main-stale"
            ),
            "oneday-main-adopted", threadID
        )
    }

    /// 主线线程未绑定 → 回落钦定 id 副本（派生缓存）
    func testUnboundMainThreadFallsBackToStoreCopy() {
        assertIDs(
            SessionModelAccount.accountIDs(
                threadServerSessionID: nil,
                threadID: threadID, isMainThread: true,
                mainServerSessionID: "oneday-main-designated"
            ),
            "oneday-main-designated", threadID
        )
    }

    /// 非主线线程未绑定 → 不回落（旁聊不许读主线账）
    func testUnboundSideThreadDoesNotFallBack() {
        assertIDs(
            SessionModelAccount.accountIDs(
                threadServerSessionID: nil,
                threadID: otherThreadID, isMainThread: false,
                mainServerSessionID: "oneday-main-designated"
            ),
            nil, otherThreadID
        )
    }

    /// 无线程（空态）→ 双 nil，落固定键口径不变
    func testNoThreadYieldsNilPair() {
        assertIDs(
            SessionModelAccount.accountIDs(
                threadServerSessionID: nil,
                threadID: nil, isMainThread: false,
                mainServerSessionID: "oneday-main-designated"
            ),
            nil, nil
        )
    }

    // MARK: - 同键定理（枢纽面 ≡ 胶囊面）

    /// 枢纽派生（mainlineAccountIDs）与胶囊在主线时的
    /// 派生（accountIDs, isMainThread=true）对一切绑
    /// 定/副本组合恒等——两面同键的结构性保证，不靠
    /// 两处代码「恰好写得一样」
    func testHubAndCapsuleDerivationsAlwaysAgree() {
        let bindings: [String?] = [nil, "oneday-main-adopted"]
        let copies: [String?] = [nil, "oneday-main-stale"]
        for binding in bindings {
            for copy in copies {
                let hub = SessionModelAccount.mainlineAccountIDs(
                    mainThreadServerSessionID: binding,
                    mainThreadID: threadID,
                    mainServerSessionID: copy
                )
                let capsule = SessionModelAccount.accountIDs(
                    threadServerSessionID: binding,
                    threadID: threadID, isMainThread: true,
                    mainServerSessionID: copy
                )
                XCTAssertEqual(hub.serverSessionID, capsule.serverSessionID)
                XCTAssertEqual(hub.threadID, capsule.threadID)
            }
        }
    }

    /// 钦定线程尚未落位 → 枢纽回落钦定 id 副本＋nil
    /// 线程（枢纽语境恒是主线，认钦定 id 那本账）
    func testHubWithoutMainThreadFallsBackToStoreCopy() {
        assertIDs(
            SessionModelAccount.mainlineAccountIDs(
                mainThreadServerSessionID: nil,
                mainThreadID: nil,
                mainServerSessionID: "oneday-main-designated"
            ),
            "oneday-main-designated", nil
        )
    }
}

/// 服务端会话行 model 字段的定性（§227 裁决）：报告
/// 值不进执行解析——化石场景下执行值恒由本地账解
/// 析链（存量＞默认＞首项）决定，报告至多产出只读
/// 的「不一致」标记。
final class SessionModelTruthTests: XCTestCase {

    private func groups() -> [ChatModelGroup] {
        [ChatModelGroup(title: "默认服务商", choices: [
            ChatModelChoice(
                model: "claude-sonnet-4-6", providerField: "custom"
            ),
            ChatModelChoice(
                model: "deepseek-flash", providerField: "custom"
            ),
        ])]
    }

    /// 收养主线实景：无存量选择、配置默认已切
    /// claude-sonnet-4-6、服务端会话行冻结在
    /// deepseek-flash——执行值必须是默认，化石只被
    /// 标记不一致，绝不进执行值
    func testFossilReportDoesNotEnterExecution() {
        let gs = groups()
        let serverDefault = gs[0].choices[0]
        let reading = SessionModelTruth.reading(
            stored: nil, groups: gs, serverDefault: serverDefault,
            serverReportedModel: "deepseek-flash"
        )
        XCTAssertEqual(reading.execution, serverDefault)
        XCTAssertTrue(reading.serverReportDisagrees)
    }

    /// 用户存量选择在场 → 存量优先，报告值不同也只标记
    func testStoredChoiceWinsAndReportOnlyMarks() {
        let gs = groups()
        let stored = gs[0].choices[1]  // 用户自选 deepseek-flash
        let reading = SessionModelTruth.reading(
            stored: stored, groups: gs,
            serverDefault: gs[0].choices[0],
            serverReportedModel: "claude-sonnet-4-6"
        )
        XCTAssertEqual(reading.execution, stored)
        XCTAssertTrue(reading.serverReportDisagrees)
    }

    /// 报告值与执行值一致 → 不标记（收口无事可记）
    func testAgreeingReportDoesNotMark() {
        let gs = groups()
        let reading = SessionModelTruth.reading(
            stored: nil, groups: gs, serverDefault: gs[0].choices[0],
            serverReportedModel: "claude-sonnet-4-6"
        )
        XCTAssertEqual(reading.execution, gs[0].choices[0])
        XCTAssertFalse(reading.serverReportDisagrees)
    }

    /// 无报告值（服务端字段缺失）→ 不标记、执行照旧
    func testMissingReportDoesNotMark() {
        let gs = groups()
        let reading = SessionModelTruth.reading(
            stored: nil, groups: gs, serverDefault: gs[0].choices[0],
            serverReportedModel: nil
        )
        XCTAssertEqual(reading.execution, gs[0].choices[0])
        XCTAssertFalse(reading.serverReportDisagrees)
    }

    /// 分组未就绪（离线/未刷新）→ 执行 nil 交既有回
    /// 落口径，报告不许在此时单独成「值」
    func testEmptyGroupsYieldsNilExecution() {
        let reading = SessionModelTruth.reading(
            stored: nil, groups: [], serverDefault: nil,
            serverReportedModel: "deepseek-flash"
        )
        XCTAssertNil(reading.execution)
        XCTAssertFalse(reading.serverReportDisagrees)
    }
}
