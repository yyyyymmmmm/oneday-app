import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 乐观删除（§232）验收钉测，用户 2026-11-14 亲
/// 定口径「先本地删，服务器后台删，成功了没事，
/// 失败了恢复然后提醒」的复现→修复对照。钉四件：
/// ①起手即时消失——绑定线程打墓碑（本体不物理
///   删）、共享目录摘行、待删入队落盘，begin 同
///   步返回不等服务端；
/// ②后台落定——物理收口（线程本体删除＋侧账清）
///   ＋销账、无提醒；
/// ③后台最终失败——解墓碑原样恢复＋目录重拉回
///   行＋恢复信号＋人话提醒置位（不露原文）；
/// ④重启续跑——新协调器自落盘队列读回＋墓碑补
///   队续跑，落定收口与失败恢复各一遍；另钉主线
///   整件不动。
/// 服务端落定/失败由协调器执行口注入口定（默认
/// 即生产 ServerSessionActions.delete），不另造
/// 网络桩；目录恢复重拉同口注入。
@MainActor
final class DeleteOptimisticTests: XCTestCase {

    private var appState: AppState!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var suiteDefaults: UserDefaults!
    private var suiteName: String!
    private var coordinator: SessionDeletionCoordinator!
    private var priorMainSessionID: String?

    private let mainKey = "sideChats.mainServerSessionID"
    private let queueKey = "sessionDeletions.pendingQueue"

    override func setUp() async throws {
        try await super.setUp()
        priorMainSessionID = UserDefaults.standard.string(
            forKey: mainKey
        )
        appState = AppState(
            client: FailingHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        context = ModelContext(container)
        suiteName = "delete-optimistic-tests-\(UUID().uuidString)"
        suiteDefaults = UserDefaults(suiteName: suiteName)
        coordinator = SessionDeletionCoordinator(
            defaults: suiteDefaults
        )
    }

    override func tearDown() async throws {
        if let priorMainSessionID {
            UserDefaults.standard.set(
                priorMainSessionID, forKey: mainKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: mainKey)
        }
        // AppState 自带协调器走标准域：本组不经它起
        // 手，仍防别组残留串扰，清键兜底
        UserDefaults.standard.removeObject(forKey: queueKey)
        suiteDefaults.removePersistentDomain(forName: suiteName)
        coordinator = nil
        suiteDefaults = nil
        appState = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - 装配

    /// ServerSession 无公开成员构造器——解码构造
    /// （与 DeleteCloseoutTests 同式）
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

    private func threadExists(_ id: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == id }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    private func catalogContains(_ sessionID: String) -> Bool {
        appState.serverSessionCatalog.visibleSessions
            .contains { $0.id == sessionID }
    }

    /// 等待异步收口（后台执行/恢复重拉都是无阻塞
    /// 后台 Task，轮询至条件成立，超时即失败）
    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待超时：\(description)")
    }

    // MARK: - ①② 即时消失＋后台成功静默收口

    func testBeginHidesImmediatelyThenSuccessFinalizes() async throws {
        let sid = "oneday-delete-optimistic-success"
        let thread = try makeThread(sessionID: sid)
        appState.serverSessionCatalog.publish(
            visible: [makeSession(id: sid)]
        )
        coordinator.deleteAction = { _, _ in .verified }

        coordinator.begin(
            sessionID: sid, title: "测试线程",
            appState: appState, modelContext: context
        )

        // 同步段断言：begin 已返回而后台执行尚未跑
        // 完的此刻——墓碑已打、本体未删、目录已摘、
        // 队列在盘
        XCTAssertTrue(thread.isPendingDeletion)
        XCTAssertTrue(try threadExists(thread.id))
        XCTAssertFalse(catalogContains(sid))
        XCTAssertTrue(coordinator.isPending(sessionID: sid))
        XCTAssertNotNil(suiteDefaults.data(forKey: queueKey))

        await waitUntil("落定销账") {
            self.coordinator.queue.isEmpty
        }
        // 落定收口：线程本体物理删除、目录仍无行、
        // 无失败提醒
        XCTAssertFalse(try threadExists(thread.id))
        XCTAssertFalse(catalogContains(sid))
        XCTAssertNil(appState.sessionDeletionFailureNotice)
        XCTAssertEqual(coordinator.restoreRevision, 0)
    }

    // MARK: - ③ 后台失败：恢复＋提醒

    func testFailureRestoresThreadCatalogAndNotice() async throws {
        let sid = "oneday-delete-optimistic-failure"
        let session = makeSession(id: sid)
        let thread = try makeThread(sessionID: sid)
        appState.serverSessionCatalog.publish(visible: [session])
        coordinator.deleteAction = { _, _ in .failed("桩失败原因") }
        coordinator.catalogRefresher = { _ in [session] }

        coordinator.begin(
            sessionID: sid, title: "测试线程",
            appState: appState, modelContext: context
        )
        XCTAssertTrue(thread.isPendingDeletion)
        XCTAssertFalse(catalogContains(sid))

        await waitUntil("失败恢复") {
            !thread.isPendingDeletion
                && self.coordinator.queue.isEmpty
        }
        // 线程本体从未物理删、解标即原样恢复；提醒
        // 人话置位（标题＋恢复语，不带桩的原文）
        XCTAssertTrue(try threadExists(thread.id))
        let notice = try XCTUnwrap(
            appState.sessionDeletionFailureNotice
        )
        XCTAssertTrue(notice.contains("删除没成功，已恢复"))
        XCTAssertTrue(notice.contains("测试线程"))
        XCTAssertFalse(notice.contains("桩失败原因"))
        XCTAssertEqual(coordinator.restoreRevision, 1)
        // 目录经恢复重拉回行
        await waitUntil("目录回行") {
            self.catalogContains(sid)
        }
    }

    // MARK: - ④ 重启续跑：落定收口

    func testResumeAfterRelaunchFinalizes() async throws {
        let sid = "oneday-delete-optimistic-resume-ok"
        let thread = try makeThread(sessionID: sid)
        appState.serverSessionCatalog.publish(
            visible: [makeSession(id: sid)]
        )
        // 第一程模拟「删除在飞时进程被杀」：执行口
        // 长睡不回，队列与墓碑留在盘上
        coordinator.deleteAction = { _, _ in
            try? await Task.sleep(for: .seconds(600))
            return .failed("不应到达")
        }
        coordinator.begin(
            sessionID: sid, title: "测试线程",
            appState: appState, modelContext: context
        )
        XCTAssertTrue(thread.isPendingDeletion)

        // 「重启」：新协调器同域读回队列并续跑（成
        // 功口），在飞去重是实例内的——新实例即新
        // 进程口径
        let relaunched = SessionDeletionCoordinator(
            defaults: suiteDefaults
        )
        XCTAssertTrue(relaunched.isPending(sessionID: sid))
        relaunched.deleteAction = { _, _ in .verified }
        relaunched.resumePending(
            appState: appState, modelContext: context
        )
        await waitUntil("续跑收口") {
            relaunched.queue.isEmpty
        }
        XCTAssertFalse(try threadExists(thread.id))
        XCTAssertNil(appState.sessionDeletionFailureNotice)
    }

    // MARK: - ④' 重启续跑：失败同样恢复＋提醒

    func testResumeFailureRestoresAndNotifies() async throws {
        let sid = "oneday-delete-optimistic-resume-fail"
        let session = makeSession(id: sid)
        // 直接构造杀进程后的盘面：线程已打墓碑、队
        // 列已落盘（用第一程协调器起手＋长睡执行口
        // 复刻，见上一法注释）
        let thread = try makeThread(sessionID: sid)
        appState.serverSessionCatalog.publish(visible: [session])
        coordinator.deleteAction = { _, _ in
            try? await Task.sleep(for: .seconds(600))
            return .verified
        }
        coordinator.begin(
            sessionID: sid, title: "测试线程",
            appState: appState, modelContext: context
        )
        XCTAssertTrue(thread.isPendingDeletion)

        let relaunched = SessionDeletionCoordinator(
            defaults: suiteDefaults
        )
        relaunched.deleteAction = { _, _ in .failed("桩失败") }
        relaunched.catalogRefresher = { _ in [session] }
        relaunched.resumePending(
            appState: appState, modelContext: context
        )
        await waitUntil("续跑失败恢复") {
            !thread.isPendingDeletion
                && relaunched.queue.isEmpty
        }
        XCTAssertTrue(try threadExists(thread.id))
        XCTAssertNotNil(appState.sessionDeletionFailureNotice)
        await waitUntil("目录回行") {
            self.catalogContains(sid)
        }
    }

    // MARK: - 主线保护

    func testBeginLeavesMainlineCompletelyUntouched() throws {
        let mainSID = "oneday-main-optimistic-test"
        appState.sideChats.setMainServerSessionID(mainSID)
        let thread = try makeThread(sessionID: mainSID)
        appState.serverSessionCatalog.publish(
            visible: [makeSession(id: mainSID)]
        )
        coordinator.deleteAction = { _, _ in .verified }

        coordinator.begin(
            sessionID: mainSID, title: "主线",
            appState: appState, modelContext: context
        )

        XCTAssertFalse(thread.isPendingDeletion)
        XCTAssertTrue(try threadExists(thread.id))
        XCTAssertTrue(catalogContains(mainSID))
        XCTAssertTrue(coordinator.queue.isEmpty)
    }
}
