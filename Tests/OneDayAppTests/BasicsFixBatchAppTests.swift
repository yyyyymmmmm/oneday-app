import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// §237（基础正解批）App 侧验收：
/// P1——发送状态字段落盘读回与存量兼容还原；
/// P10——建库工厂的主路/降级/双失败三分支。
@MainActor
final class BasicsFixBatchAppTests: XCTestCase {

    /// §184：容器租约——见 SwiftDataTestMount（容器进进程级
    /// 持有、永不释放）。本类不挂载视图，但其容器若在进程内
    /// 先死，残留观察者在别测 save 时仍可被唤醒；永不释放
    /// 即杜绝（第二轮余 1 崩的兜底收编）。
    private var swiftDataMount = SwiftDataTestMount()

    private enum StubStoreError: Error { case broken }

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

    func testSendStateRoundTripsThroughStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "测试")
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "带文件的一条", thread: thread
        )
        context.insert(entry)
        try context.save()

        entry.markSendState(.failed, in: context)
        // 换新上下文读回：状态原值与旧失败标记必须
        // 同步落盘，不许只活在内存对象上
        let readContext = ModelContext(container)
        let fetched = try readContext.fetch(FetchDescriptor<ChatEntry>())
        let stored = try XCTUnwrap(
            fetched.first { $0.id == entry.id }
        )
        XCTAssertEqual(stored.sendState, .failed)
        XCTAssertTrue(stored.sendFailed)

        stored.markSendState(.delivered, in: readContext)
        XCTAssertEqual(stored.sendState, .delivered)
        XCTAssertFalse(stored.sendFailed)
        XCTAssertNil(stored.deliveryState)
    }

    func testLegacyPendingEntryRestoresQueuedState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "存量")
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "旧待发", thread: thread
        )
        context.insert(entry)
        // 存量形态：只有旧 deliveryState、无新字段
        entry.deliveryState = "pending"
        try context.save()
        XCTAssertNil(entry.sendStateRaw)
        XCTAssertEqual(entry.sendState, .queued)
    }

    func testBootstrapUsesPrimaryWhenHealthy() throws {
        let container = try makeContainer()
        let bootstrap = ChatModelContainerBootstrapFactory.make(
            primary: { container },
            fallback: { throw StubStoreError.broken }
        )
        XCTAssertNotNil(bootstrap.container)
        XCTAssertFalse(bootstrap.usesFallback)
        XCTAssertNil(bootstrap.failureMessage)
    }

    func testBootstrapFallsBackToMemoryStore() throws {
        let fallback = try makeContainer()
        let bootstrap = ChatModelContainerBootstrapFactory.make(
            primary: { throw StubStoreError.broken },
            fallback: { fallback }
        )
        // 原库建不成：降级容器在场（界面能开）、降级
        // 位与人话提示都在，不许静默 try! 砖死
        XCTAssertNotNil(bootstrap.container)
        XCTAssertTrue(bootstrap.usesFallback)
        let message = try XCTUnwrap(bootstrap.failureMessage)
        XCTAssertTrue(message.contains("原来的记录没有删除"))
    }

    func testBootstrapReportsUnavailableWhenBothFail() {
        let bootstrap = ChatModelContainerBootstrapFactory.make(
            primary: { throw StubStoreError.broken },
            fallback: { throw StubStoreError.broken }
        )
        XCTAssertNil(bootstrap.container)
        XCTAssertTrue(bootstrap.usesFallback)
        XCTAssertNotNil(bootstrap.failureMessage)
    }
}
