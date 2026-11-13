import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// 键盘协同整包（2026-11-13）· 落码后验收门。装配
/// 与诊断件同式（AppState＋落盘长会话＋场景窗）。
/// 观测口径取自诊断轮实测教训（run 43447354946）：
/// ①点空白识别器在位且仲裁参数对（cancelsTouches-
/// InView＝false、delegate 为安装器视图）；
/// ②margin 两态值：静息 rawB＝197（账本 83+106+8）、
/// 键盘态 rawB＝449（键盘 335+舱 106+8）——快照公式
/// 与旧回报链在同装配逐 pt 同值即过（容差 ±3）；
/// adjusted 的平台键盘调整（实测 +79）不在本账、只
/// 记 raw；
/// ③顶簇静止：聚焦→收起全周期 pocketY 偏差 ≤2；
/// ④落定无尾巴：收键盘后 +0.6s 与 +2.2s 两采样
/// pocket/card 逐项一致（≤1）且 rawB 回到静息 ±3。
/// 落点 gap 绝对值不在本门：诊断实证模拟器装配的
/// LazyVStack 估算膨胀使 UIKit 层 gap 不可作生产落
/// 点判据；落点由 Core 结算状态机单测＋生产锚点贴
/// 底链承载，真机为最终判据（§194 同纪律）。
/// 装配纪律：只装配一次、只播种一次（§184 配方：
/// 同进程多次整页装配＋异容器 save 必杀为测试宿主
/// 病，压暴露面）。
@MainActor
final class KeyboardFlowAcceptanceTests: XCTestCase {
    private var window: UIWindow!

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func findViews(
        _ root: UIView, where matches: (UIView) -> Bool
    ) -> [UIView] {
        var out: [UIView] = []
        if matches(root) { out.append(root) }
        for sub in root.subviews {
            out += findViews(sub, where: matches)
        }
        return out
    }

    private func findVC<T: UIViewController>(
        _ type: T.Type
    ) -> T? {
        var found: T?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? T { found = hit }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    private func frameInWindow(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    /// 聊天滚动视图：子树内含播种段落文本的那个
    /// HostingScrollView——首版按「首个宽滚动视图」
    /// 取面，在多页装配里取错了面（验收轮实测静
    /// 态 114 的异面 inset），改以内容标记定面
    private func chatScrollView() -> UIScrollView? {
        findViews(window) { view in
            guard view is UIScrollView,
                  String(describing: type(of: view))
                    .contains("HostingScrollView"),
                  self.frameInWindow(view).width > 400,
                  let scroll = view as? UIScrollView
            else { return false }
            return self.findViews(scroll) {
                ($0 as? UITextView)?.text
                    .contains("键盘验收") == true
            }.isEmpty == false
        }.first as? UIScrollView
    }

    /// 全 HostingScrollView 的 inset 清单（判读留痕）
    private func scrollViewCensus() -> String {
        findViews(window) {
            $0 is UIScrollView
                && String(describing: type(of: $0))
                    .contains("HostingScrollView")
        }.compactMap { $0 as? UIScrollView }.map {
            let f = self.frameInWindow($0)
            let hasRecognizer = $0.gestureRecognizers?
                .contains { $0.name == "OneDayBlankTapDismiss" }
                ?? false
            return "sv@\(Int(f.minY)),\(Int(f.height))"
                + " rawB=\(Int($0.contentInset.bottom))"
                + " recog=\(hasRecognizer)"
        }.joined(separator: " | ")
    }

    private func composerCardFrame() -> CGRect? {
        guard let host = findVC(ComposerGuideHostController.self)
        else { return nil }
        return findViews(host.view) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && self.frameInWindow(view).width > 300
        }.first.map { frameInWindow($0) }
    }

    private func topPocketFrame() -> CGRect? {
        findVC(TopBarGuideHostController.self)
            .map { frameInWindow($0.traceBarView) }
    }

    func testKeyboardFlowAcceptance() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "kbaccept-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                url: dir.appendingPathComponent("store.sqlite")
            )]
        )
        let context = ModelContext(container)
        let thread = ChatThread(title: "验收长会话")
        context.insert(thread)
        let paragraph = (0..<8).map { i in
            "第\(i + 1)段：键盘验收的长段落文本，"
                + "用来撑起真实的气泡高度与行高。"
        }.joined(separator: " ")
        let base = Date().addingTimeInterval(-6 * 3600)
        for index in 0..<160 {
            let isUser = index % 2 == 0
            let entry = ChatEntry(
                role: isUser ? "user" : "assistant",
                content: isUser
                    ? "第 \(index / 2 + 1) 问：短问题。"
                    : paragraph,
                thread: thread
            )
            entry.createdAt = base
                .addingTimeInterval(Double(index * 61))
            context.insert(entry)
        }
        thread.createdAt = base
        thread.updatedAt = base.addingTimeInterval(160 * 61)
        try context.save()
        appState.sideChats.setLastThreadID(thread.id)

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
        spinRunLoop(seconds: 3.5)
        window.layoutIfNeeded()

        let scroll = try XCTUnwrap(
            chatScrollView(), "验收装配失效：聊天滚动视图缺席"
        )

        // ① 识别器在位（A5 点空白条）
        let recognizer = scroll.gestureRecognizers?.first {
            $0.name == "OneDayBlankTapDismiss"
        }
        XCTAssertNotNil(
            recognizer,
            "点空白退键盘识别器未安装到聊天滚动视图"
        )
        if let recognizer {
            XCTAssertFalse(
                recognizer.cancelsTouchesInView,
                "识别器不许吞触摸（cancelsTouchesInView 须 false）"
            )
            XCTAssertTrue(
                recognizer.delegate is TapDismissInstallerView,
                "识别器 delegate 须为安装器视图（仲裁在 delegate）"
            )
        }

        print("KBACCEPT census " + scrollViewCensus())
        // ② 静息 margin（raw 口径）
        let restRawB = scroll.contentInset.bottom
        let restPocket = topPocketFrame()?.minY ?? -1
        print(String(format:
            "KBACCEPT rest rawB=%.0f pocket=%.0f",
            restRawB, restPocket))
        XCTAssertEqual(
            restRawB, 197, accuracy: 3,
            "静息底 margin 与账本值不符（83+106+8）"
        )

        // 键盘周期：聚焦→采样→收起→两拍采样
        let composer = try XCTUnwrap(
            findVC(ComposerGuideHostController.self)
                .flatMap { findViews($0.view) { $0 is UITextView }.first }
                as? UITextView,
            "验收装配失效：输入舱文本视图缺席"
        )
        XCTAssertTrue(
            composer.becomeFirstResponder(),
            "验收装配失效：输入舱无法聚焦"
        )
        spinRunLoop(seconds: 0.8)
        window.layoutIfNeeded()
        let kbRawB = scroll.contentInset.bottom
        let kbPocket = topPocketFrame()?.minY ?? -1
        print(String(format:
            "KBACCEPT kb rawB=%.0f pocket=%.0f",
            kbRawB, kbPocket))
        XCTAssertEqual(
            kbRawB, 449, accuracy: 3,
            "键盘态底 margin 与快照公式不符（335+106+8）"
        )
        XCTAssertEqual(
            kbPocket, restPocket, accuracy: 2,
            "键盘升起顶簇位移"
        )
        _ = composer.resignFirstResponder()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
        let settledRawB = scroll.contentInset.bottom
        let settledPocket = topPocketFrame()?.minY ?? -1
        let settledCard = composerCardFrame()?.minY ?? -1
        spinRunLoop(seconds: 1.6)
        window.layoutIfNeeded()
        let latePocket = topPocketFrame()?.minY ?? -1
        let lateCard = composerCardFrame()?.minY ?? -1
        print(String(format:
            "KBACCEPT settled rawB=%.0f pocket=%.0f/%.0f card=%.0f/%.0f",
            settledRawB, settledPocket, latePocket,
            settledCard, lateCard))

        // ③④ 收起落定：无尾巴＋顶簇全周期静止＋margin 归位
        XCTAssertEqual(
            settledPocket, latePocket, accuracy: 1,
            "收键盘后顶簇仍在爬行（落定尾巴）"
        )
        XCTAssertEqual(
            settledCard, lateCard, accuracy: 1,
            "收键盘后输入舱仍在爬行（落定尾巴）"
        )
        XCTAssertEqual(
            settledPocket, restPocket, accuracy: 2,
            "顶簇收键盘全程位移超限"
        )
        XCTAssertEqual(
            settledRawB, restRawB, accuracy: 3,
            "收键盘后底 margin 未回到静息值"
        )

        window.rootViewController = nil
        window.isHidden = true
    }
}
