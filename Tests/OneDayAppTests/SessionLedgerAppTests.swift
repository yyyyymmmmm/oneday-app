import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 第 67 条会话账本包一（2026-11-15）App 层钉测：
/// 真实装配链——脚本客户端（SessionCatalogGuard-
/// Tests 的 ScriptedSessionsClient）＋SwiftData 容
/// 器（§184 租约口径）＋AllConversationsStore.load
/// 真路。钉：账本 refresh 落位两段＋liveSet 连完整
/// 性交出、目录壳转发、收养读账本、抽屉可见段刷新
@MainActor
final class SessionLedgerAppTests: XCTestCase {

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

    private func makePage(
        ids: [String], total: Int?
    ) -> SessionsPage {
        var json = "{\"sessions\":["
            + ids.map { "{\"id\":\"\($0)\"}" }
                .joined(separator: ",")
            + "]"
        if let total { json += ",\"total\":\(total)" }
        json += "}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    private func makeAppState(
        pages: [String: SessionsPage]
    ) -> AppState {
        var client = ScriptedSessionsClient()
        client.scriptedPages = pages
        return AppState(client: client, demoMode: .connected)
    }

    @discardableResult
    private func makeThread(sessionID: String?) throws -> ChatThread {
        let thread = ChatThread(title: "测试线程")
        thread.serverSessionID = sessionID
        context.insert(thread)
        try context.save()
        return thread
    }

    private func fetchThreads() throws -> [ChatThread] {
        try context.fetch(FetchDescriptor<ChatThread>())
    }

    // MARK: - refresh 落位与 liveSet

    func testRefreshPopulatesLedgerAndLiveSet() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ["s-1", "s-2"], total: 2),
            "only|0": makePage(ids: ["s-3"], total: 1),
        ])
        let thread = try makeThread(sessionID: "s-1")
        let store = AllConversationsStore()
        await store.load(
            appState: appState,
            localThreads: try fetchThreads(),
            modelContext: context
        )
        XCTAssertNil(store.loadError)
        let ledger = appState.sessionLedger
        XCTAssertEqual(ledger.visibleSessions.map(\.id), ["s-1", "s-2"])
        XCTAssertEqual(ledger.archivedSessions.map(\.id), ["s-3"])
        XCTAssertTrue(ledger.hasLoaded)
        XCTAssertTrue(ledger.hasLoadedFull)
        let live = ledger.liveSet()
        XCTAssertTrue(live.completeness.isComplete)
        XCTAssertEqual(live.ids, ["s-1", "s-2", "s-3"])
        // 合并名单：s-1 与其线程合并为一条、其余为
        // 服务端行；管理页投影与账本段名单同集
        let records = ledger.records(
            appState: appState, localThreads: try fetchThreads()
        )
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(
            records.first { $0.serverSessionID == "s-1" }?
                .localThreadID,
            thread.id
        )
        XCTAssertEqual(
            ledger.managementVisible(
                appState: appState,
                localThreads: try fetchThreads()
            ).map(\.id),
            ["s-1", "s-2"]
        )
        XCTAssertEqual(
            ledger.managementArchived(
                appState: appState,
                localThreads: try fetchThreads()
            ).map(\.id),
            ["s-3"]
        )
        // 目录壳转发读同源
        XCTAssertEqual(
            appState.sessionLedger.visibleSessions
                .map(\.id),
            ["s-1", "s-2"]
        )
    }

    /// 名单不完整：liveSet 只交出 incomplete（带原
    /// 因），对账不删线程（闸的接口级形态）
    func testRefreshIncompleteGatesLiveSet() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ["s-1"], total: 5),
            "only|0": makePage(ids: [], total: 0),
        ])
        let victim = try makeThread(
            sessionID: "oneday-side-victim"
        )
        let store = AllConversationsStore()
        await store.load(
            appState: appState,
            localThreads: try fetchThreads(),
            modelContext: context
        )
        let live = appState.sessionLedger.liveSet()
        guard case .incomplete = live.completeness else {
            XCTFail("名单不完整时 liveSet 必须交出 incomplete")
            return
        }
        XCTAssertTrue(
            try fetchThreads().contains { $0.id == victim.id }
        )
    }

    // MARK: - 名单写回面（原目录壳转发，第 90 条收尾删壳后直连账本）

    func testLedgerPublishAndRemoveVisible() throws {
        let appState = makeAppState(pages: [:])
        let session = try JSONDecoder().decode(
            ServerSession.self,
            from: Data("{\"id\":\"s-x\"}".utf8)
        )
        appState.sessionLedger.publishVisible([session])
        XCTAssertEqual(
            appState.sessionLedger.visibleSessions.map(\.id),
            ["s-x"]
        )
        XCTAssertTrue(appState.sessionLedger.hasLoaded)
        appState.sessionLedger.removeSession(sessionID: "s-x")
        XCTAssertTrue(appState.sessionLedger.visibleSessions.isEmpty)
    }

    // MARK: - 收养读账本

    /// 两段齐全后收养名单读账本（含已归档段）：脚
    /// 本客户端没有 include 页——若回落现拉必抛错
    /// 得 nil，本例以此区分两路
    func testAdoptionSessionsReadLedgerWhenLoaded() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ["s-1"], total: 1),
            "only|0": makePage(ids: ["s-arch"], total: 1),
        ])
        let store = AllConversationsStore()
        await store.load(
            appState: appState,
            localThreads: try fetchThreads(),
            modelContext: context
        )
        let sessions = await appState.sessionLedger
            .adoptionSessions(appState: appState)
        XCTAssertEqual(
            Set(sessions?.map(\.id) ?? []), ["s-1", "s-arch"]
        )
    }

    // MARK: - 可见段刷新（抽屉路）

    func testRefreshVisibleLoadsVisibleSegmentOnly() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(
                ids: ["oneday-ai-new", "s-2"], total: 2
            ),
        ])
        await appState.sessionLedger.refreshVisible(
            appState: appState,
            localThreads: try fetchThreads()
        )
        let ledger = appState.sessionLedger
        XCTAssertTrue(ledger.hasLoaded)
        XCTAssertFalse(ledger.hasLoadedFull)
        XCTAssertEqual(
            ledger.visibleSessions.map(\.id),
            ["oneday-ai-new", "s-2"]
        )
        // 未收养 AI 旁聊经账本投影进抽屉行集（s-2
        // 无出生证明、归 Hermes 频道，不进旁聊区）
        let rows = ledger.drawerSideRows(
            appState: appState, localThreads: try fetchThreads()
        )
        XCTAssertEqual(
            rows.map(\.serverSessionID), ["oneday-ai-new"]
        )
        XCTAssertEqual(
            LedgerProjection.drawerUnadoptedRows(
                ledger.records(
                    appState: appState,
                    localThreads: try fetchThreads()
                )
            ).map(\.serverSessionID),
            ["oneday-ai-new"]
        )
    }
}
