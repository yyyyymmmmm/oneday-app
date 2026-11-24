import XCTest
@testable import OneDayCore

/// §477 会话聚合钉测：同 sessionId 多次运行合成一
/// 行（代表＝最近开始的一次）、无 sessionId 不强
/// 并、组序按代表开始时刻倒序
final class LedgerSessionGroupsTests: XCTestCase {

    private func makeItem(
        id: String, sessionId: String? = nil,
        startedAt: Double, lastSeq: Int = 1,
        status: LedgerStatus = .completed
    ) -> LedgerItem {
        LedgerItem(
            id: id, kind: .run, source: .app,
            title: "标题", titleSource: "user_excerpt",
            status: status, startedAt: startedAt,
            endedAt: nil, lastEvidenceAt: nil,
            origin: "reported", link: nil, counts: [:],
            failReason: nil, evidenceLagging: false,
            lastSeq: lastSeq, sessionId: sessionId,
            runId: nil, correctedBy: nil, history: []
        )
    }

    func testSameSessionMergesToLatestRun() {
        let items = [
            makeItem(id: "r3", sessionId: "s1", startedAt: 300),
            makeItem(id: "r2", sessionId: "s1", startedAt: 200),
            makeItem(id: "r1", sessionId: "s1", startedAt: 100),
        ]
        let groups = LedgerBoard.sessionGroups(items)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[0].representative.id, "r3")
        XCTAssertEqual(groups[0].id, "r3")
    }

    func testRepresentativeTieBreakByLastSeq() {
        let items = [
            makeItem(
                id: "older", sessionId: "s1",
                startedAt: 100, lastSeq: 1
            ),
            makeItem(
                id: "newer", sessionId: "s1",
                startedAt: 100, lastSeq: 9
            ),
        ]
        let groups = LedgerBoard.sessionGroups(items)
        XCTAssertEqual(groups[0].representative.id, "newer")
    }

    func testNilSessionItemsStaySeparateAndOrderByLatest() {
        let items = [
            makeItem(id: "a", sessionId: "s1", startedAt: 100),
            makeItem(id: "b", sessionId: nil, startedAt: 500),
            makeItem(id: "c", sessionId: "s1", startedAt: 300),
            makeItem(id: "d", sessionId: nil, startedAt: 200),
        ]
        let groups = LedgerBoard.sessionGroups(items)
        // s1 合一行（代表 c）＋b、d 各自成行
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(
            groups.map(\.representative.id), ["b", "c", "d"]
        )
        XCTAssertEqual(groups[1].count, 2)
    }

    func testEmptyAndSingleton() {
        XCTAssertTrue(LedgerBoard.sessionGroups([]).isEmpty)
        let single = LedgerBoard.sessionGroups([
            makeItem(id: "x", startedAt: 1)
        ])
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].count, 1)
    }
}
