import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §374.8（换引擎步骤 5）选区单键暂缓·增量路
/// 合成测：双控制器同喂变更集——保护路（选区
/// 在场行 b）与无保护路逐趟对账：①选区在场时
/// 同键 update 暂存（连发两拍零重配）、异键直
/// 达逐拍落写；②清账回调后补发恰一次；③终态
/// （快照序／修订账／高度账按键／采用高谱）与
/// 无保护路逐值同；④暂缓开关关时选区行也直
/// 达（应急档语义）。真机选区存活（长按选字/
/// 双击选词时流式推进）实验室无触摸注入、证
/// 不了，关账门在真机（见 DESIGN §374.8）
@MainActor
final class ChatSwapStep5SelectionKeyTests: XCTestCase {

    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )

    private var windowA: UIWindow!
    private var windowB: UIWindow!
    private var protected: ChatRootViewController!
    private var protectedHandle: ChatNativeListHandle!
    private var plain: ChatRootViewController!
    private var plainHandle: ChatNativeListHandle!

    override func tearDown() {
        windowA?.isHidden = true
        windowB?.isHidden = true
        windowA = nil
        windowB = nil
        protected = nil
        protectedHandle = nil
        plain = nil
        plainHandle = nil
        super.tearDown()
    }

    private func makeController(
        in window: inout UIWindow?,
        handle: inout ChatNativeListHandle?
    ) -> ChatRootViewController {
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
        // 本文件 cell 寻址认逐行 section 构造，钉死
        // 构造口径（与 Hotfix330 同式）
        list.testSingleSectionOverride = false
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        handle = listHandle
        return list
    }

    private func assemblePair() {
        protected = makeController(
            in: &windowA, handle: &protectedHandle
        )
        plain = makeController(
            in: &windowB, handle: &plainHandle
        )
    }

    private func textRow(
        _ key: String, text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text(text)]
            ),
            height: 60,
            makeView: {
                AnyView(
                    Text(text)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    private func feed(
        _ controller: ChatRootViewController,
        rows: [ChatNativeRow],
        changeSet: EntryChangeSet
    ) {
        controller.applyChanges(
            rows: rows, changeSet: changeSet,
            layout: layout,
            topInset: 0, bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    private func feedBoth(
        rows: [ChatNativeRow],
        changeSet: EntryChangeSet
    ) {
        feed(protected, rows: rows, changeSet: changeSet)
        feed(plain, rows: rows, changeSet: changeSet)
        windowA?.layoutIfNeeded()
        windowB?.layoutIfNeeded()
    }

    private func drain(
        _ seconds: TimeInterval, window: UIWindow?
    ) {
        let exp = expectation(
            description: "drain \(seconds)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func hostingCell(
        _ controller: ChatRootViewController, at index: Int
    ) throws -> ChatNativeHostingCell {
        let cell = controller.collectionView.cellForItem(
            at: IndexPath(item: 0, section: index)
        )
        return try XCTUnwrap(
            cell as? ChatNativeHostingCell,
            "section \(index) 应有托管 cell"
        )
    }

    /// 主合成测：暂存／直达／补发恰一次／终态同
    func testSelectionKeyStagingFlushAndTerminalEquality()
        throws
    {
        assemblePair()
        let v1 = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        feedBoth(
            rows: v1,
            changeSet: EntryChangeSet(
                inserted: ["a", "b", "c"]
            )
        )
        drain(0.6, window: windowA)
        drain(0.6, window: windowB)
        let pCellB = try hostingCell(protected, at: 1)
        let pCellC = try hostingCell(protected, at: 2)
        let uCellB = try hostingCell(plain, at: 1)
        let uCellC = try hostingCell(plain, at: 2)
        let pBaseB = pCellB.configureCount
        let pBaseC = pCellC.configureCount
        let uBaseB = uCellB.configureCount
        let uBaseC = uCellC.configureCount

        protectedHandle.selectionActiveRowKey = "b"
        // 连发两拍：b 每拍更新、c 只首拍更新
        var rows = v1
        rows[1] = textRow("b", text: "b-v2")
        rows[2] = textRow("c", text: "c-v2")
        feedBoth(
            rows: rows,
            changeSet: EntryChangeSet(updated: ["b", "c"])
        )
        rows[1] = textRow("b", text: "b-v3")
        feedBoth(
            rows: rows,
            changeSet: EntryChangeSet(updated: ["b"])
        )
        XCTAssertEqual(
            pCellB.configureCount, pBaseB,
            "选区在场行同键 update 须暂存（连发两拍零重配）"
        )
        XCTAssertEqual(
            uCellB.configureCount, uBaseB + 2,
            "无保护路同键 update 须逐拍直达（对照）"
        )
        XCTAssertEqual(
            pCellC.configureCount, pBaseC + 1,
            "异键 update 须直达、不被选区暂存殃及"
        )
        XCTAssertEqual(
            uCellC.configureCount, uBaseC + 1,
            "异键 update 两路同拍落写"
        )

        protectedHandle.selectionActiveRowKey = nil
        protectedHandle.noteSelectionProtectionEnded()
        drain(0.8, window: windowA)
        XCTAssertEqual(
            pCellB.configureCount, pBaseB + 1,
            "清账后暂存须恰补发一次（按当前行值＝最新修订）"
        )
        XCTAssertEqual(pCellB.configuredKey, "b")

        // 终态逐值同（快照序/修订账/高度账/采用高谱）
        XCTAssertEqual(
            protected.testSnapshotKeyOrder,
            plain.testSnapshotKeyOrder,
            "快照条目序须逐值同"
        )
        XCTAssertEqual(
            protected.testRevisionsByKey,
            plain.testRevisionsByKey,
            "修订账须逐值同"
        )
        XCTAssertEqual(
            protected.testRowHeightsByKey,
            plain.testRowHeightsByKey,
            "高度账（按键）须逐值同"
        )
        XCTAssertEqual(
            protected.testAdoptedRowHeights,
            plain.testAdoptedRowHeights,
            "采用高谱须逐值同"
        )
    }

    /// 开关语义：暂缓停用（覆盖口置假）时选区行
    /// 也直达、清账后无幽灵补发
    func testSelectionKeyGuardOffAppliesDirectly() throws {
        assemblePair()
        protected.testSelectionKeyGuardOverride = false
        let v1 = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        feed(
            protected, rows: v1,
            changeSet: EntryChangeSet(
                inserted: ["a", "b", "c"]
            )
        )
        drain(0.6, window: windowA)
        let cellB = try hostingCell(protected, at: 1)
        let baseB = cellB.configureCount

        protectedHandle.selectionActiveRowKey = "b"
        var rows = v1
        rows[1] = textRow("b", text: "b-v2")
        feed(
            protected, rows: rows,
            changeSet: EntryChangeSet(updated: ["b"])
        )
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "暂缓停用时选区在场行 update 须直达"
        )
        protectedHandle.selectionActiveRowKey = nil
        protectedHandle.noteSelectionProtectionEnded()
        drain(0.8, window: windowA)
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "暂缓停用时不许有暂存补发"
        )
    }
}
