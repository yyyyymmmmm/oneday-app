import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.3 等价对账钉测：同一喂入序列（变更集路
/// 与旧路 apply 各一轮）分别落到逐行 section 构
/// 造（旗关）与单 section 构造（旗开）的两台控
/// 制器，逐趟终态须逐值同——快照条目序/修订账/
/// 高度账（按键与按序）/contentSize/逐行帧（高
/// 与顶位）；结构差异只许在 section 数本身
/// （逐行＝行数、单 section＝非空 1／空集 0）。
/// 覆盖：冷开/稳态/编辑/插行/删行/高度-only 回
/// 填/facet 翻转/序变/缩集/清空/再生长
@MainActor
final class ChatSwapStep3EquivalenceTests: XCTestCase {

    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )
    private var windows: [UIWindow] = []
    private var sectionVC: ChatRootViewController!
    private var singleVC: ChatRootViewController!
    private var tracker: ChatFeedChangeTracker!

    override func tearDown() {
        for window in windows { window.isHidden = true }
        windows = []
        sectionVC = nil
        singleVC = nil
        tracker = nil
        super.tearDown()
    }

    private func makeController(
        singleSection: Bool
    ) -> ChatRootViewController {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        windows.append(window)
        let handle = ChatNativeListHandle()
        let controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        controller.testSingleSectionOverride = singleSection
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
        return controller
    }

    private func assemblePair() {
        sectionVC = makeController(singleSection: false)
        singleVC = makeController(singleSection: true)
        tracker = ChatFeedChangeTracker()
    }

    /// 确定性行高谱（44…640、含极端高差）
    private static func heightFor(_ index: Int) -> CGFloat {
        52 + CGFloat((index * 53) % 7) * 61
            + (index % 5 == 0 ? 300 : 0)
    }

    private func row(
        _ index: Int, version: Int = 0,
        height: CGFloat? = nil
    ) -> ChatNativeRow {
        var revision = ChatNativeRowRevision()
        revision.addText("row-\(index)-v\(version)")
        return ChatNativeRow(
            key: "s3-\(index)",
            entryID: nil,
            revision: revision,
            height: height ?? Self.heightFor(index),
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func rows(_ indices: [Int]) -> [ChatNativeRow] {
        indices.map { row($0) }
    }

    /// 等几何落定（落定拍冲刷后 contentSize 与提
    /// 供者计数两采样不变）
    private func settle(_ vc: ChatRootViewController) {
        var last: (CGFloat, Int) = (-1, -1)
        for _ in 0..<80 {
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.02)
            )
            vc.collectionView.layoutIfNeeded()
            let now = (
                vc.collectionView.contentSize.height,
                vc.testSectionProviderCallCount
            )
            if now == last { return }
            last = now
        }
    }

    private func frame(
        _ vc: ChatRootViewController, row: Int,
        single: Bool
    ) -> CGRect? {
        vc.collectionView.layoutAttributesForItem(
            at: single
                ? IndexPath(item: row, section: 0)
                : IndexPath(item: 0, section: row)
        )?.frame
    }

    /// 双构造终态逐值对账
    private func assertEquivalent(
        rowCount: Int, label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        settle(sectionVC)
        settle(singleVC)
        XCTAssertEqual(
            singleVC.testSnapshotKeyOrder,
            sectionVC.testSnapshotKeyOrder,
            "快照条目序须逐值同（\(label)）",
            file: file, line: line
        )
        XCTAssertEqual(
            singleVC.testRevisionsByKey,
            sectionVC.testRevisionsByKey,
            "修订账须逐值同（\(label)）",
            file: file, line: line
        )
        XCTAssertEqual(
            singleVC.testRowHeightsByKey,
            sectionVC.testRowHeightsByKey,
            "高度账（按键）须逐值同（\(label)）",
            file: file, line: line
        )
        XCTAssertEqual(
            singleVC.testAdoptedRowHeights,
            sectionVC.testAdoptedRowHeights,
            "高度账（按序）须逐值同（\(label)）",
            file: file, line: line
        )
        XCTAssertEqual(
            sectionVC.collectionView.numberOfSections,
            rowCount,
            "逐行构造 section 数＝行数（\(label)）",
            file: file, line: line
        )
        XCTAssertEqual(
            singleVC.collectionView.numberOfSections,
            rowCount == 0 ? 0 : 1,
            "单 section 构造 section 数＝非空 1/空集 0（\(label)）",
            file: file, line: line
        )
        if rowCount > 0 {
            XCTAssertEqual(
                singleVC.collectionView
                    .numberOfItems(inSection: 0),
                rowCount,
                "单 section 条目数＝行数（\(label)）",
                file: file, line: line
            )
        }
        XCTAssertEqual(
            singleVC.collectionView.contentSize.height,
            sectionVC.collectionView.contentSize.height,
            accuracy: 0.5,
            "contentSize 高须逐值同（\(label)）：单 \(singleVC.collectionView.contentSize.height) vs 逐行 \(sectionVC.collectionView.contentSize.height)",
            file: file, line: line
        )
        XCTAssertEqual(
            singleVC.collectionView.contentSize.width,
            sectionVC.collectionView.contentSize.width,
            accuracy: 0.5,
            "contentSize 宽须逐值同（\(label)）",
            file: file, line: line
        )
        for index in 0..<rowCount {
            guard let a = frame(
                    sectionVC, row: index, single: false
                  ),
                  let b = frame(
                    singleVC, row: index, single: true
                  )
            else {
                XCTFail(
                    "行 \(index) 两构造帧须都在（\(label)）",
                    file: file, line: line
                )
                continue
            }
            XCTAssertEqual(
                b.height, a.height, accuracy: 0.5,
                "行 \(index) 帧高须逐值同（\(label)）",
                file: file, line: line
            )
            XCTAssertEqual(
                b.minY, a.minY, accuracy: 0.5,
                "行 \(index) 帧顶位须逐值同（\(label)）：单 \(b.minY) vs 逐行 \(a.minY)",
                file: file, line: line
            )
            XCTAssertEqual(
                b.minX, a.minX, accuracy: 0.5,
                "行 \(index) 帧左位须逐值同（\(label)）",
                file: file, line: line
            )
            XCTAssertEqual(
                b.width, a.width, accuracy: 0.5,
                "行 \(index) 帧宽须逐值同（\(label)）",
                file: file, line: line
            )
        }
    }

    private func feedChanges(
        _ rows: [ChatNativeRow], label: String
    ) {
        let set = tracker.ingest(rows: rows)
        for vc in [sectionVC, singleVC] {
            vc!.applyChanges(
                rows: rows, changeSet: set,
                layout: layout, topInset: 0,
                bottomMargin: 16,
                composerView: AnyView(Color.clear),
                arrowView: AnyView(Color.clear)
            )
        }
        assertEquivalent(
            rowCount: rows.count, label: label
        )
    }

    private func feedLegacy(
        _ rows: [ChatNativeRow], label: String
    ) {
        for vc in [sectionVC, singleVC] {
            vc!.apply(
                rows: rows, layout: layout,
                topInset: 0, bottomMargin: 16,
                composerView: AnyView(Color.clear),
                arrowView: AnyView(Color.clear)
            )
        }
        assertEquivalent(
            rowCount: rows.count, label: label
        )
    }

    func testGeometryEquivalenceViaChangeSets() {
        assemblePair()
        let base = rows(Array(0..<120))
        feedChanges(base, label: "冷开 120")
        feedChanges(base, label: "稳态")
        // 编辑（中行修订＋高变）
        var edited = base
        edited[60] = row(60, version: 1, height: 480)
        feedChanges(edited, label: "编辑")
        // 插行（第 10 位插 3 行新键）
        var inserted = edited
        inserted.insert(
            contentsOf: [row(200), row(201), row(202)],
            at: 10
        )
        feedChanges(inserted, label: "插行")
        // 删行（删第 50、51 位）
        var deleted = inserted
        deleted.removeSubrange(50...51)
        feedChanges(deleted, label: "删行")
        // 高度-only 回填（同修订、五点位高变）
        var refilled = deleted
        for index in [0, 30, 60, 90, refilled.count - 1] {
            let old = refilled[index]
            refilled[index] = ChatNativeRow(
                key: old.key, entryID: nil,
                revision: old.revision,
                height: old.height + 37,
                makeView: { AnyView(EmptyView()) }
            )
        }
        feedChanges(refilled, label: "高度-only 回填")
        // facet 翻转（修订变、高不变）
        var flipped = refilled
        flipped[20] = ChatNativeRow(
            key: flipped[20].key, entryID: nil,
            revision: {
                var r = ChatNativeRowRevision()
                r.addText("facet-flipped")
                return r
            }(),
            height: flipped[20].height,
            makeView: { AnyView(EmptyView()) }
        )
        feedChanges(flipped, label: "facet 翻转")
        // 序变（交换第 5 与第 60 位）
        var reordered = flipped
        reordered.swapAt(5, 60)
        feedChanges(reordered, label: "序变")
        // 缩集／清空／再生长
        feedChanges(
            Array(reordered.prefix(3)), label: "缩集 3"
        )
        feedChanges([], label: "清空")
        feedChanges(
            rows(Array(300..<340)), label: "再生长 40"
        )
        feedChanges(
            rows(Array(300..<340)), label: "收尾稳态"
        )
    }

    func testGeometryEquivalenceViaLegacyApply() {
        assemblePair()
        let base = rows(Array(0..<80))
        feedLegacy(base, label: "旧路冷开 80")
        feedLegacy(base, label: "旧路稳态")
        var edited = base
        edited[40] = row(40, version: 1, height: 512)
        feedLegacy(edited, label: "旧路编辑")
        var inserted = edited
        inserted.insert(row(400), at: 0)
        inserted.append(row(401))
        feedLegacy(inserted, label: "旧路首尾插行")
        var deleted = inserted
        deleted.removeSubrange(10...19)
        feedLegacy(deleted, label: "旧路删行")
        feedLegacy([], label: "旧路清空")
        feedLegacy(
            rows(Array(500..<520)), label: "旧路再生长"
        )
    }
}
