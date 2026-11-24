import XCTest
@testable import OneDayCore

/// 台账行三段派生钉测（§344，中枢四欠账·记录行三
/// 段式）：LedgerBoard.rowParts 是行中段副题与右段
/// trailing 的单源——副题只留状态词与非时间信息，
/// 时刻/已耗时归右段；subtitle(for:) 由 rowParts
/// 重组、整句口径必须与 §3/§4 旧钉死值逐字等值
/// （LedgerModelsTests 的旧期待值同时在跑、不许
/// 改）。固定日历（公历＋上海时区）与固定 now，
/// 与 LedgerModelsTests 同基准
final class LedgerRowPartsTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func epoch(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Double {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!.timeIntervalSince1970
    }

    /// 基准时刻：2026-11-10 15:10:00（上海）
    private var now: Double { epoch(2026, 11, 10, 15, 10, 0) }

    private func makeItem(
        kind: LedgerKind = .run,
        status: LedgerStatus = .running,
        startedAt: Double,
        endedAt: Double? = nil,
        lastEvidenceAt: Double? = nil,
        evidenceLagging: Bool = false,
        failCategory: String? = nil
    ) -> LedgerItem {
        LedgerItem(
            id: "run:r1", kind: kind,
            source: kind == .monitor ? .bridge : .app,
            title: "标题", titleSource: "user_excerpt",
            status: status, startedAt: startedAt,
            endedAt: endedAt, lastEvidenceAt: lastEvidenceAt,
            origin: "reported", link: nil, counts: [:],
            failReason: failCategory.map {
                LedgerFailReason(category: $0, excerpt: nil)
            },
            evidenceLagging: evidenceLagging, lastSeq: 1,
            sessionId: nil, runId: nil, correctedBy: nil,
            history: []
        )
    }

    private func parts(_ item: LedgerItem) -> LedgerRowParts {
        LedgerBoard.rowParts(
            for: item, serverNow: now, calendar: calendar
        )
    }

    private func wholeSubtitle(_ item: LedgerItem) -> String {
        LedgerBoard.subtitle(
            for: item, serverNow: now, calendar: calendar
        )
    }

    // MARK: - 九态映射

    func testMonitorPartsCarryEventWordAndDetectionTime() {
        let item = makeItem(
            kind: .monitor, status: .completed,
            startedAt: epoch(2026, 11, 10, 9, 41)
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "监测变化")
        XCTAssertEqual(parts.trailing, "09:41")
        XCTAssertNil(parts.trailingNote)
        XCTAssertEqual(wholeSubtitle(item), "监测变化 · 09:41")
    }

    func testRunningPartsSplitElapsedToTrailing() {
        let item = makeItem(startedAt: now - 133)
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "进行中")
        XCTAssertEqual(parts.trailing, "2:13")
        XCTAssertNil(parts.trailingNote)
        XCTAssertEqual(wholeSubtitle(item), "进行中 · 已运行 2:13")
    }

    func testRunningLaggingNoteGoesToTrailingNote() {
        let item = makeItem(
            startedAt: now - 133,
            lastEvidenceAt: epoch(2026, 11, 10, 15, 4, 30),
            evidenceLagging: true
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "进行中")
        XCTAssertEqual(parts.trailing, "2:13")
        XCTAssertEqual(parts.trailingNote, "最后确认 15:04:30")
        XCTAssertEqual(
            wholeSubtitle(item),
            "进行中 · 已运行 2:13 · 最后确认 15:04:30"
        )
    }

    func testQueuedPartsSplitWaitedToTrailing() {
        let item = makeItem(status: .queued, startedAt: now - 65)
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "排队中")
        XCTAssertEqual(parts.trailing, "1:05")
        XCTAssertEqual(wholeSubtitle(item), "排队中 · 已等 1:05")
    }

    func testBlockedApprovalPartsSplitWaitedToTrailing() {
        let item = makeItem(
            status: .blockedApproval, startedAt: now - 65
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "等待审批")
        XCTAssertEqual(parts.trailing, "1:05")
        XCTAssertEqual(wholeSubtitle(item), "等待审批 · 已等 1:05")
    }

    func testCompletedPartsCarryEndTime() {
        let ended = epoch(2026, 11, 10, 14, 58)
        let item = makeItem(
            status: .completed, startedAt: ended - 600,
            endedAt: ended
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "已完成")
        XCTAssertEqual(parts.trailing, "14:58")
        XCTAssertEqual(wholeSubtitle(item), "已完成 · 14:58")
    }

    func testCompletedWithoutEndTimeHasNoTrailing() {
        let item = makeItem(status: .completed, startedAt: now - 600)
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "已完成")
        XCTAssertNil(parts.trailing)
        XCTAssertEqual(wholeSubtitle(item), "已完成")
    }

    func testFailedPartsKeepCategoryInSubtitleAndEndTimeTrailing() {
        let ended = epoch(2026, 11, 10, 14, 58)
        let item = makeItem(
            status: .failed, startedAt: ended - 600,
            endedAt: ended, failCategory: "网络异常"
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "失败 · 网络异常")
        XCTAssertEqual(parts.trailing, "14:58")
        XCTAssertEqual(wholeSubtitle(item), "失败 · 网络异常")
    }

    func testFailedWithoutCategoryOrEndTime() {
        let item = makeItem(status: .failed, startedAt: now - 600)
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "失败")
        XCTAssertNil(parts.trailing)
        XCTAssertEqual(wholeSubtitle(item), "失败")
    }

    func testCancelledPartsMirrorFailedShape() {
        let ended = epoch(2026, 11, 10, 14, 58)
        let item = makeItem(
            status: .cancelled, startedAt: ended - 600,
            endedAt: ended, failCategory: "用户取消"
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "已取消 · 用户取消")
        XCTAssertEqual(parts.trailing, "14:58")
        XCTAssertEqual(wholeSubtitle(item), "已取消 · 用户取消")
    }

    func testStalePartsCarryLastConfirmedTime() {
        let item = makeItem(
            status: .stale, startedAt: now - 3600,
            lastEvidenceAt: epoch(2026, 11, 10, 14, 58)
        )
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "已失去联系")
        XCTAssertEqual(parts.trailing, "14:58")
        XCTAssertEqual(
            wholeSubtitle(item), "已失去联系 · 最后确认 14:58"
        )
    }

    func testStaleWithoutEvidenceHasNoTrailing() {
        let item = makeItem(status: .stale, startedAt: now - 3600)
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "已失去联系")
        XCTAssertNil(parts.trailing)
        XCTAssertEqual(wholeSubtitle(item), "已失去联系")
    }

    func testOtherPartsAreWordOnly() {
        let item = makeItem(status: .other("weird"), startedAt: now - 60)
        let parts = parts(item)
        XCTAssertEqual(parts.subtitle, "状态未知")
        XCTAssertNil(parts.trailing)
        XCTAssertEqual(wholeSubtitle(item), "状态未知")
    }
}
