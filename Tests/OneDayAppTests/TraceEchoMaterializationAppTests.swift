import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 回响物化落盘（§217，App 侧执行件）：留痕落成
/// 真条目后按事件时间在 sortedEntries 里归位（新
/// 消息排其后）、同线程二次运行不重复、按线程去
/// 重（主线与目标旁聊各落一条）、不动 thread.
/// updatedAt、条目进系统锚定族、失败条目在场且
/// 快照存原文。
@MainActor
final class TraceEchoMaterializationAppTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    private func trace(
        id: String = "trc_1",
        targetID: String = "oneday-ai-abc",
        at: Double = 1_763_000_000,
        status: String = "ok",
        result: String? = "已新开旁聊「关于结婚的事情」并发出任务简报",
        error: String? = nil
    ) -> BridgeTrace {
        BridgeTrace(
            id: id, action: "sessions.create", actor: "agent",
            target: BridgeTraceTarget(
                kind: "session", id: targetID,
                label: "关于结婚的事情",
                ref: "oneday://sessions/\(targetID)"),
            at: at, status: status, result: result, error: error
        )
    }

    // MARK: - 落位（事件时间归位、新消息排其后）

    /// 核心验收：昨天的回响落盘后排在今天的消息之
    /// 前——sortedEntries 按 createdAt，回响条目的
    /// createdAt 已改写为事件时间，新消息推不走它、
    /// 它也不再沉到流尾
    func testMaterializedEntrySortsAtEventTimeBeforeNewerMessage()
        throws
    {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        context.insert(thread)
        let eventAt = 1_763_000_000.0
        // 今天的新消息（事件之后一小时）
        let newer = ChatEntry(role: "user", content: "你好", thread: thread)
        newer.createdAt = Date(timeIntervalSince1970: eventAt + 3600)
        context.insert(newer)
        try context.save()

        TraceEchoMaterializationRunner.run(
            traces: [trace(at: eventAt)],
            thread: thread, isMainThread: true,
            agentName: "三狗", context: context
        )

        let sorted = thread.sortedEntries
        XCTAssertEqual(sorted.count, 2)
        let echo = sorted[0]
        XCTAssertEqual(echo.traceKey, "trace:trc_1")
        XCTAssertEqual(
            echo.createdAt, Date(timeIntervalSince1970: eventAt)
        )
        XCTAssertEqual(sorted[1].content, "你好")
        // 快照随条目自包含：主句/对象/结果/点达齐备
        XCTAssertEqual(echo.traceEcho?.headline, "三狗 新开了一个旁聊")
        XCTAssertEqual(echo.traceEcho?.targetLabel, "关于结婚的事情")
        XCTAssertEqual(
            echo.traceEcho?.openableSessionID, "oneday-ai-abc"
        )
        XCTAssertFalse(echo.traceEcho?.isFailed ?? true)
    }

    // MARK: - 去重（已物化不重出）

    /// 同一线程二次运行不产生重复条目
    func testSecondRunDoesNotDuplicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        context.insert(thread)
        try context.save()

        for _ in 0..<2 {
            TraceEchoMaterializationRunner.run(
                traces: [trace()],
                thread: thread, isMainThread: true,
                agentName: "三狗", context: context
            )
        }
        XCTAssertEqual(
            thread.entries.filter { $0.traceKey != nil }.count, 1
        )
    }

    /// 去重按线程：同一留痕在主线落一条、在它指向
    /// 的旁聊再落一条（旧双面可见语义），互不压制
    func testSameTraceMaterializesOncePerThread() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let main = ChatThread(title: "主线")
        let side = ChatThread(title: "关于结婚的事情")
        side.serverSessionID = "oneday-ai-abc"
        context.insert(main)
        context.insert(side)
        try context.save()

        TraceEchoMaterializationRunner.run(
            traces: [trace()],
            thread: main, isMainThread: true,
            agentName: "三狗", context: context
        )
        TraceEchoMaterializationRunner.run(
            traces: [trace()],
            thread: side, isMainThread: false,
            agentName: "三狗", context: context
        )
        XCTAssertEqual(
            main.entries.filter { $0.traceKey != nil }.count, 1
        )
        XCTAssertEqual(
            side.entries.filter { $0.traceKey != nil }.count, 1
        )
    }

    // MARK: - 纪律（不动 updatedAt、系统锚定族）

    /// 物化不是用户活动：thread.updatedAt 不许被顶
    func testMaterializationDoesNotTouchThreadUpdatedAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        let settled = Date(timeIntervalSince1970: 1_700_000_000)
        thread.updatedAt = settled
        context.insert(thread)
        try context.save()

        TraceEchoMaterializationRunner.run(
            traces: [trace()],
            thread: thread, isMainThread: true,
            agentName: "三狗", context: context
        )
        XCTAssertEqual(thread.updatedAt, settled)
    }

    /// 回响条目进系统锚定族：发送上下文排除/落定
    /// 替换跳过等四处守卫共用的谓词必须认它
    func testTraceEntryIsSystemAnchored() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        context.insert(thread)
        try context.save()

        TraceEchoMaterializationRunner.run(
            traces: [trace()],
            thread: thread, isMainThread: true,
            agentName: "三狗", context: context
        )
        let echo = thread.entries.first { $0.traceKey != nil }
        XCTAssertNotNil(echo)
        XCTAssertTrue(echo?.isSystemAnchored ?? false)
    }

    // MARK: - 失败同级在场

    /// 失败留痕照样落条目，快照存失败原文（P0 契约）
    func testFailedTraceMaterializesWithErrorSnapshot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        context.insert(thread)
        try context.save()

        let errorText = "taskBrief 不能为空（新旁聊的首帖任务简报）"
        TraceEchoMaterializationRunner.run(
            traces: [trace(
                status: "failed", result: nil, error: errorText
            )],
            thread: thread, isMainThread: true,
            agentName: "三狗", context: context
        )
        let echo = thread.entries.first { $0.traceKey != nil }
        XCTAssertNotNil(echo)
        XCTAssertTrue(echo?.traceEcho?.isFailed ?? false)
        XCTAssertEqual(echo?.traceEcho?.outcome, errorText)
    }
}
