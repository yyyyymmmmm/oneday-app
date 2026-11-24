import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 141/142 根治装配层（2026-11-19 用户令对话页按
/// OpenBot 做法）：选区在场行＝行 machinery 让路
/// 区——①该行修订变化不落重配（托管视图不换代、
/// 平台文本视图与选区存活的前提）；②选区清账回
/// 调到达后暂存重配恰 flush 一次；③选区记账只落
/// 账本（延迟清账语义不变）。量测备忘（143）：
/// 同串同宽二度量测只落一次账、尺寸恒同
@MainActor
final class ChatSelectionProtectionAssemblyTests: XCTestCase {
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

    private func hostingCell(
        at index: Int
    ) throws -> ChatNativeHostingCell {
        let cell = controller?.collectionView
            .cellForItem(
                at: IndexPath(item: 0, section: index)
            )
        return try XCTUnwrap(
            cell as? ChatNativeHostingCell,
            "section \(index) 应有托管 cell"
        )
    }

    /// 选区在场：该行修订变化被暂存（零重配）；保
    /// 护结束后 flush 恰一次；他行不被殃及
    func testSelectionRowReconfigureStagedUntilProtectionEnds()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let cellB = try hostingCell(at: 1)
        let cellC = try hostingCell(at: 2)
        let baseB = cellB.configureCount
        let baseC = cellC.configureCount

        handle.selectionActiveRowKey = "b"
        rows[1] = textRow("b", text: "b-v2")
        rows[2] = textRow("c", text: "c-v2")
        apply(rows)
        drain(0.6)
        XCTAssertEqual(
            cellB.configureCount, baseB,
            "选区在场行重配须暂存（托管视图不许换代）"
        )
        XCTAssertEqual(
            cellC.configureCount, baseC + 1,
            "他行重配不受选区暂存殃及"
        )

        handle.selectionActiveRowKey = nil
        handle.noteSelectionProtectionEnded()
        drain(0.8)
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "选区保护结束后暂存重配须恰 flush 一次"
        )
    }

    /// 账本选区记账：置位即读得到、消选延迟清账
    /// （350ms 旧制）、清账回调恰达一次
    func testLedgerSelectionBookkeeping() {
        let ledger = ChatRowStateLedger()
        let entryID = UUID()
        var endedCount = 0
        ledger.noteTextSelection(
            entryID: entryID, active: true,
            onProtectionEnded: { endedCount += 1 }
        )
        XCTAssertEqual(ledger.textSelectionEntryID, entryID)
        ledger.noteTextSelection(
            entryID: entryID, active: false,
            onProtectionEnded: { endedCount += 1 }
        )
        // 延迟窗内仍在账（换块选字的保护不误清）
        XCTAssertEqual(ledger.textSelectionEntryID, entryID)
        let exp = expectation(description: "clear delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertNil(ledger.textSelectionEntryID)
        XCTAssertEqual(endedCount, 1)
    }

    /// 143 量测备忘：同串同宽二度量测尺寸恒同、备
    /// 忘只落一笔（第二度走备忘、不再真量）
    func testMeasuredSizeMemoized() {
        let attributed = NSAttributedString(
            string: "量测备忘样本 \(UUID().uuidString)",
            attributes: [
                .font: UIFont.preferredFont(
                    forTextStyle: .body
                )
            ]
        )
        let proposal = ProposedViewSize(
            width: 300, height: nil
        )
        let before = SelectableTextRepresentable
            .measuredSizeCacheCount
        let first = SelectableTextRepresentable.measuredSize(
            attributed: attributed, proposal: proposal
        )
        let afterFirst = SelectableTextRepresentable
            .measuredSizeCacheCount
        let second = SelectableTextRepresentable.measuredSize(
            attributed: attributed, proposal: proposal
        )
        let afterSecond = SelectableTextRepresentable
            .measuredSizeCacheCount
        XCTAssertEqual(first, second)
        XCTAssertEqual(afterFirst, before + 1)
        XCTAssertEqual(
            afterSecond, afterFirst,
            "同串同宽第二度量测须命中备忘（零新增真量）"
        )
    }
}
