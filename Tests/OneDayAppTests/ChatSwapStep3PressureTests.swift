import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.3 压测（§329 成环条件在单 section 构造
/// 下的复刻）：临界估高（确高×0.72、临界标记）
/// 整批喂入→连续小步滚动（40pt/步＋layoutIf-
/// Needed、每 5 步部分 drain）到底回顶再回底，
/// 滚动途中逐批把行替换为量测确高（pass 间行
/// 高方差注入＝当年成环的点火条件）、且下行途
/// 中反向上行（中途反向）。断言收敛：终局
/// contentSize 与期望值（顶 16＋Σ确高＋行距
/// 24×(n−1)＋底 8）逐值等、逐行帧高/顶位与确
/// 高前缀和逐值等、稳态下强制布局零新增提供
/// 者调用（无自失效环）。本组为步骤 3 硬门：
/// 任一红先停手报告、不许绕断言
@MainActor
final class ChatSwapStep3PressureTests: XCTestCase {

    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )
    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var tracker: ChatFeedChangeTracker!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        tracker = nil
        super.tearDown()
    }

    private func assemble() {
        let w = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let root = UIViewController()
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
        let handle = ChatNativeListHandle()
        let vc = ChatRootViewController()
        vc.handle = handle
        vc.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = vc
        vc.testSingleSectionOverride = true
        root.addChild(vc)
        vc.view.frame = root.view.bounds
        root.view.addSubview(vc.view)
        vc.didMove(toParent: root)
        root.view.layoutIfNeeded()
        controller = vc
        tracker = ChatFeedChangeTracker()
    }

    /// 确高谱（48…～700、含极端高差相邻排布）
    private static func exactHeight(_ index: Int) -> CGFloat {
        48 + CGFloat((index * 41) % 9) * 37
            + (index % 10 == 0 ? 420 : 0)
    }

    private func row(
        _ index: Int, exact: Bool
    ) -> ChatNativeRow {
        var revision = ChatNativeRowRevision()
        revision.addText("pressure-\(index)")
        let exactH = Self.exactHeight(index)
        return ChatNativeRow(
            key: "p3-\(index)",
            entryID: nil,
            revision: revision,
            height: exact
                ? exactH
                : (exactH * 0.72).rounded(),
            heightIsProvisional: !exact,
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func feed(_ rows: [ChatNativeRow]) {
        let set = tracker.ingest(rows: rows)
        controller.applyChanges(
            rows: rows, changeSet: set,
            layout: layout, topInset: 0,
            bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    private func settle() {
        var last: (CGFloat, Int) = (-1, -1)
        for _ in 0..<100 {
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.02)
            )
            controller.collectionView.layoutIfNeeded()
            let now = (
                controller.collectionView.contentSize.height,
                controller.testSectionProviderCallCount
            )
            if now == last { return }
            last = now
        }
    }

    func testSingleSectionSurvivesCriticalHeightReplacement()
        throws
    {
        assemble()
        let count = 120
        var current = (0..<count).map {
            row($0, exact: false)
        }
        feed(current)
        settle()
        XCTAssertEqual(
            controller.collectionView.numberOfSections, 1,
            "单 section 构造：section 数须 1"
        )
        XCTAssertEqual(
            controller.collectionView
                .numberOfItems(inSection: 0),
            count,
            "单 section 构造：条目数须＝行数"
        )

        let cv = controller.collectionView
        func maxOffset() -> CGFloat {
            max(
                0,
                cv.contentSize.height - cv.bounds.height
            )
        }
        // 滚动脚本：自底上行（阶段一）→中途反向
        // 下行回底（阶段二）→再上行到顶（阶段
        // 三）；每 6 步回填一批 12 行确高（共 10
        // 批、全量落定），回填在滚动途中发生＝
        // pass 间行高替换
        var backfilled = 0
        func backfillBatch() {
            guard backfilled < count else { return }
            let end = min(count, backfilled + 12)
            for index in backfilled..<end {
                current[index] = row(index, exact: true)
            }
            backfilled = end
            feed(current)
        }
        var step = 0
        func scrollSteps(
            toward target: CGFloat, direction: CGFloat
        ) {
            var y = cv.contentOffset.y
            while (direction < 0 && y > target)
                    || (direction > 0 && y < target) {
                y = direction < 0
                    ? max(target, y - 40)
                    : min(target, y + 40)
                y = min(max(0, y), maxOffset())
                cv.contentOffset = CGPoint(x: 0, y: y)
                cv.layoutIfNeeded()
                step += 1
                if step % 5 == 0 {
                    RunLoop.main.run(
                        until: Date()
                            .addingTimeInterval(0.02)
                    )
                }
                if step % 6 == 0 {
                    backfillBatch()
                }
            }
        }
        cv.contentOffset = CGPoint(
            x: 0, y: maxOffset()
        )
        cv.layoutIfNeeded()
        // 阶段一：上行至 45% 处（中途反向点）
        scrollSteps(
            toward: maxOffset() * 0.45, direction: -1
        )
        // 阶段二：反向下行回底
        scrollSteps(toward: maxOffset(), direction: 1)
        // 阶段三：上行到顶
        scrollSteps(toward: 0, direction: -1)
        // 残批回填落定（滚动步数不足以排空时兜底）
        while backfilled < count { backfillBatch() }
        settle()

        // 收敛断言：终局几何与确高账逐值等
        let expected = 16
            + (0..<count).map(Self.exactHeight)
                .reduce(0, +)
            + 24 * CGFloat(count - 1) + 8
        XCTAssertEqual(
            cv.contentSize.height, expected,
            accuracy: 0.5,
            "终局 contentSize 须＝顶 16＋Σ确高＋行距＋底 8，实测 \(cv.contentSize.height) vs 期望 \(expected)"
        )
        var prefix: CGFloat = 16
        for index in 0..<count {
            let attrs = cv.layoutAttributesForItem(
                at: IndexPath(item: index, section: 0)
            )
            let frame = try XCTUnwrap(attrs).frame
            XCTAssertEqual(
                frame.height, Self.exactHeight(index),
                accuracy: 0.5,
                "行 \(index) 帧高须＝确高"
            )
            XCTAssertEqual(
                frame.minY, prefix, accuracy: 0.5,
                "行 \(index) 帧顶位须＝确高前缀和"
            )
            prefix += Self.exactHeight(index) + 24
        }
        // 稳态无环：强制布局零新增提供者调用、
        // contentSize 逐值不动
        let passes = controller
            .testSectionProviderCallCount
        let steadySize = cv.contentSize.height
        for _ in 0..<3 {
            cv.layoutIfNeeded()
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.02)
            )
        }
        XCTAssertEqual(
            controller.testSectionProviderCallCount,
            passes,
            "稳态强制布局不得再触发提供者（无自失效环），\(passes) → \(controller.testSectionProviderCallCount)"
        )
        XCTAssertEqual(
            cv.contentSize.height, steadySize,
            accuracy: 0.5,
            "稳态 contentSize 须逐值不动"
        )
        print(
            "SINGLE-PASSES passes=\(passes) steps=\(step) content=\(steadySize)"
        )
    }
}
