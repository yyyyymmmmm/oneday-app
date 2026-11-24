import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §321（助手回复呈现与大厂对齐）装配断言：
/// ①原原生散文 cell 气泡填充断言——§325（B 档）
/// 散文 cell 整件退役后断言对象不复存在，改单路
/// 径结构断言：助手行在新承载全体落托管 cell、
/// 呈现口径由 ChatView.assistantBubble 单源承
/// 接（填充 .clear 为代码直读＋真机清单承接，
/// 托管子树背景色不在 §294.1 可观测面内、不另
/// 设观测通道）；
/// ②顶簇底缘回报：TopBarGuideHostController 以
/// 活帧 convert 报顶簇在窗口里的真实底边（安全
/// 区＋实高），新面列表顶 inset 的单源供数成立。
@MainActor
final class ReplyRenderingAlignmentTests: XCTestCase {

    private final class RigWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func assembleWindow() {
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    // MARK: - ① 单路径：助手行落托管 cell（§325）

    func testAssistantRowUsesSingleHostedPath() throws {
        assembleWindow()
        let handle = ChatNativeListHandle()
        let controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        let root = window.rootViewController!
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        controller.apply(
            rows: [
                ChatNativeRow(
                    key: "a1", entryID: nil,
                    revision: ChatNativeRowRevision(
                        parts: [.text("助手回复正文")]
                    ),
                    makeView: {
                        AnyView(
                            MarkdownText(
                                "这是一段助手回复正文，用来装配单路径托管行。"
                            )
                            .padding(
                                .horizontal,
                                OneDayMetrics.bubblePaddingH
                            )
                            .padding(
                                .vertical,
                                OneDayMetrics.bubblePaddingV
                            )
                        )
                    }
                ),
            ],
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: OneDayMetrics.spacingS,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
        window.layoutIfNeeded()
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.2
        ) { exp.fulfill() }
        wait(for: [exp], timeout: 12)
        window.layoutIfNeeded()
        let cell = controller.collectionView.cellForItem(
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertEqual(
            cell?.reuseIdentifier, "ChatNativeHostingCell",
            "§325：助手行须落唯一托管形态，实得 \(String(describing: cell?.reuseIdentifier))"
        )
        let height = controller.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )?.frame.height ?? 0
        XCTAssertGreaterThan(
            height, 30,
            "托管行高须来自真实排版，实测 \(height)"
        )
    }

    // MARK: - ② 顶簇底缘单源回报

    func testTopClusterBottomReportMatchesWindowFrame() throws {
        let rig = RigWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window = rig
        let root = UIViewController()
        rig.rootViewController = root
        rig.makeKeyAndVisible()

        let host = TopBarGuideHostController()
        var reported: [CGFloat] = []
        host.onBarBottomChange = { reported.append($0) }
        root.addChild(host)
        host.view.frame = root.view.bounds
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        host.updateBarContentHeight(52)
        rig.layoutIfNeeded()

        // 顶簇顶＝窗口安全区 59、高 52 → 底缘 111
        let last = try XCTUnwrap(
            reported.last,
            "§321：顶簇底缘须有回报（实报 \(reported))"
        )
        XCTAssertEqual(
            last, 111, accuracy: 1.5,
            "§321：顶簇底缘回报须＝安全区＋实高的活帧实测"
        )
        // 与活帧本体对账（同一帧、同一值）
        let liveBottom = host.traceBarView.convert(
            host.traceBarView.bounds, to: rig
        ).maxY
        XCTAssertEqual(
            last, liveBottom, accuracy: 0.6,
            "回报值须与顶簇宿主活帧底边逐值一致"
        )
    }
}
