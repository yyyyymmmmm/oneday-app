import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374（换引擎步骤 1）变更集产出钉测：
/// ①等价矩阵——合成富会话 300 条、十趟喂入覆盖
/// 六类变更（纯流式尾行／落定／编辑／删除／插行
/// ／facet 翻转）＋冷开／稳态／高度-only，新路变
/// 更集（条目走 §362 快照＋环境尾段判定）与旧路
/// 修订差集（applyNow 口径：键集差＋同键修订全
/// 量比较）逐趟逐集相等、影子账全程清零；
/// ②行值缓存身份——未变条目 Record 对象 === 沿
/// 用、修订级变更换账、高-only 变对象不变高刷新；
/// ③影子账非空转——故意喂陈旧验证基（新路判未
/// 变、旧路判已变）时差异必须被抓住并记首键；
/// ④开关缺省关（Core 旗口径）
@MainActor
final class ChatFeedChangeSetStep1Tests: XCTestCase {

    private let styleKey = "style-a"

    // MARK: - 语料与构建口（与 nativeEntryRow 同法）

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

    /// 条目行构建：基段（快照前缀＋分隔／未读尾段）
    /// ＋来源折入＋点亮＋样式键——与 ChatView.
    /// nativeEntryRow 的修订组装逐项同法
    private func entryRow(
        _ entry: ChatEntry,
        sources: [MessageSource] = [],
        highlighted: Bool = false,
        height: CGFloat = 100
    ) -> ChatNativeRow {
        var revision = ChatNativeRowRevision.entryBase(
            entry, dividerText: nil, showsUnreadDivider: false
        )
        for source in sources {
            revision.addText(source.url)
            revision.addText(source.title)
        }
        revision.addFlag(highlighted)
        revision.addText(styleKey)
        return ChatNativeRow(
            key: "entry-\(entry.id.uuidString)",
            entryID: entry.id,
            revision: revision,
            height: height,
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func basis(
        for entry: ChatEntry,
        sources: [MessageSource] = [],
        highlighted: Bool = false,
        height: CGFloat = 100
    ) -> ChatFeedEntryBasis {
        ChatFeedEntryBasis(
            entryID: entry.id,
            snapshot: ChatEntryRevisionSnapshot.capture(entry),
            dividerText: nil,
            showsUnreadDivider: false,
            sources: sources,
            highlighted: highlighted,
            styleKey: styleKey,
            feedHeight: height,
            heightIsProvisional: false
        )
    }

    /// 直播行（非条目行）：修订随流式正文生长
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

    /// 旧路差集（applyNow 现行定义复刻）：键集差
    /// ＋同键修订全量比较
    private func oldRoadDiff(
        previous: [ChatNativeRow],
        current: [ChatNativeRow]
    ) -> EntryChangeSet {
        let prevKeys = Set(previous.map(\.key))
        let newKeys = Set(current.map(\.key))
        let prevRevisions = Dictionary(
            uniqueKeysWithValues: previous.map {
                ($0.key, $0.revision)
            }
        )
        var set = EntryChangeSet()
        set.inserted = newKeys.subtracting(prevKeys)
        set.deleted = prevKeys.subtracting(newKeys)
        for row in current where prevKeys.contains(row.key) {
            if prevRevisions[row.key] != row.revision {
                set.updated.insert(row.key)
            }
        }
        // §374.2 追加两字段（喂入级事实、与生产追
        // 踪器同定义）：高-only＝续行键（高，临界
        // 旗）变且未入 updated；序变＝续行键在两
        // 趟序中的相对序变
        let prevHeights = Dictionary(
            uniqueKeysWithValues: previous.map {
                ($0.key, (height: $0.height,
                          provisional:
                            $0.heightIsProvisional))
            }
        )
        for row in current
        where prevKeys.contains(row.key)
            && !set.updated.contains(row.key) {
            if let prev = prevHeights[row.key],
               (prev.height != row.height
                || prev.provisional
                    != row.heightIsProvisional) {
                set.heightChanged.insert(row.key)
            }
        }
        set.orderChanged = previous.filter {
            newKeys.contains($0.key)
        }.map(\.key) != current.filter {
            prevKeys.contains($0.key)
        }.map(\.key)
        return set
    }

    @discardableResult
    private func feed(
        _ tracker: ChatFeedChangeTracker,
        rows: [ChatNativeRow],
        bases: [ChatFeedEntryBasis]
    ) -> EntryChangeSet {
        for base in bases {
            tracker.noteEntryBasis(base)
        }
        return tracker.ingest(rows: rows)
    }

    // MARK: - ① 等价矩阵（六类变更十趟）

    func testShadowEquivalenceAcrossSixChangeKinds() {
        let tracker = ChatFeedChangeTracker()
        var settled = (0..<300).map { makeEntry($0) }
        var liveContent: String? = "流式片段 A"
        var highlightedIDs: Set<UUID> = []
        var heightOverrides: [UUID: CGFloat] = [:]
        var previousRows: [ChatNativeRow] = []

        func currentRows() -> [ChatNativeRow] {
            var rows = settled.map { entry in
                entryRow(
                    entry,
                    highlighted: highlightedIDs
                        .contains(entry.id),
                    height: heightOverrides[entry.id] ?? 100
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
                    height: heightOverrides[entry.id] ?? 100
                )
            }
        }
        func pass(_ label: String) -> EntryChangeSet {
            let rows = currentRows()
            let set = feed(
                tracker, rows: rows, bases: currentBases()
            )
            XCTAssertEqual(
                set,
                oldRoadDiff(
                    previous: previousRows, current: rows
                ),
                "变更集须与旧路差集逐趟等价（\(label)）"
            )
            XCTAssertEqual(
                tracker.shadowLedger.diffCount, 0,
                "影子账须清零（\(label)）"
            )
            previousRows = rows
            return set
        }

        // 趟 1：冷开全量（300 落定行＋1 直播行）
        let first = pass("冷开")
        XCTAssertEqual(first.inserted.count, 301)
        XCTAssertTrue(
            first.updated.isEmpty && first.deleted.isEmpty
        )
        let probeEntry = settled[5]
        let recordAfterFirst = tracker.rowValueCache
            .record(for: probeEntry.id)
        XCTAssertNotNil(recordAfterFirst)

        // 趟 2：稳态无变化——变更集为空、行值记录
        // 身份不变、全行修订级沿用
        let steady = pass("稳态")
        XCTAssertTrue(steady.isEmpty)
        XCTAssertTrue(
            tracker.rowValueCache.record(
                for: probeEntry.id
            ) === recordAfterFirst
        )
        XCTAssertEqual(tracker.rowValueCache.reuseCount, 300)

        // 趟 3：纯流式尾行生长（六类之一）
        liveContent = "流式片段 A＋B＋C，继续生长"
        let streaming = pass("流式尾行")
        XCTAssertEqual(streaming.updated, ["live-open-1"])
        XCTAssertTrue(
            streaming.inserted.isEmpty
                && streaming.deleted.isEmpty
        )

        // 趟 4：落定（六类之二）——直播行退场、落
        // 定条目以条目键入列
        let settledTail = makeEntry(300, role: "assistant")
        settledTail.content = "流式片段 A＋B＋C，继续生长（落定全文）"
        settled.append(settledTail)
        liveContent = nil
        let settle = pass("落定")
        XCTAssertEqual(settle.deleted, ["live-open-1"])
        XCTAssertEqual(
            settle.inserted,
            ["entry-\(settledTail.id.uuidString)"]
        )
        XCTAssertTrue(settle.updated.isEmpty)

        // 趟 5：编辑（六类之三）——同 id 内容变更
        let edited = settled[150]
        edited.content = "编辑后的正文（同 id 内容变更）"
        let edit = pass("编辑")
        XCTAssertEqual(
            edit.updated, ["entry-\(edited.id.uuidString)"]
        )

        // 趟 6：删除（六类之四）
        let removed = settled.remove(at: 200)
        let deletion = pass("删除")
        XCTAssertEqual(
            deletion.deleted,
            ["entry-\(removed.id.uuidString)"]
        )
        XCTAssertTrue(
            deletion.updated.isEmpty
                && deletion.inserted.isEmpty
        )

        // 趟 7：插行（六类之五）——中段插入只入新
        // 行、无连带 update（键基非序位基的账面）
        let insertedEntry = makeEntry(301, role: "user")
        settled.insert(insertedEntry, at: 100)
        let insertion = pass("插行")
        XCTAssertEqual(
            insertion.inserted,
            ["entry-\(insertedEntry.id.uuidString)"]
        )
        XCTAssertTrue(
            insertion.updated.isEmpty
                && insertion.deleted.isEmpty
        )

        // 趟 8：facet 翻转（六类之六）——条目字段
        // （发送失败旗）＋环境项（点亮）同趟翻转
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

        // 趟 9：高度-only——变更集为空（旧路高变不
        // 重配）、记录身份不变、高账原地刷新
        let heightEntry = settled[30]
        let recordBeforeHeight = tracker.rowValueCache
            .record(for: heightEntry.id)
        heightOverrides[heightEntry.id] = 186
        let heightOnly = pass("高度-only")
        XCTAssertTrue(heightOnly.isEmpty)
        let recordAfterHeight = tracker.rowValueCache
            .record(for: heightEntry.id)
        XCTAssertTrue(recordAfterHeight === recordBeforeHeight)
        XCTAssertEqual(recordAfterHeight?.row.height, 186)

        // 趟 10：稳态收尾——影子账十趟全清零
        let final = pass("收尾稳态")
        XCTAssertTrue(final.isEmpty)
        XCTAssertEqual(tracker.shadowLedger.passCount, 10)
        XCTAssertEqual(tracker.shadowLedger.diffCount, 0)
        XCTAssertNil(tracker.shadowLedger.firstDiffKey)
    }

    // MARK: - ② 行值缓存身份生命周期

    func testRowValueCacheRecordIdentityLifecycle() {
        let tracker = ChatFeedChangeTracker()
        let a = makeEntry(1)
        let b = makeEntry(2)
        _ = feed(
            tracker,
            rows: [entryRow(a), entryRow(b)],
            bases: [basis(for: a), basis(for: b)]
        )
        let recordA1 = tracker.rowValueCache.record(for: a.id)
        XCTAssertNotNil(recordA1)
        XCTAssertEqual(tracker.rowValueCache.rebuildCount, 2)

        // 无变化趟：同一 Record 对象沿用
        _ = feed(
            tracker,
            rows: [entryRow(a), entryRow(b)],
            bases: [basis(for: a), basis(for: b)]
        )
        XCTAssertTrue(
            tracker.rowValueCache.record(for: a.id)
                === recordA1
        )
        XCTAssertEqual(tracker.rowValueCache.reuseCount, 2)

        // 内容变更：换账（新 Record 对象）
        a.content = "变更后的正文"
        _ = feed(
            tracker,
            rows: [entryRow(a), entryRow(b)],
            bases: [basis(for: a), basis(for: b)]
        )
        let recordA2 = tracker.rowValueCache.record(for: a.id)
        XCTAssertFalse(recordA2 === recordA1)

        // 高-only 变：对象不变、行值高刷新
        _ = feed(
            tracker,
            rows: [entryRow(a, height: 150), entryRow(b)],
            bases: [basis(for: a, height: 150), basis(for: b)]
        )
        XCTAssertTrue(
            tracker.rowValueCache.record(for: a.id)
                === recordA2
        )
        XCTAssertEqual(
            tracker.rowValueCache.record(for: a.id)?
                .row.height,
            150
        )
    }

    // MARK: - ③ 影子账非空转（陈旧基必须被抓）

    func testShadowLedgerCatchesStaleBasisDisagreement() {
        let tracker = ChatFeedChangeTracker()
        let a = makeEntry(1)
        let b = makeEntry(2)
        _ = feed(
            tracker,
            rows: [entryRow(a), entryRow(b)],
            bases: [basis(for: a), basis(for: b)]
        )
        XCTAssertEqual(tracker.shadowLedger.diffCount, 0)

        // 故意喂陈旧验证基：新路据旧快照判未变、旧
        // 路据新修订判已变——影子账必须抓住并记首键
        let staleBasis = basis(for: a)
        a.content = "修订已变但基仍旧"
        let set = feed(
            tracker,
            rows: [entryRow(a), entryRow(b)],
            bases: [staleBasis, basis(for: b)]
        )
        XCTAssertTrue(set.updated.isEmpty)
        XCTAssertEqual(
            tracker.lastOldRoadChangeSet.updated,
            ["entry-\(a.id.uuidString)"]
        )
        XCTAssertEqual(tracker.shadowLedger.diffCount, 1)
        XCTAssertEqual(
            tracker.shadowLedger.firstDiffKey,
            "entry-\(a.id.uuidString)"
        )
        XCTAssertEqual(
            tracker.shadowLedger.firstDiffKind, "updated"
        )
    }

    // MARK: - 来源集折入两路同值

    func testSourcesFoldIntoBothRoads() {
        let tracker = ChatFeedChangeTracker()
        let a = makeEntry(1)
        let source = MessageSource(
            title: "来源标题", url: "https://example.com/a"
        )
        _ = feed(
            tracker,
            rows: [entryRow(a)],
            bases: [basis(for: a)]
        )
        let set = feed(
            tracker,
            rows: [entryRow(a, sources: [source])],
            bases: [basis(for: a, sources: [source])]
        )
        XCTAssertEqual(
            set.updated, ["entry-\(a.id.uuidString)"]
        )
        XCTAssertEqual(tracker.shadowLedger.diffCount, 0)
    }

    // MARK: - ④ 开关缺省开（0.50.96 组版转正）

    func testIncrementalFeatureDefaultsOn() {
        let suite = UserDefaults(
            suiteName: "swap-step1-\(UUID().uuidString)"
        )!
        XCTAssertEqual(
            ChatListIncrementalFeature.defaultsKey,
            "chat.list.incremental"
        )
        XCTAssertTrue(
            ChatListIncrementalFeature.isEnabled(
                defaults: suite
            )
        )
        suite.set(
            false, forKey: ChatListIncrementalFeature.defaultsKey
        )
        XCTAssertFalse(
            ChatListIncrementalFeature.isEnabled(
                defaults: suite
            )
        )
        suite.set(
            true, forKey: ChatListIncrementalFeature.defaultsKey
        )
        XCTAssertTrue(
            ChatListIncrementalFeature.isEnabled(
                defaults: suite
            )
        )
    }
}
