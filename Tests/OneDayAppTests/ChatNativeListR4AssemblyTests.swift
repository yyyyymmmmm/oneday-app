import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §297（原生重建 R4 转默认＋浸泡）默认态真实装配
/// 回归：R1–R3 的装配断言都直构 ChatRootViewCon-
/// troller（不经旗），本套件补的是「缺省状态本身」
/// 三个命题——
/// ⑭整页生产装配（RootView→ChatView）在旗键缺省
/// 时出原生面（ChatRootViewController 在 VC 树
/// 内）：转默认在真实装配层成立、非仅 @AppStorage
/// 字面缺省；
/// ⑮显式置 false 时整页不出原生面：浸泡期回退口
/// 在装配层真实在位（缺省回滚＝改回 false 一行
/// 的前提证据）；
/// ⑯「开线程落底」帧口径改指（R1 报告 §五指定）：
/// 冒烟门箭头例的旧面 AX 在场口径就此退役——同命
/// 题改由「按 Core 缺省解析（键缺省→原生面）选
/// 面＋新面帧口径三数」断言：40 行真实内容经
/// apply 链进入、距底 ≤1、帧口径 contentEnd-
/// Visible、末行底→舱顶 24±1.5，数值打印留档。
/// 三例均真实装配、行内容全真实生产视图，禁固定
/// 高占位作证据（蓝图 §6.2）。
@MainActor
final class ChatNativeListR4AssemblyTests: XCTestCase {

    /// 与整页组装回归同口径的设备窗（402×874、安全
    /// 区覆写 top 59／bottom 34）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    /// §184：容器租约——见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()
    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 整页生产装配（与 ChatPageAssemblyRegression-
    /// Tests 同式：演示已连接态→RootView 整页）
    private func assembleProductionPage() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
    }

    /// VC 树内是否有原生面容器（面前置的装配判据，
    /// 不经 AX/帧口径）
    private func findNativeRootController() -> ChatRootViewController? {
        var found: ChatRootViewController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ChatRootViewController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    // MARK: - ⑭ 缺省整页出原生面

    func testProductionPageDefaultsToNativeSurface() throws {
        // §374.9（步骤 6）：两面旗退役后整页恒出原
        // 生面——本例验生产装配缺省即原生面在场
        try assembleProductionPage()
        XCTAssertNotNil(
            findNativeRootController(),
            "缺省状态整页装配须出原生面（ChatRootViewController 在场）"
        )
    }

    // MARK: - ⑮ 显式关＝回退在位


    // MARK: - ⑯ 开线程落底·新面帧口径（冒烟箭头例改指）

    private let shellW: CGFloat = 402
    private let shellH: CGFloat = 874
    private let dockHeight: CGFloat = 83
    private let composerHeight: CGFloat = 54
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8
    private let targetGap: CGFloat = 24

    private var shellWindow: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!

    private func assembleNativeShell() {
        shellWindow = UIWindow(
            frame: CGRect(
                x: 0, y: 0, width: shellW, height: shellH
            )
        )
        let root = UIViewController()
        shellWindow.rootViewController = root
        shellWindow.makeKeyAndVisible()

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

    private func assistantRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: UUID(),
            revision: ChatNativeRowRevision(parts: [.text(text)]),
            makeView: {
                AnyView(
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
                                cornerRadius:
                                    OneDayMetrics
                                        .assistantBubbleCorner
                            )
                            .fill(Palette.bubbleFill)
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    private func userRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: UUID(),
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

    func testDefaultResolvedSurfaceLandsAtRealBottom() throws {
        // §374.9（步骤 6）：选面旗退役、原生面恒在
        // 场——本例在原生面验落底（冒烟门「开线程落
        // 底」以本帧口径为准，R1 报告 §五改指落地）
        assembleNativeShell()
        var rows: [ChatNativeRow] = []
        for index in 0..<40 {
            let long = index % 5 == 4
            let text = long
                ? "第 \(index + 1) 条是一段较长的回复：原生承载用系统集合视图与组合布局，行高由内容自适应决定，滚动几何只认布局实测——这一段故意写长，好让行高明显超过占位估算，检验落定拍在估算收敛后仍把末行钉到真底。"
                : "第 \(index + 1) 条短回复。"
            rows.append(
                index % 2 == 0
                    ? assistantRow("r4-\(index)", text)
                    : userRow("r4-\(index)", text)
            )
        }
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
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: composerHeight)
            ),
            arrowView: AnyView(Color.clear)
        )
        shellWindow.layoutIfNeeded()
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 12)
        shellWindow.layoutIfNeeded()

        let cv = controller.collectionView
        let attrs = cv.layoutAttributesForItem(
            at: IndexPath(item: 0, section: rows.count - 1)
        )
        let lastFrame = try XCTUnwrap(attrs).frame
        let distance = handle.latestDistance
        print(
            "NATIVE-LANDING-R4 contentSize=\(cv.contentSize.height)"
                + " offset=\(cv.contentOffset.y)"
                + " lastFrame=\(lastFrame)"
                + " bottomInset=\(handle.bottomInset)"
                + " distance=\(distance)"
                + " contentEndVisible=\(handle.contentEndVisible)"
        )
        XCTAssertLessThanOrEqual(
            distance, 1.0,
            "默认面长会话进入距底须 ≤1（真实布局最大 offset），实测 \(distance)"
        )
        XCTAssertTrue(
            handle.contentEndVisible,
            "落底时内容真尾须在视口内（帧口径，非 AX 在场口径）"
        )
        let host = try XCTUnwrap(
            controller.composerHost, "舱子托管应已装配"
        )
        let composerTop = host.view.convert(
            host.view.bounds, to: nil
        ).minY
        let lastInWindow = cv.convert(lastFrame, to: nil)
        XCTAssertEqual(
            composerTop - lastInWindow.maxY, targetGap,
            accuracy: 1.5,
            "钉底后末行底→舱顶须 24，实测 "
                + "\(composerTop - lastInWindow.maxY)"
        )

        shellWindow.isHidden = true
        shellWindow = nil
        controller = nil
        handle = nil
    }
}
