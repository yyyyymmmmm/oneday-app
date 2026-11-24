import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 第 67 条会话账本包二（2026-11-15）App 层钉测：
/// ①清理面完整性闸——名单不完整不许生成候选（删
/// 除向过闸的钉子，施工图 §4.4-4）；②频道名单读
/// 账本投影——Hermes/平台频道分流、收养升层后行
/// 消失（频道页私抄退役的等值锚）；③删除走账本单
/// 管线——经协调器壳起手、落账本引擎，失败恢复把
/// 名单回行落账本（壳与引擎同队列）
@MainActor
final class SessionLedgerPackage2Tests: XCTestCase {

    private var container: ModelContainer!
    private var swiftDataMount = SwiftDataTestMount()
    private var context: ModelContext!
    private var priorMainSessionID: String?

    private let mainKey = "sideChats.mainServerSessionID"
    private let queueKey = "sessionDeletions.pendingQueue"

    override func setUp() async throws {
        try await super.setUp()
        priorMainSessionID = UserDefaults.standard.string(
            forKey: mainKey
        )
        UserDefaults.standard.removeObject(forKey: queueKey)
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        if let priorMainSessionID {
            UserDefaults.standard.set(
                priorMainSessionID, forKey: mainKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: mainKey)
        }
        UserDefaults.standard.removeObject(forKey: queueKey)
        context = nil
        await swiftDataMount.release()
        container = nil
        try await super.tearDown()
    }

    // MARK: - 夹具

    private func makeSession(
        id: String, source: String? = nil,
        messageCount: Int? = nil
    ) -> ServerSession {
        var fields = ["\"id\":\"\(id)\""]
        if let source {
            fields.append("\"source\":\"\(source)\"")
        }
        if let messageCount {
            fields.append(
                "\"message_count\":\(messageCount)"
            )
        }
        return try! JSONDecoder().decode(
            ServerSession.self,
            from: Data(
                "{\(fields.joined(separator: ","))}".utf8
            )
        )
    }

    private func makePage(
        sessions: [ServerSession], total: Int?
    ) -> SessionsPage {
        let items = sessions.map { session in
            var fields = ["\"id\":\"\(session.id)\""]
            if let source = session.source {
                fields.append("\"source\":\"\(source)\"")
            }
            return "{\(fields.joined(separator: ","))}"
        }
        var json = "{\"sessions\":["
            + items.joined(separator: ",") + "]"
        if let total { json += ",\"total\":\(total)" }
        json += "}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    private func fetchThreads() throws -> [ChatThread] {
        try context.fetch(FetchDescriptor<ChatThread>())
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(
                for: .milliseconds(50)
            )
        }
        XCTFail("等待超时")
    }

    // MARK: - ① 清理面完整性闸

    func testCleanupGateBlocksCandidatesWhenIncomplete() {
        let empty = makeSession(
            id: "s-empty", messageCount: 0
        )
        for reason in [
            SessionLedger.IncompleteReason
                .pageCapReached,
            .totalMismatch(reported: 1500, fetched: 1000),
            .duplicateRows(count: 3),
        ] {
            let result = SessionLedger.FetchResult(
                sessions: [empty], incompleteReason: reason
            )
            XCTAssertNil(
                EmptyCleanupScanGate.candidates(from: result),
                "名单不完整（\(reason.traceLabel)）不许生成候选"
            )
        }
    }

    func testCleanupGatePassesCandidatesWhenComplete() {
        let empty = makeSession(
            id: "s-empty", messageCount: 0
        )
        let busy = makeSession(
            id: "s-busy", messageCount: 5
        )
        let result = SessionLedger.FetchResult(
            sessions: [empty, busy], incompleteReason: nil
        )
        XCTAssertEqual(
            EmptyCleanupScanGate.candidates(from: result)?
                .map(\.id),
            ["s-empty"]
        )
    }

    // MARK: - ② 频道名单读账本投影

    func testChannelListReadsLedgerProjection() async throws {
        var client = ScriptedSessionsClient()
        client.scriptedPages = [
            "exclude|0": makePage(
                sessions: [
                    makeSession(id: "s-web", source: "api_server"),
                    makeSession(id: "s-wa", source: "whatsapp"),
                    makeSession(id: "oneday-ai-new"),
                ],
                total: 3
            ),
        ]
        let appState = AppState(
            client: client, demoMode: .connected
        )
        let ledger = appState.sessionLedger
        await ledger.refreshVisible(
            appState: appState,
            localThreads: try fetchThreads()
        )
        XCTAssertEqual(
            ledger.channelList(
                appState: appState,
                localThreads: try fetchThreads(),
                channelID: ChannelRegistry.hermesChannelID
            ).map(\.id),
            ["s-web"]
        )
        XCTAssertEqual(
            ledger.channelList(
                appState: appState,
                localThreads: try fetchThreads(),
                channelID: "whatsapp"
            ).map(\.id),
            ["s-wa"]
        )
        // 收养升层：s-web 绑上本地线程后不再归频道
        let thread = ChatThread(title: "收养线程")
        thread.serverSessionID = "s-web"
        context.insert(thread)
        try context.save()
        XCTAssertEqual(
            ledger.channelList(
                appState: appState,
                localThreads: try fetchThreads(),
                channelID: ChannelRegistry.hermesChannelID
            ).map(\.id),
            []
        )
    }

    // MARK: - ③ 删除走账本单管线

    func testDeletionViaShellLandsInLedgerEngine() async throws {
        let appState = AppState(
            client: FailingHermesClient(),
            demoMode: .connected
        )
        let session = makeSession(id: "s-del")
        appState.sessionLedger.publishVisible([session]
        )
        let thread = ChatThread(title: "待删线程")
        thread.serverSessionID = "s-del"
        context.insert(thread)
        try context.save()

        appState.sessionDeletions.deleteAction = { _, _ in
            .failed("桩失败")
        }
        appState.sessionDeletions.catalogRefresher = { _ in
            [session]
        }
        appState.sessionDeletions.begin(
            sessionID: "s-del", title: "待删线程",
            appState: appState, modelContext: context
        )
        // 起手同拍：墓碑＋账本摘行＋入队（壳与账本引
        // 擎同一队列两面可见）
        XCTAssertTrue(thread.isPendingDeletion)
        XCTAssertTrue(
            appState.sessionLedger.visibleSessions.isEmpty
        )
        XCTAssertTrue(
            appState.sessionLedger.deletions.isPending(
                sessionID: "s-del"
            )
        )
        XCTAssertEqual(
            appState.sessionDeletions.queue.sessionIDs,
            appState.sessionLedger.deletions.queue.sessionIDs
        )
        // 后台失败：恢复把名单回行落账本、解墓碑、出队
        await waitUntil {
            appState.sessionLedger.deletions.restoreRevision
                == 1
                && !thread.isPendingDeletion
        }
        XCTAssertEqual(
            appState.sessionLedger.visibleSessions.map(\.id),
            ["s-del"]
        )
        XCTAssertTrue(
            appState.sessionLedger.deletions.queue.isEmpty
        )
        XCTAssertEqual(
            appState.sessionDeletionFailureNotice,
            "「待删线程」删除没成功，已恢复。"
        )
    }
}
