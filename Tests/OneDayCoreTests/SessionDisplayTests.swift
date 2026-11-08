import XCTest
@testable import OneDayCore

final class SessionDisplayTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func epoch(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Double {
        calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi
        ))!.timeIntervalSince1970
    }

    private func session(
        source: String? = "api_server",
        displayName: String? = nil,
        startedAt: Double? = nil,
        messageCount: Int? = nil
    ) -> ServerSession {
        ServerSession(
            id: "sess-1", source: source, sessionKey: nil,
            displayName: displayName, model: nil, profile: nil,
            startedAt: startedAt, endedAt: nil, endReason: nil,
            messageCount: messageCount, toolCallCount: nil,
            inputTokens: nil, outputTokens: nil
        )
    }

    /// 本轮反例回归：无 display_name 的 api_server 会
    /// 话不再同名——标题按时间＋条数区分，原始标识
    /// 「api_server」在标题与来源标签里都不出现；两
    /// 条同来源会话标题互不相同。
    func testRawSourceSessionsGetDistinctHumanTitles() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12
        ))!
        let a = session(
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 24
        )
        let b = session(
            startedAt: epoch(2026, 11, 8, 21, 30), messageCount: 7
        )
        let titleA = a.humanTitle(now: now, calendar: calendar)
        let titleB = b.humanTitle(now: now, calendar: calendar)
        XCTAssertEqual(titleA, "今天 06:12 · 24 条")
        XCTAssertEqual(titleB, "昨天 21:30 · 7 条")
        XCTAssertNotEqual(titleA, titleB)
        XCTAssertFalse(titleA.contains("api_server"))
        XCTAssertFalse(titleB.contains("api_server"))
        XCTAssertEqual(a.sourceLabel, "API 接口")
    }

    /// 人话 display_name 直接采用（首条消息/摘要标
    /// 题的服务端承载）；标识符形态的 display_name
    /// 视为原始名、走时间回落。
    func testHumanDisplayNameWinsAndIdentifierNameFallsBack() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12
        ))!
        let named = session(
            displayName: "帮我写周报",
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 3
        )
        XCTAssertTrue(named.hasHumanName)
        XCTAssertEqual(
            named.humanTitle(now: now, calendar: calendar), "帮我写周报"
        )
        let raw = session(
            displayName: "api_server",
            startedAt: epoch(2026, 11, 5, 9, 0), messageCount: nil
        )
        XCTAssertFalse(raw.hasHumanName)
        XCTAssertEqual(
            raw.humanTitle(now: now, calendar: calendar), "11月5日 09:00"
        )
    }

    /// 兜底：无时间无条数只剩通用名；未知来源只给
    /// 「服务端」、原样标识永不透出。
    func testFallbacksNeverLeakRawIdentifiers() {
        let now = Date()
        let bare = session(source: "some_internal_bus")
        XCTAssertEqual(bare.humanTitle(now: now, calendar: calendar), "服务端会话")
        XCTAssertEqual(bare.sourceLabel, "服务端")
        XCTAssertEqual(session(source: nil).sourceLabel, "服务端")
        XCTAssertEqual(session(source: "dashboard").sourceLabel, "控制台")
        XCTAssertEqual(session(source: "cron").sourceLabel, "定时任务")
    }
}
