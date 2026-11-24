import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// 名单分页拉取计数器（§370）：引用型记录器，跨
/// ScriptedSessionsClient 值拷贝存活（与 §331 消息
/// 计数器同式）；按键（"archived|offset"）逐次记账
final class SessionsPageFetchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []

    var callCount: Int { lock.withLock { keys.count } }

    func record(key: String) {
        lock.withLock { keys.append(key) }
    }
}

/// 缓存 C3 抽屉名单新鲜度门钉测（§370）：假客户端
/// 请求计数——TTL 内连开两趟＝第二趟 0 请求、过期
/// ＝真拉、删除/一轮落地/改名落定后＝真拉、换服务
/// 器（配置键）＝真拉、失败不落账不冒充新鲜
@MainActor
final class DrawerListFreshnessC3Tests: XCTestCase {

    private func makePage(
        ids: [String], total: Int?
    ) -> SessionsPage {
        var json = "{\"sessions\":["
            + ids.map {
                "{\"id\":\"\($0)\",\"title\":\"标题-\($0)\"}"
            }.joined(separator: ",")
            + "]"
        if let total { json += ",\"total\":\(total)" }
        json += "}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    private func makeAppState(
        pages: [String: SessionsPage],
        recorder: SessionsPageFetchRecorder
    ) -> AppState {
        var client = ScriptedSessionsClient()
        client.scriptedPages = pages
        client.sessionsPageRecorder = recorder
        return AppState(client: client, demoMode: .connected)
    }

    private func standardPages() -> [String: SessionsPage] {
        ["exclude|0": makePage(ids: ["s-1", "s-2"], total: 2)]
    }

    // MARK: - TTL 内零请求／过期真拉

    func testSecondTriggerWithinTTLZeroRequests() async {
        let recorder = SessionsPageFetchRecorder()
        let appState = makeAppState(
            pages: standardPages(), recorder: recorder
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)
        XCTAssertEqual(
            ledger.visibleSessions.map(\.id), ["s-1", "s-2"]
        )

        // TTL 内连开第二趟：零名单请求、名单照旧
        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(30)
        )
        XCTAssertEqual(recorder.callCount, 1)
        XCTAssertEqual(
            ledger.visibleSessions.map(\.id), ["s-1", "s-2"]
        )
    }

    func testTriggerAfterTTLExpiryFetchesAgain() async {
        let recorder = SessionsPageFetchRecorder()
        let appState = makeAppState(
            pages: standardPages(), recorder: recorder
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(61)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }

    // MARK: - 强制路不经门、成功落账

    func testForcedRefreshBypassesGateAndStamps() async {
        let recorder = SessionsPageFetchRecorder()
        let appState = makeAppState(
            pages: standardPages(), recorder: recorder
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)

        // 强制路（令牌/行操作口径）：TTL 内照样真拉
        await ledger.refreshVisible(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(10)
        )
        XCTAssertEqual(recorder.callCount, 2)

        // 强制路成功已落账：其后门控触发零请求
        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(20)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }

    // MARK: - 写事件失效

    func testRemoveSessionInvalidatesGate() async {
        let recorder = SessionsPageFetchRecorder()
        let appState = makeAppState(
            pages: standardPages(), recorder: recorder
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)

        ledger.removeSession(sessionID: "s-1")
        XCTAssertEqual(ledger.visibleSessions.map(\.id), ["s-2"])

        // 删除落定后 TTL 内读触发必真拉对账
        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(10)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }

    func testTurnFinishedInvalidatesGate() async {
        let recorder = SessionsPageFetchRecorder()
        let appState = makeAppState(
            pages: standardPages(), recorder: recorder
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)

        // 旁聊一轮落地（新会话/服务端新标题成立点）
        appState.noteLinkedSideChatTurnFinished()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(10)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }

    func testRenameVerifiedInvalidatesGate() async throws {
        let recorder = SessionsPageFetchRecorder()
        var client = ScriptedSessionsClient()
        client.scriptedPages = standardPages()
        client.sessionsPageRecorder = recorder
        client.updateRecorder = SessionUpdateRecorder()
        let renamed = try JSONDecoder().decode(
            ServerSession.self,
            from: Data(
                "{\"id\":\"s-1\",\"title\":\"新标题\"}".utf8
            )
        )
        client.scriptedSessions = ["s-1": renamed]
        let appState = AppState(
            client: client, demoMode: .connected
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)

        let outcome = await ServerSessionActions.rename(
            appState: appState, id: "s-1", title: "新标题"
        )
        XCTAssertEqual(outcome, .verified)

        // 改名落定后 TTL 内读触发必真拉对账
        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(10)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }

    // MARK: - 换服务器（配置键）

    func testConfigChangeFetchesAgain() async throws {
        let recorder = SessionsPageFetchRecorder()
        var client = ScriptedSessionsClient()
        client.scriptedPages = standardPages()
        client.sessionsPageRecorder = recorder
        client.scriptedHealth = try JSONDecoder().decode(
            HealthResponse.self,
            from: Data("{\"status\":\"ok\"}".utf8)
        )
        client.scriptedModels = ["deepseek-chat"]
        let appState = AppState(
            client: client, demoMode: .connected
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)
        let oldKey = appState.config?.baseString

        try await appState.connectDirect(
            config: try XCTUnwrap(
                ServerConfig(rawInput: "https://other.test")
            ),
            apiKey: "test-key"
        )
        XCTAssertNotEqual(appState.config?.baseString, oldKey)

        // 配置键已变：TTL 内读触发必真拉
        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(10)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }

    // MARK: - 失败不落账

    func testFailedFetchDoesNotStamp() async {
        let recorder = SessionsPageFetchRecorder()
        // 无脚本页：fetchAll 首步即失败
        let appState = makeAppState(
            pages: [:], recorder: recorder
        )
        let ledger = appState.sessionLedger
        let t0 = Date()

        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [], now: t0
        )
        XCTAssertEqual(recorder.callCount, 1)
        XCTAssertFalse(ledger.hasLoaded)

        // 失败没落账：紧接着的读触发照旧重试、不被
        // 假新鲜吞掉
        await ledger.refreshVisibleIfNeeded(
            appState: appState, localThreads: [],
            now: t0.addingTimeInterval(5)
        )
        XCTAssertEqual(recorder.callCount, 2)
    }
}
