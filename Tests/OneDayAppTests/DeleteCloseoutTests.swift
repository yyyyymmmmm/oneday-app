import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 删除全域收口（§217）验收钉测，用户 2026-11-14
/// 真机实报的复现→修复对照：管理页删掉的旁聊在抽
/// 屉残留、点开撞 404。钉三件事：
/// ①共享收口 apply——删除落定后绑定本地线程、共享
///   目录行、侧账同拍消失；主线整件保护；删的若是
///   当前线程经 drawerDeletedThreadID 通知 ChatView；
/// ②名单对账 reconcile——存活集之外的自有旁聊绑定
///   清除（prune/他端删除的残留回收），存活集内、
///   导入会话绑定、主线绑定一律保留；
/// ③点开 404 防御收口 handleOpenedSessionMissing
///   ——目录行与侧账就地清掉。
/// 「未落定本地不动」由各调用点的 .verified 闸保
/// 证（抽屉/行组件/批删三处同式），本组钉收口本
/// 体被调用后的落点口径。
@MainActor
final class DeleteCloseoutTests: XCTestCase {

    private var appState: AppState!
    private var container: ModelContainer!
    /// 全组共用一个写上下文（与生产同一形态：宿主
    /// 视图的 @Query 与 @Environment modelContext
    /// 本就是同一上下文，跨上下文删对象不合法）
    private var context: ModelContext!
    private var priorMainSessionID: String?

    private let mainKey = "sideChats.mainServerSessionID"

    override func setUp() async throws {
        try await super.setUp()
        priorMainSessionID = UserDefaults.standard.string(forKey: mainKey)
        appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        // 主线钦定 id 是持久账：恢复测试前原值，不许
        // 把本组的假钦定漏给同进程其他测试
        if let priorMainSessionID {
            UserDefaults.standard.set(priorMainSessionID, forKey: mainKey)
        } else {
            UserDefaults.standard.removeObject(forKey: mainKey)
        }
        appState = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - 装配

    /// ServerSession 无公开成员构造器（Core 内部
    /// 可见）——App 侧构造走解码，与 DemoHermes-
    /// Client 同式
    private func makeSession(id: String) -> ServerSession {
        try! JSONDecoder().decode(
            ServerSession.self,
            from: Data("{\"id\":\"\(id)\"}".utf8)
        )
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

    private func threadExists(_ id: UUID) throws -> Bool {
        try fetchThreads().contains { $0.id == id }
    }

    // MARK: - ① 共享收口

    /// 管理页删后残留的正解形态：绑定线程、目录行、
    /// 侧账（标题覆盖）同拍消失，旁观线程不动
    func testApplyRemovesBoundThreadCatalogRowAndSideRecords() throws {
        let sid = "oneday-side-closeout-victim"
        let other = "oneday-side-closeout-bystander"
        let victim = try makeThread(sessionID: sid)
        let bystander = try makeThread(sessionID: other)
        appState.serverSessionCatalog.publish(visible: [
            makeSession(id: sid), makeSession(id: other),
        ])
        appState.sideChats.setTitleOverride("旧标题", for: sid)

        DeletedSessionCloseout.apply(
            sessionID: sid, appState: appState,
            threads: try fetchThreads(),
            modelContext: context
        )

        XCTAssertFalse(try threadExists(victim.id))
        XCTAssertTrue(try threadExists(bystander.id))
        XCTAssertFalse(
            appState.serverSessionCatalog.visibleSessions
                .contains { $0.id == sid }
        )
        XCTAssertTrue(
            appState.serverSessionCatalog.visibleSessions
                .contains { $0.id == other }
        )
        XCTAssertNil(appState.sideChats.titleOverrides[sid])
    }

    /// 无绑定的本地线程（纯本地草稿类）不被任何收
    /// 口带走
    func testApplyLeavesUnboundThreadsAlone() throws {
        let local = try makeThread(sessionID: nil)
        DeletedSessionCloseout.apply(
            sessionID: "oneday-side-closeout-nobody",
            appState: appState,
            threads: try fetchThreads(),
            modelContext: context
        )
        XCTAssertTrue(try threadExists(local.id))
    }

    /// 主线保护在收口内兜死：主线会话 id 递进来，
    /// 线程/目录行/侧账整件不动（批删/prune/对账误
    /// 递时的最后防线）
    func testApplyProtectsMainlineSessionCompletely() throws {
        let mainSID = "oneday-main-closeout-test"
        appState.sideChats.setMainServerSessionID(mainSID)
        let mainThread = try makeThread(sessionID: mainSID)
        appState.serverSessionCatalog.publish(visible: [
            makeSession(id: mainSID),
        ])
        appState.sideChats.setTitleOverride("主线名", for: mainSID)

        DeletedSessionCloseout.apply(
            sessionID: mainSID, appState: appState,
            threads: try fetchThreads(),
            modelContext: context
        )

        XCTAssertTrue(try threadExists(mainThread.id))
        XCTAssertTrue(
            appState.serverSessionCatalog.visibleSessions
                .contains { $0.id == mainSID }
        )
        XCTAssertEqual(
            appState.sideChats.titleOverrides[mainSID], "主线名"
        )
        appState.sideChats.setTitleOverride(nil, for: mainSID)
    }

    /// 删的若是正在看的线程：drawerDeletedThreadID
    /// 置位（ChatView 据此置空当前线程＋清草稿锚）；
    /// 删别的线程不许误置
    func testApplyNotifiesChatViewOnlyForCurrentThread() throws {
        let currentSID = "oneday-side-closeout-current"
        let otherSID = "oneday-side-closeout-background"
        let current = try makeThread(sessionID: currentSID)
        _ = try makeThread(sessionID: otherSID)
        appState.currentDrawerObject = .side(current.id)

        DeletedSessionCloseout.apply(
            sessionID: otherSID, appState: appState,
            threads: try fetchThreads(),
            modelContext: context
        )
        XCTAssertNil(appState.drawerDeletedThreadID)

        DeletedSessionCloseout.apply(
            sessionID: currentSID, appState: appState,
            threads: try fetchThreads(),
            modelContext: context
        )
        XCTAssertEqual(appState.drawerDeletedThreadID, current.id)
        appState.drawerDeletedThreadID = nil
    }

    // MARK: - ② 名单对账

    /// 存活集外的自有旁聊绑定被清（他端删/prune 的
    /// 残留）；存活集内（含已归档段救回的）、导入
    /// 会话绑定、主线绑定全部保留
    func testReconcilePurgesOnlyDeadOwnSideChats() throws {
        let mainSID = "oneday-main-closeout-reconcile"
        appState.sideChats.setMainServerSessionID(mainSID)
        let dead = try makeThread(
            sessionID: "oneday-side-closeout-dead"
        )
        let live = try makeThread(
            sessionID: "oneday-side-closeout-live"
        )
        let archivedLive = try makeThread(
            sessionID: "oneday-side-closeout-archived-live"
        )
        let imported = try makeThread(
            sessionID: "tg-imported-session-1"
        )
        let mainThread = try makeThread(sessionID: mainSID)

        let purged = DeletedSessionCloseout.reconcileLocalThreads(
            threads: try fetchThreads(),
            liveSessionIDs: [
                "oneday-side-closeout-live",
                "oneday-side-closeout-archived-live",
            ],
            appState: appState,
            modelContext: context
        )

        XCTAssertEqual(purged, ["oneday-side-closeout-dead"])
        XCTAssertFalse(try threadExists(dead.id))
        XCTAssertTrue(try threadExists(live.id))
        XCTAssertTrue(try threadExists(archivedLive.id))
        XCTAssertTrue(try threadExists(imported.id))
        XCTAssertTrue(try threadExists(mainThread.id))
    }

    /// 存活集覆盖全部绑定时对账零动作（名单齐全不
    /// 许误删）
    func testReconcileKeepsEverythingWhenLiveSetCoversAll() throws {
        let a = try makeThread(sessionID: "oneday-side-closeout-a")
        let b = try makeThread(sessionID: "oneday-ai-closeout-b")
        let purged = DeletedSessionCloseout.reconcileLocalThreads(
            threads: try fetchThreads(),
            liveSessionIDs: [
                "oneday-side-closeout-a", "oneday-ai-closeout-b",
            ],
            appState: appState,
            modelContext: context
        )
        XCTAssertTrue(purged.isEmpty)
        XCTAssertTrue(try threadExists(a.id))
        XCTAssertTrue(try threadExists(b.id))
    }

    // MARK: - ③ 点开 404 防御

    /// 点开残留行撞 404 的收口：目录行摘掉＋侧账
    /// 清掉，行不会再被点第二次
    func testHandleOpenedSessionMissingClearsCatalogAndSideRecords() {
        let sid = "oneday-side-closeout-ghost"
        appState.serverSessionCatalog.publish(visible: [
            makeSession(id: sid),
        ])
        appState.sideChats.setTitleOverride("残留名", for: sid)

        DeletedSessionCloseout.handleOpenedSessionMissing(
            sessionID: sid, appState: appState
        )

        XCTAssertFalse(
            appState.serverSessionCatalog.visibleSessions
                .contains { $0.id == sid }
        )
        XCTAssertNil(appState.sideChats.titleOverrides[sid])
    }

    /// 404 防御的人话文案钉死三语目录值：不许再把
    /// 状态码原文给用户看
    func testSessionMissingCopyPinnedAcrossLocales() {
        let key = "这条会话已不在服务器上，本地列表已同步清理。"
        XCTAssertEqual(
            L10n.string(key, locale: Locale(identifier: "zh-Hans")),
            "这条会话已不在服务器上，本地列表已同步清理。"
        )
        XCTAssertEqual(
            L10n.string(key, locale: Locale(identifier: "zh-Hant")),
            "這條會話已不在伺服器上，本地列表已同步清理。"
        )
        XCTAssertEqual(
            L10n.string(key, locale: Locale(identifier: "en")),
            "This conversation is no longer on the server. "
                + "The local list has been cleaned up to match."
        )
        XCTAssertFalse(key.contains("404"))
    }
}
