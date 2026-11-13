import SwiftData
import XCTest
@testable import OneDayApp

/// 基础体验止血包（2026-11-13）App 侧验收：P1/P2
/// 的失败留存地基——ChatEntry.sendFailed 新字段默
/// 认 false（存量条目轻量迁移口径，同 isPinned 先
/// 例）、置真落盘后可读回（气泡旁重发标记的数据源
/// 就是它，杀进程重启后标记不许丢）
@MainActor
final class BasicsStopgapAppTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    func testSendFailedDefaultsFalseAndPersists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "止血包验收")
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "你好", thread: thread
        )
        context.insert(entry)
        // 新字段默认 false：正常条目不带失败标记
        XCTAssertFalse(entry.sendFailed)
        try context.save()

        // 模拟发送失败落标记（markTurnFailed 同动作）
        entry.sendFailed = true
        try context.save()

        // 重新取回：标记随条目落盘存活
        let entryID = entry.id
        let descriptor = FetchDescriptor<ChatEntry>(
            predicate: #Predicate { $0.id == entryID }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.sendFailed, true)

        // 落定成功清标记（applySettledTurn 同动作）
        fetched.first?.sendFailed = false
        try context.save()
        let refetched = try context.fetch(descriptor)
        XCTAssertEqual(refetched.first?.sendFailed, false)
    }
}
