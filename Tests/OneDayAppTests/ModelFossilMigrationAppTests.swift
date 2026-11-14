import OneDayCore
import XCTest
@testable import OneDayApp

/// 主线模型化石一次性迁移（§216.2）App 侧验收：
/// 裁决执行（AppState.adjudicate…）的动账形态与
/// runner 的一次性标记闸序。存量图按用户实机推演
/// 复刻：钦定副本键（收养会话）存 deepseek-flash
/// 化石、实看主线线程绑定另一 id、其账无存量。
/// 落盘键 chatModelBySession 与标记键在 setUp/
/// tearDown 保存恢复，不污染测试宿主档案。
/// 解析环境钉死说明：演示档分组为空、解析走历史
/// 回落口（chatModelID＞演示默认）——演示默认
/// deepseek-chat 的 canonical 恰是 deepseek-flash，
/// 会污染「线程账现行解析值」，故各测试以
/// chatModelID 显式钉住线程账解析值（该键同在
/// setUp/tearDown 保存恢复）。
@MainActor
final class ModelFossilMigrationAppTests: XCTestCase {

    private let storeID = "oneday-main-bfb4e3ed-adopted"
    private let threadBindingID = "oneday-main-3e3108d3-stale"
    private let sideID = "oneday-side-ba9ed7b3-live"
    private let threadID = UUID(
        uuidString: "33333333-3333-3333-3333-333333333333"
    )!
    private let handledKey = "mainlineModelFossilMigrationHandled"

    private var savedChoicesData: Data?
    private var savedLegacyModelID: String?
    private var savedHandled: Bool?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedChoicesData = defaults.data(forKey: "chatModelBySession")
        savedLegacyModelID = defaults.string(forKey: "chatModelID")
        savedHandled = defaults.object(forKey: handledKey) as? Bool
        defaults.removeObject(forKey: "chatModelBySession")
        defaults.removeObject(forKey: "chatModelID")
        defaults.removeObject(forKey: handledKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        if let savedChoicesData {
            defaults.set(savedChoicesData, forKey: "chatModelBySession")
        } else {
            defaults.removeObject(forKey: "chatModelBySession")
        }
        if let savedLegacyModelID {
            defaults.set(savedLegacyModelID, forKey: "chatModelID")
        } else {
            defaults.removeObject(forKey: "chatModelID")
        }
        if let savedHandled {
            defaults.set(savedHandled, forKey: handledKey)
        } else {
            defaults.removeObject(forKey: handledKey)
        }
        super.tearDown()
    }

    private func makeState() -> AppState {
        AppState(client: FailingHermesClient(), demoMode: .connected)
    }

    private var storeKey: String { "s:\(storeID)" }
    private var threadKey: String { "s:\(threadBindingID)" }
    private var sideKey: String { "s:\(sideID)" }

    /// 复刻实机存量：钦定键化石＋旁聊账同值条目
    /// （旁聊真选 deepseek，迁移绝不许殃及）
    private func seedFossil(_ state: AppState) {
        state.selectSessionModel(
            ChatModelChoice(model: "deepseek-flash", providerField: nil),
            serverSessionID: storeID, threadID: nil
        )
        state.selectSessionModel(
            ChatModelChoice(model: "deepseek-flash", providerField: nil),
            serverSessionID: sideID, threadID: nil
        )
    }

    private func adjudicate(
        _ state: AppState, server: String?
    ) -> MainlineModelFossilMigration.Action {
        state.adjudicateMainlineModelFossilMigration(
            threadServerSessionID: threadBindingID,
            threadID: threadID,
            storeServerSessionID: storeID,
            serverReportedModel: server
        )
    }

    // MARK: - 命中处置

    /// 命中清条：钦定键化石删除、合一后两面同值，
    /// 旁聊账同值条目原样保留
    func testAdjudicateClearsFossilAndFacesAgree() {
        let state = makeState()
        seedFossil(state)
        UserDefaults.standard.set(
            "claude-sonnet-4-6", forKey: "chatModelID"
        )
        let action = adjudicate(state, server: "deepseek-flash")
        XCTAssertEqual(action, .clearStoreEntry)
        XCTAssertNil(state.sessionModelChoices[storeKey])
        // 旁聊账不受殃及（同为 deepseek 也不在射程）
        XCTAssertEqual(
            state.sessionModelChoices[sideKey]?.model,
            "deepseek-flash"
        )
        // 合一账（钦定键）与线程账读数同值——两面一致
        XCTAssertEqual(
            state.sessionModelChoice(
                serverSessionID: storeID, threadID: threadID
            ),
            state.sessionModelChoice(
                serverSessionID: threadBindingID, threadID: threadID
            )
        )
    }

    /// 命中迁入：线程账有真选择（claude 存量）→ 覆
    /// 盖钦定键化石，真选择成为合一账存量、源保留
    func testAdjudicateAdoptsThreadStoredChoice() {
        let state = makeState()
        seedFossil(state)
        state.selectSessionModel(
            ChatModelChoice(
                model: "claude-sonnet-4-6", providerField: "custom"
            ),
            serverSessionID: threadBindingID, threadID: nil
        )
        UserDefaults.standard.set(
            "claude-sonnet-4-6", forKey: "chatModelID"
        )
        let action = adjudicate(state, server: "deepseek-flash")
        XCTAssertEqual(action, .adoptThreadStored)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "claude-sonnet-4-6"
        )
        XCTAssertEqual(
            state.sessionModelChoices[threadKey]?.model,
            "claude-sonnet-4-6"
        )
        XCTAssertEqual(
            state.sessionModelChoices[sideKey]?.model,
            "deepseek-flash"
        )
    }

    // MARK: - 不命中

    /// 用户真选 deepseek 且线程账解析同值 → 两面本
    /// 已一致，不动账（真选不殃及的主线形态）
    func testAdjudicateKeepsGenuineDeepSeekPick() {
        let state = makeState()
        seedFossil(state)
        state.selectSessionModel(
            ChatModelChoice(model: "deepseek-flash", providerField: nil),
            serverSessionID: threadBindingID, threadID: nil
        )
        UserDefaults.standard.set(
            "deepseek-flash", forKey: "chatModelID"
        )
        let action = adjudicate(state, server: "deepseek-flash")
        XCTAssertEqual(action, .keep)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "deepseek-flash"
        )
    }

    /// 副本同值（单账常态）→ 即使条目与服务端行同
    /// 值也不动
    func testAdjudicateKeepsWhenConverged() {
        let state = makeState()
        seedFossil(state)
        let action = state.adjudicateMainlineModelFossilMigration(
            threadServerSessionID: storeID,
            threadID: threadID,
            storeServerSessionID: storeID,
            serverReportedModel: "deepseek-flash"
        )
        XCTAssertEqual(action, .keep)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "deepseek-flash"
        )
    }

    /// 服务端行 model 是别的值 → 钦定键条目不是该
    /// 会话化石，不动
    func testAdjudicateKeepsWhenServerModelDiffers() {
        let state = makeState()
        seedFossil(state)
        UserDefaults.standard.set(
            "claude-sonnet-4-6", forKey: "chatModelID"
        )
        let action = adjudicate(state, server: "gpt-5.6-terra")
        XCTAssertEqual(action, .keep)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "deepseek-flash"
        )
    }

    /// 服务端值未知（nil）→ 不裁决、不动账
    func testAdjudicateKeepsWhenServerModelUnknown() {
        let state = makeState()
        seedFossil(state)
        let action = adjudicate(state, server: nil)
        XCTAssertEqual(action, .keep)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "deepseek-flash"
        )
    }

    // MARK: - runner 标记闸序

    /// 分叉但钦定键无存量 → 无化石可清，裁决完成
    /// 置一次性标记（此后不再跑）
    func testRunnerSetsHandledWhenNoStoreEntry() async {
        let state = makeState()
        let action = await state
            .runMainlineModelFossilMigrationIfNeeded(
                threadServerSessionID: threadBindingID,
                threadID: threadID,
                storeServerSessionID: storeID
            )
        XCTAssertEqual(action, .keep)
        XCTAssertTrue(state.mainlineFossilMigrationHandled)
    }

    /// 有存量但服务端回读失败（离线桩）→ 不裁决、
    /// 不置标记、账不动，下次落地再试
    func testRunnerLeavesHandledUnsetWhenServerUnreachable() async {
        let state = makeState()
        seedFossil(state)
        let action = await state
            .runMainlineModelFossilMigrationIfNeeded(
                threadServerSessionID: threadBindingID,
                threadID: threadID,
                storeServerSessionID: storeID
            )
        XCTAssertEqual(action, .keep)
        XCTAssertFalse(state.mainlineFossilMigrationHandled)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "deepseek-flash"
        )
    }

    /// 已置标记 → runner 直接返、不动账（一次性）
    func testRunnerSkipsWhenAlreadyHandled() async {
        let state = makeState()
        seedFossil(state)
        UserDefaults.standard.set(true, forKey: handledKey)
        let action = await state
            .runMainlineModelFossilMigrationIfNeeded(
                threadServerSessionID: threadBindingID,
                threadID: threadID,
                storeServerSessionID: storeID
            )
        XCTAssertEqual(action, .keep)
        XCTAssertEqual(
            state.sessionModelChoices[storeKey]?.model,
            "deepseek-flash"
        )
    }
}
