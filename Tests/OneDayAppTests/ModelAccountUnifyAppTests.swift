import OneDayCore
import XCTest
@testable import OneDayApp

/// 模型账合一（§227，诊断题三）App 侧验收：迁账语
/// 义（AppState.migrateSessionModelChoice）与枢纽/
/// 胶囊账面同源（两面派生入参落同一键、枢纽写账胶
/// 囊认账）。AppState 走演示档＋离线桩构造（账本初
/// 始为空、不触网）；落盘键 chatModelBySession 在
/// setUp/tearDown 保存恢复，不污染测试宿主档案。
@MainActor
final class ModelAccountUnifyAppTests: XCTestCase {

    private var savedChoicesData: Data?
    private var savedLegacyModelID: String?

    override func setUp() {
        super.setUp()
        savedChoicesData = UserDefaults.standard.data(
            forKey: "chatModelBySession"
        )
        savedLegacyModelID = UserDefaults.standard.string(forKey: "chatModelID")
        UserDefaults.standard.removeObject(forKey: "chatModelBySession")
        UserDefaults.standard.removeObject(forKey: "chatModelID")
    }

    override func tearDown() {
        if let savedChoicesData {
            UserDefaults.standard.set(
                savedChoicesData, forKey: "chatModelBySession"
            )
        } else {
            UserDefaults.standard.removeObject(forKey: "chatModelBySession")
        }
        if let savedLegacyModelID {
            UserDefaults.standard.set(savedLegacyModelID, forKey: "chatModelID")
        } else {
            UserDefaults.standard.removeObject(forKey: "chatModelID")
        }
        super.tearDown()
    }

    private func makeState() -> AppState {
        AppState(client: DemoHermesClient(), demoMode: .connected)
    }

    private func key(
        _ ids: (serverSessionID: String?, threadID: UUID?)
    ) -> String {
        AppState.sessionModelKey(
            serverSessionID: ids.serverSessionID, threadID: ids.threadID
        )
    }

    private func publishSession(
        _ state: AppState, id: String, model: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id, "model": model
        ])
        let session = try JSONDecoder().decode(ServerSession.self, from: data)
        state.serverSessionCatalog.publish(visible: [session])
    }

    // MARK: - Read-time fossil rule

    func testMainlineFossilFallsBackToDemoDefault() async throws {
        let state = makeState()
        await state.refreshModelCatalog()
        let mainID = "oneday-main-fossil"
        state.sideChats.setMainServerSessionID(mainID)
        state.selectSessionModel(
            ChatModelChoice(model: "deepseek-flash", providerField: nil),
            serverSessionID: mainID, threadID: nil
        )
        try publishSession(state, id: mainID, model: "deepseek-flash")

        XCTAssertEqual(
            state.sessionModelChoice(serverSessionID: mainID, threadID: nil).model,
            ModelDisplayNames.canonicalID(for: "deepseek-chat")
        )
    }

    func testMainlineDifferentStoredChoiceIsNotFiltered() async throws {
        let state = makeState()
        await state.refreshModelCatalog()
        let mainID = "oneday-main-fossil"
        state.sideChats.setMainServerSessionID(mainID)
        state.selectSessionModel(
            ChatModelChoice(model: "deepseek-v4-pro", providerField: "custom"),
            serverSessionID: mainID, threadID: nil
        )
        try publishSession(state, id: mainID, model: "deepseek-flash")

        XCTAssertEqual(
            state.sessionModelChoice(serverSessionID: mainID, threadID: nil).model,
            "deepseek-v4-pro"
        )
    }

    func testSideChatMatchingServerModelIsNotFiltered() async throws {
        let state = makeState()
        await state.refreshModelCatalog()
        let mainID = "oneday-main-fossil"
        let sideID = "oneday-side-fossil"
        state.sideChats.setMainServerSessionID(mainID)
        state.selectSessionModel(
            ChatModelChoice(model: "deepseek-v4-pro", providerField: "custom"),
            serverSessionID: sideID, threadID: nil
        )
        try publishSession(state, id: sideID, model: "deepseek-v4-pro")

        XCTAssertEqual(
            state.sessionModelChoice(serverSessionID: sideID, threadID: nil).model,
            "deepseek-v4-pro"
        )
    }

    // MARK: - 账面同源（题三验收主断言）

    /// 分叉实景：主线线程绑定收养会话 A、store 副本
    /// 还停在旧值 B。枢纽派生与胶囊派生必须落同一
    /// 键；枢纽经该键写账后，胶囊按自家派生键读到的
    /// 正是同一笔——「枢纽改模型、发送/显示不认」在
    /// 账面层不许再发生
    func testHubWriteLandsInCapsuleKeyUnderFork() {
        let state = makeState()
        let threadID = UUID()
        let hubIDs = SessionModelAccount.mainlineAccountIDs(
            mainThreadServerSessionID: "oneday-main-adopted",
            mainThreadID: threadID,
            mainServerSessionID: "oneday-main-stale"
        )
        let capsuleIDs = SessionModelAccount.accountIDs(
            threadServerSessionID: "oneday-main-adopted",
            threadID: threadID, isMainThread: true,
            mainServerSessionID: "oneday-main-stale"
        )
        XCTAssertEqual(key(hubIDs), "s:oneday-main-adopted")
        XCTAssertEqual(key(hubIDs), key(capsuleIDs))

        // 枢纽写账（用户在枢纽点选）
        let picked = ChatModelChoice(
            model: "claude-sonnet-4-6", providerField: "custom"
        )
        state.selectSessionModel(
            picked, serverSessionID: hubIDs.serverSessionID,
            threadID: hubIDs.threadID
        )
        // 胶囊键下正是这一笔（账面同源）
        XCTAssertEqual(
            state.sessionModelChoices[key(capsuleIDs)]?.model,
            "claude-sonnet-4-6"
        )
        // 两面读数同值（演示档无分组时同走回落口径，
        // 亦不许一面一值）
        XCTAssertEqual(
            state.sessionModelChoice(
                serverSessionID: hubIDs.serverSessionID,
                threadID: hubIDs.threadID
            ),
            state.sessionModelChoice(
                serverSessionID: capsuleIDs.serverSessionID,
                threadID: capsuleIDs.threadID
            )
        )
        // 链接对齐落定后（store 副本与线程绑定同值），
        // 以 store 副本取键（发送计划的会话 id 来源）
        // 派生出的仍是同一本账
        let alignedIDs = SessionModelAccount.accountIDs(
            threadServerSessionID: "oneday-main-adopted",
            threadID: threadID, isMainThread: true,
            mainServerSessionID: "oneday-main-adopted"
        )
        XCTAssertEqual(key(alignedIDs), key(capsuleIDs))
    }

    // MARK: - 迁账语义

    /// 改绑/收养：旧键存量选择迁到新键，源账保留
    func testMigrationMovesChoiceAndKeepsSource() {
        let state = makeState()
        let picked = ChatModelChoice(
            model: "claude-sonnet-4-6", providerField: "custom"
        )
        state.selectSessionModel(
            picked, serverSessionID: "oneday-main-old", threadID: nil
        )
        let moved = state.migrateSessionModelChoice(
            fromServerSessionID: "oneday-main-old",
            toServerSessionID: "oneday-main-adopted"
        )
        XCTAssertTrue(moved)
        XCTAssertEqual(
            state.sessionModelChoices["s:oneday-main-adopted"]?.model,
            "claude-sonnet-4-6"
        )
        XCTAssertEqual(
            state.sessionModelChoices["s:oneday-main-old"]?.model,
            "claude-sonnet-4-6"
        )
    }

    /// 目标键已有自己的存量 → 不覆盖、不迁
    func testMigrationDoesNotOverwriteOccupiedTarget() {
        let state = makeState()
        state.selectSessionModel(
            ChatModelChoice(model: "model-old", providerField: "custom"),
            serverSessionID: "oneday-main-old", threadID: nil
        )
        state.selectSessionModel(
            ChatModelChoice(model: "model-new", providerField: "custom"),
            serverSessionID: "oneday-main-adopted", threadID: nil
        )
        let moved = state.migrateSessionModelChoice(
            fromServerSessionID: "oneday-main-old",
            toServerSessionID: "oneday-main-adopted"
        )
        XCTAssertFalse(moved)
        XCTAssertEqual(
            state.sessionModelChoices["s:oneday-main-adopted"]?.model,
            "model-new"
        )
    }

    /// 源键无存量 / 同键 / 空 id → 不动账
    func testMigrationNoOps() {
        let state = makeState()
        XCTAssertFalse(
            state.migrateSessionModelChoice(
                fromServerSessionID: "oneday-main-old",
                toServerSessionID: "oneday-main-adopted"
            )
        )
        state.selectSessionModel(
            ChatModelChoice(model: "model-old", providerField: "custom"),
            serverSessionID: "oneday-main-old", threadID: nil
        )
        XCTAssertFalse(
            state.migrateSessionModelChoice(
                fromServerSessionID: "oneday-main-old",
                toServerSessionID: "oneday-main-old"
            )
        )
        XCTAssertFalse(
            state.migrateSessionModelChoice(
                fromServerSessionID: nil,
                toServerSessionID: "oneday-main-adopted"
            )
        )
        XCTAssertFalse(
            state.migrateSessionModelChoice(
                fromServerSessionID: "oneday-main-old",
                toServerSessionID: ""
            )
        )
        XCTAssertNil(state.sessionModelChoices["s:oneday-main-adopted"])
    }
}
