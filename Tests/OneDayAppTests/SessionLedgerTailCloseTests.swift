import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 第 90 条账本收尾（余三件＋B-07）App 层钉测：
/// ①迁移挂载点——全量 refresh 归档段同步完成后自
/// 动执行待迁计划（改名/归档回写＋对账落定清本地、
/// 失败留痕＋本地值保留、尾步重拉不自触发成环）；
/// ②③持有迁入——主线钦定/归档列/三张关联表由
/// SessionLedger 以 sideChats.* 原键读写（持有者
/// 换人、键不变：裸 UserDefaults 写原键、账本读到
/// 同值；账本写、原键落盘同值）
@MainActor
final class SessionLedgerTailCloseTests: XCTestCase {

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

    private func makeSession(_ json: String) -> ServerSession {
        try! JSONDecoder().decode(
            ServerSession.self, from: Data(json.utf8)
        )
    }

    // MARK: - ① 迁移挂载点：refresh 完成即触发

    func testRefreshTriggersMigrationAndClearsLocals() async throws {
        let recorder = SessionUpdateRecorder()
        var client = ScriptedSessionsClient()
        client.scriptedPages = [
            "exclude|0": makePage(ids: ["s-mig", "s-old"], total: 2),
            "only|0": makePage(ids: [], total: 0),
        ]
        // 服务端回读对账的落定形态：改名后标题、归档后位值
        client.scriptedSessions = [
            "s-mig": makeSession("{\"id\":\"s-mig\",\"title\":\"新标题\"}"),
            "s-old": makeSession("{\"id\":\"s-old\",\"archived\":true}"),
        ]
        client.updateRecorder = recorder
        let appState = AppState(client: client, demoMode: .connected)
        appState.sideChats.setTitleOverride("新标题", for: "s-mig")
        appState.sessionLedger.archive(serverSessionID: "s-old")

        try await appState.sessionLedger.refresh(
            appState: appState, localThreads: [],
            modelContext: context
        )

        // 两项各回写恰一次（尾步重拉的 refresh 不许
        // 二次触发——计划已排空且在飞守卫挡重入）
        XCTAssertEqual(
            recorder.calls.filter { $0.title != nil }.map(\.id),
            ["s-mig"]
        )
        XCTAssertEqual(
            recorder.calls.filter { $0.archived != nil }.map(\.id),
            ["s-old"]
        )
        // 落定清本地：覆盖表删项、归档键删项、无失败留痕
        XCTAssertNil(appState.sideChats.titleOverrides["s-mig"])
        XCTAssertFalse(
            appState.sessionLedger.archivedKeys
                .contains("server:s-old")
        )
        XCTAssertTrue(appState.sessionLedger.migrationFailures.isEmpty)
    }

    func testMigrationFailureLeavesTraceAndKeepsLocals() async throws {
        let recorder = SessionUpdateRecorder()
        var client = ScriptedSessionsClient()
        client.scriptedPages = [
            "exclude|0": makePage(ids: ["s-mig"], total: 1),
            "only|0": makePage(ids: [], total: 0),
        ]
        // 回读标题与覆盖不一致＝未落定
        client.scriptedSessions = [
            "s-mig": makeSession("{\"id\":\"s-mig\",\"title\":\"旧标题\"}"),
        ]
        client.updateRecorder = recorder
        let appState = AppState(client: client, demoMode: .connected)
        appState.sideChats.setTitleOverride("新标题", for: "s-mig")

        try await appState.sessionLedger.refresh(
            appState: appState, localThreads: [],
            modelContext: context
        )

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(
            appState.sessionLedger.migrationFailures.count, 1
        )
        XCTAssertEqual(
            appState.sideChats.titleOverrides["s-mig"], "新标题"
        )
    }

    // MARK: - ②③ 持有迁入：原键同值（双轨回写）

    func testLedgerReadsAndWritesLegacyKeys() throws {
        let defaults = UserDefaults.standard
        let keys = [
            "sideChats.mainThreadID",
            "sideChats.mainServerSessionID",
            "sideChats.mainServerConfirmed",
            "sideChats.mainServerSeeded",
            "sideChats.archivedKeys",
            "sideChats.ideaThreadIDs",
            "sideChats.goalThreadIDs",
            "sideChats.feedDiscussPostIDs",
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        defer { for key in keys { defaults.removeObject(forKey: key) } }

        // 裸写原键（旧版 App 的落盘形态）→ 账本读到同值
        let mainID = UUID()
        defaults.set(mainID.uuidString, forKey: "sideChats.mainThreadID")
        defaults.set("srv-main", forKey: "sideChats.mainServerSessionID")
        defaults.set(true, forKey: "sideChats.mainServerConfirmed")
        defaults.set(
            ["server:s-a", "local:\(UUID().uuidString)"],
            forKey: "sideChats.archivedKeys"
        )
        let ledger = SessionLedger(persisted: true)
        XCTAssertEqual(ledger.mainThreadID, mainID)
        XCTAssertEqual(ledger.mainServerSessionID, "srv-main")
        XCTAssertTrue(ledger.mainServerConfirmed)
        XCTAssertTrue(ledger.archivedKeys.contains("server:s-a"))

        // 账本写 → 原键落盘同值（回滚读同键即恢复）
        let thread = UUID()
        ledger.linkThread(thread, forGoalID: "g-1")
        let rawGoal = defaults.data(forKey: "sideChats.goalThreadIDs")
        let decodedGoal = try JSONDecoder().decode(
            [String: String].self, from: XCTUnwrap(rawGoal)
        )
        XCTAssertEqual(decodedGoal["g-1"], thread.uuidString)
        ledger.archive(serverSessionID: "s-b")
        XCTAssertTrue(
            (defaults.stringArray(forKey: "sideChats.archivedKeys") ?? [])
                .contains("server:s-b")
        )
        ledger.setMainServerSessionID("srv-next")
        XCTAssertEqual(
            defaults.string(forKey: "sideChats.mainServerSessionID"),
            "srv-next"
        )
    }
}
