import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 收敛包（2026-11-24）App 层验收：带引用消息回补
/// 全链（导入拆解→落盘回填槽位→再同步不新增行，
/// P3-1/P4-1）与存量收敛（修复前落盘的线格式原文
/// 行原地规范化、同指纹重复行在同步时合并）。
@MainActor
final class HistoryConvergeFixTests: XCTestCase {
    private var swiftDataMount = SwiftDataTestMount()

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        return container
    }

    private let epoch = Date(timeIntervalSince1970: 1762000400)

    /// 本地原条：干净正文＋引用槽位（发送时落盘形态）
    @discardableResult
    private func makeLocalOriginal(
        in thread: ChatThread, context: ModelContext
    ) -> ChatEntry {
        let entry = ChatEntry(
            role: "user", content: "展开讲讲", thread: thread
        )
        entry.quoteRole = "assistant"
        entry.quoteContent = "原回答"
        entry.createdAt = epoch
        context.insert(entry)
        return entry
    }

    private func serverMessages() -> [SessionMessage] {
        [
            SessionMessage(
                id: 41, role: "assistant", content: "原回答",
                timestamp: 1762000399, displayKind: nil
            ),
            SessionMessage(
                id: 42, role: "user",
                content: "[引用 Hermes 的消息]\n原回答\n\n展开讲讲",
                timestamp: 1762000400, displayKind: nil
            ),
        ]
    }

    /// 全链：服务端线格式回补到已有本地原条的线程——
    /// 指纹判同不新增行、原条结构在位、对账钉桩落原条
    func testBackfillDoesNotDuplicateQuotedMessage() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "收敛全链")
        context.insert(thread)
        let original = makeLocalOriginal(in: thread, context: context)
        let assistant = ChatEntry(
            role: "assistant", content: "原回答", thread: thread
        )
        assistant.createdAt = Date(timeIntervalSince1970: 1762000399)
        context.insert(assistant)
        try context.save()

        // 回补一轮的落盘三步（与 Backfiller.ingest 同
        // 序）：对账 → 指纹过滤 → 落盘
        let items = SessionHistoryImport.richItems(
            from: serverMessages()
        )
        SessionHistoryInserter.reconcileReactions(
            items: items, entries: thread.entries
        )
        let existing = Set(thread.entries.map {
            SessionHistoryInserter.fingerprint(of: $0)
        })
        let unseen = SessionHistorySync.unseenItems(
            items, existing: existing
        )
        XCTAssertTrue(
            unseen.isEmpty, "带引用消息不许再被判为本地没有"
        )
        SessionHistoryInserter.insert(
            items: unseen, into: thread, context: context
        )
        try context.save()
        XCTAssertEqual(thread.entries.count, 2)
        XCTAssertEqual(original.content, "展开讲讲")
        XCTAssertEqual(original.quoteContent, "原回答")
        XCTAssertEqual(original.serverRowID, 42)
    }

    /// 导入落盘：线格式 user 消息落成（干净正文＋引
    /// 用槽位），不再把线格式原文直写 content
    func testInsertFillsQuoteSlotsFromWireItem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "导入落盘")
        context.insert(thread)
        let items = SessionHistoryImport.richItems(
            from: serverMessages()
        )
        SessionHistoryInserter.insert(
            items: items, into: thread, context: context
        )
        try context.save()
        let userEntry = try XCTUnwrap(
            thread.entries.first { $0.role == "user" }
        )
        XCTAssertEqual(userEntry.content, "展开讲讲")
        XCTAssertEqual(userEntry.quoteRole, "assistant")
        XCTAssertEqual(userEntry.quoteContent, "原回答")
    }

    /// 存量收敛：修复前回补落的重复行（正文＝线格式
    /// 原文、无槽位、带 serverRowID）与本地原条并存
    /// 时，一轮收敛后只剩一行——正文拆净、槽位与服
    /// 务端锚都在
    func testConvergeMergesPrefixedDuplicateRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "存量合并")
        context.insert(thread)
        makeLocalOriginal(in: thread, context: context)
        let legacy = ChatEntry(
            role: "user",
            content: "[引用 Hermes 的消息]\n原回答\n\n展开讲讲",
            thread: thread
        )
        legacy.createdAt = epoch
        legacy.serverRowID = 42
        context.insert(legacy)
        try context.save()
        XCTAssertEqual(thread.entries.count, 2)

        let removed = SessionHistoryInserter
            .convergeStockDuplicates(
                entries: thread.entries, context: context
            )
        try context.save()
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(thread.entries.count, 1)
        let keeper = try XCTUnwrap(thread.entries.first)
        XCTAssertEqual(keeper.content, "展开讲讲")
        XCTAssertEqual(keeper.quoteRole, "assistant")
        XCTAssertEqual(keeper.quoteContent, "原回答")
        XCTAssertEqual(keeper.serverRowID, 42)
    }

    /// 存量收敛·孤行：没有本地原条、只有修复前落的
    /// 原文行时，原地拆回（正文＋槽位），行数不变
    func testConvergeNormalizesLoneLegacyRowInPlace() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "存量孤行")
        context.insert(thread)
        let legacy = ChatEntry(
            role: "user",
            content: "[引用 我 的消息]\n我之前说的\n\n对，就是这个",
            thread: thread
        )
        legacy.createdAt = epoch
        legacy.serverRowID = 43
        context.insert(legacy)
        try context.save()

        let removed = SessionHistoryInserter
            .convergeStockDuplicates(
                entries: thread.entries, context: context
            )
        try context.save()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(thread.entries.count, 1)
        XCTAssertEqual(legacy.content, "对，就是这个")
        XCTAssertEqual(legacy.quoteRole, "user")
        XCTAssertEqual(legacy.quoteContent, "我之前说的")
    }

    /// 不误伤：正文互异、无引用的行收敛后全保留
    func testConvergeLeavesUnrelatedEntriesAlone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "不误伤")
        context.insert(thread)
        for (index, text) in ["一问", "二问", "三问"].enumerated() {
            let entry = ChatEntry(
                role: "user", content: text, thread: thread
            )
            entry.createdAt = Date(
                timeIntervalSince1970: 1762000400 + Double(index)
            )
            context.insert(entry)
        }
        try context.save()
        let removed = SessionHistoryInserter
            .convergeStockDuplicates(
                entries: thread.entries, context: context
            )
        try context.save()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(thread.entries.count, 3)
    }
}
