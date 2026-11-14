import XCTest
import SwiftData
@testable import OneDayApp
@testable import OneDayCore

/// 目标创建引用的落盘往返（§233，2026-11-14）：带
/// .goal 引用的用户消息落盘后，goalQuoteCategory 一
/// 字段足以重组引用（呈现与回放拼装走 ChatEntry.
/// sourceQuote 统一读口）；不带引用的消息读口为 nil，
/// 不许凭空组出引用
@MainActor
final class GoalQuoteEntryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let config = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
        container = try ModelContainer(
            for: schema, configurations: [config]
        )
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testGoalQuoteRoundTripsThroughEntry() throws {
        let thread = ChatThread()
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "亲笔",
            thread: thread,
            sourceQuote: .goal(GoalQuote(category: .health))
        )
        context.insert(entry)
        try context.save()
        XCTAssertEqual(entry.goalQuoteCategory, "health")
        XCTAssertEqual(
            entry.sourceQuote,
            .goal(GoalQuote(category: .health))
        )
        // 与其他族互斥：目标引用在场时 idea/file 字段恒空
        XCTAssertNil(entry.ideaQuoteID)
        XCTAssertNil(entry.fileQuoteName)
        XCTAssertNil(entry.feedPostID)
    }

    func testPlainEntryHasNoSourceQuote() throws {
        let entry = ChatEntry(role: "user", content: "亲笔")
        context.insert(entry)
        try context.save()
        XCTAssertNil(entry.goalQuoteCategory)
        XCTAssertNil(entry.sourceQuote)
    }

    func testUnknownCategoryRawValueReadsAsNoQuote() throws {
        let entry = ChatEntry(role: "user", content: "亲笔")
        entry.goalQuoteCategory = "not-a-category"
        context.insert(entry)
        try context.save()
        XCTAssertNil(entry.goalQuote)
        XCTAssertNil(entry.sourceQuote)
    }
}
