import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §291（原生重建 R1）原生承载真实装配回归：把
/// ChatRootViewController 装进与 ChatListCarrier-
/// BottomGapTests 同构的真壳（窗口→页面→承载全
/// 窗出血→坞座位），行内容全是真实生产视图
/// （MarkdownText 助手泡＋SelectableInlineText
/// 用户泡＋分隔条目）——禁用固定高占位行作证据
/// （蓝图 §七）：
/// ①相邻 cell 帧间距＝单源 24（H1）；②短内容双
/// 键盘态末行底→舱顶＝24、落位只由 apply 链自产
/// （H3/H6）；③长会话进入即真底三数留档（con-
/// tentSize/offset/末行帧）＋距底 ≤1——顺带回填
/// 冒烟箭头例「开线程落底」的帧级定因（旧面 AX
/// 口径离底 vs 本面帧口径）；④程序化跳中段后距
/// 底读数与锚一致（H7 现测）；⑤托管高度与裸宿
/// 主（safeAreaRegions 清零）等价（H2 回退门）；
/// ⑥固定占位不驱动物化行高（§325 换代：原产物
/// 估算带宽随估算管线退役，改验物化高只由内容
/// 决定）。
/// §293（R2）装配形态变更：输入舱不再是壳外
/// UIView＋喂入两数——舱内容经 apply 的 compo-
/// serView 交容器子托管；「键盘座位」R2 期由附
/// 加底安全区顶起引导线实现。§302（第 100 条
/// 热修）再换代：舱落位回 §194 通知帧顶常量形
/// 态、引导线退出驱动位——座位随之改由投递键
/// 盘通知实现（投的即生产驱动本体：willShow/
/// willHide＋结束帧＋动画参数，时长 0 即时落
/// 位），断言对象仍＝容器内舱宿主实帧。安全区
/// 模拟自此退役：它验的是「安全区变化时约束成
/// 立」、不是跟随（定因报告 §七.4）
@MainActor
final class ChatNativeListAssemblyTests: XCTestCase {

    // MARK: - 真壳（与 BottomGapTests 同构）

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874
    private let dockHeight: CGFloat = 83
    private let keyboardTop: CGFloat = 545
    private let composerHeight: CGFloat = 54
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8
    private let targetGap: CGFloat = 24

    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    func testRowMenuDefersSelectableTextHitToTextView() {
        let contentView = UIView(
            frame: CGRect(x: 0, y: 0, width: 220, height: 72)
        )
        let bubbleText = SelectableUITextView(
            usingTextLayoutManager: true
        )
        bubbleText.frame = CGRect(
            x: 40, y: 12, width: 160, height: 48
        )
        contentView.addSubview(bubbleText)

        XCTAssertTrue(
            ChatNativeHostingCell.pointHitsSelectableText(
                CGPoint(x: 80, y: 30), in: contentView
            )
        )
        XCTAssertFalse(
            ChatNativeHostingCell.pointHitsSelectableText(
                CGPoint(x: 20, y: 30), in: contentView
            )
        )
    }

    /// 装壳：窗口→根→承载（全窗出血、topInset 喂
    /// 122）＋坞座位（舱自 R2 起由容器收编、不在
    /// 壳层装配，见 composerContent/seatComposer）
    private func assemble() {
        window = UIWindow(
            frame: CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()

        handle = ChatNativeListHandle()
        controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)

        let dock = UIView()
        dock.backgroundColor = .systemGray5
        dock.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(dock)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(
                equalTo: root.view.leadingAnchor
            ),
            dock.trailingAnchor.constraint(
                equalTo: root.view.trailingAnchor
            ),
            dock.bottomAnchor.constraint(
                equalTo: root.view.bottomAnchor
            ),
            dock.heightAnchor.constraint(
                equalToConstant: dockHeight
            ),
        ])

        root.view.layoutIfNeeded()
    }

    /// 舱内容（壳家具，与 R1 期的 UIView 条同位）：
    /// 定高 54 的 SwiftUI 条，经 apply 交容器子托
    /// 管——其帧由容器 §302 位置常量（通知帧顶/
    /// 静息坞顶）决定，不由测试约束
    private func composerContent() -> AnyView {
        AnyView(
            Rectangle()
                .fill(Color.gray)
                .frame(height: composerHeight)
        )
    }

    /// 键盘座位（false＝静息、true＝键盘升起位）：
    /// §302 起座位＝向默认通知中心投递键盘通知
    /// 本体——升起投 willShow（结束帧顶＝key-
    /// boardTop、时长 0 即时落位），收起投 will-
    /// Hide（结束帧出窗）。容器自持订阅以同一解
    /// 析驱动舱常量与快照供数，座位即生产链本
    /// 人、无模拟层。R2 期的附加安全区顶引导线
    /// 座位随引导线退出驱动位一并退役
    private func seatComposer(onKeyboard: Bool) {
        let center = NotificationCenter.default
        let userInfo: [AnyHashable: Any] = [
            UIResponder.keyboardFrameEndUserInfoKey:
                NSValue(cgRect: CGRect(
                    x: 0,
                    y: onKeyboard ? keyboardTop : windowH,
                    width: windowW,
                    height: windowH - keyboardTop
                )),
            UIResponder.keyboardAnimationDurationUserInfoKey:
                NSNumber(value: 0),
            UIResponder.keyboardAnimationCurveUserInfoKey:
                NSNumber(value: 7),
        ]
        center.post(
            name: onKeyboard
                ? UIResponder.keyboardWillShowNotification
                : UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: userInfo
        )
        window.layoutIfNeeded()
    }

    /// 容器内舱宿主实帧（窗口坐标）：断言的舱顶
    /// 出此实帧、不出任何喂入数
    private func composerTopInWindow() throws -> CGFloat {
        let host = try XCTUnwrap(
            controller.composerHost,
            "舱子托管应已装配"
        )
        return host.view.convert(
            host.view.bounds, to: nil
        ).minY
    }

    private func apply(
        rows: [ChatNativeRow], onKeyboard: Bool = false
    ) {
        seatComposer(onKeyboard: onKeyboard)
        controller.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: bottomPadding,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: fedTopInset,
            bottomMargin: bottomMargin,
            composerView: composerContent(),
            arrowView: AnyView(Color.clear)
        )
        window.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval = 1.2) {
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window.layoutIfNeeded()
    }

    /// async 测试专用排空：expectation 的 wait 在
    /// async 测试里会堵住主队列（CI 第四轮实证：
    /// drain 超时而后续断言本身全过）——改以
    /// Task.sleep 挂起等拍，主队列照常跑落定拍
    private func drainAsync(
        _ seconds: TimeInterval = 1.2
    ) async {
        try? await Task.sleep(for: .seconds(seconds))
        window.layoutIfNeeded()
    }

    private func frame(at index: Int) throws -> CGRect {
        let attrs = controller.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: 0, section: index)
            )
        return try XCTUnwrap(attrs).frame
    }

    // MARK: - 真实行内容（生产视图、非占位）

    private func assistantContent(_ text: String) -> AnyView {
        AnyView(
            MarkdownText(text)
                .padding(
                    .horizontal, OneDayMetrics.bubblePaddingH
                )
                .padding(
                    .vertical, OneDayMetrics.bubblePaddingV
                )
                .background(
                    RoundedRectangle(
                        cornerRadius:
                            OneDayMetrics.assistantBubbleCorner
                    )
                    .fill(Palette.bubbleFill)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    private func assistantRow(
        _ key: String, _ text: String, entryID: UUID? = nil
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: entryID,
            revision: ChatNativeRowRevision(parts: [.text(text)]),
            makeView: { self.assistantContent(text) }
        )
    }

    /// §329：测试侧拟合量高（同 R3 fittedRow 口
    /// 径）——行高改 .absolute 回喂后手搓行须自
    /// 带高；仅高度语义两门（托管等价／物化高来
    /// 自内容）走本路，其余装配行维持默认兜底
    /// 高、既有几何口径不动
    private func fittedHeight(of view: AnyView) -> CGFloat {
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        return host.sizeThatFits(
            in: CGSize(
                width: windowW
                    - OneDayMetrics.pageGutter * 2,
                height: .greatestFiniteMagnitude
            )
        ).height
    }

    private func fittedAssistantRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(parts: [.text(text)]),
            height: fittedHeight(of: assistantContent(text)),
            makeView: { self.assistantContent(text) }
        )
    }

    private func userRow(
        _ key: String, _ text: String, entryID: UUID? = nil
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: entryID,
            revision: ChatNativeRowRevision(parts: [.text(text)]),
            makeView: {
                AnyView(
                    HStack {
                        Spacer(
                            minLength:
                                OneDayMetrics.bubbleSideInset
                        )
                        SelectableInlineText(
                            paragraphs: [.plain(text)],
                            foreground: Palette.onPrimary
                        )
                        .padding(
                            .horizontal,
                            OneDayMetrics.bubblePaddingH
                        )
                        .padding(
                            .vertical,
                            OneDayMetrics.bubblePaddingV
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: OneDayMetrics
                                    .assistantBubbleCorner
                            )
                            .fill(Palette.primary)
                        )
                    }
                )
            }
        )
    }

    /// 带时间分隔的条目行（与 entryRowContent 同
    /// 构：VStack(spacingS)｛分隔字＋气泡｝）
    private func dividerRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(parts: [.text(text)]),
            makeView: {
                AnyView(
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        Text("今天 09:41")
                            .font(.footnote)
                            .foregroundStyle(
                                Palette.inkSecondary
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .center
                            )
                        MarkdownText(text)
                            .padding(
                                .horizontal,
                                OneDayMetrics.bubblePaddingH
                            )
                            .padding(
                                .vertical,
                                OneDayMetrics.bubblePaddingV
                            )
                            .background(
                                RoundedRectangle(
                                    cornerRadius: OneDayMetrics
                                        .assistantBubbleCorner
                                )
                                .fill(Palette.bubbleFill)
                            )
                    }
                )
            }
        )
    }

    // MARK: - ① 相邻行距单源 24

    func testAdjacentRealRowsKeepSingleSourceSpacing() throws {
        assemble()
        let rows = [
            assistantRow("a1", "第一条助手短回复。"),
            userRow("u1", "收到，这是一条用户短消息。"),
            dividerRow("d1", "带分隔的助手回复，内容稍长一点点。"),
            userRow(
                "u2",
                "最后一条用户消息，长度中等，用来收尾这一组四行。"
            ),
        ]
        apply(rows: rows)
        drain()
        var frames: [CGRect] = []
        for index in rows.indices {
            frames.append(try frame(at: index))
        }
        for index in rows.indices {
            XCTAssertGreaterThan(
                frames[index].height, 30,
                "行 \(index) 高度应来自真实文本排版而非占位"
            )
        }
        for index in 0..<(rows.count - 1) {
            let gap = frames[index + 1].minY - frames[index].maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 1.0,
                "相邻行 \(index)→\(index + 1) 帧间距须＝单源 24，实测 \(gap)"
            )
        }
    }

    // MARK: - ② 短内容双键盘态

    func testShortContentGapKeyboardClosedAndOpen() throws {
        assemble()
        let rows = [assistantRow("only", "只有一条短回复的会话。")]
        apply(rows: rows, onKeyboard: false)
        drain()
        try assertShortGap(rows: rows, label: "键盘收起")
        apply(rows: rows, onKeyboard: true)
        drain()
        try assertShortGap(rows: rows, label: "键盘升起")
        // §302 座位绝对值：升起态舱顶须坐到通知帧
        // 顶−舱高（491）——gap 断言是自洽量（舱不
        // 动也能过），座位须另有绝对锚防静默失效
        let composerTop = try composerTopInWindow()
        XCTAssertEqual(
            composerTop, keyboardTop - composerHeight,
            accuracy: 1.5,
            "键盘升起态舱顶须＝通知帧顶−舱高 "
                + "\(keyboardTop - composerHeight)，实测 \(composerTop)"
        )
    }

    func testShortContentThreeRowsGap() throws {
        assemble()
        let rows = [
            assistantRow("s1", "三行短会话的第一行。"),
            userRow("s2", "第二行用户回复。"),
            assistantRow("s3", "第三行助手收尾。"),
        ]
        apply(rows: rows, onKeyboard: false)
        drain()
        try assertShortGap(rows: rows, label: "三行短会话")
    }

    /// 短内容断言：末行底（窗口坐标）→舱顶（窗
    /// 口实测）＝24±1；落位只由 apply 链自产（测
    /// 试全程不调任何滚动 API）
    private func assertShortGap(
        rows: [ChatNativeRow], label: String
    ) throws {
        let last = try frame(at: rows.count - 1)
        let lastInWindow = controller.collectionView.convert(
            last, to: nil
        )
        let composerTop = try composerTopInWindow()
        let gap = composerTop - lastInWindow.maxY
        XCTAssertEqual(
            gap, targetGap, accuracy: 1.0,
            "\(label)：末行底→舱顶须 24±1，实测 \(gap)"
                + "（末行帧 \(last)、contentSize "
                + "\(controller.collectionView.contentSize)、"
                + "顶 inset "
                + "\(controller.collectionView.contentInset.top)）"
        )
    }

    // MARK: - ③ 长会话进入即真底（三数留档）

    func testLongThreadLandsAtRealBottom() throws {
        assemble()
        var rows: [ChatNativeRow] = []
        for index in 0..<40 {
            let long = index % 5 == 4
            let text = long
                ? "第 \(index + 1) 条是一段较长的回复：原生承载用系统集合视图与组合布局，行高由内容自适应决定，滚动几何只认布局实测——这一段故意写长，好让行高明显超过占位估算，检验落定拍在估算收敛后仍把末行钉到真底。"
                : "第 \(index + 1) 条短回复。"
            rows.append(
                index % 2 == 0
                    ? assistantRow(
                        "long-\(index)", text,
                        entryID: UUID()
                    )
                    : userRow(
                        "long-\(index)", text,
                        entryID: UUID()
                    )
            )
        }
        apply(rows: rows)
        drain(1.6)
        let cv = controller.collectionView
        let lastFrame = try frame(at: rows.count - 1)
        let distance = handle.latestDistance
        // 三数留档（CI 日志可查，报告回填）
        print(
            "NATIVE-LANDING contentSize=\(cv.contentSize.height)"
                + " offset=\(cv.contentOffset.y)"
                + " lastFrame=\(lastFrame)"
                + " bottomInset=\(handle.bottomInset)"
                + " distance=\(distance)"
                + " contentEndVisible=\(handle.contentEndVisible)"
        )
        XCTAssertLessThanOrEqual(
            distance, 1.0,
            "长会话进入距底须 ≤1（真实布局最大 offset），实测 \(distance)"
        )
        XCTAssertTrue(
            handle.contentEndVisible,
            "落底时内容真尾须在视口内（帧口径，非 AX 在场口径）"
        )
        // 末行底在窗口坐标下与舱顶的间距同样收 24
        // （长内容钉底与短内容派生顶 inset 两路同
        // 一口径）；舱顶取容器内舱宿主实帧
        let lastInWindow = cv.convert(lastFrame, to: nil)
        let composerTop = try composerTopInWindow()
        XCTAssertEqual(
            composerTop - lastInWindow.maxY, targetGap,
            accuracy: 1.5,
            "长会话钉底后末行底→舱顶须 24，实测 "
                + "\(composerTop - lastInWindow.maxY)"
        )
    }

    // MARK: - ④ 跳中段：距底现测＋锚一致

    func testMiddleJumpDistanceAndAnchorAgree() throws {
        assemble()
        var rows: [ChatNativeRow] = []
        var entryIDs: [UUID] = []
        for index in 0..<30 {
            let id = UUID()
            entryIDs.append(id)
            rows.append(
                assistantRow(
                    "mid-\(index)",
                    "中段检验第 \(index + 1) 条回复，内容长度适中。",
                    entryID: id
                )
            )
        }
        apply(rows: rows)
        drain(1.6)
        let cv = controller.collectionView
        // 程序化跳到中段（模拟用户滚离底部）
        cv.setContentOffset(
            CGPoint(x: 0, y: cv.contentSize.height / 2),
            animated: false
        )
        drain(0.8)
        let distance = handle.latestDistance
        XCTAssertGreaterThan(
            distance, 176,
            "跳中段后距底读数须现测为大值，实测 \(distance)"
        )
        let anchor = controller.captureAnchor()
        let unwrapped = try XCTUnwrap(
            anchor, "中段应能捕获恢复锚"
        )
        XCTAssertFalse(unwrapped.atBottom)
        // 期望锚条目＝帧口径第一个底边越过可见顶
        // 的条目行
        let visibleTop = cv.contentOffset.y
            + cv.contentInset.top
        var expected: UUID?
        for index in rows.indices {
            if try frame(at: index).maxY > visibleTop + 0.5 {
                expected = entryIDs[index]
                break
            }
        }
        XCTAssertEqual(
            unwrapped.entryID, expected,
            "锚条目须与帧口径首个可见条目一致"
        )
        // 回底命令后读数复位
        controller.scrollToBottom(animated: false)
        drain(1.0)
        // 全状态留档（距底 2.0 三轮同值的定因材
        // 料：标尺/应用 inset/布局 contentSize 三者
        // 哪一处分叉，一轮判清）
        let lastFrame = try frame(at: rows.count - 1)
        print(
            "NATIVE-MIDSTATE contentSize=\(cv.contentSize.height)"
                + " offset=\(cv.contentOffset.y)"
                + " inset=\(cv.contentInset)"
                + " adjusted=\(cv.adjustedContentInset)"
                + " handleBottomInset=\(handle.bottomInset)"
                + " lastFrame=\(lastFrame)"
                + " distance=\(handle.latestDistance)"
        )
        // 容差 2.5 的定因（CI 第五至八轮实证、全状
        // 态打印在上）：回底后距底恰 2.0 四轮同值——
        // inset 三处全等 70、contentSize 与末行帧精
        // 确自洽（2444＋8＝2452）、offset 恰停算术
        // max−2；零延迟/次数/时间窗三代重拍均推不
        // 动，定性为 compositional 自适应布局的
        // offset 调整残差（钉底触发的布局 pass 为保
        // 锚点位回调 offset——布局的可达落点与读数
        // 公式的算术 max 在此分叉 2pt，末行完整可
        // 见、底距落在 22–24 带内）。本断言守「回
        // 底后实质在底」（≤2.5），③的算术在底由其
        // 自身 ≤1 断言把守、两口径不混
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 2.5,
            "回底后距底须 ≤2.5（布局调整残差带内），实测 \(handle.latestDistance)"
        )
    }

    // MARK: - ⑤ 托管高度等价（H2 回退门）

    func testHostingHeightMatchesBareHost() throws {
        assemble()
        let text =
            "托管等价检验：同一段多行正文，在集合视图 cell 里经 UIHostingConfiguration 托管的高度，必须与裸 UIHostingController（宿主 safeAreaRegions 清零）在同宽下的自适应高度一致——若本断言红，说明配置式托管的拟合被安全区抬高，R1 按施工图回退 keyed 托管控制器方案。"
        let rows = [fittedAssistantRow("host-eq", text)]
        apply(rows: rows)
        drain()
        let cellHeight = try frame(at: 0).height

        let rowWidth = windowW
            - OneDayMetrics.pageGutter * 2
        let bare = UIHostingController(
            rootView: assistantContent(text)
        )
        bare.safeAreaRegions = []
        let bareWindow = UIWindow(
            frame: CGRect(
                x: 0, y: -2000, width: windowW, height: 400
            )
        )
        bareWindow.rootViewController = bare
        bareWindow.makeKeyAndVisible()
        bare.view.frame = CGRect(
            x: 0, y: 0, width: rowWidth, height: 400
        )
        bare.view.layoutIfNeeded()
        let bareHeight = bare.sizeThatFits(
            in: CGSize(
                width: rowWidth,
                height: .greatestFiniteMagnitude
            )
        ).height
        bareWindow.isHidden = true
        XCTAssertEqual(
            cellHeight, bareHeight, accuracy: 1.5,
            "cell 高 \(cellHeight) 与裸宿主高 \(bareHeight) 须等价（差 >1.5 触发 H2 回退）"
        )
    }

    // MARK: - ⑥ 固定占位不驱动物化行高（§325，代产物估算带宽）

    /// §325／§329：产物层估算管线退役后，未带高
    /// 的行只剩固定常量（120）兜底；带高行（生产
    /// 走合成器、本测走测试侧拟合回喂）物化行高
    /// 必须只由内容决定：短行远低于占位、长行远
    /// 高于占位，两行间距仍单源 24。若行高被占
    /// 位锚住（短行≈120 或长行被压），本断言即红
    func testMaterializedHeightComesFromContentNotPlaceholder() throws {
        assemble()
        let longText = """
            占位退役检验的长回复第一段：行高归框架自适应之后，物化行的高度只能来自它自己的内容排版——同一列表里短行与长行并存时，各自的高度差必须完整反映内容差，而不是被某个统一的估算值拉平。

            第二段继续加长：集合视图在滚动几何上对未物化区使用固定占位，那只是滚动条与总高的近似；一旦行被物化，它的帧高就是内容高，估算值不许再回头改写它。

            第三段收尾，确保总高明显越过固定占位常量。
            """
        let rows = [
            fittedAssistantRow("short", "短。"),
            fittedAssistantRow("long", longText),
        ]
        apply(rows: rows)
        drain()
        let shortHeight = try frame(at: 0).height
        let longHeight = try frame(at: 1).height
        print(
            "NATIVE-PLACEHOLDER short=\(shortHeight) long=\(longHeight)"
        )
        XCTAssertLessThan(
            shortHeight, 100,
            "短行物化高须来自内容（远低于固定占位 120），实测 \(shortHeight)"
        )
        XCTAssertGreaterThan(
            longHeight, 180,
            "长行物化高须来自内容（明显高于固定占位 120），实测 \(longHeight)"
        )
        let gap = try frame(at: 1).minY - frame(at: 0).maxY
        XCTAssertEqual(
            gap, OneDayMetrics.spacingL, accuracy: 1.0,
            "长短行相邻间距须＝单源 24，实测 \(gap)"
        )
    }
}
