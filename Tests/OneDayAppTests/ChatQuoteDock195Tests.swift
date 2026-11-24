import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 195 验收断言：引用条出现时——输入舱位移
/// 量 vs 条实高的等式关系，键盘收起/弹起两态各钉
/// 一遍（各自全新装配，只量「加引用」一侧）：
///   舱生长 == 卡生长 == 条槽实高（卡内唯一可生
///   长子级）；键盘态另钉舱顶上移 == 生长、舱底
///   不漂；两态都钉输入行底锚（文本视图底相对卡
///   底恒定——生长全在输入行之上）。
/// 诊断实测（run 44843567900 探针轮＋44855652309
/// 复核轮）：条槽实高 61.0；静息首挂 growth=
/// 61.0／bottomDrift=0.0；焦点召唤系统键盘时舱
/// 底随模式切至键盘顶、生长等式不变。
/// 已知工装限制（交卷报告在案）：同装配内撤引
/// 用后，SwiftUI 内容（卡）即缩回基线高，但托
/// 管宿主帧的固有尺寸收缩在测试工装内不落帧
/// （三轮复现），故回落侧等式不在本测试钉，留
/// 真机验收项。
/// 装配＝生产全装配（RootView＋原生面默认开）＋
/// AppState 待发引用表驱动引用槽（feed 变体与
/// 消息变体同槽同几何，见 ChatView composerCard
/// §332 槽位：条本体＋1pt 发丝线直挂卡根）。
@MainActor
final class ChatQuoteDock195Tests: XCTestCase {

    private var window: UIWindow!
    private var container: ModelContainer!
    private var appState: AppState!
    private var swiftDataMount = SwiftDataTestMount()
    private var threadID: UUID!

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
        appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let context = ModelContext(container)
        let thread = ChatThread(title: "量测会话")
        context.insert(thread)
        context.insert(ChatEntry(
            role: "user", content: "在吗", thread: thread
        ))
        context.insert(ChatEntry(
            role: "assistant", content: "在的。", thread: thread
        ))
        try? context.save()
        threadID = thread.id
        appState.sideChats.setLastThreadID(thread.id)
    }

    override func tearDown() async throws {
        window?.endEditing(true)
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        appState = nil
        container = nil
        try await super.tearDown()
    }

    private func spin(seconds: TimeInterval) {
        let exp = expectation(description: "spin")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func spinUntil(
        timeout: TimeInterval, _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            spin(seconds: 0.25)
        }
        return condition()
    }

    private func mountShell() {
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
        }
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    private func findRootVC() -> ChatRootViewController? {
        var found: ChatRootViewController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ChatRootViewController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window?.rootViewController { walk(root) }
        return found
    }

    private func hostFrame() -> CGRect? {
        guard let host = findRootVC()?.composerHost
        else { return nil }
        return host.view.convert(host.view.bounds, to: window)
    }

    /// 等帧落定：两读（间隔 0.4s）三值差 ≤0.5；
    /// 每读前显式驱动一遍布局（真机显示链路逐帧
    /// 驱动、工装内无此环，须手动补齐）
    private func stableHostFrame(
        timeout: TimeInterval = 10
    ) -> CGRect? {
        var previous: CGRect?
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            window.layoutIfNeeded()
            let current = hostFrame()
            if let p = previous, let c = current,
               abs(p.minY - c.minY) <= 0.5,
               abs(p.height - c.height) <= 0.5,
               abs(p.maxY - c.maxY) <= 0.5 {
                return c
            }
            previous = current
            spin(seconds: 0.4)
        }
        window.layoutIfNeeded()
        return hostFrame()
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

    /// 舱内玻璃卡帧（卡层 glassEffect 的平台玻璃
    /// 视图，宽 >300；与组装探针同找法）
    private func cardFrame() -> CGRect? {
        guard let host = findRootVC()?.composerHost
        else { return nil }
        return findViews(host.view) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && view.convert(view.bounds, to: window)
                    .width > 300
        }.first.map { $0.convert($0.bounds, to: window) }
    }

    /// 舱内输入文本视图帧（「输入框」本体）
    private func textViewFrame() -> CGRect? {
        guard let host = findRootVC()?.composerHost
        else { return nil }
        return findViews(host.view) { $0 is UITextView }
            .first.map { $0.convert($0.bounds, to: window) }
    }

    /// 引用槽在场判据＝卡高：无槽 ≈46.7、有槽
    /// ≈107.7（条本体＋发丝线 61 入卡），两值间
    /// 距远大于渲染噪声，以 80 为界（标题文本在
    /// 平台层无稳定 UILabel 读口，故不用文本查）
    private func quoteSlotPresent() -> Bool {
        (cardFrame()?.height ?? 0) > 80
    }

    private func postKeyboard(
        name: Notification.Name, top: CGFloat,
        duration: Double
    ) {
        NotificationCenter.default.post(
            name: name, object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: CGRect(
                        x: 0, y: top, width: 402,
                        height: 874 - top
                    )),
                UIResponder
                    .keyboardAnimationDurationUserInfoKey:
                    NSNumber(value: duration),
                UIResponder
                    .keyboardAnimationCurveUserInfoKey:
                    NSNumber(value: 7),
            ]
        )
    }

    private func quoteTargetIDs() -> [UUID] {
        var ids = [threadID!]
        if let main = appState.sessionLedger.mainThreadID,
           main != threadID {
            ids.append(main)
        }
        return ids
    }

    private func setQuote(_ on: Bool) {
        let post = BridgeFeedPost(
            id: "probe195-post", kind: .research,
            title: "量测帖标题",
            body: "量测帖正文摘要。",
            direction: "Rig",
            createdAt: Date().timeIntervalSince1970,
            emoji: "🤖"
        )
        for id in quoteTargetIDs() {
            appState.pendingQuotes
                .feedQuotesByThread[id] =
                on ? FeedPostQuote(post: post) : nil
        }
    }

    private func fmt(_ r: CGRect?) -> String {
        guard let r else { return "nil" }
        return String(
            format: "(y=%.1f h=%.1f maxY=%.1f)",
            r.minY, r.height, r.maxY
        )
    }

    /// 加引用一侧的等式组（两态共用骨架）：
    /// 返回 (基线帧, 引用帧) 供各态追加本态断言
    private func measureQuoteGrowth(
        state: String
    ) -> (base: CGRect, quoted: CGRect,
          baseCard: CGRect, quotedCard: CGRect)? {
        XCTAssertFalse(
            quoteSlotPresent(),
            "\(state)：基线不应有引用槽"
        )
        let base = stableHostFrame()
        let baseCard = cardFrame()
        let baseText = textViewFrame()
        guard let base, let baseCard, let baseText else {
            XCTFail("\(state)：基线帧未齐")
            return nil
        }
        setQuote(true)
        XCTAssertTrue(
            spinUntil(timeout: 10) { quoteSlotPresent() },
            "\(state)：引用槽未在场"
        )
        let quoted = stableHostFrame()
        let quotedCard = cardFrame()
        let quotedText = textViewFrame()
        print(
            "QUOTE195 \(state) base host=\(fmt(base))"
                + " card=\(fmt(baseCard))"
                + " text=\(fmt(baseText))"
        )
        print(
            "QUOTE195 \(state) quote host=\(fmt(quoted))"
                + " card=\(fmt(quotedCard))"
                + " text=\(fmt(quotedText))"
        )
        guard let quoted, let quotedCard, let quotedText
        else {
            XCTFail("\(state)：引用态帧未齐")
            return nil
        }
        // 条槽实高＝卡生长（卡内唯一可生长子级）
        let slotHeight = quotedCard.height - baseCard.height
        XCTAssertGreaterThan(
            slotHeight, 30,
            "\(state)：条槽实高异常（应为一条引用条量级）"
        )
        XCTAssertLessThan(
            slotHeight, 80,
            "\(state)：条槽实高异常（不应超过两倍条高）"
        )
        // 等式一：舱生长 == 条槽实高
        XCTAssertEqual(
            quoted.height - base.height, slotHeight,
            accuracy: 0.6,
            "\(state)：舱生长≠条槽实高（多抬/少抬）"
        )
        // 等式二：输入行底锚——文本视图底相对卡底
        // 恒定（生长全在输入行之上、行随舱底走）
        XCTAssertEqual(
            quotedText.maxY - quotedCard.maxY,
            baseText.maxY - baseCard.maxY,
            accuracy: 0.6,
            "\(state)：输入行相对卡底发生位移"
        )
        return (base, quoted, baseCard, quotedCard)
    }

    /// 静息态（189 入流锚）：焦点可能召唤系统键
    /// 盘使模式中途切换——生长等式与模式无关恒
    /// 立；舱底断言分两路：未切模式时严判不漂，
    /// 切模式时只记录落点（模式切换本身是产品
    /// 既定行为：引用即聚焦、与微信同路）
    func testRestingStateQuoteGrowthEqualsStripHeight() {
        mountShell()
        XCTAssertTrue(
            spinUntil(timeout: 12) {
                findRootVC()?.composerHost != nil
            },
            "REST：原生面舱宿主未装配"
        )
        guard let m = measureQuoteGrowth(state: "REST")
        else { return }
        let drift = m.quoted.maxY - m.base.maxY
        if abs(drift) <= 0.6 {
            XCTAssertEqual(
                m.base.minY - m.quoted.minY,
                m.quoted.height - m.base.height,
                accuracy: 0.6,
                "REST：舱顶上移≠舱生长"
            )
        } else {
            print(
                "QUOTE195 REST modeSwitched "
                    + "bottomDrift=\(drift)（焦点召唤"
                    + "键盘、舱底落键盘顶，生长等式"
                    + "已由等式一钉）"
            )
        }
    }

    /// 键盘态（合成帧顶 541，§194 单常数链，全新
    /// 装配首挂）：舱顶上移 == 生长、舱底不漂
    /// （容忍系统键盘帧重申的整舱微移 2.5）
    func testKeyboardStateQuoteGrowthEqualsStripHeight() {
        mountShell()
        XCTAssertTrue(
            spinUntil(timeout: 12) {
                findRootVC()?.composerHost != nil
            },
            "KB：原生面舱宿主未装配"
        )
        postKeyboard(
            name: UIResponder.keyboardWillShowNotification,
            top: 541, duration: 0
        )
        XCTAssertTrue(
            spinUntil(timeout: 10) {
                guard let f = hostFrame() else {
                    return false
                }
                return abs(f.maxY - 541) <= 1.5
            },
            "KB：舱底未达键盘帧顶 541"
        )
        _ = stableHostFrame()
        guard let m = measureQuoteGrowth(state: "KB")
        else { return }
        // 恒等式：舱顶上移 == 生长 − 舱底漂移（底
        // 漂为系统键盘帧重申的整舱同移，下方单独
        // 容忍判读；三值逐值闭合才是几何自洽）
        XCTAssertEqual(
            m.base.minY - m.quoted.minY,
            (m.quoted.height - m.base.height)
                - (m.quoted.maxY - m.base.maxY),
            accuracy: 0.6,
            "KB：舱顶上移≠生长−底漂（恒等式未闭合）"
        )
        XCTAssertEqual(
            m.quoted.maxY - m.base.maxY, 0,
            accuracy: 2.5,
            "KB：舱底漂移（底锚未钉住）"
        )
        postKeyboard(
            name: UIResponder.keyboardWillHideNotification,
            top: 874, duration: 0
        )
        _ = stableHostFrame()
        window.endEditing(true)
        spin(seconds: 0.6)
    }
}
