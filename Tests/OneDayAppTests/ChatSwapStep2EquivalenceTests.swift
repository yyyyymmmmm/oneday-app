import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374（换引擎步骤 2）控制器去对账钉测：
/// ①等价矩阵——合成富会话 300 条、十三趟喂入覆
/// 盖六类变更（流式尾行／落定同键换代／编辑／删
/// 除／插行／facet 翻转）＋冷开／稳态／高度-only
/// ／高回填／序变／整批替换，新路（追踪器变更集
/// →applyChanges）与旧路（apply 全量对账）逐趟
/// 终态逐值同：快照条目序、修订账、高度账（按
/// 键与按序两读口）；影子账全程清零；
/// ②落定同键换代的追踪器口径（§247：直播行键
/// 被落定条目沿用——首见条目＋同键修订差必须入
/// updated，步骤 2 实查的步骤 1 缺口）；
/// ③高-only 回填不触发快照施工/重配（计数断言）
@MainActor
final class ChatSwapStep2EquivalenceTests: XCTestCase {

    private let styleKey = "style-a"
    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )

    private var oldWindow: UIWindow!
    private var newWindow: UIWindow!
    private var oldController: ChatRootViewController!
    private var newController: ChatRootViewController!
    private var tracker: ChatFeedChangeTracker!

    override func tearDown() {
        oldWindow?.isHidden = true
        newWindow?.isHidden = true
        oldWindow = nil
        newWindow = nil
        oldController = nil
        newController = nil
        tracker = nil
        super.tearDown()
    }

    private func makeController(
        in window: inout UIWindow?
    ) -> ChatRootViewController {
        let w = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let root = UIViewController()
        w.rootViewController = root
        w.makeKeyAndVisible()
        let handle = ChatNativeListHandle()
        let controller = ChatRootViewController()
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
        root.view.layoutIfNeeded()
        window = w
        return controller
    }

    private func assemblePair() {
        oldController = makeController(in: &oldWindow)
        newController = makeController(in: &newWindow)
        tracker = ChatFeedChangeTracker()
    }

    private func feedOld(rows: [ChatNativeRow]) {
        oldController.apply(
            rows: rows, layout: layout,
            topInset: 0, bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    private func feedNew(
        rows: [ChatNativeRow],
        changeSet: EntryChangeSet
    ) {
        newController.applyChanges(
            rows: rows, changeSet: changeSet,
            layout: layout,
            topInset: 0, bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    /// 双路同喂＋终态对账（快照序/修订账/高度账
    /// 按键/高度账按序/影子账）
    @discardableResult
    private func feedBoth(
        rows: [ChatNativeRow],
        bases: [ChatFeedEntryBasis],
        label: String
    ) -> EntryChangeSet {
        feedOld(rows: rows)
        for basis in bases {
            tracker.noteEntryBasis(basis)
        }
        let set = tracker.ingest(rows: rows)
        feedNew(rows: rows, changeSet: set)
        XCTAssertEqual(
            tracker.shadowLedger.diffCount, 0,
            "影子账须清零（\(label)）"
        )
        XCTAssertEqual(
            newController.testSnapshotKeyOrder,
            oldController.testSnapshotKeyOrder,
            "快照条目序须逐值同（\(label)）"
        )
        XCTAssertEqual(
            newController.testRevisionsByKey,
            oldController.testRevisionsByKey,
            "修订账须逐值同（\(label)）"
        )
        XCTAssertEqual(
            newController.testRowHeightsByKey,
            oldController.testRowHeightsByKey,
            "高度账（按键）须逐值同（\(label)）"
        )
        XCTAssertEqual(
            newController.testAdoptedRowHeights,
            oldController.testAdoptedRowHeights,
            "高度账（按序）须逐值同（\(label)）"
        )
        return set
    }

    // MARK: - 语料构建（与步骤 1 测试同法）

    private func makeEntry(
        _ index: Int, role: String? = nil
    ) -> ChatEntry {
        let entry = ChatEntry(
            role: role ?? (index % 2 == 0 ? "user" : "assistant"),
            content: "第 \(index) 条正文：合成会话语料，"
                + "长度随序号变 \(String(repeating: "文", count: index % 40))。",
            thread: nil,
            reasoning: index % 10 == 3 ? "思考 \(index)" : nil,
            reasoningSeconds: index % 10 == 3 ? 2.5 : nil
        )
        if index % 25 == 7 {
            entry.toolCardData = Data(
                "{\"tool\":\"web_search\",\"i\":\(index)}".utf8
            )
        }
        if index % 30 == 11 {
            entry.reactionsData = Data([1, 2, 3])
        }
        entry.createdAt = Date(
            timeIntervalSinceReferenceDate:
                780_000_000 + Double(index * 60)
        )
        return entry
    }

    private func entryRow(
        _ entry: ChatEntry,
        sources: [MessageSource] = [],
        highlighted: Bool = false,
        height: CGFloat = 100,
        provisional: Bool = false,
        keyOverride: String? = nil
    ) -> ChatNativeRow {
        var revision = ChatNativeRowRevision.entryBase(
            entry, dividerText: nil,
            showsUnreadDivider: false
        )
        for source in sources {
            revision.addText(source.url)
            revision.addText(source.title)
        }
        revision.addFlag(highlighted)
        revision.addText(styleKey)
        return ChatNativeRow(
            key: keyOverride
                ?? "entry-\(entry.id.uuidString)",
            entryID: entry.id,
            revision: revision,
            height: height,
            heightIsProvisional: provisional,
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func basis(
        for entry: ChatEntry,
        sources: [MessageSource] = [],
        highlighted: Bool = false,
        height: CGFloat = 100,
        provisional: Bool = false
    ) -> ChatFeedEntryBasis {
        ChatFeedEntryBasis(
            entryID: entry.id,
            snapshot: ChatEntryRevisionSnapshot
                .capture(entry),
            dividerText: nil,
            showsUnreadDivider: false,
            sources: sources,
            highlighted: highlighted,
            styleKey: styleKey,
            feedHeight: height,
            heightIsProvisional: provisional
        )
    }

    private func liveRow(content: String) -> ChatNativeRow {
        var revision = ChatNativeRowRevision()
        revision.addText(content)
        return ChatNativeRow(
            key: "live-open-1",
            entryID: nil,
            revision: revision,
            height: 80,
            makeView: { AnyView(EmptyView()) }
        )
    }

    // MARK: - ① 等价矩阵（十三趟）

    func testControllerEquivalenceAcrossChangeKinds() {
        assemblePair()
        var settled = (0..<300).map { makeEntry($0) }
        var liveContent: String? = "流式片段 A"
        var highlightedIDs: Set<UUID> = []
        var heightOverrides: [UUID: CGFloat] = [:]
        var provisionalIDs: Set<UUID> = []
        var keyOverrides: [UUID: String] = [:]

        func currentRows() -> [ChatNativeRow] {
            var rows = settled.map { entry in
                entryRow(
                    entry,
                    highlighted: highlightedIDs
                        .contains(entry.id),
                    height: heightOverrides[entry.id] ?? 100,
                    provisional: provisionalIDs
                        .contains(entry.id),
                    keyOverride: keyOverrides[entry.id]
                )
            }
            if let liveContent {
                rows.append(liveRow(content: liveContent))
            }
            return rows
        }
        func currentBases() -> [ChatFeedEntryBasis] {
            settled.map { entry in
                basis(
                    for: entry,
                    highlighted: highlightedIDs
                        .contains(entry.id),
                    height: heightOverrides[entry.id] ?? 100,
                    provisional: provisionalIDs
                        .contains(entry.id)
                )
            }
        }
        func pass(_ label: String) -> EntryChangeSet {
            feedBoth(
                rows: currentRows(),
                bases: currentBases(),
                label: label
            )
        }

        // 趟 1：冷开（300 落定行＋1 直播行）——新
        // 路空态走重建路
        let first = pass("冷开")
        XCTAssertEqual(first.inserted.count, 301)

        // 趟 2：稳态——新路快路（变更集全空）
        let steady = pass("稳态")
        XCTAssertTrue(
            steady.isEmpty && steady.heightChanged.isEmpty
                && !steady.orderChanged
        )

        // 趟 3：纯流式尾行生长
        liveContent = "流式片段 A＋B＋C，继续生长"
        let streaming = pass("流式尾行")
        XCTAssertEqual(streaming.updated, ["live-open-1"])
        XCTAssertTrue(
            streaming.inserted.isEmpty
                && streaming.deleted.isEmpty
        )

        // 趟 4：落定同键换代（§247）——直播行退
        // 场、落定条目沿用直播行键入列：键续行、
        // 身份新现、修订差判更新（非删/插）
        let settledTail = makeEntry(300, role: "assistant")
        settledTail.content = "流式片段 A＋B＋C，继续生长（落定全文）"
        settled.append(settledTail)
        keyOverrides[settledTail.id] = "live-open-1"
        liveContent = nil
        let settle = pass("落定同键换代")
        XCTAssertEqual(settle.updated, ["live-open-1"])
        XCTAssertTrue(
            settle.inserted.isEmpty
                && settle.deleted.isEmpty
        )

        // 趟 5：落定后稳态——记录沿用、变更集空
        let afterSettle = pass("落定后稳态")
        XCTAssertTrue(afterSettle.isEmpty)

        // 趟 6：编辑（同 id 内容变更）
        let edited = settled[150]
        edited.content = "编辑后的正文（同 id 内容变更）"
        let edit = pass("编辑")
        XCTAssertEqual(
            edit.updated,
            ["entry-\(edited.id.uuidString)"]
        )

        // 趟 7：删除
        let removed = settled.remove(at: 200)
        let deletion = pass("删除")
        XCTAssertEqual(
            deletion.deleted,
            ["entry-\(removed.id.uuidString)"]
        )
        XCTAssertTrue(deletion.updated.isEmpty)

        // 趟 8：中段插行
        let insertedEntry = makeEntry(301, role: "user")
        settled.insert(insertedEntry, at: 100)
        let insertion = pass("插行")
        XCTAssertEqual(
            insertion.inserted,
            ["entry-\(insertedEntry.id.uuidString)"]
        )
        XCTAssertTrue(insertion.updated.isEmpty)

        // 趟 9：facet 翻转（条目字段＋环境点亮）
        let facetEntry = settled[10]
        facetEntry.sendFailed = true
        let litEntry = settled[20]
        highlightedIDs.insert(litEntry.id)
        let facet = pass("facet 翻转")
        XCTAssertEqual(
            facet.updated,
            [
                "entry-\(facetEntry.id.uuidString)",
                "entry-\(litEntry.id.uuidString)",
            ]
        )

        // 趟 10：高度-only——编辑集空、高集独载
        let heightEntry = settled[30]
        heightOverrides[heightEntry.id] = 186
        let heightOnly = pass("高度-only")
        XCTAssertTrue(heightOnly.isEmpty)
        XCTAssertEqual(
            heightOnly.heightChanged,
            ["entry-\(heightEntry.id.uuidString)"]
        )

        // 趟 11：高回填三拍（§335 确高纪律）——临
        // 界喂入（匣内已有同修订确高 100→回填
        // 100）／确高 140 入账／再临界喂入（回填
        // 140、不打回临界）
        let backfillEntry = settled[40]
        let backfillKey =
            "entry-\(backfillEntry.id.uuidString)"
        heightOverrides[backfillEntry.id] = 90
        provisionalIDs.insert(backfillEntry.id)
        _ = pass("回填·临界")
        XCTAssertEqual(
            newController.testRowHeightsByKey[backfillKey],
            100
        )
        heightOverrides[backfillEntry.id] = 140
        provisionalIDs.remove(backfillEntry.id)
        _ = pass("回填·确高")
        XCTAssertEqual(
            newController.testRowHeightsByKey[backfillKey],
            140
        )
        heightOverrides[backfillEntry.id] = 90
        provisionalIDs.insert(backfillEntry.id)
        _ = pass("回填·再临界")
        XCTAssertEqual(
            newController.testRowHeightsByKey[backfillKey],
            140
        )

        // 趟 12：序变（相邻两行换位）——新路见序
        // 变旗走重建路
        settled.swapAt(10, 11)
        let reorder = pass("序变")
        XCTAssertTrue(reorder.orderChanged)

        // 趟 13：整批替换（会话切换形态）＋收尾稳态
        settled = (0..<50).map { makeEntry(1000 + $0) }
        highlightedIDs = []
        heightOverrides = [:]
        provisionalIDs = []
        keyOverrides = [:]
        _ = pass("整批替换")
        let final = pass("收尾稳态")
        XCTAssertTrue(final.isEmpty)
        XCTAssertEqual(tracker.shadowLedger.passCount, 16)
        XCTAssertEqual(tracker.shadowLedger.diffCount, 0)
    }

    // MARK: - ② 落定同键换代（追踪器口径）

    func testSameKeySettleProducesUpdate() {
        let tracker = ChatFeedChangeTracker()
        let live = liveRow(content: "流式正文")
        let first = tracker.ingest(rows: [live])
        XCTAssertEqual(first.inserted, ["live-open-1"])

        // 落定条目沿用直播行键、条目身份本趟初现
        let entry = makeEntry(7, role: "assistant")
        entry.content = "流式正文（落定全文）"
        let row = entryRow(
            entry, keyOverride: "live-open-1"
        )
        tracker.noteEntryBasis(basis(for: entry))
        let settle = tracker.ingest(rows: [row])
        XCTAssertEqual(settle.updated, ["live-open-1"])
        XCTAssertTrue(
            settle.inserted.isEmpty
                && settle.deleted.isEmpty
        )
        XCTAssertEqual(tracker.shadowLedger.diffCount, 0)

        // 落定后稳态：记录沿用、变更集空
        tracker.noteEntryBasis(basis(for: entry))
        let steady = tracker.ingest(rows: [row])
        XCTAssertTrue(steady.isEmpty)
        XCTAssertEqual(tracker.shadowLedger.diffCount, 0)
    }

    // MARK: - ③ 高-only 回填不触发快照施工/重配

    func testHeightOnlyBackfillSkipsSnapshotApply() {
        assemblePair()
        let entries = (0..<50).map { makeEntry($0) }
        let rows = entries.map { entryRow($0) }
        for entry in entries {
            tracker.noteEntryBasis(basis(for: entry))
        }
        let cold = tracker.ingest(rows: rows)
        feedNew(rows: rows, changeSet: cold)
        let appliesAfterCold =
            newController.testSnapshotApplyCount
        let reconfigsAfterCold =
            newController.testReconfiguredItemCount
        XCTAssertGreaterThan(appliesAfterCold, 0)

        // 高-only 一趟：快照施工与重配计数纹丝不动
        let target = entries[10]
        var rows2 = rows
        rows2[10] = entryRow(target, height: 186)
        for entry in entries {
            tracker.noteEntryBasis(
                basis(
                    for: entry,
                    height: entry.id == target.id
                        ? 186 : 100
                )
            )
        }
        let heightSet = tracker.ingest(rows: rows2)
        XCTAssertTrue(heightSet.isEmpty)
        XCTAssertEqual(
            heightSet.heightChanged,
            ["entry-\(target.id.uuidString)"]
        )
        feedNew(rows: rows2, changeSet: heightSet)
        XCTAssertEqual(
            newController.testSnapshotApplyCount,
            appliesAfterCold,
            "高-only 回填不许触发快照施工"
        )
        XCTAssertEqual(
            newController.testReconfiguredItemCount,
            reconfigsAfterCold,
            "高-only 回填不许触发 cell 重配"
        )
        XCTAssertEqual(
            newController.testRowHeightsByKey[
                "entry-\(target.id.uuidString)"
            ],
            186
        )

        // 对照：真编辑一趟——计数必须动（防计数口
        // 本身失灵的假绿）
        target.content = "计数对照编辑"
        var rows3 = rows2
        rows3[10] = entryRow(target, height: 186)
        for entry in entries {
            tracker.noteEntryBasis(
                basis(
                    for: entry,
                    height: entry.id == target.id
                        ? 186 : 100
                )
            )
        }
        let editSet = tracker.ingest(rows: rows3)
        XCTAssertEqual(
            editSet.updated,
            ["entry-\(target.id.uuidString)"]
        )
        feedNew(rows: rows3, changeSet: editSet)
        XCTAssertEqual(
            newController.testSnapshotApplyCount,
            appliesAfterCold + 1
        )
        XCTAssertEqual(
            newController.testReconfiguredItemCount,
            reconfigsAfterCold + 1
        )
    }
}
