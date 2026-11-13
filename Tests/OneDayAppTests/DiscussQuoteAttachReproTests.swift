import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import OneDayApp
@testable import OneDayCore

/// 动态「讨论」引用挂载复现＋回归 rig（2026-11-13 立，
/// §210 修复后形态）。用户真机实报 0.50.30：动态点「讨
/// 论」跳到聊天后引用卡没挂上。
///
/// 历史（定因全程见 discuss-quote-attach-report-
/// 20261113）：v1/v2 在基线（种子制）上四场景全红坐实
/// 复现；跨轮判读定案——可存活进程里种子消费本身成功，
/// 败在形态脆弱面（全局一次性种子＋视图本地态）。§210
/// 修法把待发引用改挂 AppState.pendingFeedQuotesBy-
/// Thread 按线程寻址、ChatView 派生呈现，本 rig 随之
/// 改为**状态级断言**：只读待发表，不再依赖高度/标签
/// 等间接信号（v1/v2 的仪表教训：标签遍历四轮全空、
/// 高度方向可反）。
///
/// 形态：单装配多阶段——全程一个 RootView 壳层＋一个
/// 落盘容器、顺序走完五段（同进程反复整页装配会触发
/// §184 测试宿主配方，前序轮次已实证会把用例在挂载
/// 期毒杀、与生产无关；单装配同时也更像真实用户会话）。
/// 写组 performDiscussWrites 与 FeedView.discuss 本尊
/// 逐字同序（fetchThread 复用判据→insert＋save→link→
/// 待发引用直写→抽屉选择→切格请求）。
@MainActor
final class DiscussQuoteAttachReproTests: XCTestCase {

    private var window: UIWindow!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: schema, configurations: [config]
        )
        context = ModelContext(container)
        appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
    }

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        appState = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - 壳层与自旋

    private func mark(_ s: String) {
        print("RIG3-MARK \(s)")
        fflush(stdout)
    }

    private func mountShell() {
        let root = RootView()
            .environment(appState)
            .modelContainer(container)
        let host = UIHostingController(rootView: root)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        let win: UIWindow
        if let scene {
            win = UIWindow(windowScene: scene)
        } else {
            win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        }
        win.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        win.rootViewController = host
        win.makeKeyAndVisible()
        window = win
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.05)
            )
        }
    }

    @discardableResult
    private func spinUntil(
        timeout: TimeInterval, _ condition: () -> Bool
    ) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.05)
            )
        }
        return condition()
    }

    private func findComposerVC() -> ComposerGuideHostController? {
        var found: ComposerGuideHostController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ComposerGuideHostController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window?.rootViewController { walk(root) }
        return found
    }

    // MARK: - discuss 写组（与 FeedView.discuss 本尊同序，§210 形）

    private func makePost(id: String) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: .research, title: "Rig 讨论帖",
            body: "帖子正文全文，用于引用快照。",
            direction: "Rig",
            createdAt: Date().timeIntervalSince1970,
            emoji: "🤖"
        )
    }

    private func fetchThread(_ id: UUID) -> ChatThread? {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    private func performDiscussWrites(post: BridgeFeedPost) -> UUID {
        let thread: ChatThread
        if let linkedID = appState.sideChats.threadID(
            forFeedDiscussPostID: post.id
        ), let existing = fetchThread(linkedID) {
            thread = existing
        } else {
            let fresh = ChatThread()
            context.insert(fresh)
            try? context.save()
            appState.sideChats.linkFeedDiscussThread(
                fresh.id, postID: post.id
            )
            thread = fresh
        }
        appState.pendingFeedQuotesByThread[thread.id] =
            FeedPostQuote(post: post)
        appState.drawerThreadSelection = thread.id
        appState.mainTabSwitchRequest = .chat
        return thread.id
    }

    private func pendingQuote(for threadID: UUID) -> FeedPostQuote? {
        appState.pendingFeedQuotesByThread[threadID]
    }

    // MARK: - 五段全程（单装配）

    func testDiscussQuoteLifecycle_SingleAssembly() {
        mark("mount")
        mountShell()
        XCTAssertTrue(
            spinUntil(timeout: 8) { findComposerVC() != nil },
            "聊天页未在壳层内呈现"
        )
        // 进场在动态格（复刻用户点讨论时的在场状态）
        appState.mainTabSwitchRequest = .feed
        spinRunLoop(seconds: 1.0)
        mark("on-feed-tab")

        // P1：新帖讨论（新线程）——待发引用写入后，在落
        // 点收敛的数秒内恒在（不许被后续事件追毁）
        let post1 = makePost(id: "rig3-post-1")
        let t1 = performDiscussWrites(post: post1)
        mark("p1-writes-done t1=\(t1)")
        XCTAssertTrue(
            spinUntil(timeout: 8) { pendingQuote(for: t1) != nil },
            "P1：讨论写入后目标线程待发引用不在场"
        )
        var p1Stable = true
        for _ in 0..<10 {
            spinRunLoop(seconds: 0.25)
            if pendingQuote(for: t1) == nil { p1Stable = false }
        }
        XCTAssertTrue(p1Stable, "P1：待发引用落位后 2.5s 内被追毁")
        XCTAssertEqual(
            pendingQuote(for: t1)?.postID, post1.id,
            "P1：待发引用快照与帖不一致"
        )
        mark("p1-ok")

        // P2：切去主线程——离开 T1，其待发引用按规格
        // §3.3 作废（定点清离开者）
        guard let mainID = appState.sideChats.mainThreadID else {
            XCTFail("主线程 id 缺席，P2 无法执行")
            return
        }
        appState.drawerThreadSelection = mainID
        XCTAssertTrue(
            spinUntil(timeout: 8) { pendingQuote(for: t1) == nil },
            "P2：切离 T1 后其待发引用未作废（残留/串带）"
        )
        mark("p2-ok")

        // P3：同帖再讨论（复用线程）——待发引用重新在场
        let t1Again = performDiscussWrites(post: post1)
        XCTAssertEqual(t1Again, t1, "P3：同帖讨论未复用同一线程")
        XCTAssertTrue(
            spinUntil(timeout: 8) { pendingQuote(for: t1) != nil },
            "P3：复用线程再讨论后待发引用不在场"
        )
        mark("p3-ok")

        // P4：壳层重现（rootViewController 卸下再装回，
        // 视图整树重建）——待发引用是 AppState 状态、
        // 不随视图存亡
        let host = window.rootViewController
        window.rootViewController = nil
        spinRunLoop(seconds: 0.8)
        window.rootViewController = host
        XCTAssertTrue(
            spinUntil(timeout: 8) { findComposerVC() != nil },
            "P4：壳层重现后聊天页未再呈现"
        )
        spinRunLoop(seconds: 1.0)
        XCTAssertNotNil(
            pendingQuote(for: t1),
            "P4：壳层重现后待发引用丢失（状态仍系于视图）"
        )
        mark("p4-ok")

        // P5：另一帖讨论（新线程 T2）——落点切到 T2：
        // T2 待发引用在场、T1 的已随切离作废（不串带）
        let post2 = makePost(id: "rig3-post-2")
        let t2 = performDiscussWrites(post: post2)
        XCTAssertNotEqual(t2, t1)
        XCTAssertTrue(
            spinUntil(timeout: 8) {
                pendingQuote(for: t2) != nil
                    && pendingQuote(for: t1) == nil
            },
            "P5：切到 T2 后待发引用归属错位（T2 缺失或 T1 残留）"
        )
        mark("p5-ok")
    }
}
