import XCTest
@testable import OneDayCore

/// 待删队列纯值钉测（§232）：入队去重（先入队者
/// 为准）、出队回条、集视图与 Codable 往返（落盘
/// 续跑的地基）
final class PendingSessionDeletionQueueTests: XCTestCase {

    private func record(
        _ id: String, title: String = "标题"
    ) -> PendingSessionDeletion {
        PendingSessionDeletion(
            sessionID: id, title: title,
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testEnqueueDedupesBySessionIDKeepingFirst() {
        var queue = PendingSessionDeletionQueue()
        XCTAssertTrue(queue.enqueue(record("s1", title: "先")))
        XCTAssertFalse(queue.enqueue(record("s1", title: "后")))
        XCTAssertTrue(queue.enqueue(record("s2")))
        XCTAssertEqual(queue.records.count, 2)
        XCTAssertEqual(queue.record(sessionID: "s1")?.title, "先")
        XCTAssertTrue(queue.contains(sessionID: "s2"))
        XCTAssertFalse(queue.contains(sessionID: "s3"))
        XCTAssertEqual(queue.sessionIDs, ["s1", "s2"])
        XCTAssertFalse(queue.isEmpty)
    }

    func testDequeueReturnsRecordAndRemoves() {
        var queue = PendingSessionDeletionQueue()
        queue.enqueue(record("s1"))
        queue.enqueue(record("s2"))
        XCTAssertEqual(queue.dequeue(sessionID: "s1")?.sessionID, "s1")
        XCTAssertNil(queue.dequeue(sessionID: "s1"))
        XCTAssertEqual(queue.sessionIDs, ["s2"])
        XCTAssertEqual(queue.dequeue(sessionID: "s2")?.sessionID, "s2")
        XCTAssertTrue(queue.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var queue = PendingSessionDeletionQueue()
        queue.enqueue(record("s1", title: "甲"))
        queue.enqueue(record("s2", title: "乙"))
        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(
            PendingSessionDeletionQueue.self, from: data
        )
        XCTAssertEqual(decoded, queue)
    }
}
