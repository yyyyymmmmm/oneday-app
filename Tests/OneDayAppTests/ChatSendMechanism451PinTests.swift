import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §451（发送机制换代）App 层钉测。
///
/// 可达面口径与 §414/§419 钉同源：send() 本体在挂
/// 载环境不可达，钉走生产同路的消费面——播种与
/// send() 落盘形态逐字同的待发条目（.queued＋待
/// 发双写＋幂等键预置），挂载后由提交泵真提交，
/// 服务端半边由 ScriptedRunsClient＋RunsScript
/// 出演（受理回 run_id、同 key 回原 run、状态恒
/// 在飞）。主线会话 id 预绑定（setMainServerSess-
/// ionID），链接段走 .session 直发计划、真抵达
/// submitRun——与离线桩套件「链接段落败」的落点
/// 刻意不同，本套钉的是提交段本体。
/// 钉 A（连发受理）：首轮在飞不落定，后两条照常
/// 被提交受理——三条提交键序＝落盘序、三条账本
/// 齐在、三条全部脱离未确认态（受理回执即满色，
/// 不等首轮落定）；账本 runID 与脚本同 key 出演
/// 恒一致（154 同条重投回原 run、不双跑），静置
/// 后账本与键序不变。
/// 钉 B（严格保序堵泵）：首条被明确拒绝落 .fai-
/// led 后，后条永不被提交（提交键集只有首条）、
/// 原地待发身份不变、无账本；首条账本已清（未受
/// 理不留账）。
/// 列真机门：已受理条目长按「撤回」手势全程（撤
/// 回谓词与动作在 ChatView 私有面，挂载环境不可
/// 达，与 §419 Q3 同口径）、连发变色时序的在屏
/// 观感、堵泵时第二条的气泡呈现。
@MainActor
final class ChatSendMechanism451PinTests: XCTestCase {

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

    // MARK: - 装配与播种

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
        let thread = ChatThread(title: "发送机制钉测线程")
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
        mainThreadID: UUID, script: RunsScript
    ) async throws -> AppState {
        let appState = AppState(
            client: ScriptedRunsClient(
                recorder: CatalogCallRecorder(), runs: script
            ),
            demoMode: .connected
        )
        appState.sessionLedger.designateMainThread(mainThreadID)
        appState.sessionLedger.setMainServerSessionID(
            "sendmech-pin-session"
        )
        appState.sideChats.setLastThreadID(mainThreadID)
        ledgerStore = appState.runLedger
        connectedState = appState
        try await appState.connectDirect(
            config: try XCTUnwrap(
                ServerConfig(rawInput: "https://sendmechpin.test")
            ),
            apiKey: "sendmech-pin-key"
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

    /// 播种：一问一答已落定＋N 条待发落位（形态与
    /// send() 落盘逐字同：markSendState(.queued)
    /// 后 markPendingSend 双写；幂等键预置为首投
    /// 铸造后的恒定值形态）
    private func seedPendingScene(
        in container: ModelContainer,
        pendingContents: [String]
    ) throws -> (thread: ChatThread, pendingIDs: [UUID]) {
        var rows: [(role: String, content: String)] = [
            ("user", "发送机制钉已落定问句"),
            ("assistant", "发送机制钉已落定答复"),
        ]
        for content in pendingContents {
            rows.append(("user", content))
        }
        let thread = try seedThread(in: container, entries: rows)
        let context = ModelContext(container)
        let seeded = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        var ids: [UUID] = []
        for (index, content) in pendingContents.enumerated() {
            let entry = try XCTUnwrap(
                seeded.first { $0.content == content }
            )
            entry.clientMessageID = "sendmech-pin-msg-\(index)"
            entry.markSendState(.queued, in: context)
            entry.markPendingSend(in: context)
            ids.append(entry.id)
        }
        try context.save()
        return (thread, ids)
    }

    // MARK: - 钉 A：连发三条，首轮在飞时后条照常受理满色

    func testThreePendingAcceptedWhileFirstRunInFlight()
        async throws
    {
        let script = RunsScript()
        let container = try makeContainer()
        let scene = try seedPendingScene(
            in: container,
            pendingContents: ["发送机制钉甲", "发送机制钉乙", "发送机制钉丙"]
        )
        let appState = try await makeConnectedAppState(
            mainThreadID: scene.thread.id, script: script
        )
        ledgerThreadIDs = [scene.thread.id]
        await mountRoot(container: container, appState: appState)

        let keys = [
            "sendmech-pin-msg-0", "sendmech-pin-msg-1",
            "sendmech-pin-msg-2",
        ]
        // 提交序＝落盘序：泵逐条真投，三键按序到达
        let allSubmitted = await pollUntil(seconds: 20) {
            script.firstSeenKeys == keys
        }
        XCTAssertTrue(
            allSubmitted,
            "三条未按落盘序全部提交：\(script.firstSeenKeys)"
        )
        let allLedgered = await pollUntil(seconds: 10) {
            appState.runLedger.entries(
                forThreadID: scene.thread.id
            ).count == 3
        }
        XCTAssertTrue(allLedgered, "三条受理后账本未齐三条")
        // 满色钉：首轮恒在飞（脚本状态 .running 不
        // 落定），三条却已全部脱离未确认态——变色
        // 只挂受理回执、不等落定
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        XCTAssertEqual(entries.count, 5)
        for pendingID in scene.pendingIDs {
            let entry = try XCTUnwrap(
                entries.first { $0.id == pendingID }
            )
            XCTAssertFalse(
                entry.isUnconfirmedSend,
                "已受理条目仍呈未确认态（浅色）"
            )
            XCTAssertFalse(entry.sendFailed)
        }
        // 154 钉：账本 runID 与脚本同 key 出演恒一
        // 致——同条重投回原 run、不双跑
        for (index, pendingID) in scene.pendingIDs.enumerated() {
            let ledgerEntry = appState.runLedger.entry(
                forUserEntryID: pendingID
            )
            XCTAssertEqual(
                ledgerEntry?.runID, script.runID(forKey: keys[index])
            )
        }
        // 静置后账本与键序不变（对账重演不新增 run）
        await spinRunLoop(seconds: 2.5)
        XCTAssertEqual(
            appState.runLedger.entries(
                forThreadID: scene.thread.id
            ).count, 3
        )
        XCTAssertEqual(script.firstSeenKeys, keys)
    }

    // MARK: - 钉 B：首条明确拒绝堵泵，后条不越过

    func testRejectedFirstBlocksSecond() async throws {
        let script = RunsScript()
        script.submitError = .apiKeyRejected
        let container = try makeContainer()
        let scene = try seedPendingScene(
            in: container,
            pendingContents: ["发送机制钉甲", "发送机制钉乙"]
        )
        let appState = try await makeConnectedAppState(
            mainThreadID: scene.thread.id, script: script
        )
        ledgerThreadIDs = [scene.thread.id]
        await mountRoot(container: container, appState: appState)

        let firstID = scene.pendingIDs[0]
        let secondID = scene.pendingIDs[1]
        let landed = await pollUntil(seconds: 15) {
            (try? readEntries(
                in: container, threadID: scene.thread.id
            ))?.first { $0.id == firstID }?.sendFailed == true
        }
        XCTAssertTrue(landed, "首条被拒后未原位落失败态")
        await spinRunLoop(seconds: 2.5)
        // 提交键集只有首条：后条从未被提交（严格保
        // 序——失败条堵泵、后续不越过）
        XCTAssertEqual(
            Set(script.submissions.map(\.key)),
            ["sendmech-pin-msg-0"],
            "后条越过失败条被提交：\(script.submissions)"
        )
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        XCTAssertEqual(entries.count, 4)
        let second = try XCTUnwrap(
            entries.first { $0.id == secondID }
        )
        XCTAssertTrue(second.isPendingSend)
        XCTAssertEqual(second.sendState, .queued)
        XCTAssertNil(
            appState.runLedger.entry(forUserEntryID: secondID),
            "后条未提交却有账本"
        )
        XCTAssertNil(
            appState.runLedger.entry(forUserEntryID: firstID),
            "未受理失败条账本未清"
        )
    }
}
