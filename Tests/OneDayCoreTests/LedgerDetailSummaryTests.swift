import XCTest
@testable import OneDayCore

/// §475 详情页首一句话摘要钉测：只用条目自有字段
/// 拼人话，逐状态断言；摘要里不许出现任何原始
/// 枚举（running／bridge／job:…），状态词归 chip
/// 单源（LedgerText.statusWord）不在摘要里重复。
final class LedgerDetailSummaryTests: XCTestCase {

    private func makeItem(
        status: LedgerStatus,
        startedAt: Double = 1_000,
        endedAt: Double? = nil,
        lastEvidenceAt: Double? = nil,
        counts: [String: Int] = [:],
        failReason: LedgerFailReason? = nil
    ) -> LedgerItem {
        LedgerItem(
            id: "job:morning:1000", kind: .job, source: .bridge,
            title: "动态调研 · 11月24日", titleSource: "job_name",
            status: status, startedAt: startedAt,
            endedAt: endedAt, lastEvidenceAt: lastEvidenceAt,
            origin: "bridge_self", link: nil, counts: counts,
            failReason: failReason, evidenceLagging: false,
            lastSeq: 1, sessionId: nil, runId: nil,
            correctedBy: nil, history: []
        )
    }

    func testCompletedSummaryCarriesDurationAndCounts() {
        let item = makeItem(
            status: .completed, endedAt: 1_316,
            counts: ["toolCalls": 12]
        )
        let summary = LedgerBoard.detailSummary(
            for: item, serverNow: 2_000
        )
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("用时"))
        XCTAssertTrue(summary!.contains("工具调用 12 次"))
        XCTAssertFalse(summary!.contains("completed"))
        XCTAssertFalse(summary!.contains("已完成"))
    }

    func testRunningSummaryCarriesElapsed() {
        let item = makeItem(status: .running)
        let summary = LedgerBoard.detailSummary(
            for: item, serverNow: 1_183
        )
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("已运行"))
        XCTAssertFalse(summary!.contains("running"))
    }

    func testFailedSummaryLeadsWithCategory() {
        let item = makeItem(
            status: .failed, endedAt: 1_060,
            failReason: LedgerFailReason(
                category: "执行被打断", excerpt: "进程重启"
            )
        )
        let summary = LedgerBoard.detailSummary(
            for: item, serverNow: 2_000
        )
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.hasPrefix("执行被打断"))
        XCTAssertFalse(summary!.contains("failed"))
    }

    func testStaleSummaryCarriesLastEvidence() {
        let item = makeItem(
            status: .stale, lastEvidenceAt: 1_000
        )
        let summary = LedgerBoard.detailSummary(
            for: item, serverNow: 9_999
        )
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("最后确认"))
        XCTAssertFalse(summary!.contains("stale"))
    }

    func testCompletedWithoutEndReturnsNil() {
        // 缺结束时刻的终态不编时长、无计数时整行不显
        let item = makeItem(status: .completed, endedAt: nil)
        XCTAssertNil(
            LedgerBoard.detailSummary(for: item, serverNow: 2_000)
        )
    }

    func testStatusWordsStayHuman() {
        // chip 单源抽查：六态全是人话、零原文
        for status in [
            LedgerStatus.queued, .running, .blockedApproval,
            .completed, .failed, .cancelled, .stale,
        ] {
            let word = LedgerText.statusWord(status)
            XCTAssertFalse(word.isEmpty)
            XCTAssertFalse(word.contains(status.rawValue))
        }
    }
}
