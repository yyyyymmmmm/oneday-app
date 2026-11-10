import XCTest
@testable import OneDayCore

/// 进展胶囊派生（0.37.0 模型包）：只收进行中、剔除本
/// 聊会话、领衔取最近开始、多件收敛文案、审批件不进。
final class ProgressCapsuleTests: XCTestCase {

    private func item(
        id: String, status: LedgerStatus, startedAt: Double,
        sessionId: String? = nil, title: String = "标题"
    ) -> LedgerItem {
        LedgerItem(
            id: id, kind: .run, source: .app,
            title: title, titleSource: "user_excerpt",
            status: status, startedAt: startedAt,
            endedAt: nil, lastEvidenceAt: nil,
            origin: "reported", link: nil, counts: [:],
            failReason: nil, evidenceLagging: false, lastSeq: 1,
            sessionId: sessionId, runId: nil, correctedBy: nil,
            history: []
        )
    }

    func testEmptyWhenNothingActive() {
        XCTAssertNil(ProgressCapsule.derive(
            items: [item(id: "a", status: .completed, startedAt: 1)],
            currentSessionID: nil
        ))
        XCTAssertNil(ProgressCapsule.derive(items: [], currentSessionID: nil))
    }

    func testSingleRunning() {
        let content = ProgressCapsule.derive(
            items: [item(id: "a", status: .running, startedAt: 10, title: "查资料")],
            currentSessionID: "other"
        )
        XCTAssertEqual(content?.count, 1)
        XCTAssertEqual(content?.headlineText, "查资料")
        XCTAssertEqual(content?.headlineItemID, "a")
    }

    func testExcludesCurrentSession() {
        let items = [
            item(id: "mine", status: .running, startedAt: 99, sessionId: "s1"),
            item(id: "theirs", status: .running, startedAt: 10, sessionId: "s2"),
        ]
        let content = ProgressCapsule.derive(items: items, currentSessionID: "s1")
        XCTAssertEqual(content?.count, 1)
        XCTAssertEqual(content?.headlineItemID, "theirs")
        // 本聊是唯一进行中 → 胶囊不出现
        XCTAssertNil(ProgressCapsule.derive(
            items: [items[0]], currentSessionID: "s1"
        ))
    }

    func testHeadlineIsMostRecentAndCountCoversQueued() {
        let items = [
            item(id: "old", status: .running, startedAt: 10, title: "早先的"),
            item(id: "new", status: .queued, startedAt: 50, title: "刚排的"),
        ]
        let content = ProgressCapsule.derive(items: items, currentSessionID: nil)
        XCTAssertEqual(content?.count, 2)
        XCTAssertEqual(content?.headlineText, "正在进行 2 件 · 刚排的")
    }

    func testBlockedApprovalNotCounted() {
        let items = [
            item(id: "appr", status: .blockedApproval, startedAt: 10),
        ]
        XCTAssertNil(ProgressCapsule.derive(items: items, currentSessionID: nil))
    }
}
