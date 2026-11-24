import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 150 装配层：控制器收敛落点——目标行停到
/// 顶留位（顶内边距＋12）且漂移后能自校正、用户
/// 拖动即弃权。收敛判定本身在 Core 测
/// （SearchFocusTests）
@MainActor
final class ChatSearchFocusAssemblyTests: XCTestCase {
    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!
    private var ids: [UUID] = []

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

    private func apply(_ rows: [ChatNativeRow]) {
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
                    .frame(height: 54)
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

    private func makeRows(
        count: Int, growFirst: CGFloat = 0
    ) -> [ChatNativeRow] {
        // 条目 id 跨 apply 稳定（同线程重喂同批条目）
        if ids.count != count {
            ids = (0..<count).map { _ in UUID() }
        }
        return (0..<count).map { index in
            let height: CGFloat = index == 0 && growFirst > 0
                ? growFirst : 60
            return ChatNativeRow(
                key: "r\(index)", entryID: ids[index],
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
    }

    /// 目标行屏上位置（行顶距视口顶）
    private func shownPosition(of index: Int) -> CGFloat? {
        let cv = controller.collectionView
        guard let attrs = cv.layoutAttributesForItem(
            at: IndexPath(item: 0, section: index)
        ) else { return nil }
        return attrs.frame.minY - cv.contentOffset.y
    }

    /// 期望落点：顶内边距＋topGap（长内容派生顶距为 0）
    private var expectedLanding: CGFloat {
        controller.collectionView.contentInset.top
            + SearchFocusConvergence.topGap
    }

    func testFocusLandsAtTopGap() throws {
        assemble()
        apply(makeRows(count: 40))
        drain(1.2)
        handle.focusEntry(ids[5])
        drain(1.0)
        let shown = try XCTUnwrap(shownPosition(of: 5))
        XCTAssertEqual(
            shown, expectedLanding, accuracy: 2,
            "搜索落点须停在顶留位，实测 \(shown) 期望 \(expectedLanding)"
        )
    }

    func testFocusCorrectsMidFlightDrift() throws {
        assemble()
        apply(makeRows(count: 40))
        drain(1.2)
        handle.focusEntry(ids[8])
        // 落点途中首行变高（图片/量实迟到同型）：上方
        // 内容增高 100，收敛环须把目标重新校正回留位
        apply(makeRows(count: 40, growFirst: 160))
        drain(1.2)
        let shown = try XCTUnwrap(shownPosition(of: 8))
        XCTAssertEqual(
            shown, expectedLanding, accuracy: 2,
            "漂移后须收敛回顶留位，实测 \(shown) 期望 \(expectedLanding)"
        )
    }

    func testUserDragAbandonsFocus() throws {
        assemble()
        apply(makeRows(count: 40))
        drain(1.2)
        handle.focusEntry(ids[8])
        controller.scrollViewWillBeginDragging(
            controller.collectionView
        )
        // 读者拖去别处停下；其后上方行变高触发落定
        // 拍——弃权后不得把人拽回搜索落点（保位逻辑
        // 保持屏上位置即可），落点机若还活着会滚回
        // 顶留位
        let cv = controller.collectionView
        cv.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        window?.layoutIfNeeded()
        let shownBefore = try XCTUnwrap(shownPosition(of: 8))
        apply(makeRows(count: 40, growFirst: 160))
        drain(1.0)
        let shown = try XCTUnwrap(shownPosition(of: 8))
        XCTAssertEqual(
            shown, shownBefore, accuracy: 3,
            "拖动弃权后须停在读者位置，实测 \(shown) 弃权前 \(shownBefore)"
        )
        XCTAssertGreaterThan(
            abs(shown - expectedLanding), 20,
            "弃权后不得回到搜索落点"
        )
    }
}
