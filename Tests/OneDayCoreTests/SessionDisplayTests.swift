import XCTest
@testable import OneDayCore

/// 会话屏上文案（0.3.6 立、0.3.7 按卡 16/18 收紧）：
/// 标题只有内容名（display_name/首条消息摘要），无
/// 内容可名时「未命名会话」；时间＋条数只作副信息；
/// source 原始标识永不上屏。
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
        endedAt: Double? = nil,
        messageCount: Int? = nil
    ) -> ServerSession {
        ServerSession(
            id: "sess-1", source: source, sessionKey: nil,
            displayName: displayName, model: nil, profile: nil,
            startedAt: startedAt, endedAt: endedAt, endReason: nil,
            messageCount: messageCount, toolCallCount: nil,
            inputTokens: nil, outputTokens: nil
        )
    }

    /// 0.3.7 收紧回归（用户真机纠正）：无 display_name
    /// 的会话标题不再是「今天 06:12 · 24 条」——标题
    /// 只给「未命名会话」，时间条数全部下沉副题；两
    /// 条同来源会话靠副题区分，原始标识两处都不出现。
    func testUnnamedSessionsUsePlaceholderTitleAndRichSubtitle() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12
        ))!
        let a = session(
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 24
        )
        let b = session(
            startedAt: epoch(2026, 11, 8, 21, 30),
            endedAt: epoch(2026, 11, 8, 22, 0), messageCount: 7
        )
        XCTAssertEqual(a.humanTitle, "未命名会话")
        XCTAssertEqual(b.humanTitle, "未命名会话")
        let subA = a.humanSubtitle(now: now, calendar: calendar)
        let subB = b.humanSubtitle(now: now, calendar: calendar)
        XCTAssertEqual(subA, "API 接口 · 今天 06:12 · 24 条 · 进行中")
        XCTAssertEqual(subB, "API 接口 · 昨天 21:30 · 7 条")
        XCTAssertNotEqual(subA, subB)
        XCTAssertFalse(subA.contains("api_server"))
        XCTAssertEqual(a.sourceLabel, "API 接口")
    }

    /// 人话 display_name 直接采用；标识符形态的
    /// display_name 视为原始名、回落未命名会话。
    func testHumanDisplayNameWinsAndIdentifierNameFallsBack() {
        let named = session(
            displayName: "帮我写周报",
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 3
        )
        XCTAssertTrue(named.hasHumanName)
        XCTAssertEqual(named.humanTitle, "帮我写周报")
        let raw = session(
            displayName: "api_server",
            startedAt: epoch(2026, 11, 5, 9, 0), messageCount: nil
        )
        XCTAssertFalse(raw.hasHumanName)
        XCTAssertEqual(raw.humanTitle, "未命名会话")
    }

    /// 首条用户消息摘要（待裁 5 已裁口径）：取首个
    /// 非空行、压平空白、剥 Markdown 行首标记、超
    /// 24 字截断；摘要优先于未命名回落，但不压过
    /// 人话 display_name 之外——contentTitle 的优先
    /// 序＝摘要 → display_name → 未命名会话。
    func testContentSummaryTitle() {
        XCTAssertEqual(
            ServerSession.contentSummaryTitle("  帮我看看今天的日程  "),
            "帮我看看今天的日程"
        )
        XCTAssertEqual(
            ServerSession.contentSummaryTitle("\n\n## 修复登录页崩溃\n第二行不进标题"),
            "修复登录页崩溃"
        )
        XCTAssertEqual(
            ServerSession.contentSummaryTitle("这是一个非常长的首条消息用来验证截断行为是否正确工作"),
            "这是一个非常长的首条消息用来验证截断行为是否正确…"
        )
        XCTAssertNil(ServerSession.contentSummaryTitle("   \n  "))
        XCTAssertNil(ServerSession.contentSummaryTitle(nil))

        let plain = session()
        XCTAssertEqual(
            plain.contentTitle(firstUserMessage: "查一下服务器状态"),
            "查一下服务器状态"
        )
        XCTAssertEqual(plain.contentTitle(firstUserMessage: nil), "未命名会话")
        let named = session(displayName: "帮我写周报")
        XCTAssertEqual(named.contentTitle(firstUserMessage: nil), "帮我写周报")
    }

    /// 兜底：未知来源只给「服务端」，原样标识永不透出。
    func testFallbacksNeverLeakRawIdentifiers() {
        let now = Date()
        let bare = session(source: "some_internal_bus")
        XCTAssertEqual(bare.humanTitle, "未命名会话")
        XCTAssertEqual(
            bare.humanSubtitle(now: now, calendar: calendar), "服务端"
        )
        XCTAssertEqual(bare.sourceLabel, "服务端")
        XCTAssertEqual(session(source: nil).sourceLabel, "服务端")
        XCTAssertEqual(session(source: "dashboard").sourceLabel, "控制台")
        XCTAssertEqual(session(source: "cron").sourceLabel, "定时任务")
    }
}
