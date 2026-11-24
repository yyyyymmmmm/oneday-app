import OneDayCore
import XCTest

/// 回告留存合并（§241）：现行优先、存档补位、倒
/// 序与留存上限逐项钉死
final class ReportCardHistoryTests: XCTestCase {
    private func item(
        _ id: String, at createdAt: String, read: Bool = false,
        title: String? = nil
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: "monitor_change", title: title ?? id,
            body: "", createdAt: createdAt, read: read)
    }

    func testLiveWinsOverArchivedCopy() {
        let archived = [item(
            "a", at: "2026-11-14T01:00:00Z", title: "旧标题")]
        let live = [item(
            "a", at: "2026-11-14T01:00:00Z", read: true,
            title: "新标题")]
        let merged = ReportCardHistory.merge(
            live: live, archived: archived)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "新标题")
        XCTAssertTrue(merged[0].read)
    }

    func testArchivedOnlyItemsSurvive() {
        let live = [item("new", at: "2026-11-14T02:00:00Z")]
        let archived = [
            item("new", at: "2026-11-14T02:00:00Z"),
            item("old", at: "2026-11-13T02:00:00Z", read: true),
        ]
        let merged = ReportCardHistory.merge(
            live: live, archived: archived)
        XCTAssertEqual(merged.map(\.id), ["new", "old"])
        XCTAssertTrue(merged[1].read)
    }

    func testMergeSortsNewestFirst() {
        let live = [
            item("b", at: "2026-11-13T00:00:00Z"),
            item("a", at: "2026-11-14T00:00:00Z"),
        ]
        let merged = ReportCardHistory.merge(live: live, archived: [])
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
    }

    func testRetentionCapDropsOldest() {
        let archived = (0..<250).map { i in
            item("n\(i)", at: "2026-11-14T00:00:00Z")
        }
        let live = [item("fresh", at: "2026-11-15T00:00:00Z")]
        let merged = ReportCardHistory.merge(
            live: live, archived: archived)
        XCTAssertEqual(merged.count, ReportCardHistory.retentionLimit)
        XCTAssertEqual(merged.first?.id, "fresh")
    }

    func testEmptyInputs() {
        XCTAssertEqual(
            ReportCardHistory.merge(live: [], archived: []), [])
    }
}
