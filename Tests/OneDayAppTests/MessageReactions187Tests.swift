import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 187 消息反应包·App 层验收：可反应门控谓
/// 词（单点）、行高两态（有/无反应差＝预留单源
/// 值）、落盘钉桩与回补对账（补钉＋真源覆写）、
/// 镜像写口同值不落写、修订随反应翻转、动作项朗
/// 读末尾。真机观感（pill 悬挂位置/长按触发竞速）
/// CI 无信号、归用户真机（交卷清单）
@MainActor
final class MessageReactions187Tests: XCTestCase {
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

    private func makeComposer() -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ChatRowStateLedger(),
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    // MARK: 门控谓词

    func testCanReactGate() {
        let assistant = ChatEntry(
            role: "assistant", content: "回复", thread: nil
        )
        XCTAssertFalse(
            assistant.canReact, "未钉桩（服务端无此行）不可反应"
        )
        assistant.serverRowID = 42
        XCTAssertTrue(
            assistant.canReact, "钉桩＋已落定的助手行可反应"
        )
        let user = ChatEntry(
            role: "user", content: "问", thread: nil
        )
        user.serverRowID = 7
        XCTAssertTrue(user.canReact)
        user.deliveryState = "pending"
        XCTAssertFalse(user.canReact, "待发条目不可反应")
        user.deliveryState = nil
        user.sendFailed = true
        XCTAssertFalse(user.canReact, "发送失败条目不可反应")
        // 工具卡数据在身的条目不是发言行
        let cardLike = ChatEntry(
            role: "assistant", content: "回复", thread: nil
        )
        cardLike.serverRowID = 9
        cardLike.toolCardData = Data()
        XCTAssertFalse(cardLike.canReact, "工具卡条目不可反应")
        // 系统锚定回响不是发言
        let echo = ChatEntry(
            role: "assistant", content: "回响", thread: nil,
            echoKey: "goal:1"
        )
        echo.serverRowID = 10
        XCTAssertFalse(echo.canReact, "系统锚定条目不可反应")
    }

    // MARK: 行高两态

    func testHeightReserveTwoStates() {
        let composer = makeComposer()
        let assistant = ChatEntry(
            role: "assistant", content: "一条回复", thread: nil
        )
        let plainAssistant = composer.entryHeightCore(
            ChatEntryHeightSnapshot(assistant), dividerText: nil
        )
        assistant.applyReactions([
            MessageReaction(emoji: "👍", author: "user", at: 1),
        ])
        let reactedAssistant = composer.entryHeightCore(
            ChatEntryHeightSnapshot(assistant), dividerText: nil
        )
        XCTAssertEqual(
            reactedAssistant - plainAssistant,
            ChatReactionMetrics.rowReserve,
            accuracy: 0.001,
            "助手行有反应须恰多一笔 pill 悬出预留（单源值）"
        )
        let user = ChatEntry(
            role: "user", content: "一条提问", thread: nil
        )
        let plainUser = composer.entryHeightCore(
            ChatEntryHeightSnapshot(user), dividerText: nil
        )
        user.applyReactions([
            MessageReaction(emoji: "🔥", author: "agent", at: 1),
        ])
        let reactedUser = composer.entryHeightCore(
            ChatEntryHeightSnapshot(user), dividerText: nil
        )
        XCTAssertEqual(
            reactedUser - plainUser,
            ChatReactionMetrics.rowReserve,
            accuracy: 0.001,
            "用户行同口径（两支同预留）"
        )
        // 几何自洽：预留＝悬出净深＋2pt 呼吸、pill 高
        // 与悬深同源（半身悬出）
        XCTAssertEqual(
            ChatReactionMetrics.rowReserve,
            ChatReactionMetrics.hangDepth + 2,
            "预留与悬出几何必须同源（差一像素行高与渲染打架）"
        )
        XCTAssertEqual(
            ChatReactionMetrics.hangDepth * 2,
            ChatReactionMetrics.pillHeight,
            "pill 半身悬出（悬深＝高的一半）"
        )
    }

    // MARK: 镜像写口

    func testApplyReactionsWriteGate() {
        let entry = ChatEntry(
            role: "assistant", content: "回复", thread: nil
        )
        let reaction = MessageReaction(
            emoji: "👍", author: "user", at: 1
        )
        entry.applyReactions([reaction])
        let data = entry.reactionsData
        XCTAssertNotNil(data)
        XCTAssertEqual(entry.reactions, [reaction])
        entry.applyReactions([reaction])
        XCTAssertEqual(
            entry.reactionsData, data,
            "同值覆写不许落写（回补每轮覆写不翻修订/行高）"
        )
        entry.applyReactions([])
        XCTAssertNil(
            entry.reactionsData, "空集落 nil（与各 JSON 字段同口径）"
        )
        XCTAssertTrue(entry.reactions.isEmpty)
    }

    // MARK: 修订随反应/钉桩翻转

    func testRevisionChangesWithReactionAndPin() {
        let entry = ChatEntry(
            role: "assistant", content: "回复", thread: nil
        )
        func revision() -> ChatNativeRowRevision {
            ChatNativeRowRevision.entry(
                entry, dividerText: nil, highlighted: false,
                styleKey: "s"
            )
        }
        let base = revision()
        entry.applyReactions([
            MessageReaction(emoji: "👍", author: "user", at: 1),
        ])
        XCTAssertNotEqual(
            base, revision(), "反应一变修订必变（行原位重配出 pill）"
        )
        let reacted = revision()
        entry.serverRowID = 3
        XCTAssertNotEqual(
            reacted, revision(), "钉桩同列入账（字段枚举全量纪律）"
        )
    }

    // MARK: 落盘钉桩＋回补对账

    func testInserterPinsRowIDAndMirror() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "测试")
        context.insert(thread)
        let item = SessionHistoryImport.RichItem(
            role: "assistant", content: "你好",
            date: Date(timeIntervalSince1970: 1_762_000_000),
            imagePaths: [], toolCard: nil,
            serverRowID: 123,
            reactions: [
                MessageReaction(emoji: "❤️", author: "user", at: 1),
            ]
        )
        SessionHistoryInserter.insert(
            items: [item], into: thread, context: context
        )
        try context.save()
        let entry = try XCTUnwrap(thread.entries.first)
        XCTAssertEqual(entry.serverRowID, 123)
        XCTAssertEqual(entry.reactions.map(\.emoji), ["❤️"])
        XCTAssertTrue(entry.canReact)
    }

    func testBackfillReconcilePinsAndOverwrites() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "测试")
        context.insert(thread)
        let date = Date(timeIntervalSince1970: 1_762_000_000)
        let entry = ChatEntry(
            role: "user", content: "问题", thread: thread
        )
        entry.createdAt = date
        context.insert(entry)
        try context.save()
        XCTAssertNil(entry.serverRowID)
        // 指纹命中：补钉＋镜像覆写
        let item = SessionHistoryImport.RichItem(
            role: "user", content: "问题", date: date,
            imagePaths: [], toolCard: nil,
            serverRowID: 55,
            reactions: [
                MessageReaction(emoji: "😂", author: "agent", at: 1),
            ]
        )
        SessionHistoryInserter.reconcileReactions(
            items: [item], entries: thread.entries
        )
        XCTAssertEqual(entry.serverRowID, 55)
        XCTAssertEqual(entry.reactions.map(\.emoji), ["😂"])
        // 服务端清空：镜像随真源清
        let cleared = SessionHistoryImport.RichItem(
            role: "user", content: "问题", date: date,
            imagePaths: [], toolCard: nil,
            serverRowID: 55, reactions: []
        )
        SessionHistoryInserter.reconcileReactions(
            items: [cleared], entries: thread.entries
        )
        XCTAssertTrue(entry.reactions.isEmpty)
        // 指纹不命中（正文不同）：钉桩与镜像都不动
        let other = SessionHistoryImport.RichItem(
            role: "user", content: "别的问题", date: date,
            imagePaths: [], toolCard: nil,
            serverRowID: 99,
            reactions: [
                MessageReaction(emoji: "🔥", author: "user", at: 1),
            ]
        )
        SessionHistoryInserter.reconcileReactions(
            items: [other], entries: thread.entries
        )
        XCTAssertEqual(entry.serverRowID, 55)
        XCTAssertTrue(entry.reactions.isEmpty)
    }

    // MARK: 动作项（朗读末尾）

    func testActionItemsSpeakLast() {
        let data = ChatRowActionSheetData(
            plainText: "正文",
            canReact: true, ownEmoji: "👍",
            onPickReaction: { _ in },
            onReply: {}, onFork: {},
            onSelect: {}, onShare: {},
            makeSpeakItem: {
                ChatRowSpeakItem(
                    title: "朗读",
                    systemImage: MessageActionSymbols.speak,
                    action: {}
                )
            }
        )
        let items = data.actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.reply, .fork, .copy, .select, .share, .speak],
            "朗读恒居动作列表末尾（H2-a 项序口径）"
        )
        XCTAssertEqual(items.last?.title, "朗读")
    }
}
