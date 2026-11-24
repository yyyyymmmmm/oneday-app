import Foundation
import SwiftData
import XCTest
@testable import OneDayApp

/// 台账 154（DESIGN §383）消息级幂等身份验收钉测：
/// ChatEntry.clientMessageID 的存储口径——默认 nil
/// （存量条目/助手条目无身份）、赋值后落盘可回读、
/// 条目间互不串扰。铸造与复用的驱动逻辑在 ChatView
/// .driveRun（视图层，与既有账本落盘同层），本套只
/// 钉存储面；迁移面（V2 旧库→V3 为默认 nil）由
/// SchemaFoundationAppTests 的 V2 迁移测钉死。
@MainActor
final class ClientMessageIDTests: XCTestCase {

    private var swiftDataMount = SwiftDataTestMount()

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentChatSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        return container
    }

    /// 新条目默认无幂等身份（nil）：存量与助手条目
    /// 的口径——只有用户消息首轮驱动时才铸造
    func testClientMessageIDDefaultsToNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "幂等钉测")
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "你好", thread: thread
        )
        context.insert(entry)
        try context.save()
        XCTAssertNil(entry.clientMessageID)
    }

    /// 铸造后落盘：换新上下文回读仍是同一 id——发件
    /// 箱跨进程重发复用同一身份的存储前提
    func testClientMessageIDPersistsAcrossContexts() throws {
        let container = try makeContainer()
        let minted = UUID().uuidString
        let writer = ModelContext(container)
        let thread = ChatThread(title: "幂等钉测")
        writer.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "带身份的消息", thread: thread
        )
        entry.clientMessageID = minted
        writer.insert(entry)
        try writer.save()

        let reader = ModelContext(container)
        let fetched = try reader.fetch(FetchDescriptor<ChatEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.clientMessageID, minted)
    }

    /// 条目间身份独立：一线程多条用户消息各持各的
    /// id，重发定位不串扰
    func testClientMessageIDsArePerEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "幂等钉测")
        context.insert(thread)
        let first = ChatEntry(
            role: "user", content: "第一条", thread: thread
        )
        first.clientMessageID = "msg-first"
        let second = ChatEntry(
            role: "user", content: "第二条", thread: thread
        )
        second.clientMessageID = "msg-second"
        context.insert(first)
        context.insert(second)
        try context.save()

        let byContent = Dictionary(
            uniqueKeysWithValues: thread.sortedEntries.map {
                ($0.content, $0.clientMessageID)
            }
        )
        XCTAssertEqual(byContent["第一条"], "msg-first")
        XCTAssertEqual(byContent["第二条"], "msg-second")
    }
}
