import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 主线发现与认领（根治版包 1，DESIGN §330）App 层
/// 全旅程钉测：脚本目录客户端＋内存账本——①登录后
/// 拉目录认领既有主线（id/确认位/认领记录落定）②
/// 归档主线认领保持归档（不发解档写）③服务端无主
/// 线回冷启动信号且认领本程不铸造④删除账在册会话
/// 不被认领复活⑤重新发现改认失效指针/现任在册无
/// 事⑥身份键 Keychain 迁移（旧值搬运/双轨同写/降
/// 级往返末写胜）
/// 注：候选标题取 SideChatStore.mainTitle 与生产同
/// 源（随 locale 变——CI 英文环境为 "Main conver-
/// sation"），不写死「主线」字面（§220 同源口径）
@MainActor
final class MainlineClaimAppTests: XCTestCase {

    private var container: ModelContainer!
    private var swiftDataMount = SwiftDataTestMount()
    private var context: ModelContext!
    private let queueKey = "sessionDeletions.pendingQueue"

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
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: queueKey)
        context = nil
        await swiftDataMount.release()
        container = nil
        try await super.tearDown()
    }

    // MARK: - 装配

    private func sessionJSON(
        id: String, title: String?, messageCount: Int?,
        archived: Bool, ended: Double? = nil
    ) -> String {
        var fields = ["\"id\":\"\(id)\""]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let messageCount {
            fields.append("\"message_count\":\(messageCount)")
        }
        fields.append("\"archived\":\(archived ? 1 : 0)")
        fields.append("\"started_at\":1000")
        if let ended { fields.append("\"ended_at\":\(ended)") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func makePage(
        sessions: [String], total: Int? = nil
    ) -> SessionsPage {
        var json = "{\"sessions\":["
            + sessions.joined(separator: ",") + "]"
        if let total { json += ",\"total\":\(total)" }
        json += "}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    private func makeAppState(
        pages: [String: SessionsPage],
        recorder: SessionUpdateRecorder? = nil
    ) -> AppState {
        var client = ScriptedSessionsClient()
        client.scriptedPages = pages
        client.updateRecorder = recorder
        return AppState(client: client, demoMode: .connected)
    }

    // MARK: - ① 认领既有主线

    func testClaimExistingMainlineAfterLogin() async {
        let appState = makeAppState(pages: [
            "include|0": makePage(sessions: [
                sessionJSON(
                    id: "srv-side-1", title: "旁聊",
                    messageCount: 3, archived: false
                ),
                sessionJSON(
                    id: "oneday-main-serve", title: SideChatStore.mainTitle,
                    messageCount: 243, archived: false, ended: 1700
                ),
            ], total: 2),
        ])
        let ledger = appState.sessionLedger
        XCTAssertNil(ledger.mainServerSessionID)

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
        XCTAssertEqual(ledger.mainServerSessionID, "oneday-main-serve")
        XCTAssertTrue(ledger.mainServerConfirmed)
        XCTAssertEqual(ledger.mainClaimRecord?.sessionID, "oneday-main-serve")
        XCTAssertEqual(ledger.mainClaimRecord?.messageCount, 243)
        XCTAssertEqual(ledger.mainClaimRecord?.lastActivityAt, 1700)
        XCTAssertEqual(ledger.mainClaimRecord?.isArchived, false)
    }

    func testClaimShortCircuitsWhenLocalIDKnown() async {
        let appState = makeAppState(pages: [:])
        let ledger = appState.sessionLedger
        ledger.setMainServerSessionID("oneday-main-local")

        let outcome = await ledger.discoverAndClaimMainline(
            appState: appState
        )

        XCTAssertEqual(outcome, .alreadyKnown)
        XCTAssertEqual(ledger.mainServerSessionID, "oneday-main-local")
        XCTAssertNil(ledger.mainClaimRecord)
    }

    // MARK: - ② 归档主线：认领保持归档

    func testClaimArchivedMainlineKeepsArchived() async {
        let recorder = SessionUpdateRecorder()
        let appState = makeAppState(
            pages: [
                "include|0": makePage(sessions: [
                    sessionJSON(
                        id: "oneday-main-archived", title: SideChatStore.mainTitle,
                        messageCount: 57, archived: true, ended: 900
                    ),
                ], total: 1),
            ],
            recorder: recorder
        )
        let ledger = appState.sessionLedger

        let outcome = await ledger.discoverAndClaimMainline(
            appState: appState
        )

        XCTAssertEqual(
            outcome,
            .claimed(
                sessionID: "oneday-main-archived",
                candidateCount: 1, isArchived: true
            )
        )
        XCTAssertEqual(ledger.mainClaimRecord?.isArchived, true)
        // 认领只定指针：不许发任何服务端写（解档归打开动作）
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    // MARK: - ③ 服务端无主线：冷启动信号＋不铸造

    func testNoMainlineOnServerYieldsColdStartSignal() async {
        let appState = makeAppState(pages: [
            "include|0": makePage(sessions: [
                sessionJSON(
                    id: "srv-side-1", title: "旁聊",
                    messageCount: 3, archived: false
                ),
            ], total: 1),
        ])
        let ledger = appState.sessionLedger

        let outcome = await ledger.discoverAndClaimMainline(
            appState: appState
        )

        XCTAssertEqual(outcome, .noCandidateOnServer)
        // 认领本程永不铸造：id 仍为空，铸造归调用方冷启动
        XCTAssertNil(ledger.mainServerSessionID)
        XCTAssertFalse(ledger.mainServerConfirmed)
        XCTAssertNil(ledger.mainClaimRecord)
    }

    // MARK: - ④ 防复活：删除账在册不认领

    func testPendingDeletionSessionIsNotResurrected() async {
        let appState = makeAppState(pages: [
            "include|0": makePage(sessions: [
                sessionJSON(
                    id: "oneday-main-dead", title: SideChatStore.mainTitle,
                    messageCount: 12, archived: false, ended: 800
                ),
            ], total: 1),
        ])
        let ledger = appState.sessionLedger
        // 删除挂账：后台删除桩拖住落定，会话在删除账在册
        ledger.deletions.deleteAction = { _, _ in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return .verified
        }
        ledger.deletions.begin(
            sessionID: "oneday-main-dead", title: SideChatStore.mainTitle,
            appState: appState, modelContext: context
        )
        XCTAssertTrue(
            ledger.deletions.queue.sessionIDs
                .contains("oneday-main-dead")
        )

        let outcome = await ledger.discoverAndClaimMainline(
            appState: appState
        )

        XCTAssertEqual(outcome, .noCandidateOnServer)
        XCTAssertNil(ledger.mainServerSessionID)
        XCTAssertNil(ledger.mainClaimRecord)
    }

    // MARK: - ⑤ 重新发现

    func testRediscoveryReplacesStalePointer() async {
        let appState = makeAppState(pages: [
            "include|0": makePage(sessions: [
                sessionJSON(
                    id: "oneday-main-real", title: SideChatStore.mainTitle,
                    messageCount: 88, archived: false, ended: 1500
                ),
            ], total: 1),
        ])
        let ledger = appState.sessionLedger
        ledger.setMainServerSessionID("oneday-main-stale")

        let outcome = await ledger.rediscoverMainline(
            appState: appState
        )

        XCTAssertEqual(
            outcome,
            .claimed(
                sessionID: "oneday-main-real",
                candidateCount: 1, isArchived: false
            )
        )
        XCTAssertEqual(ledger.mainServerSessionID, "oneday-main-real")
        XCTAssertEqual(ledger.mainClaimRecord?.sessionID, "oneday-main-real")
    }

    func testRediscoveryKeepsKnownPointer() async {
        let appState = makeAppState(pages: [
            "include|0": makePage(sessions: [
                sessionJSON(
                    id: "oneday-main-real", title: SideChatStore.mainTitle,
                    messageCount: 88, archived: false, ended: 1500
                ),
            ], total: 1),
        ])
        let ledger = appState.sessionLedger
        ledger.setMainServerSessionID("oneday-main-real")

        let outcome = await ledger.rediscoverMainline(
            appState: appState
        )

        XCTAssertEqual(outcome, .alreadyKnown)
        XCTAssertEqual(ledger.mainServerSessionID, "oneday-main-real")
        XCTAssertNil(ledger.mainClaimRecord)
    }

    // MARK: - ⑥ 身份键迁移（Keychain 存放整改）

    private func makeSuite() -> UserDefaults {
        let suite = UserDefaults(
            suiteName: "claim-migration-\(UUID().uuidString)"
        )!
        return suite
    }

    func testIdentityMigrationMovesLegacyValues() {
        let suite = makeSuite()
        let threadID = UUID()
        suite.set(
            threadID.uuidString, forKey: "sideChats.mainThreadID"
        )
        suite.set("srv-legacy", forKey: "sideChats.mainServerSessionID")
        suite.set(true, forKey: "sideChats.mainServerConfirmed")
        let store = MemoryIdentityValueStore()

        let ledger = SessionLedger(
            defaults: suite, identityStore: store
        )

        XCTAssertEqual(ledger.mainThreadID, threadID)
        XCTAssertEqual(ledger.mainServerSessionID, "srv-legacy")
        XCTAssertTrue(ledger.mainServerConfirmed)
        // 搬运落点：身份存储持有同值
        XCTAssertEqual(
            store.string(forKey: IdentityKey.mainServerSessionID),
            "srv-legacy"
        )
        XCTAssertEqual(
            store.string(forKey: IdentityKey.mainThreadID),
            threadID.uuidString
        )
        XCTAssertTrue(
            store.bool(forKey: IdentityKey.mainServerConfirmed)
        )
    }

    func testIdentityMigrationIdempotentAndDualTrackWrites() {
        let suite = makeSuite()
        suite.set("srv-legacy", forKey: "sideChats.mainServerSessionID")
        let store = MemoryIdentityValueStore()
        let first = SessionLedger(
            defaults: suite, identityStore: store
        )
        first.setMainServerSessionID("srv-new")

        // 写路径双轨：身份存储与旧键同值（回滚读同键即恢复）
        XCTAssertEqual(
            store.string(forKey: IdentityKey.mainServerSessionID),
            "srv-new"
        )
        XCTAssertEqual(
            suite.string(forKey: "sideChats.mainServerSessionID"),
            "srv-new"
        )

        // 二次构造（重复搬运）：值不变、不回退
        let second = SessionLedger(
            defaults: suite, identityStore: store
        )
        XCTAssertEqual(second.mainServerSessionID, "srv-new")
        XCTAssertEqual(
            store.string(forKey: IdentityKey.mainServerSessionID),
            "srv-new"
        )
    }

    func testIdentityMigrationDowngradeRoundTripLastWriteWins() {
        let suite = makeSuite()
        suite.set("srv-v1", forKey: "sideChats.mainServerSessionID")
        let store = MemoryIdentityValueStore()
        _ = SessionLedger(defaults: suite, identityStore: store)
        XCTAssertEqual(
            store.string(forKey: IdentityKey.mainServerSessionID),
            "srv-v1"
        )

        // 降级往返：旧版 App 期间只写旧键——再升级时
        // 旧值是最后写入值，搬运以它覆写（末写胜）
        suite.set(
            "srv-from-old-app", forKey: "sideChats.mainServerSessionID"
        )
        let ledger = SessionLedger(
            defaults: suite, identityStore: store
        )
        XCTAssertEqual(ledger.mainServerSessionID, "srv-from-old-app")
        XCTAssertEqual(
            store.string(forKey: IdentityKey.mainServerSessionID),
            "srv-from-old-app"
        )
    }
}
