import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 发送解门与历史补齐（根治版包 2，DESIGN §331）
/// App 层旅程钉测：脚本客户端＋内存库——
/// ①重装形态：认领落定→发送闸即 ready，全程零历
///   史拉取、零种子导入（不等补齐即可发送的钉点）
/// ②回补：分页拉齐＋指纹去重不重复落、重拉幂等
/// ③回补降级：中途页失败保留已落部分＋未同步标
///   记，修复后第二轮拉齐；首屏失败整轮失败但标
///   记在位（空开/呈现由 ChatView 承接，不在此层）
/// ④种子：回读决策四路（不存在落行/空行补种/同
///   数认自家/异数仅本地）＋稳定 request_id＋落定
///   后不再重复导入；导入失败落 failed 待重试
@MainActor
final class ImportDemotionAppTests: XCTestCase {

    private var container: ModelContainer!
    private var swiftDataMount = SwiftDataTestMount()
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
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
        context = nil
        await swiftDataMount.release()
        container = nil
        try await super.tearDown()
    }

    // MARK: - 装配

    private func serverSession(
        id: String, messageCount: Int?, runtimeRevision: Int? = nil
    ) -> ServerSession {
        var fields = ["\"id\":\"\(id)\"", "\"started_at\":1000"]
        if let messageCount {
            fields.append("\"message_count\":\(messageCount)")
        }
        if let runtimeRevision {
            fields.append("\"runtime_revision\":\(runtimeRevision)")
        }
        let json = "{" + fields.joined(separator: ",") + "}"
        return try! JSONDecoder().decode(
            ServerSession.self, from: Data(json.utf8)
        )
    }

    private func directoryPage(
        sessions: [String]
    ) -> SessionsPage {
        let json = "{\"sessions\":["
            + sessions.joined(separator: ",") + "]}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    private func directoryRow(
        id: String, title: String?, messageCount: Int?
    ) -> String {
        var fields = ["\"id\":\"\(id)\"", "\"started_at\":1000"]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let messageCount {
            fields.append("\"message_count\":\(messageCount)")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// 一批连续服务端消息（id 1 起、隔 10 秒、问答交替）
    private func messages(
        _ range: ClosedRange<Int>
    ) -> [SessionMessage] {
        range.map { index in
            SessionMessage(
                id: Double(index),
                role: index.isMultiple(of: 2) ? "assistant" : "user",
                content: "消息 \(index)",
                timestamp: 1_700_000_000 + Double(index * 10)
            )
        }
    }

    private func makeThread(
        serverSessionID: String?, unsynced: Bool = false
    ) -> ChatThread {
        let thread = ChatThread(title: "测线程")
        thread.serverSessionID = serverSessionID
        thread.historyUnsynced = unsynced
        context.insert(thread)
        try? context.save()
        return thread
    }

    // MARK: - ① 认领 → 发送闸（不等历史补齐即可发送）

    func testClaimMakesSendGateReadyWithZeroHistoryMovement() async {
        var client = ScriptedSessionsClient()
        client.scriptedPages = [
            "include|0": directoryPage(sessions: [
                directoryRow(
                    id: "oneday-main-serve",
                    title: SideChatStore.mainTitle,
                    messageCount: 243
                ),
            ]),
        ]
        let fetchRecorder = SessionMessageFetchRecorder()
        let importRecorder = SessionImportRecorder()
        client.messageFetchRecorder = fetchRecorder
        client.importRecorder = importRecorder
        let appState = AppState(client: client, demoMode: .connected)
        let ledger = appState.sessionLedger

        // 认领前：身份未定，发送闸关闭
        XCTAssertEqual(ledger.mainSendGate(), .needsIdentity)

        let outcome = await ledger.discoverAndClaimMainline(
            appState: appState
        )
        XCTAssertEqual(
            outcome,
            .claimed(
                sessionID: "oneday-main-serve",
                candidateCount: 1, isArchived: false
            )
        )

        // 认领落定即 ready：发送只认 id 已知——243 条
        // 历史一条没拉、种子一次没导，发送已解门
        XCTAssertEqual(
            ledger.mainSendGate(), .ready(sessionID: "oneday-main-serve")
        )
        XCTAssertEqual(fetchRecorder.pageCallCount, 0)
        XCTAssertEqual(fetchRecorder.fullCallCount, 0)
        XCTAssertTrue(importRecorder.calls.isEmpty)
    }

    // MARK: - ② 回补拉齐＋去重＋幂等

    func testBackfillCompletesWithDedupAndIsIdempotent() async {
        var client = ScriptedSessionsClient()
        client.scriptedSessions = [
            "srv-hist": serverSession(
                id: "srv-hist", messageCount: 150
            ),
        ]
        client.scriptedMessagePages = [
            "srv-hist|0": messages(1...100),
            "srv-hist|100": messages(101...150),
        ]
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(
            serverSessionID: "srv-hist", unsynced: true
        )
        // 本地先有前 10 条（认领前本地副本形态）：回
        // 补必须按指纹认出、不许重复落
        for message in messages(1...10) {
            let entry = ChatEntry(
                role: message.role, content: message.content,
                thread: thread
            )
            entry.createdAt = message.date ?? Date()
            context.insert(entry)
        }
        try? context.save()

        let backfiller = SessionHistoryBackfiller(appState: appState)
        let outcome = await backfiller.backfill(
            thread: thread, context: context
        )

        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(thread.entries.count, 150)
        XCTAssertEqual(
            Set(thread.entries.map(\.content)).count, 150
        )
        XCTAssertFalse(thread.historyUnsynced)
        XCTAssertEqual(thread.historyServerCount, 150)

        // 整轮重拉（下个触发点再排一轮）：指纹对账
        // 全跳过，一条不重复落
        let again = await backfiller.backfill(
            thread: thread, context: context
        )
        XCTAssertEqual(again, .complete)
        XCTAssertEqual(thread.entries.count, 150)
    }

    // MARK: - ③ 回补降级链

    func testBackfillMidPageFailureKeepsPartialThenCompletes() async {
        var client = ScriptedSessionsClient()
        client.scriptedSessions = [
            "srv-hist": serverSession(
                id: "srv-hist", messageCount: 150
            ),
        ]
        // 第二页缺席＝分页失败（桩抛 unreachable）
        client.scriptedMessagePages = [
            "srv-hist|0": messages(1...100),
        ]
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(
            serverSessionID: "srv-hist", unsynced: true
        )
        let backfiller = SessionHistoryBackfiller(appState: appState)

        let first = await backfiller.backfill(
            thread: thread, context: context
        )
        // 已落 100 条保留、未同步标记在位——不整段失败
        XCTAssertEqual(first, .partial)
        XCTAssertEqual(thread.entries.count, 100)
        XCTAssertTrue(thread.historyUnsynced)

        // 服务端恢复后第二轮：从头对账续拉、拉齐清位
        var healedClient = client
        healedClient.scriptedMessagePages["srv-hist|100"] =
            messages(101...150)
        let healedState = AppState(
            client: healedClient, demoMode: .connected
        )
        let second = await SessionHistoryBackfiller(
            appState: healedState
        ).backfill(thread: thread, context: context)
        XCTAssertEqual(second, .complete)
        XCTAssertEqual(thread.entries.count, 150)
        XCTAssertFalse(thread.historyUnsynced)
    }

    func testBackfillFirstPageFailureKeepsUnsyncedMark() async {
        let client = ScriptedSessionsClient()
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(
            serverSessionID: "srv-hist", unsynced: true
        )
        let outcome = await SessionHistoryBackfiller(
            appState: appState
        ).backfill(thread: thread, context: context)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(thread.entries.count, 0)
        XCTAssertTrue(thread.historyUnsynced)
    }

    // MARK: - ③′ 回补分页被拒降级（台账 117，§389）

    func testBackfillPaginationRejectedFallsBackToFullFetch() async {
        var client = ScriptedSessionsClient()
        client.scriptedSessions = [
            "srv-hist": serverSession(
                id: "srv-hist", messageCount: 150
            ),
        ]
        // 分页被服务端以 400 invalid_pagination 拒
        // （服务端分页口径漂移形态）；全量脚本在位
        client.scriptedMessagePageErrors = [
            "srv-hist|0": .serverError(
                endpoint: "服务端会话消息", status: 400,
                code: "invalid_pagination"
            ),
        ]
        client.scriptedFullMessages = [
            "srv-hist": messages(1...150),
        ]
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(
            serverSessionID: "srv-hist", unsynced: true
        )
        let outcome = await SessionHistoryBackfiller(
            appState: appState
        ).backfill(thread: thread, context: context)
        // 降级全量一次拉齐：不许整轮失败、不许留未同步
        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(thread.entries.count, 150)
        XCTAssertFalse(thread.historyUnsynced)
    }

    func testBackfillPaginationRejectedFullFetchAlsoFailsKeepsFailed() async {
        var client = ScriptedSessionsClient()
        client.scriptedSessions = [
            "srv-hist": serverSession(
                id: "srv-hist", messageCount: 150
            ),
        ]
        client.scriptedMessagePageErrors = [
            "srv-hist|0": .serverError(
                endpoint: "服务端会话消息", status: 400,
                code: "invalid_pagination"
            ),
        ]
        // 全量脚本缺席＝全量也失败：回既有失败收尾
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(
            serverSessionID: "srv-hist", unsynced: true
        )
        let outcome = await SessionHistoryBackfiller(
            appState: appState
        ).backfill(thread: thread, context: context)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(thread.entries.count, 0)
        XCTAssertTrue(thread.historyUnsynced)
    }

    // MARK: - ④ 种子同步（回读决策＋稳定 id＋幂等）

    private let seedEntriesFixture: [SeedEntry] = [
        SeedEntry(role: "user", content: "一问", timestamp: 1000),
        SeedEntry(role: "assistant", content: "一答", timestamp: 1001),
    ]

    func testSeedImportLandsWithStableRequestIDAndNoRepeat() async {
        var client = ScriptedSessionsClient()
        client.scriptedMissingSessions = ["oneday-side-seed"]
        let importRecorder = SessionImportRecorder()
        client.importRecorder = importRecorder
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(serverSessionID: "oneday-side-seed")
        thread.seedSyncState = .pending
        try? context.save()

        let syncer = SessionSeedSyncer(appState: appState)
        let state = await syncer.syncSeed(
            thread: thread, seed: seedEntriesFixture,
            title: "测线程", model: nil, context: context
        )

        XCTAssertEqual(state, .syncedTextOnly)
        XCTAssertTrue(thread.serverSeeded)
        XCTAssertEqual(importRecorder.calls.count, 1)
        // request_id 必须是稳定派生值（同种子重试靠
        // 它对账），且围栏修订取新锚 0
        let transcript = SideChatLink.seedTranscript(
            from: seedEntriesFixture
        )
        XCTAssertEqual(
            importRecorder.calls.first?.requestID,
            SideChatLink.seedRequestID(
                sessionID: "oneday-side-seed", messages: transcript
            )
        )
        XCTAssertEqual(importRecorder.calls.first?.expectedRevision, 0)

        // 落定后再触发：态已结清、不再重复导入
        let again = await syncer.syncSeed(
            thread: thread, seed: seedEntriesFixture,
            title: "测线程", model: nil, context: context
        )
        XCTAssertEqual(again, .syncedTextOnly)
        XCTAssertEqual(importRecorder.calls.count, 1)
    }

    func testSeedImportIntoEmptyExistingSessionUsesReadRevision() async {
        var client = ScriptedSessionsClient()
        client.scriptedSessions = [
            "oneday-side-seed": serverSession(
                id: "oneday-side-seed", messageCount: 0,
                runtimeRevision: 7
            ),
        ]
        let importRecorder = SessionImportRecorder()
        client.importRecorder = importRecorder
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(serverSessionID: "oneday-side-seed")
        thread.seedSyncState = .pending
        try? context.save()

        let state = await SessionSeedSyncer(appState: appState)
            .syncSeed(
                thread: thread, seed: seedEntriesFixture,
                title: "测线程", model: nil, context: context
            )
        XCTAssertEqual(state, .syncedTextOnly)
        XCTAssertEqual(importRecorder.calls.count, 1)
        XCTAssertEqual(importRecorder.calls.first?.expectedRevision, 7)
    }

    func testSeedSettlesWhenServerAlreadyHoldsSeedItself() async {
        var client = ScriptedSessionsClient()
        // 服务端条数恰等于种子转录条数＝自家种子先
        // 前已落（回执丢失过的形态）：认账不重导
        client.scriptedSessions = [
            "oneday-side-seed": serverSession(
                id: "oneday-side-seed", messageCount: 2,
                runtimeRevision: 3
            ),
        ]
        let importRecorder = SessionImportRecorder()
        client.importRecorder = importRecorder
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(serverSessionID: "oneday-side-seed")
        thread.seedSyncState = .failed
        try? context.save()

        let state = await SessionSeedSyncer(appState: appState)
            .syncSeed(
                thread: thread, seed: seedEntriesFixture,
                title: "测线程", model: nil, context: context
            )
        XCTAssertEqual(state, .syncedTextOnly)
        XCTAssertTrue(thread.serverSeeded)
        XCTAssertTrue(importRecorder.calls.isEmpty)
    }

    func testSeedStaysLocalWhenServerHoldsOtherContent() async {
        var client = ScriptedSessionsClient()
        client.scriptedSessions = [
            "oneday-side-seed": serverSession(
                id: "oneday-side-seed", messageCount: 9,
                runtimeRevision: 3
            ),
        ]
        let importRecorder = SessionImportRecorder()
        client.importRecorder = importRecorder
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(serverSessionID: "oneday-side-seed")
        thread.seedSyncState = .pending
        try? context.save()

        let state = await SessionSeedSyncer(appState: appState)
            .syncSeed(
                thread: thread, seed: seedEntriesFixture,
                title: "测线程", model: nil, context: context
            )
        // 服务端另有内容：种子不冒进上行（防覆盖/防
        // 串话），本地保留、如实记 localOnly
        XCTAssertEqual(state, .localOnly)
        XCTAssertFalse(thread.serverSeeded)
        XCTAssertTrue(importRecorder.calls.isEmpty)
    }

    func testSeedImportFailureMarksFailedForRetry() async {
        var client = ScriptedSessionsClient()
        client.scriptedMissingSessions = ["oneday-side-seed"]
        // 无 importRecorder＝import 抛错（服务端故障形态）
        let appState = AppState(client: client, demoMode: .connected)
        let thread = makeThread(serverSessionID: "oneday-side-seed")
        thread.seedSyncState = .pending
        try? context.save()

        let state = await SessionSeedSyncer(appState: appState)
            .syncSeed(
                thread: thread, seed: seedEntriesFixture,
                title: "测线程", model: nil, context: context
            )
        XCTAssertEqual(state, .failed)
        XCTAssertTrue(state.needsSyncAttempt)
        XCTAssertEqual(thread.linkFailureCount, 1)
        XCTAssertNotNil(thread.linkLastError)
    }
}
