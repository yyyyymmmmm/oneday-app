import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §208 真机第一验翻车（0.50.30，用户 2026-11-13
/// 21:39 实报：动态点「讨论」跳到聊天后引用卡没挂
/// 上）生产同构复现 rig：真实壳层 RootView（真
/// TabView＋真 ChatView＋真 FeedView）＋真 AppState
/// （演示连接）＋落盘容器，按 FeedView.discuss 的
/// 同一组写、同一顺序驱动，断言引用条真出现在输
/// 入舱里。已交付单测只钉了 Core 拼装与存储层反
/// 查/清扫——导航交接面（种子→切格→落点→消费）
/// 零覆盖，本 rig 补的就是这一面。
@MainActor
final class DiscussQuoteAttachReproTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    // MARK: - 装配（与 ChatPageDeviceConditionProbeTests 同款）

    private struct Assembly {
        var appState: AppState
        var container: ModelContainer
        var host: UIHostingController<AnyView>
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "dqrig-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent("store.sqlite")
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, url: url
            )]
        )
    }

    private func assemble(
        appState: AppState, container: ModelContainer
    ) throws -> Assembly {
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first,
            "测试宿主无 UIWindowScene"
        )
        let win = UIWindow(windowScene: scene)
        win.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window = win
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 3.0)
        window.layoutIfNeeded()
        return Assembly(
            appState: appState, container: container, host: host
        )
    }

    // MARK: - discuss 写组（与 FeedView.discuss 逐字同序）

    private func makePost(id: String) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: .research,
            title: "复现帖标题DQ\(id)",
            body: "这篇复现帖的正文，只在帖里有的一句：蓝铜矿标本编号DQ-7391。",
            createdAt: 1_700_000_000
        )
    }

    /// FeedView.discuss 的新建路：建线程落盘→登记
    /// 关联→置种子→置抽屉线程选择→置切格请求。
    /// markRead 只动动态已读账、与引用交接无关，不入。
    @discardableResult
    private func performDiscussFreshThread(
        post: BridgeFeedPost, assembly: Assembly
    ) -> UUID {
        let context = ModelContext(assembly.container)
        let fresh = ChatThread()
        context.insert(fresh)
        try? context.save()
        assembly.appState.sideChats.linkFeedDiscussThread(
            fresh.id, postID: post.id
        )
        performDiscussWrites(
            threadID: fresh.id, post: post, assembly: assembly
        )
        return fresh.id
    }

    /// discuss 的后半组写（种子→选择→切格），新建与
    /// 复用两路共用、顺序与源码逐字一致
    private func performDiscussWrites(
        threadID: UUID, post: BridgeFeedPost, assembly: Assembly
    ) {
        assembly.appState.pendingFeedDiscussSeed = FeedDiscussSeed(
            threadID: threadID, quote: FeedPostQuote(post: post)
        )
        assembly.appState.drawerThreadSelection = threadID
        assembly.appState.mainTabSwitchRequest = .chat
    }

    /// 先把壳层切到动态格（用户点讨论时的真实在场
    /// 状态：ChatView 已挂载但不在选中格）
    private func switchToFeedTab(assembly: Assembly) {
        assembly.appState.mainTabSwitchRequest = .feed
        spinRunLoop(seconds: 1.5)
        window.layoutIfNeeded()
    }

    // MARK: - 引用条检测（双信号＋倾印）

    private func findVC<T: UIViewController>(_ type: T.Type) -> T? {
        var found: T?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? T { found = hit }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    private func collectLabels(_ root: UIView) -> [String] {
        var out: [String] = []
        if let label = root.accessibilityLabel, !label.isEmpty {
            out.append(label)
        }
        for sub in root.subviews {
            out += collectLabels(sub)
        }
        return out
    }

    /// 引用条在场判定：输入舱宿主子树里出现「取消
    /// 引用」无障碍标签（feedQuoteBar ✕ 的钉死文
    /// 案），或宿主高较基线生长 ≥30（引用段展开的
    /// 结构信号）。两信号分别倾印、断言取或。
    private func quoteProbe(
        scenario: String, baselineHeight: CGFloat?
    ) -> Bool {
        let composer = findVC(ComposerGuideHostController.self)
        var labels: [String] = []
        var height: CGFloat = -1
        if let composer {
            let hostView = composer.traceComposerHostView
            labels = collectLabels(hostView)
            height = hostView.bounds.height
        }
        let labelHit = labels.contains("取消引用")
        var grew = false
        if let baselineHeight, height > 0 {
            grew = height - baselineHeight >= 30
        }
        let dump = "RIG-DUMP \(scenario): composer在场="
            + "\(composer != nil) host高=\(height) 基线="
            + "\(baselineHeight ?? -1) 标签命中=\(labelHit) "
            + "高生长=\(grew) 舱内标签=\(labels)"
        print(dump)
        add(XCTAttachment(string: dump))
        return labelHit || grew
    }

    private func composerBaselineHeight() -> CGFloat? {
        guard let composer = findVC(
            ComposerGuideHostController.self
        ) else { return nil }
        return composer.traceComposerHostView.bounds.height
    }

    // MARK: - 场景一：新帖讨论（用户主报路径）

    func testDiscussAttachesQuote_FreshThread_FromFeedTab() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let assembly = try assemble(
            appState: appState, container: container
        )
        let baseline = composerBaselineHeight()
        switchToFeedTab(assembly: assembly)
        let post = makePost(id: "fp_dq_fresh")
        performDiscussFreshThread(post: post, assembly: assembly)
        spinRunLoop(seconds: 3.0)
        window.layoutIfNeeded()
        XCTAssertTrue(
            quoteProbe(
                scenario: "freshFromFeed", baselineHeight: baseline
            ),
            "点讨论后引用条未出现在输入舱（新线程路）"
        )
        XCTAssertNil(
            appState.pendingFeedDiscussSeed,
            "种子消费后应清零（残留说明消费路未走通）"
        )
    }

    // MARK: - 场景二：同帖复用且人已在该线程

    func testDiscussAttachesQuote_ReusedThread_AlreadyThere() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        // 预建讨论线程并登记关联、钉为冷启落点
        let context = ModelContext(container)
        let thread = ChatThread()
        context.insert(thread)
        try? context.save()
        appState.sideChats.linkFeedDiscussThread(
            thread.id, postID: "fp_dq_reuse"
        )
        appState.sideChats.setLastThreadID(thread.id)
        let assembly = try assemble(
            appState: appState, container: container
        )
        let baseline = composerBaselineHeight()
        switchToFeedTab(assembly: assembly)
        // 复用路：线程解析命中既有线程，只走后半组写
        let post = makePost(id: "fp_dq_reuse")
        performDiscussWrites(
            threadID: thread.id, post: post, assembly: assembly
        )
        spinRunLoop(seconds: 3.0)
        window.layoutIfNeeded()
        XCTAssertTrue(
            quoteProbe(
                scenario: "reuseAlreadyThere",
                baselineHeight: baseline
            ),
            "点讨论后引用条未出现在输入舱（复用线程路）"
        )
    }

    // MARK: - 场景三：挂上后壳层重现（视图重建不许吞引用）

    func testDiscussQuoteSurvivesShellReappearance() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let assembly = try assemble(
            appState: appState, container: container
        )
        let baseline = composerBaselineHeight()
        switchToFeedTab(assembly: assembly)
        let post = makePost(id: "fp_dq_reappear")
        performDiscussFreshThread(post: post, assembly: assembly)
        spinRunLoop(seconds: 3.0)
        window.layoutIfNeeded()
        XCTAssertTrue(
            quoteProbe(
                scenario: "reappearBefore", baselineHeight: baseline
            ),
            "前置：引用条应先挂上"
        )
        // 壳层重现：宿主离窗再回（模拟页签/呈现层重建
        // 引发的 onAppear 重放）
        window.rootViewController = nil
        spinRunLoop(seconds: 0.6)
        window.rootViewController = assembly.host
        window.makeKeyAndVisible()
        spinRunLoop(seconds: 2.5)
        window.layoutIfNeeded()
        XCTAssertTrue(
            quoteProbe(
                scenario: "reappearAfter", baselineHeight: baseline
            ),
            "壳层重现后引用条丢失"
        )
    }

    // MARK: - 场景四：种子先于 ChatView 挂载（冷入聊天格）

    func testDiscussSeedWrittenBeforeChatMounts() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        // 视图尚未挂载时先把 discuss 写组打完（ChatView
        // 首建走 onAppear 补消费路）
        let preAssembly = Assembly(
            appState: appState, container: container,
            host: UIHostingController(rootView: AnyView(EmptyView()))
        )
        let post = makePost(id: "fp_dq_cold")
        performDiscussFreshThread(post: post, assembly: preAssembly)
        let assembly = try assemble(
            appState: appState, container: container
        )
        _ = assembly
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
        XCTAssertTrue(
            quoteProbe(scenario: "seedBeforeMount", baselineHeight: nil),
            "种子先于挂载写入时引用条未挂上"
        )
    }
}
