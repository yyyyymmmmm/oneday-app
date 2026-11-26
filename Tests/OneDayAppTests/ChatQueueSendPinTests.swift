import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §419（修复包二·生成中排队）钉测。
///
/// 可达面口径与 §414 钉同源（见 ChatFailKeepPinTests
/// 文件头实证）：托管单测环境供不出 SwiftUI 无障碍
/// 元素，send() 本体与右端钮点按在挂载环境不可达——
/// 本套钉其消费面与模型面，行为话逐钉如下：
/// 钉一（§451 改写）：未受理失败堵泵、后条不
/// 越过（严格保序，用户亲选）——取代 §419 的
/// 串行派发＋裁决 B（已落失败态不挡队首投）。
/// 钉二（§451 改写）：提交不被旧账本拦——提
/// 交与落定解耦，旧轮对账中时新条目照常提交
/// （服务端 FIFO 排班）；§419「账本未落定时
/// 原地不动」作废。
/// 钉三（Q4 落定形态）：排队条目原位编辑——正文
/// 覆写、id／创建时间／排队状态／幂等键全不动
/// （§414 路三同原语，排队态同样成立）。
/// 钉四（Q8 模型面）：排队条目落盘后以全新上下文
/// 回读，排队态＋待发＋未确认三谓词如实还原（冷启
/// 恢复与对账未清前不投递的存储面前提）。
/// 钉五（Q9 常量面）：贴底判定容差常量 == 48pt。
/// 列真机门（DESIGN §419）：Q1 的 send() 落位本体
/// 与双钮点按、Q3 撤回、Q5 同拍双触发、Q6 停止保
/// 队列、Q9 行为面（47/96pt）、Q10 在屏行高——挂
/// 载环境不可达或须真轮驱动，理由见 §419。
@MainActor
final class ChatQueueSendPinTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    private let swiftDataMount = SwiftDataTestMount()
    private weak var ledgerStore: RunLedgerStore?
    private var ledgerThreadIDs: [UUID] = []
    private weak var connectedState: AppState?

    override func tearDown() {
        if let ledgerStore {
            for threadID in ledgerThreadIDs {
                ledgerStore.remove(threadID: threadID)
            }
        }
        ledgerThreadIDs = []
        ledgerStore = nil
        connectedState?.disconnect()
        connectedState = nil
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 真挂起等待（口径同 §414 钉：同步自旋会饿死
    /// 被测 App 的 MainActor 任务，等待必须让拍）
    private func spinRunLoop(seconds: TimeInterval) async {
        try? await Task.sleep(
            nanoseconds: UInt64(seconds * 1_000_000_000)
        )
    }

    private func pollUntil(
        seconds: TimeInterval, _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await spinRunLoop(seconds: 0.25)
        }
        return condition()
    }

    // MARK: - 装配与播种（与 §414 钉同装配）

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    @discardableResult
    private func seedThread(
        in container: ModelContainer,
        entries: [(role: String, content: String)]
    ) throws -> ChatThread {
        let context = ModelContext(container)
        let thread = ChatThread(title: "排队钉测线程")
        context.insert(thread)
        let base = Date(timeIntervalSince1970: 1_763_000_000)
        for (index, item) in entries.enumerated() {
            let entry = ChatEntry(
                role: item.role, content: item.content,
                thread: thread
            )
            entry.createdAt = base.addingTimeInterval(
                Double(index) * 10
            )
            context.insert(entry)
        }
        try context.save()
        return thread
    }

    private func mountRoot(
        container: ModelContainer, appState: AppState
    ) async {
        swiftDataMount.retain(container)
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await spinRunLoop(seconds: 4.0)
        window.layoutIfNeeded()
        await spinRunLoop(seconds: 0.8)
        window.layoutIfNeeded()
    }

    private func makeConnectedAppState(
        mainThreadID: UUID
    ) async throws -> AppState {
        let appState = AppState(
            client: CountingCatalogClient(
                recorder: CatalogCallRecorder()
            ),
            demoMode: .connected
        )
        appState.sessionLedger.designateMainThread(mainThreadID)
        appState.sideChats.setLastThreadID(mainThreadID)
        ledgerStore = appState.runLedger
        connectedState = appState
        try await appState.connectDirect(
            config: try XCTUnwrap(
                ServerConfig(rawInput: "https://queuepin.test")
            ),
            apiKey: "queue-pin-test-key"
        )

        XCTAssertNotNil(
            appState.apiKey,
            "演示态 apiKey 应返回假值 demo-api-key"
        )
        return appState
    }

    private func readEntries(
        in container: ModelContainer, threadID: UUID
    ) throws -> [ChatEntry] {
        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        guard let thread = threads.first(
            where: { $0.id == threadID }
        ) else { return [] }
        return thread.sortedEntries
    }

    /// 播种：一问一答已落定＋两条排队落位（落位形
    /// 态与 send() 账本分支逐字同：markSendState
    /// (.queued) 后 markPendingSend 双写；幂等键预置
    /// 为首投铸造后的恒定值形态）
    private func seedQueueScene(
        in container: ModelContainer
    ) throws -> (
        thread: ChatThread, firstID: UUID, secondID: UUID
    ) {
        let thread = try seedThread(in: container, entries: [
            ("user", "排队钉已落定问句"),
            ("assistant", "排队钉已落定答复"),
            ("user", "排队钉甲"),
            ("user", "排队钉乙"),
        ])
        let context = ModelContext(container)
        let seeded = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        let first = try XCTUnwrap(
            seeded.first { $0.content == "排队钉甲" }
        )
        let second = try XCTUnwrap(
            seeded.first { $0.content == "排队钉乙" }
        )
        first.clientMessageID = "queue-pin-msg-a"
        second.clientMessageID = "queue-pin-msg-b"
        for entry in [first, second] {
            entry.markSendState(.queued, in: context)
            entry.markPendingSend(in: context)
        }
        try context.save()
        return (thread, first.id, second.id)
    }

    // MARK: - 钉一（§451 改写）：未受理失败堵泵，后条不越过

    /// §451 严格保序（用户 2026-11-24 亲选）取代
    /// §419 钉一的串行派发＋裁决 B：甲未受理失败
    /// 落 .failed 后泵停在甲上——乙永不被提交（无
    /// 账本、待发身份与排队态一字不动），两条幂等
    /// 键与序位恒定。离线桩下甲的失败落点在链接段
    /// （prepareFailed，同为未受理失败、与提交段
    /// 被拒同堵泵口径，见 SubmissionLane 注释）。
    func testUnacceptedFailureBlocksLaterEntries()
        async throws
    {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        let appState = try await makeConnectedAppState(
            mainThreadID: scene.thread.id
        )
        await mountRoot(container: container, appState: appState)

        let landed = await pollUntil(seconds: 15) {
            (try? readEntries(
                in: container, threadID: scene.thread.id
            ))?.first { $0.id == scene.firstID }?.sendFailed
                == true
        }
        XCTAssertTrue(
            landed, "首条未受理失败后未原位落失败态"
        )
        await spinRunLoop(seconds: 2.5)
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[2].id, scene.firstID)
        XCTAssertEqual(entries[3].id, scene.secondID)
        XCTAssertEqual(
            entries[2].clientMessageID, "queue-pin-msg-a",
            "派发改动了第一条的幂等键"
        )
        XCTAssertEqual(
            entries[3].clientMessageID, "queue-pin-msg-b",
            "派发改动了第二条的幂等键"
        )
        // 乙从未被提交：无账本、待发＋排队态原样
        XCTAssertNil(
            appState.runLedger.entry(
                forUserEntryID: scene.secondID
            ),
            "后条越过失败条被提交（竟有账本）"
        )
        XCTAssertTrue(entries[3].isPendingSend)
        XCTAssertEqual(entries[3].sendState, .queued)
        // 甲未受理：账本不留
        XCTAssertNil(
            appState.runLedger.entry(
                forUserEntryID: scene.firstID
            ),
            "未受理失败条账本未清"
        )
    }

    // MARK: - 钉二（§451 改写）：提交不被旧账本拦

    /// §451 提交与落定解耦：上一轮账本未落定（结
    /// 果未知对账中）不再是提交的闸——甲照常被提
    /// 交（服务端 FIFO 受理多轮、按序排班），离线
    /// 桩下未受理失败落 .failed；乙被失败条堵住不
    /// 越过（无账本、待发＋排队态原样）。§419 钉
    /// 二「账本未落定时排队条目原地不动」自此作
    /// 废：那是单轮互斥的前提，已被用户亲裁的发
    /// 送机制换代取代（DESIGN §451）。
    func testSubmissionNotGatedByStaleLedger() async throws {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        let appState = try await makeConnectedAppState(
            mainThreadID: scene.thread.id
        )
        let settledID = try XCTUnwrap(
            try readEntries(in: container, threadID: scene.thread.id)
                .first?.id
        )
        appState.runLedger.upsert(RunLedgerEntry(
            threadID: scene.thread.id.uuidString,
            sessionID: "oneday-queue-stale-session",
            runID: nil,
            idempotencyKey: "queue-stale-key",
            userEntryID: settledID.uuidString,
            submittedAt: Date()
        ))
        ledgerThreadIDs = [scene.thread.id]
        await mountRoot(container: container, appState: appState)

        let landed = await pollUntil(seconds: 15) {
            (try? readEntries(
                in: container, threadID: scene.thread.id
            ))?.first { $0.id == scene.firstID }?.sendFailed
                == true
        }
        XCTAssertTrue(
            landed,
            "旧账本在位时新条目未被提交（提交被账本门拦）"
        )
        await spinRunLoop(seconds: 2.5)
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(entries[3].isPendingSend)
        XCTAssertEqual(entries[3].sendState, .queued)
        XCTAssertNil(
            appState.runLedger.entry(
                forUserEntryID: scene.secondID
            ),
            "后条越过失败条被提交（竟有账本）"
        )
    }

    // MARK: - 钉三：排队条目原位编辑保状态

    func testQueuedEntryEditInPlaceKeepsStateAndID() throws {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        let context = ModelContext(container)
        let fetched = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        let entry = try XCTUnwrap(
            fetched.first { $0.id == scene.firstID }
        )
        let createdAt = entry.createdAt
        entry.applyUnsentEdit(
            content: "排队钉甲改后正文",
            imageDatas: [], quote: nil, sourceQuote: nil,
            in: context
        )
        try context.save()
        let after = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatEntry>())
                .first { $0.id == scene.firstID }
        )
        XCTAssertEqual(after.content, "排队钉甲改后正文")
        XCTAssertEqual(after.createdAt, createdAt)
        XCTAssertEqual(after.sendState, .queued)
        XCTAssertTrue(after.isPendingSend)
        XCTAssertEqual(after.clientMessageID, "queue-pin-msg-a")
    }

    // MARK: - 钉四：排队态落盘回读还原

    func testQueuedStateRestoredFromStorage() throws {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        // 全新上下文回读（模拟冷启恢复读数）
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        let restored = try XCTUnwrap(
            entries.first { $0.id == scene.firstID }
        )
        XCTAssertEqual(restored.sendState, .queued)
        XCTAssertTrue(restored.isPendingSend)
        XCTAssertTrue(
            restored.isUnconfirmedSend,
            "排队条目未被呈现面认作未确认发送（浅色＋时钟）"
        )
        XCTAssertTrue(ChatSendState.queued.remainsInQueue)
        XCTAssertTrue(ChatSendState.queued.mayAutoResume)
    }

    // MARK: - 钉五：贴底容差常量

    func testAtBottomToleranceIs48() {
        XCTAssertEqual(
            ChatRootViewController.atBottomTolerance, 48,
            accuracy: 0.001
        )
    }
}
