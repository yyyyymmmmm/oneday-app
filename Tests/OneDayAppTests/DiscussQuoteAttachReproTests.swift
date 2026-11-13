import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import OneDayApp
@testable import OneDayCore

/// 动态「讨论」引用挂载复现 rig v2（2026-11-13，用户真机
/// 实报 0.50.30：动态点「讨论」跳到聊天后引用卡没挂上）。
///
/// v1 结果（run 43436579164）：四场景全红——三例断言超时、
/// 主场景无裁决行无 dump（疑挂死/死亡）。但 v1 仪表有两处
/// 不可靠：①标签信号走 subviews 属性遍历（SwiftUI 的无障
/// 碍标签不在视图属性上，四例全空、信号已死）；②高度判据
/// 只认「长高」，而引用落位会聚焦输入舱、键盘导引区预留
/// 反而使宿主变矮，方向可能反了。
///
/// v2 仪表：①种子消费状态（appState.pendingFeedDiscussSeed
/// 是否被清＝tryApplyFeedSeed 是否命中过目标线程，状态级
/// 硬信号）；②无障碍元素树遍历（accessibilityElementCount/
/// at: 递归）找硬编码标签「取消引用」，并打印标签样本作阳
/// 性对照（遍历器到底看不看得见世界，样本即证据）；③宿主
/// 高度轨迹（写组后 10×0.25s 采样序列）；④主场景分步
/// MARK 标记，挂死也要留下死在哪一步。
///
/// 驱动法与 v1 同：performDiscussWrites 与 FeedView.discuss
/// 的状态写组逐字同序复刻（ModelContext insert ChatThread
/// ＋save → linkFeedDiscussThread → 置种子 → 置抽屉选择 →
/// 置切格请求）。markRead 只动动态已读账、不入 rig。
@MainActor
final class DiscussQuoteAttachReproTests: XCTestCase {

    private var window: UIWindow!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!
    private var baselineHostHeight: CGFloat = -1

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "discuss-rig-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        container = try ModelContainer(
            for: schema,
            configurations: [config]
        )
        _ = dir
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

    // MARK: - 壳层装配（RootView 真壳层，探针同款）

    private func mark(_ s: String) {
        print("RIG-MARK \(s)")
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

    private func composerHost() -> UIView? {
        findComposerVC()?.traceComposerHostView
    }

    /// 沿 VC 树找 ComposerGuideHostController（探针同款定位法）
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

    private func spinUntilChatPresented() {
        _ = spinUntil(timeout: 8) { composerHost() != nil }
    }

    // MARK: - 无障碍元素树遍历（v2 新仪表，带阳性对照）

    /// 从任意对象沿 UIAccessibility 容器协议递归收集标签。
    /// SwiftUI 的无障碍元素不在 subviews 的属性上，必须走
    /// accessibilityElementCount()/accessibilityElement(at:)。
    private func collectA11yLabels(from root: AnyObject) -> [String] {
        var out: [String] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ obj: AnyObject, _ depth: Int) {
            guard depth <= 16, out.count < 600 else { return }
            let oid = ObjectIdentifier(obj)
            guard seen.insert(oid).inserted else { return }
            guard let ns = obj as? NSObject else { return }
            if ns.isAccessibilityElement,
               let label = ns.accessibilityLabel, !label.isEmpty {
                out.append(label)
            }
            let count = ns.accessibilityElementCount()
            if count != NSNotFound, count > 0, count < 1000 {
                for i in 0..<count {
                    if let child = ns.accessibilityElement(at: i)
                        as? NSObject {
                        walk(child, depth + 1)
                    }
                }
            }
            if let view = obj as? UIView {
                for sub in view.subviews { walk(sub, depth + 1) }
            }
        }
        walk(root, 0)
        return out
    }

    private func quoteSignalFromLabels() -> Bool {
        guard let window else { return false }
        return collectA11yLabels(from: window).contains("取消引用")
    }

    // MARK: - discuss 写组（与 FeedView.discuss 同序复刻）

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

    /// 返回讨论落点线程 id。stepMark=true 时逐步打点（主场景
    /// 挂死定位用）。写组与 FeedView.discuss 本尊逐字同序。
    @discardableResult
    private func performDiscussWrites(
        post: BridgeFeedPost, stepMark: Bool = false
    ) -> UUID {
        if stepMark { mark("discuss-begin") }
        let thread: ChatThread
        if let linkedID = appState.sideChats.threadID(
            forFeedDiscussPostID: post.id
        ), let existing = fetchThread(linkedID) {
            if stepMark { mark("discuss-reuse-path") }
            thread = existing
        } else {
            let fresh = ChatThread()
            if stepMark { mark("before-insert") }
            context.insert(fresh)
            if stepMark { mark("before-save") }
            try? context.save()
            if stepMark { mark("after-save") }
            appState.sideChats.linkFeedDiscussThread(
                fresh.id, postID: post.id
            )
            if stepMark { mark("after-link") }
            thread = fresh
        }
        appState.pendingFeedDiscussSeed = FeedDiscussSeed(
            threadID: thread.id,
            quote: FeedPostQuote(post: post)
        )
        appState.drawerThreadSelection = thread.id
        appState.mainTabSwitchRequest = .chat
        if stepMark { mark("discuss-writes-done") }
        return thread.id
    }

    // MARK: - 观测与断言

    private struct Snapshot {
        var seedPresent: Bool
        var labelHit: Bool
        var hostHeight: CGFloat
        var labelSample: [String]
    }

    private func snapshot() -> Snapshot {
        let labels = window.map { collectA11yLabels(from: $0) } ?? []
        return Snapshot(
            seedPresent: appState.pendingFeedDiscussSeed != nil,
            labelHit: labels.contains("取消引用"),
            hostHeight: composerHost()?.frame.height ?? -1,
            labelSample: Array(labels.prefix(24))
        )
    }

    /// 高度轨迹：2.5 秒内 10 次采样，序列即证据（落位聚焦会
    /// 改变宿主几何，单点读数不可判读）。
    private func heightTrace() -> [Int] {
        var out: [Int] = []
        for _ in 0..<10 {
            spinRunLoop(seconds: 0.25)
            out.append(Int(composerHost()?.frame.height ?? -1))
        }
        return out
    }

    private func dump(_ tag: String, _ snap: Snapshot, trace: [Int] = []) {
        let line = """
            RIG2-DUMP \(tag): 种子在=\(snap.seedPresent) \
            标签命中=\(snap.labelHit) host高=\(snap.hostHeight) \
            轨迹=\(trace) 标签样本=\(snap.labelSample)
            """
        print(line)
        add(XCTAttachment(string: line))
    }

    /// 引用「到达」的复合判据（v2）：种子被消费（硬信号）
    /// 或元素树出现「取消引用」。高度只留轨迹作旁证。
    private func quoteArrived() -> Bool {
        appState.pendingFeedDiscussSeed == nil || quoteSignalFromLabels()
    }

    private func assertQuoteArrives(_ tag: String) {
        let ok = spinUntil(timeout: 12) { quoteArrived() }
        let trace = heightTrace()
        let snap = snapshot()
        dump(tag, snap, trace: trace)
        XCTAssertTrue(
            ok || snap.labelHit,
            "\(tag)：写组后 12s 内引用未到达（种子未消费且引用条标签未现）"
        )
    }

    // MARK: - 场景一：新线程（用户主报路径，全程打点）

    func testDiscussAttachesQuote_FreshThread_FromFeedTab() {
        mark("s1-mount")
        mountShell()
        spinUntilChatPresented()
        mark("s1-chat-presented")
        appState.mainTabSwitchRequest = .feed
        spinRunLoop(seconds: 1.0)
        mark("s1-on-feed-tab")
        baselineHostHeight =
            composerHost()?.frame.height ?? -1
        mark("s1-baseline=\(baselineHostHeight)")
        performDiscussWrites(post: makePost(id: "rig-post-fresh"), stepMark: true)
        mark("s1-writes-returned")
        assertQuoteArrives("freshNewThread")
        mark("s1-done")
        XCTAssertNil(
            appState.pendingFeedDiscussSeed,
            "种子落位后应被消费清零"
        )
    }

    // MARK: - 场景二：复用既有讨论线程（落点已在该线程）

    func testDiscussAttachesQuote_ReusedThread_AlreadyThere() {
        mountShell()
        spinUntilChatPresented()
        let post = makePost(id: "rig-post-reuse")
        let thread = ChatThread()
        context.insert(thread)
        try? context.save()
        appState.sideChats.linkFeedDiscussThread(
            thread.id, postID: post.id
        )
        appState.sideChats.setLastThreadID(thread.id.uuidString)
        spinRunLoop(seconds: 1.2)
        performDiscussWrites(post: post)
        assertQuoteArrives("reuseAlreadyThere")
    }

    // MARK: - 场景三：挂上后壳层重现，引用须仍在

    func testDiscussQuoteSurvivesShellReappearance() {
        mountShell()
        spinUntilChatPresented()
        performDiscussWrites(post: makePost(id: "rig-post-reappear"))
        assertQuoteArrives("reappearBefore")
        let host = window.rootViewController
        window.rootViewController = nil
        spinRunLoop(seconds: 0.8)
        window.rootViewController = host
        spinUntilChatPresented()
        let snap = snapshot()
        dump("reappearAfter", snap)
        XCTAssertTrue(
            snap.labelHit,
            "壳层重现（onAppear 重放）后引用条消失"
        )
    }

    // MARK: - 场景四：种子先于 ChatView 挂载写入

    func testDiscussSeedWrittenBeforeChatMounts() {
        let post = makePost(id: "rig-post-seedfirst")
        performDiscussWrites(post: post)
        mountShell()
        spinUntilChatPresented()
        assertQuoteArrives("seedBeforeMount")
    }
}
