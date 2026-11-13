import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 键盘协同整包·开工诊断（主报告 §5 同录清单）：在
/// 生产装配（RootView 全页＋落盘长会话）上同录
/// {contentSize, contentOffset, containerHeight,
/// contentMargins.bottom 实值（adjustedContentInset),
/// 尾行文本底, 舱顶, 顶簇帧, 坞帧}，一次跑回答两问：
/// ①症③残余留白的分账——回底落点缺口里估算 Δ 与
/// 留位记账各占多少；②症①顶簇位移的内部路径——
/// 键盘收回段顶簇窗口帧的逐拍位移序列。
/// 本文件只诊断不判修法：硬断言只守装配有效性（长
/// 会话在场、滚动视图在场、键盘真升起），量测全量
/// 倾印 KBFLOW-DIAG 行供报告引用。
@MainActor
final class KeyboardFlowDiagnosticTests: XCTestCase {

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

    // MARK: - 装配（与设备条件探针同式：落盘长会话）

    private func seedLongThread(
        into container: ModelContainer, appState: AppState
    ) {
        let context = ModelContext(container)
        let thread = ChatThread(title: "壁挂炉选型")
        context.insert(thread)
        let longParagraph = """
        但有一条必须盯死：最低输出功率。86 平米采暖只要 \
        7～9kW，如果你买的炉子最小火就是 7kW 甚至更高，它就会不停地 \
        开开关关，费气、有噪音、还伤机器。选最低输出 ≤4kW 的冷凝炉，\
        最好能到 3kW 出头，这样大部分时间它都稳在低火运行。\
        这一条比牌子重要。照单抓药，买的时候问商家这几项：\
        型式是燃气冷凝两用炉，采暖加生活热水一体。\
        额定 24kW，最低输出功率 ≤4kW。采暖水温能调到 \
        40～50°C（地暖专用低温档），最好支持室外温度补偿。
        """
        let base = Date().addingTimeInterval(-6 * 3600)
        for index in 0..<160 {
            let isUser = index % 2 == 0
            let entry = ChatEntry(
                role: isUser ? "user" : "assistant",
                content: isUser
                    ? "第 \(index / 2 + 1) 问：这个参数再确认一下。"
                    : longParagraph,
                thread: thread
            )
            entry.createdAt = base
                .addingTimeInterval(Double(index * 61))
            context.insert(entry)
        }
        thread.createdAt = base
        thread.updatedAt = base.addingTimeInterval(160 * 61)
        try? context.save()
        appState.sideChats.setLastThreadID(thread.id)
    }

    // MARK: - 层级定位

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

    private func chatScrollView() -> UIScrollView? {
        findViews(window) { view in
            view is UIScrollView
                && String(describing: type(of: view))
                    .contains("HostingScrollView")
                && self.frameInWindow(view).width > 400
        }.first as? UIScrollView
    }

    /// 舱卡（宽玻璃条）窗口帧——用户眼里的输入框顶
    private func composerCardFrame() -> CGRect? {
        guard let host = findVC(ComposerGuideHostController.self)
        else { return nil }
        return findViews(host.view) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && self.frameInWindow(view).width > 300
        }.first.map { frameInWindow($0) }
    }

    /// 顶簇宿主视图窗口帧（R3 量测对象）
    private func topPocketFrame() -> CGRect? {
        findVC(TopBarGuideHostController.self)
            .map { frameInWindow($0.traceBarView) }
    }

    /// 坞（UITabBar 本体）窗口帧＋可见性
    private func dockState() -> (frame: CGRect, hidden: Bool)? {
        guard let bar = findViews(window, where: {
            $0 is UITabBar
        }).first else { return nil }
        return (frameInWindow(bar), bar.isHidden || bar.alpha < 0.05)
    }

    /// 视口内最靠下的消息文本视图底边（末行代理量）
    private func lastTextBottomInWindow(
        in scroll: UIScrollView
    ) -> CGFloat? {
        let texts = findViews(scroll) { $0 is UITextView }
        let bottoms = texts
            .map { frameInWindow($0) }
            .filter { $0.maxY > 0 && $0.minY < 874 }
            .map { $0.maxY }
        return bottoms.max()
    }

    private struct Sample {
        var tag: String
        var contentSize: CGFloat
        var offsetY: CGFloat
        var insetBottom: CGFloat
        var insetTop: CGFloat
        var distance: CGFloat
        var cardTop: CGFloat?
        var gapToCard: CGFloat?
        var pocketY: CGFloat?
        var dockY: CGFloat?
        var dockHidden: Bool?
        // 诊断扩容（评审合成条目 10/8，2026-11-13）：
        // 原始 contentInset、尾锚 CGRect、键盘帧顶、
        // 键盘引导线顶（当前承载重验臂）、窗口安全
        // 区实值与 reportTopSafe 对照臂（顶 inset
        // 实值−顶簇高＝留位记账隐含的顶安全区，与
        // 窗口真值之差＝回报链误差）
        var rawInsetBottom: CGFloat
        var anchorRect: CGRect?
        var keyboardTop: CGFloat?
        var guideTop: CGFloat?
        var safeTop: CGFloat
        var safeBottom: CGFloat
        var impliedTopSafe: CGFloat?
    }

    /// 尾锚（栈尾 1pt 透明视图）的窗口系 CGRect：
    /// 滚动内容子树里高度 ≤2.5 的视图中取窗口底边
    /// 最大者（评审条目 10 加录项）
    private func tailAnchorRect(
        in scroll: UIScrollView
    ) -> CGRect? {
        let candidates = findViews(scroll) { view in
            view.frame.height >= 0.4
                && view.frame.height <= 2.5
                && view.frame.width > 200
        }
        return candidates
            .map { frameInWindow($0) }
            .max(by: { $0.maxY < $1.maxY })
    }

    /// 真键盘窗口顶（键盘窗口系类名定位，与装配回
    /// 归测试的找键盘帧同式）；无键盘窗口记 nil
    private func keyboardWindowTop() -> CGFloat? {
        for win in UIApplication.shared.windows {
            let name = String(describing: type(of: win))
            if name.contains("Keyboard") {
                return win.frame.minY
            }
        }
        return nil
    }

    /// 当前承载上 keyboardLayoutGuide 的可用性重
    /// 验臂（评审条目 8）：舱宿主根视图的引导线帧
    /// 顶（窗口坐标）——与真键盘顶逐拍对照，差值
    /// 即引导线在本承载＋本运行环境下的跟踪误差
    /// （§194 的退役证据出自真机旧承载；本臂只证
    /// 模拟器当前承载，口径在报告里分开记）
    private func composerGuideTop() -> CGFloat? {
        guard let host = findVC(
            ComposerGuideHostController.self
        ) else { return nil }
        let frame = host.view.keyboardLayoutGuide
            .layoutFrame
        return host.view.convert(frame, to: window).minY
    }

    private func takeSample(
        _ tag: String, scroll: UIScrollView
    ) -> Sample {
        let card = composerCardFrame()
        let lastBottom = lastTextBottomInWindow(in: scroll)
        let dock = dockState()
        let pocket = topPocketFrame()
        let adjTop = scroll.adjustedContentInset.top
        return Sample(
            tag: tag,
            contentSize: scroll.contentSize.height,
            offsetY: scroll.contentOffset.y,
            insetBottom: scroll.adjustedContentInset.bottom,
            insetTop: adjTop,
            distance: scroll.contentSize.height
                - scroll.contentOffset.y - scroll.bounds.height,
            cardTop: card?.minY,
            gapToCard: card.flatMap { c in
                lastBottom.map { c.minY - $0 }
            },
            pocketY: pocket?.minY,
            dockY: dock?.frame.minY,
            dockHidden: dock?.hidden,
            rawInsetBottom: scroll.contentInset.bottom,
            anchorRect: tailAnchorRect(in: scroll),
            keyboardTop: keyboardWindowTop(),
            guideTop: composerGuideTop(),
            safeTop: window.safeAreaInsets.top,
            safeBottom: window.safeAreaInsets.bottom,
            impliedTopSafe: pocket.map { adjTop - $0.height }
        )
    }

    private func fmt(_ s: Sample) -> String {
        func n(_ v: CGFloat?) -> String {
            v.map { String(Int($0.rounded())) } ?? "-"
        }
        let anchor = s.anchorRect.map {
            "\(Int($0.minX)),\(Int($0.minY)),"
                + "\(Int($0.width))x\(Int($0.height))"
        } ?? "-"
        return "KBFLOW \(s.tag)"
            + " cs=\(Int(s.contentSize.rounded()))"
            + " off=\(Int(s.offsetY.rounded()))"
            + " dist=\(Int(s.distance.rounded()))"
            + " inB=\(Int(s.insetBottom.rounded()))"
            + " inT=\(Int(s.insetTop.rounded()))"
            + " rawB=\(Int(s.rawInsetBottom.rounded()))"
            + " cardTop=\(n(s.cardTop))"
            + " gap=\(n(s.gapToCard))"
            + " pocketY=\(n(s.pocketY))"
            + " dockY=\(n(s.dockY))"
            + " dockHidden=\(s.dockHidden.map { $0 ? 1 : 0 } ?? -1)"
            + " anchor=\(anchor)"
            + " kbTop=\(n(s.keyboardTop))"
            + " guideTop=\(n(s.guideTop))"
            + " saT=\(Int(s.safeTop.rounded()))"
            + " saB=\(Int(s.safeBottom.rounded()))"
            + " impTS=\(n(s.impliedTopSafe))"
    }

    // MARK: - 诊断主程

    func testKeyboardFlowAccountingDiagnostic() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "kbflow-\(UUID().uuidString)", isDirectory: true
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
        seedLongThread(into: container, appState: appState)

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
            chatScrollView(), "聊天滚动视图缺席，诊断无从跑起"
        )
        var lines: [String] = []
        lines.append("KBFLOW-DIAG-BEGIN winSafe="
            + "\(window.safeAreaInsets)")

        // 阶段 0：落点静息（开线程首帧贴底＋复核跑完
        // 后的定态）——用户 173pt 残余的对应位
        for i in 0..<5 {
            spinRunLoop(seconds: 0.4)
            window.layoutIfNeeded()
            lines.append(fmt(takeSample("rest\(i)", scroll: scroll)))
        }

        // 阶段 1：上滑到中段并等量实稳定
        let midOffset = scroll.contentSize.height * 0.45
        scroll.setContentOffset(
            CGPoint(x: 0, y: midOffset), animated: false
        )
        spinRunLoop(seconds: 1.5)
        window.layoutIfNeeded()
        lines.append(fmt(takeSample("mid", scroll: scroll)))

        // 阶段 2：按当前（估算）最大值动画回底——
        // scrollTo 锚点落点的同构复刻；逐 100ms 同录
        // 至读数稳定，捕落点缺口与收敛全程
        func scrollToEstimatedBottom(_ tag: String) {
            let target = scroll.contentSize.height
                - scroll.bounds.height
                + scroll.adjustedContentInset.bottom
            scroll.setContentOffset(
                CGPoint(x: 0, y: max(0, target)), animated: true
            )
            var prevCS: CGFloat = -1
            var stableRun = 0
            for i in 0..<45 {
                spinRunLoop(seconds: 0.1)
                let s = takeSample("\(tag)\(i)", scroll: scroll)
                lines.append(fmt(s))
                if abs(s.contentSize - prevCS) <= 1 {
                    stableRun += 1
                    if stableRun >= 6, i > 10 { break }
                } else {
                    stableRun = 0
                }
                prevCS = s.contentSize
            }
        }
        scrollToEstimatedBottom("land")
        // 第二贴（复贴同构）：稳定后再按新最大值贴一次
        scrollToEstimatedBottom("re")

        // 阶段 3：键盘周期——聚焦升起逐拍同录、失焦
        // 收回逐拍同录＋3 秒尾巴（顶簇位移与落定尾巴
        // 的逐拍序列在此一并落账）
        let composer = try XCTUnwrap(
            findVC(ComposerGuideHostController.self),
            "输入舱宿主缺席"
        )
        let textView = try XCTUnwrap(
            findViews(composer.view) { $0 is UITextView }.first,
            "输入舱文本视图缺席"
        )
        let pocketBefore = topPocketFrame()?.minY ?? -1
        XCTAssertTrue(
            textView.becomeFirstResponder(),
            "输入框未能成为第一响应者，键盘段无从验起"
        )
        var rose = false
        for i in 0..<20 {
            spinRunLoop(seconds: 0.1)
            window.layoutIfNeeded()
            let s = takeSample("up\(i)", scroll: scroll)
            lines.append(fmt(s))
            if let top = s.cardTop, top < 560 { rose = true }
            if rose, i >= 8 { break }
        }
        lines.append("KBFLOW keyboardRose=\(rose)")
        XCTAssertTrue(rose, "键盘未升起（舱顶未上移）")
        spinRunLoop(seconds: 0.8)
        lines.append(fmt(takeSample("upSettled", scroll: scroll)))

        textView.resignFirstResponder()
        var prevPocket: CGFloat = pocketBefore
        var maxPocketDev: CGFloat = 0
        for i in 0..<40 {
            spinRunLoop(seconds: 0.1)
            window.layoutIfNeeded()
            let s = takeSample("down\(i)", scroll: scroll)
            lines.append(fmt(s))
            if let y = s.pocketY {
                maxPocketDev = max(
                    maxPocketDev, abs(y - pocketBefore)
                )
                prevPocket = y
            }
            _ = prevPocket
        }
        lines.append(
            "KBFLOW pocketDevMaxDuringDown="
                + "\(Int(maxPocketDev.rounded()))"
                + " pocketBefore=\(Int(pocketBefore.rounded()))"
        )
        lines.append("KBFLOW-DIAG-END")
        let text = lines.joined(separator: "\n")
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
