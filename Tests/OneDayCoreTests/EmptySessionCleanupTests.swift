import XCTest

import OneDayCore

/// 空会话清理安全处置（§241）：候选口径、围栏对
/// 账、删后核验与审计记录编解码逐项钉死
final class EmptySessionCleanupTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func session(
        id: String, messageCount: Int?
    ) throws -> ServerSession {
        var fields = "\"id\": \"\(id)\""
        if let messageCount {
            fields += ", \"message_count\": \(messageCount)"
        }
        return try decoder.decode(
            ServerSession.self, from: Data("{\(fields)}".utf8))
    }

    func testCandidatesOnlyExplicitZero() throws {
        let sessions = [
            try session(id: "empty1", messageCount: 0),
            try session(id: "hasMessages", messageCount: 3),
            try session(id: "unknownCount", messageCount: nil),
            try session(id: "empty2", messageCount: 0),
        ]
        XCTAssertEqual(
            EmptySessionCleanup.candidates(from: sessions).map(\.id),
            ["empty1", "empty2"])
    }

    func testCountsMatchRequiresExactEquality() {
        XCTAssertTrue(
            EmptySessionCleanup.countsMatch(
                candidateCount: 4, serverCount: 4))
        XCTAssertFalse(
            EmptySessionCleanup.countsMatch(
                candidateCount: 3, serverCount: 4))
        XCTAssertFalse(
            EmptySessionCleanup.countsMatch(
                candidateCount: 5, serverCount: 4))
        XCTAssertTrue(
            EmptySessionCleanup.countsMatch(
                candidateCount: 0, serverCount: 0))
    }

    func testVerifySplitsGoneAndRemaining() {
        let result = EmptySessionCleanup.verify(
            candidateIDs: ["a", "b", "c"],
            survivingIDs: ["b", "zzz"])
        XCTAssertEqual(result.goneIDs, ["a", "c"])
        XCTAssertEqual(result.remainingIDs, ["b"])
    }

    func testVerifyEmptyCandidates() {
        let result = EmptySessionCleanup.verify(
            candidateIDs: [], survivingIDs: ["a"])
        XCTAssertEqual(result.goneIDs, [])
        XCTAssertEqual(result.remainingIDs, [])
    }

    func testAuditRecordCodableRoundTrip() throws {
        let record = EmptyCleanupAuditRecord(
            id: "run-1", plannedAt: "2026-11-14T06:00:00Z",
            scannedCount: 120, serverReportedCount: 2,
            candidates: [
                .init(id: "s1", title: "无标题会话",
                      startedAt: "2026-11-01T00:00:00Z"),
                .init(id: "s2", title: "测试", startedAt: nil),
            ],
            deletedIDs: ["s1"],
            failures: [.init(id: "s2", reason: "会话还在运行中")],
            verifiedGoneIDs: ["s1"], verifiedRemainingIDs: ["s2"],
            finishedAt: "2026-11-14T06:01:00Z")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            EmptyCleanupAuditRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testAuditRecordPlanOnlyDefaults() throws {
        // 计划段先落盘的形态：执行/核验段全空未收口
        let record = EmptyCleanupAuditRecord(
            id: "run-2", plannedAt: "2026-11-14T06:00:00Z",
            scannedCount: 10, serverReportedCount: 0,
            candidates: [])
        XCTAssertEqual(record.deletedIDs, [])
        XCTAssertEqual(record.failures, [])
        XCTAssertNil(record.verifiedGoneIDs)
        XCTAssertNil(record.finishedAt)
    }
}
