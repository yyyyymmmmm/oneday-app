import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 双击选字·生产同构 rig（fix/text-selection-doubletap）
///
/// 仪器与判读纪律（承调研 chat-surface-selection-
/// research-20261113 §2.6，避一行装置覆辙）：
/// - 装配走 App 自家组合根（RootView＋DemoHermes-
///   Client＋落盘种子长会话），全栈在场：栈级收键
///   盘 tap、行级 contextMenu、右滑 simultaneous-
///   Gesture、抽屉容器、LazyVStack 多行；
/// - 触摸为伪造 UITouch/UIEvent 经 window.sendEvent
///   投递，走系统真仲裁（不是直接写 selectedRange）；
/// - 仪器自检臂（裸文本视图）先行：自检不过＝仪器
///   无效，任何产品判读不成立；
/// - 双击与长按分开统计；指标＝选区形成（selected-
///   Range 与目标词 NSRange 逐字相等）＋1 秒存活；
/// - 消融臂在真装配上运行时关掉单层祖先识别器
///   （单变量），关了什么逐条打印留痕。
@MainActor
final class TextSelectionDoubleTapRigTests: XCTestCase {

    // MARK: - 伪造触摸

    private final class RigTouch: UITouch {
        private let windowPoint: CGPoint
        private weak var hostWindow: UIWindow?
        var rigPhase: UITouch.Phase = .began
        var rigTapCount: Int = 1
        var rigTimestamp: TimeInterval = 0

        init(point: CGPoint, window: UIWindow) {
            windowPoint = point
            hostWindow = window
            super.init()
        }

        override var phase: UITouch.Phase { rigPhase }
        override var tapCount: Int { rigTapCount }
        override var timestamp: TimeInterval { rigTimestamp }

        override func location(in view: UIView?) -> CGPoint {
            guard let view, let hostWindow else { return windowPoint }
            return view.convert(windowPoint, from: hostWindow)
        }

        override func previousLocation(
            in view: UIView?
        ) -> CGPoint {
            location(in: view)
        }
    }

    private final class RigEvent: UIEvent {
        var rigTouches: Set<UITouch> = []
        var rigTimestamp: TimeInterval = 0

        override var allTouches: Set<UITouch>? { rigTouches }
        override var timestamp: TimeInterval { rigTimestamp }
        override var type: UIEvent.EventType { .touches }
        override var subtype: UIEvent.EventSubtype { .none }

        override func touches(
            for view: UIView
        ) -> Set<UITouch>? { rigTouches }

        override func touches(
            for window: UIWindow
        ) -> Set<UITouch>? { rigTouches }

        override func touches(
            for gesture: UIGestureRecognizer
        ) -> Set<UITouch>? { rigTouches }
    }

    /// 触摸投递器：相位序列＋假时钟，拍间旋主循环让
    /// 识别器状态机与多击计时器真实推进
    private final class TouchDriver {
        let window: UIWindow
        var clock: TimeInterval

        init(window: UIWindow) {
            self.window = window
            clock = ProcessInfo.processInfo.systemUptime
        }

        private func deliver(
            _ touch: RigTouch, phase: UITouch.Phase
        ) {
            touch.rigPhase = phase
            touch.rigTimestamp = clock
            let event = RigEvent()
            event.rigTouches = [touch]
            event.rigTimestamp = clock
            window.sendEvent(event)
        }

        private func tick(_ seconds: TimeInterval) {
            clock += seconds
        }

        /// 单击（按下→抬起）
        func tap(at point: CGPoint, tapCount: Int = 1) {
            let touch = RigTouch(point: point, window: window)
            touch.rigTapCount = tapCount
            deliver(touch, phase: .began)
            tick(0.06)
            deliver(touch, phase: .ended)
        }

        /// 双击：两拍间隔 0.16s（假时钟），投递间旋
        /// 主循环放行识别器计时
        func doubleTap(
            at point: CGPoint, spin: (TimeInterval) -> Void
        ) {
            tap(at: point, tapCount: 1)
            spin(0.10)
            tick(0.06)
            tap(at: point, tapCount: 2)
            spin(0.05)
        }

        /// 长按：按下后保持 0.7s（旋主循环）再抬起
        func longPress(
            at point: CGPoint, spin: (TimeInterval) -> Void
        ) {
            let touch = RigTouch(point: point, window: window)
            deliver(touch, phase: .began)
            spin(0.70)
            tick(0.70)
            deliver(touch, phase: .ended)
        }

        /// 拖动：起点按下→分步 moved→抬起
        func drag(
            from start: CGPoint,
            to end: CGPoint,
            steps: Int = 6,
            spin: (TimeInterval) -> Void
        ) {
            let touch = RigTouch(point: start, window: window)
            deliver(touch, phase: .began)
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                )
                let moved = RigTouch(point: point, window: window)
                moved.rigTapCount = 1
                tick(0.03)
                deliver(moved, phase: .moved)
                spin(0.02)
            }
            tick(0.03)
            let up = RigTouch(point: end, window: window)
            deliver(up, phase: .ended)
        }
    }

    // MARK: - 装配

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

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

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "selrig-\(UUID().uuidString)", isDirectory: true
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

    /// 种子会话：24 条交替消息（长散文），末条助手
    /// 消息首段埋三个互不相同的目标词，供双击三连
    /// 与拖柄/长按各臂取点（互不污染）
    private let targetWords = ["ZEBRAWORD", "QUARKWORD", "JUNIPERWORD"]
    private let fillerParagraph = """
    但有一条必须盯死：最低输出功率。86 平米采暖只要 \
    7～9kW，如果你买的炉子最小火就是 7kW 甚至更高，它就会不停地 \
    开开关关，费气、有噪音、还伤机器。选最低输出 ≤4kW 的冷凝炉，\
    最好能到 3kW 出头，这样大部分时间它都稳在低火运行。\
    这一条比牌子重要。照单抓药，买的时候问商家这几项：\
    型式是燃气冷凝两用炉，采暖加生活热水一体。\
    额定 24kW，最低输出功率 ≤4kW。采暖水温能调到 \
    40～50°C（地暖专用低温档），最好支持室外温度补偿。
    """

    private func seedThread(
        into container: ModelContainer, appState: AppState
    ) {
        let context = ModelContext(container)
        let thread = ChatThread(title: "选字 rig")
        context.insert(thread)
        let base = Date().addingTimeInterval(-6 * 3600)
        for index in 0..<24 {
            let isUser = index % 2 == 0
            let entry = ChatEntry(
                role: isUser ? "user" : "assistant",
                content: isUser
                    ? "第 \(index / 2 + 1) 问：这个参数再确认一下。"
                    : fillerParagraph,
                thread: thread
            )
            entry.createdAt = base
                .addingTimeInterval(Double(index * 61))
            context.insert(entry)
        }
        // 末条（助手）：目标段——目标词各居一句、段
        // 首即达（防引用条/片段截断丢词）
        let target = ChatEntry(
            role: "assistant",
            content: "先说结论。The ZEBRAWORD marks the first "
                + "checkpoint clearly. Then the QUARKWORD sits "
                + "in the middle of this passage. Finally the "
                + "JUNIPERWORD closes the target paragraph "
                + "with enough trailing words after it.",
            thread: thread
        )
        target.createdAt = base.addingTimeInterval(24 * 61)
        context.insert(target)
        thread.createdAt = base
        thread.updatedAt = base.addingTimeInterval(24 * 61)
        try? context.save()
        appState.sideChats.setLastThreadID(thread.id)
    }

    private struct Assembly {
        var appState: AppState
        var container: ModelContainer
    }

    private func assemble() throws -> Assembly {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        seedThread(into: container, appState: appState)
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
        let win = DeviceWindow(windowScene: scene)
        win.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window = win
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 3.5)
        window.layoutIfNeeded()
        return Assembly(appState: appState, container: container)
    }

    // MARK: - 视图定位与几何

    private func allViews(_ root: UIView) -> [UIView] {
        var out = [root]
        for sub in root.subviews { out += allViews(sub) }
        return out
    }

    /// 在场可选文本视图（承载类）全集
    private func carrierTextViews() -> [SelectableUITextView] {
        guard let root = window.rootViewController?.view
        else { return [] }
        return allViews(root).compactMap {
            $0 as? SelectableUITextView
        }
    }

    /// 含目标词且整帧落在窗口内的承载视图（取最后
    /// 一条消息的散文视图）
    private func targetTextView(
        word: String
    ) -> (view: SelectableUITextView, range: NSRange)? {
        for view in carrierTextViews() {
            guard let text = view.attributedText?.string,
                  let hit = text.range(of: word)
            else { continue }
            let frame = view.convert(view.bounds, to: window)
            guard frame.minY > 90, frame.maxY < 874 - 120,
                  frame.width > 100
            else { continue }
            return (view, NSRange(hit, in: text))
        }
        return nil
    }

    /// 目标词在窗口坐标中的点位（经 UITextInput 的
    /// selectionRects 取词矩形中心——公开 API、不碰
    /// layoutManager 防 TK1 回退）
    private func windowPoint(
        in view: SelectableUITextView, range: NSRange
    ) -> CGPoint? {
        guard let start = view.position(
            from: view.beginningOfDocument, offset: range.location
        ), let end = view.position(
            from: start, offset: range.length
        ), let textRange = view.textRange(from: start, to: end)
        else { return nil }
        let rects = view.selectionRects(for: textRange)
        guard let first = rects.first, first.rect.width > 0
        else { return nil }
        let center = CGPoint(
            x: first.rect.midX, y: first.rect.midY
        )
        return view.convert(center, to: window)
    }

    private func fmt(_ r: NSRange) -> String {
        "{\(r.location),\(r.length)}"
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("SELRIG-BEGIN")
        print(text)
        print("SELRIG-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 普查（手势识别器图谱）

    /// 自承载视图起逐祖先打印识别器图谱：视图类、
    /// 识别器类、cancels/delays/enabled/委托有无
    private func census(from leaf: UIView) -> [String] {
        var lines: [String] = []
        var view: UIView? = leaf
        var depth = 0
        while let current = view, depth < 14 {
            let typeName = String(describing: type(of: current))
            let frame = current.convert(current.bounds, to: window)
            lines.append(
                "L\(depth) \(typeName) "
                    + "frame=(\(Int(frame.minX)),\(Int(frame.minY)) "
                    + "\(Int(frame.width))x\(Int(frame.height))) "
                    + "recs=\(current.gestureRecognizers?.count ?? 0)"
            )
            for (i, rec) in (current.gestureRecognizers ?? [])
                .enumerated() {
                var desc = "  [\(i)] \(String(describing: type(of: rec)))"
                    + " state=\(rec.state.rawValue)"
                    + " enabled=\(rec.isEnabled)"
                    + " cancels=\(rec.cancelsTouchesInView)"
                    + " delaysBegan=\(rec.delaysTouchesBegan)"
                    + " delaysEnded=\(rec.delaysTouchesEnded)"
                    + " delegate=\(rec.delegate != nil)"
                if let tap = rec as? UITapGestureRecognizer {
                    desc += " taps=\(tap.numberOfTapsRequired)"
                }
                if let press = rec as? UILongPressGestureRecognizer {
                    desc += " minDur=\(press.minimumPressDuration)"
                }
                lines.append(desc)
            }
            view = current.superview
            depth += 1
        }
        return lines
    }

    // MARK: - 仪器自检臂（裸文本）

    /// 裸 SelectableInlineText（无任何祖先手势）双击
    /// 应选中目标词。自检不过＝伪造触摸仪器无效，
    /// 后续产品判读全部不成立（本用例单独红、注明）
    func testInstrumentSelfCheckBareTextView() throws {
        let word = "SELF CHECK".components(separatedBy: " ")[0]
        let text = "alpha SELFCHECKWORD bravo charlie delta"
        let host = UIHostingController(
            rootView: SelectableInlineText(
                paragraphs: [.plain(text)]
            )
            .frame(width: 320, alignment: .leading)
            .padding()
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        )
        let win = DeviceWindow(windowScene: scene)
        win.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window = win
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 1.0)
        window.layoutIfNeeded()

        let view = try XCTUnwrap(
            carrierTextViews().first, "自检台无承载视图"
        )
        let range = (text as NSString)
            .range(of: "SELFCHECKWORD")
        let point = try XCTUnwrap(
            windowPoint(in: view, range: range), "自检词无矩形"
        )
        let driver = TouchDriver(window: window)
        driver.doubleTap(at: point) { spinRunLoop(seconds: $0) }
        spinRunLoop(seconds: 0.6)
        emit([
            "SELFCHECK word=\(word) target=\(fmt(range))",
            "SELFCHECK selected=\(fmt(view.selectedRange))",
            "SELFCHECK verdict="
                + (view.selectedRange == range ? "VALID" : "INVALID"),
        ])
        XCTAssertEqual(
            view.selectedRange, range,
            "仪器自检失败：裸文本双击未选中目标词"
                + "（伪造触摸未穿过系统仲裁）——仪器无效"
        )
    }

    // MARK: - 生产臂（双击三连＋存活）

    /// 双击程序化打三个目标词：逐词断言选区与目标
    /// 词逐字相等、形成后 1 秒仍存活。返回逐词读数
    private func runDoubleTapBattery(
        label: String
    ) -> [String] {
        var lines: [String] = []
        var formed = 0
        for word in targetWords {
            guard let target = targetTextView(word: word),
                  let point = windowPoint(
                      in: target.view, range: target.range
                  )
            else {
                lines.append("\(label) \(word): TARGET-MISSING")
                continue
            }
            let driver = TouchDriver(window: window)
            driver.doubleTap(at: point) {
                spinRunLoop(seconds: $0)
            }
            spinRunLoop(seconds: 0.5)
            let now = target.view.selectedRange
            let alive: Bool
            if now == target.range {
                spinRunLoop(seconds: 1.0)
                alive = target.view.selectedRange == target.range
            } else {
                alive = false
            }
            if now == target.range { formed += 1 }
            lines.append(
                "\(label) \(word) target=\(fmt(target.range)) "
                    + "selected=\(fmt(now)) formed=\(now == target.range) "
                    + "alive1s=\(alive)"
            )
        }
        lines.append("\(label) formed=\(formed)/\(targetWords.count)")
        return lines
    }

    /// 生产原样臂：普查留痕＋双击电池（修复前应红、
    /// 读数即定因证据；修复后本臂即验收臂）
    func testProductionDoubleTap() throws {
        _ = try assemble()
        let probe = try XCTUnwrap(
            targetTextView(word: targetWords[0]),
            "目标文本视图未在场（装配或定位失败）"
        )
        var lines = census(from: probe.view)
        lines += runDoubleTapBattery(label: "PROD")
        emit(lines)
        XCTAssertTrue(
            lines.last?.contains("formed=3/3") == true,
            "生产双击形成率未满：\n" + lines.joined(separator: "\n")
        )
    }

    // MARK: - 消融臂（运行时关单层、单变量）

    private enum Ablation {
        case ancestorTaps      // 栈级 tap（C1）
        case ancestorLongPress // 行级 contextMenu 长按（C2）
        case ancestorPans      // 行级右滑 Drag（C3）
    }

    /// 在真装配上关掉一类祖先识别器（承载视图自身
    /// 与列表滚动视图本体的不碰），逐条打印被关件
    private func ablate(
        _ kind: Ablation, from leaf: UIView
    ) -> [String] {
        var lines: [String] = []
        var view = leaf.superview
        while let current = view {
            if current is UIScrollView { break }
            for rec in current.gestureRecognizers ?? [] {
                let hit: Bool
                switch kind {
                case .ancestorTaps:
                    hit = rec is UITapGestureRecognizer
                case .ancestorLongPress:
                    hit = rec is UILongPressGestureRecognizer
                case .ancestorPans:
                    hit = rec is UIPanGestureRecognizer
                }
                if hit, rec.isEnabled {
                    rec.isEnabled = false
                    lines.append(
                        "ABLATED \(kind) on "
                            + "\(String(describing: type(of: current)))"
                            + " rec="
                            + "\(String(describing: type(of: rec)))"
                    )
                }
            }
            view = current.superview
        }
        if lines.isEmpty {
            lines.append("ABLATED \(kind): NONE-FOUND")
        }
        return lines
    }

    private func ablationTest(_ kind: Ablation) throws {
        _ = try assemble()
        let probe = try XCTUnwrap(
            targetTextView(word: targetWords[0]),
            "目标文本视图未在场"
        )
        var lines = ablate(kind, from: probe.view)
        lines += runDoubleTapBattery(label: "ABL-\(kind)")
        emit(lines)
        XCTAssertTrue(
            lines.last?.contains("formed=3/3") == true,
            "消融 \(kind) 后形成率未满：\n"
                + lines.joined(separator: "\n")
        )
    }

    func testAblationAncestorTaps() throws {
        try ablationTest(.ancestorTaps)
    }

    func testAblationAncestorLongPress() throws {
        try ablationTest(.ancestorLongPress)
    }

    func testAblationAncestorPans() throws {
        try ablationTest(.ancestorPans)
    }

    // MARK: - 长按臂（C2 分辨）

    /// 长按目标词：文本选字长按应形成同词选区（若
    /// 长按也被行菜单夺走，读数会是空选区）
    func testLongPressSelectsWord() throws {
        _ = try assemble()
        let target = try XCTUnwrap(
            targetTextView(word: targetWords[1]),
            "目标文本视图未在场"
        )
        let point = try XCTUnwrap(
            windowPoint(in: target.view, range: target.range)
        )
        let driver = TouchDriver(window: window)
        driver.longPress(at: point) { spinRunLoop(seconds: $0) }
        spinRunLoop(seconds: 0.5)
        let selected = target.view.selectedRange
        emit([
            "LONGPRESS target=\(fmt(target.range)) "
                + "selected=\(fmt(selected))",
        ])
        XCTAssertEqual(
            selected, target.range,
            "长按未形成目标词选区"
        )
    }

    // MARK: - 拖柄扩选臂

    /// 选区形成后拖尾柄向右扩选：选区起点不变、长
    /// 度变大（手柄由系统选区交互承接）
    func testHandleDragExpandsSelection() throws {
        _ = try assemble()
        let target = try XCTUnwrap(
            targetTextView(word: targetWords[0]),
            "目标文本视图未在场"
        )
        let point = try XCTUnwrap(
            windowPoint(in: target.view, range: target.range)
        )
        let driver = TouchDriver(window: window)
        driver.doubleTap(at: point) { spinRunLoop(seconds: $0) }
        spinRunLoop(seconds: 0.5)
        let formed = target.view.selectedRange
        guard formed == target.range else {
            emit(["HANDLE formed=\(fmt(formed)) — 未形成，拖柄无从测"])
            XCTFail("选区未形成，拖柄臂不成立：\(fmt(formed))")
            return
        }
        // 尾柄点位：选区尾矩形右缘（selectionRects）
        guard let start = target.view.position(
            from: target.view.beginningOfDocument,
            offset: formed.location
        ), let end = target.view.position(
            from: start, offset: formed.length
        ), let textRange = target.view.textRange(
            from: start, to: end
        ), let lastRect = target.view.selectionRects(
            for: textRange
        ).last
        else {
            XCTFail("选区矩形不可得")
            return
        }
        let handleInView = CGPoint(
            x: lastRect.rect.maxX, y: lastRect.rect.midY
        )
        let handle = target.view.convert(handleInView, to: window)
        let dragEnd = CGPoint(x: handle.x + 60, y: handle.y)
        driver.drag(from: handle, to: dragEnd) {
            spinRunLoop(seconds: $0)
        }
        spinRunLoop(seconds: 0.5)
        let grown = target.view.selectedRange
        emit([
            "HANDLE formed=\(fmt(formed)) grown=\(fmt(grown))",
        ])
        XCTAssertEqual(
            grown.location, formed.location, "扩选起点不应移位"
        )
        XCTAssertGreaterThan(
            grown.length, formed.length, "拖柄后选区未扩大"
        )
    }

    // MARK: - 回归臂（收键盘 tap／右滑回复）

    /// 回归一：作曲舱聚焦后，点消息区空白（目标行
    /// 左缘页边距、栈命中域内）应收键盘
    func testBlankTapDismissesKeyboard() throws {
        _ = try assemble()
        let target = try XCTUnwrap(
            targetTextView(word: targetWords[0]),
            "目标文本视图未在场"
        )
        // 作曲舱文本视图：全窗 UITextView 中非承载、
        // 位于窗口下半者
        let composer = allViews(
            window.rootViewController!.view
        ).compactMap { $0 as? UITextView }
            .first {
                !($0 is SelectableUITextView)
                    && $0.convert($0.bounds, to: window).minY > 500
            }
        let composerView = try XCTUnwrap(
            composer, "作曲舱文本视图未在场"
        )
        composerView.becomeFirstResponder()
        spinRunLoop(seconds: 0.4)
        XCTAssertTrue(
            composerView.isFirstResponder, "作曲舱未能聚焦（前置失败）"
        )
        let rowFrame = target.view.convert(
            target.view.bounds, to: window
        )
        let blank = CGPoint(x: 6, y: rowFrame.midY)
        let driver = TouchDriver(window: window)
        driver.tap(at: blank)
        spinRunLoop(seconds: 0.5)
        emit([
            "DISMISS firstResponderAfter="
                + "\(composerView.isFirstResponder)",
        ])
        XCTAssertFalse(
            composerView.isFirstResponder,
            "点空白后键盘未收（收键盘行为回归）"
        )
    }

    /// 回归二：目标行横向拖动（自左缘页边距起手、
    /// 向右 90pt）应触发右滑回复——引用条入作曲舱
    /// （窗口内出现含目标词的引用文本）
    func testSwipeReplyStillTriggers() throws {
        _ = try assemble()
        let target = try XCTUnwrap(
            targetTextView(word: targetWords[0]),
            "目标文本视图未在场"
        )
        let rowFrame = target.view.convert(
            target.view.bounds, to: window
        )
        let start = CGPoint(x: 24, y: rowFrame.midY)
        let end = CGPoint(x: 114, y: rowFrame.midY)
        let driver = TouchDriver(window: window)
        driver.drag(from: start, to: end) {
            spinRunLoop(seconds: $0)
        }
        spinRunLoop(seconds: 0.8)
        // 引用落点：作曲舱上方出现含目标词的文本载体
        let quotePresent = allViews(
            window.rootViewController!.view
        ).contains { view in
            guard let label = view.accessibilityLabel,
                  label.contains(targetWords[0])
            else { return false }
            let frame = view.convert(view.bounds, to: window)
            return frame.minY > 500
        }
        emit(["SWIPE quotePresent=\(quotePresent)"])
        XCTAssertTrue(
            quotePresent, "右滑后引用未入作曲舱（右滑回复回归）"
        )
    }
}
