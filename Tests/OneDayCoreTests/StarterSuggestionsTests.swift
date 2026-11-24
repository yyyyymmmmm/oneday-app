import XCTest

@testable import OneDayCore

/// §455 空态建议引擎钉测：建议必须从用户当下真实状态
/// 长出来——有待批时首条必为待批类、无上下文整面回落
/// 冷启三条、用过的短期内不再现。
final class StarterSuggestionsTests: XCTestCase {

    private func fullContext() -> StarterContext {
        StarterContext(
            pendingApprovals: .init(count: 2, token: "2|rec-9"),
            failedCronJob: .init(
                id: "job-1", name: "夜间巡检", token: "2026-11-24T01:00:00Z"
            ),
            blockedGoal: .init(
                id: "goal-1", title: "OneDay 发版", token: "1700000000"
            ),
            activeGoal: .init(id: "goal-2", title: "婚礼筹备"),
            recentDelivery: .init(
                newestName: "周报.pdf", extraCount: 1, token: "p|1.0"
            ),
            upcomingCronCount: 3,
            hour: 9
        )
    }

    /// 一级三件齐在时：顺序＝待批 > 定时异常 > 目标卡住，
    /// 且只取三条（一级占满，低级不入）
    func testActionTierOrderAndCap() {
        let result = StarterSuggestionsEngine.suggestions(
            context: fullContext()
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.tier), [
            .actionNeeded, .actionNeeded, .actionNeeded,
        ])
        XCTAssertTrue(result[0].key.hasPrefix("approvals/"))
        XCTAssertTrue(result[0].text.contains("2 条"))
        XCTAssertTrue(result[1].key.hasPrefix("cronFailed/"))
        XCTAssertTrue(result[2].key.hasPrefix("goalBlocked/"))
    }

    /// 无上下文（冷启未就绪，hour 也为 nil）：整面回落
    /// 冷启三条，文案与符号与回落池逐条同
    func testNoContextFallsBackToThree() {
        let result = StarterSuggestionsEngine.suggestions(
            context: StarterContext()
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.text), EmptyChatSuggestions.texts)
        XCTAssertEqual(result.map(\.symbol), EmptyChatSuggestions.symbols)
        XCTAssertEqual(
            result.map(\.tier), [.fallback, .fallback, .fallback]
        )
    }

    /// 上下文已就绪但当下无事（只有钟点）：时段条打头，
    /// 其余由回落池补位到三条
    func testTimeOnlyContextLeadsWithTimeThenFallback() {
        let result = StarterSuggestionsEngine.suggestions(
            context: StarterContext(hour: 20)
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].tier, .timeContext)
        XCTAssertEqual(result[0].key, "time/evening")
        XCTAssertEqual(result[1].tier, .fallback)
        XCTAssertEqual(result[2].tier, .fallback)
    }

    /// 用过的建议不再现：待批条被抑制后，首条顺延到
    /// 定时异常，空位由下级补
    func testUsedSuggestionDoesNotReappear() {
        var context = fullContext()
        context.suppressedKeys = ["approvals/2|rec-9"]
        let result = StarterSuggestionsEngine.suggestions(
            context: context
        )
        XCTAssertFalse(result.contains { $0.key.hasPrefix("approvals/") })
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].key.hasPrefix("cronFailed/"))
    }

    /// 状态指纹重装：待批换了新指纹（有新待批到达），
    /// 旧抑制不拦新条
    func testStateTokenRearmsSuppression() {
        var context = fullContext()
        context.pendingApprovals = .init(count: 3, token: "3|rec-10")
        context.suppressedKeys = ["approvals/2|rec-9"]
        let result = StarterSuggestionsEngine.suggestions(
            context: context
        )
        XCTAssertTrue(result[0].key.hasPrefix("approvals/"))
        XCTAssertTrue(result[0].text.contains("3 条"))
    }

    /// 记账本：标记后窗内抑制、窗外释放；弃过同用过
    func testMarkBookWindow() {
        var book = StarterSuggestionMarkBook()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        book.markUsed(key: "approvals/x", tier: .actionNeeded, at: t0)
        book.markDismissed(key: "time/morning", tier: .timeContext, at: t0)

        let within = book.suppressedKeys(
            now: t0.addingTimeInterval(3600)
        )
        XCTAssertTrue(within.contains("approvals/x"))
        XCTAssertTrue(within.contains("time/morning"))

        // 时段条 20 小时窗：21 小时后释放；状态条 7 天窗仍在
        let later = book.suppressedKeys(
            now: t0.addingTimeInterval(21 * 3600)
        )
        XCTAssertFalse(later.contains("time/morning"))
        XCTAssertTrue(later.contains("approvals/x"))

        // 8 天后状态条也释放，prune 后账本清空
        let muchLater = t0.addingTimeInterval(8 * 24 * 3600)
        XCTAssertTrue(book.suppressedKeys(now: muchLater).isEmpty)
        book.prune(now: muchLater)
        XCTAssertTrue(book.used.isEmpty)
        XCTAssertTrue(book.dismissed.isEmpty)
    }

    /// 全部候选连同回落都被抑制时也不许空面：整池原样出
    func testEverythingSuppressedStillShowsFallback() {
        var context = StarterContext()
        context.suppressedKeys = ["fallback/0", "fallback/1", "fallback/2"]
        let result = StarterSuggestionsEngine.suggestions(
            context: context
        )
        XCTAssertEqual(result.map(\.text), EmptyChatSuggestions.texts)
    }

    /// 建议文案纪律：每条都是可直接发出的完整句、无内
    /// 部词（占位符/英文键名/调试字样）
    func testSuggestionTextsAreSendable() {
        let result = StarterSuggestionsEngine.suggestions(
            context: fullContext()
        )
        for suggestion in result {
            XCTAssertFalse(suggestion.text.isEmpty)
            XCTAssertFalse(suggestion.text.contains("TODO"))
            XCTAssertFalse(suggestion.text.contains("%@"))
            XCTAssertFalse(suggestion.symbol.isEmpty)
        }
    }
}
