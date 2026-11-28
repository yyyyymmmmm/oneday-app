import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 149（贴底四触发源验收清单）：数据到达/
/// 行布局变化/页脚变化/整体布局变化四源，逐源成
/// 对钉住——读者在底时保持贴底、离底时不拽回。
/// 判定面是句柄回读的离底距离（report 链）与偏移
/// 本体；机制映射见 Core BottomFollowTrigger
@MainActor
final class ChatNativeFollowSourceTests: XCTestCase {
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

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        controller = list
        handle = listHandle
    }

    private func apply(
        _ rows: [ChatNativeRow], composerHeight: CGFloat = 54
    ) {
        controller?.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: 8,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: composerHeight)
            ),
            arrowView: AnyView(Color.clear)
        )
        window?.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(description: "drain \(seconds)")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func row(
        _ index: Int, height: CGFloat = 60
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: "r\(index)", entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text("row \(index) h\(Int(height))")]
            ),
            height: height,
            makeView: {
                AnyView(
                    Text("row")
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    private func rows(_ count: Int) -> [ChatNativeRow] {
        (0..<count).map { row($0) }
    }

    private func scrollUpFromBottom(by delta: CGFloat) {
        let cv = controller.collectionView
        cv.setContentOffset(
            CGPoint(x: 0, y: cv.contentOffset.y - delta),
            animated: false
        )
        window?.layoutIfNeeded()
    }

    // MARK: - 源一：数据到达（dataChange）

    func testDataChangeAtBottomStaysPinned() {
        assemble()
        apply(rows(30))
        drain(1.2)
        XCTAssertLessThanOrEqual(
            abs(handle.latestDistance), 0.5,
            "冷开须贴底，实测 \(handle.latestDistance)"
        )
        apply(rows(31))
        // dataChange 源的生产链不在控制器自发钉底：
        // ChatView 以在底事实经贴底单口（Bottom-
        // StickCoordinator）下达 scrollToBottom、
        // 控制器以落点意图钉住（其余三源才是控制
        // 器布局拍自发保底）。本用例如实镜像该链：
        // 在底事实成立→下达同一命令→钉底成立
        handle.scrollToBottom(animated: false)
        drain(0.8)
        XCTAssertLessThanOrEqual(
            abs(handle.latestDistance), 0.5,
            "在底时新数据到达经生产跟随链须保持贴底，实测 \(handle.latestDistance)"
        )
    }

    func testDataChangeOffBottomDoesNotYank() {
        assemble()
        apply(rows(30))
        drain(1.2)
        scrollUpFromBottom(by: 400)
        drain(0.5)
        let before = controller.collectionView.contentOffset.y
        apply(rows(31))
        drain(0.8)
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, before,
            accuracy: 1,
            "离底读史时新数据到达不得拽动位置"
        )
    }

    // MARK: - 源二：行布局变化（itemLayout）

    func testItemLayoutAtBottomStaysPinned() {
        assemble()
        apply(rows(30))
        drain(1.2)
        var changed = rows(30)
        changed[10] = row(10, height: 160)
        apply(changed)
        drain(0.8)
        XCTAssertLessThanOrEqual(
            abs(handle.latestDistance), 0.5,
            "在底时行高变须保持贴底，实测 \(handle.latestDistance)"
        )
    }

    func testItemLayoutOffBottomKeepsVisiblePosition() throws {
        assemble()
        apply(rows(30))
        drain(1.2)
        scrollUpFromBottom(by: 400)
        drain(0.5)
        let cv = controller.collectionView
        // 视口上方行变高：可见内容位置不得跳（保位）
        let anchor = try XCTUnwrap(cv.indexPathsForVisibleItems.sorted().first)
        XCTAssertNotEqual(anchor, IndexPath(item: 0, section: 0))
        let attrsBefore = try XCTUnwrap(cv.layoutAttributesForItem(at: anchor))
        let shownBefore = attrsBefore.frame.minY - cv.contentOffset.y
        var changed = rows(30)
        changed[0] = row(0, height: 160)
        apply(changed)
        drain(0.8)
        let attrsAfter = try XCTUnwrap(cv.layoutAttributesForItem(at: anchor))
        let shownAfter = attrsAfter.frame.minY - cv.contentOffset.y
        XCTAssertEqual(
            shownAfter, shownBefore, accuracy: 2,
            "离底时上方行高变须保可见位置（偏移随增高补偿）"
        )
    }

    // MARK: - 源三：页脚变化（footerLayout）

    func testFooterLayoutAtBottomStaysPinned() {
        assemble()
        apply(rows(30))
        drain(1.2)
        apply(rows(30), composerHeight: 110)
        drain(1.0)
        XCTAssertLessThanOrEqual(
            abs(handle.latestDistance), 0.5,
            "在底时输入舱变高须保持贴底，实测 \(handle.latestDistance)"
        )
    }

    func testFooterLayoutOffBottomDoesNotYank() {
        assemble()
        apply(rows(30))
        drain(1.2)
        scrollUpFromBottom(by: 400)
        drain(0.5)
        let before = controller.collectionView.contentOffset.y
        apply(rows(30), composerHeight: 110)
        drain(1.0)
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, before,
            accuracy: 1,
            "离底时页脚变化不得拽动位置"
        )
    }

    // MARK: - 源四：整体布局变化（layout）

    func testLayoutAtBottomStaysPinned() {
        assemble()
        apply(rows(30))
        drain(1.2)
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 700
        )
        window?.layoutIfNeeded()
        drain(0.8)
        XCTAssertLessThanOrEqual(
            abs(handle.latestDistance), 0.5,
            "在底时视口变高须保持贴底，实测 \(handle.latestDistance)"
        )
    }

    func testLayoutOffBottomDoesNotYank() {
        assemble()
        apply(rows(30))
        drain(1.2)
        scrollUpFromBottom(by: 400)
        drain(0.5)
        let before = controller.collectionView.contentOffset.y
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 700
        )
        window?.layoutIfNeeded()
        drain(0.8)
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, before,
            accuracy: 2,
            "离底时视口变化不得拽动位置"
        )
    }
}
