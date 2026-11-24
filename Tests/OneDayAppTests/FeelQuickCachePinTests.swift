import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// F1/F2 钉测（2026-11-23，手感快速项）：只守语义——
/// 键化排序与旧比较器逐位等价、快照缓存变更必失效、
/// 标题字典与旧线性扫描逐字等价。性能对账在
/// FeelQuickProbeTests（同口径探针）。
final class FeelQuickCachePinTests: XCTestCase {

    // MARK: - 夹具

    private func entry(
        _ name: String, path: String, mtime: Double?,
        mime: String? = nil
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: path, isDirectory: false,
            size: 100, mtime: mtime, mimeType: mime
        )
    }

    private func deliverable(
        _ name: String, path: String, mtime: Double?,
        source: String = "产出", mime: String? = nil
    ) -> Deliverable {
        Deliverable(
            entry: entry(name, path: path, mtime: mtime, mime: mime),
            source: source
        )
    }

    // MARK: - 排序等价（旧比较器原文作参照）

    /// F1 前 LibraryOrdering.sorted 的逐字复刻——键化
    /// 实现的输出必须与它逐位同（同入参、同顺序）
    private func referenceSorted(
        _ entries: [WorkspaceFileEntry],
        by sort: LibrarySort,
        openedAt: [String: TimeInterval],
        pinned: Set<String>
    ) -> [WorkspaceFileEntry] {
        entries.sorted { a, b in
            if !pinned.isEmpty {
                let ap = pinned.contains(a.path)
                let bp = pinned.contains(b.path)
                if ap != bp { return ap }
            }
            switch sort {
            case .lastOpened:
                let ao = openedAt[a.path] ?? 0
                let bo = openedAt[b.path] ?? 0
                if ao != bo { return ao > bo }
                let am = a.mtime ?? 0
                let bm = b.mtime ?? 0
                if am != bm { return am > bm }
            case .lastModified:
                let am = a.mtime ?? 0
                let bm = b.mtime ?? 0
                if am != bm { return am > bm }
            case .size:
                let aS = a.size ?? -1
                let bS = b.size ?? -1
                if aS != bS { return aS > bS }
            case .title:
                break
            }
            return DeliverableFileType.displayTitle(forFileName: a.name)
                .localizedStandardCompare(
                    DeliverableFileType.displayTitle(forFileName: b.name)
                ) == .orderedAscending
        }
    }

    private func assertSortEquivalence(
        _ entries: [WorkspaceFileEntry],
        openedAt: [String: TimeInterval],
        pinned: Set<String>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for sort in LibrarySort.allCases {
            let expected = referenceSorted(
                entries, by: sort, openedAt: openedAt, pinned: pinned
            ).map(\.path)
            let actual = LibraryOrdering.sorted(
                entries, by: sort, openedAt: openedAt, pinned: pinned
            ).map(\.path)
            XCTAssertEqual(
                actual, expected,
                "sort=\(sort.rawValue) 键化输出与旧比较器不一致",
                file: file, line: line
            )
        }
    }

    func testKeyedSortMatchesReferenceOnAuditFixture() {
        let stems = ["会议记录", "项目方案", "数据报表", "合同审阅",
                     "需求说明", "截图", "财务流水", "产品原型"]
        let exts = [".docx", ".pdf", ".xlsx", ".md", ".txt"]
        let entries = (0..<300).map { i in
            entry(
                "\(stems[i % stems.count])-\(i)\(exts[i % exts.count])",
                path: "/opt/data/\(i)",
                mtime: 1_700_000_000 - Double(i) * 137
            )
        }
        var opened: [String: TimeInterval] = [:]
        for (i, e) in entries.enumerated() where i % 3 == 0 {
            opened[e.path] = 1_700_000_000 - Double(i) * 61
        }
        assertSortEquivalence(entries, openedAt: opened, pinned: [])
        assertSortEquivalence(
            entries, openedAt: opened,
            pinned: [entries[5].path, entries[250].path]
        )
        assertSortEquivalence(entries, openedAt: [:], pinned: [])
    }

    func testKeyedSortMatchesReferenceOnEdgeNames() {
        // 数字后缀（numeric 口径）、大小写、同名不同
        // 路径、无扩展名、点文件、拉丁＋中文混排
        let names = [
            "文件2.docx", "文件10.docx", "文件1.docx",
            "Abc.pdf", "abc.pdf", "ABD.pdf",
            "报告.docx", "报告.docx", "README",
            ".env", "a.tar.gz", "Zebra.txt", "苹果.txt",
            "苹果2.txt", "苹果10.txt", "  空格.docx",
        ]
        let entries = names.enumerated().map { i, name in
            entry(name, path: "/edge/\(i)", mtime: Double(100 - i))
        }
        assertSortEquivalence(entries, openedAt: [:], pinned: [])
        assertSortEquivalence(
            entries,
            openedAt: ["/edge/3": 999],
            pinned: ["/edge/10"]
        )
    }

    // MARK: - 快照缓存失效矩阵

    private func baseItems() -> [Deliverable] {
        [
            deliverable("甲.docx", path: "/a", mtime: 300),
            deliverable("乙.docx", path: "/b", mtime: 200),
            deliverable("丙.docx", path: "/c", mtime: 100),
            deliverable(
                "视频.mp4", path: "/v", mtime: 400,
                source: "产出", mime: "video/mp4"
            ),
        ]
    }

    func testSnapshotCacheServesSameInputs() {
        let cache = LibrarySnapshotCache()
        let items = baseItems()
        let first = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        let second = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        XCTAssertEqual(
            second.sortedDocuments.map(\.path),
            first.sortedDocuments.map(\.path)
        )
        XCTAssertEqual(
            second.documents.map(\.entry.path),
            first.documents.map(\.entry.path)
        )
    }

    /// 缓存结果必须与同入参 make 直算逐项同——任一
    /// 入参变更后若还回上一份快照，此对账即红
    private func assertCacheMatchesMake(
        _ cache: LibrarySnapshotCache,
        deliverables: [Deliverable]?,
        query: String,
        sort: LibrarySort,
        openedAt: [String: TimeInterval],
        pinned: Set<String>,
        segment: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let viaCache = cache.snapshot(
            deliverables: deliverables, query: query, sort: sort,
            openedAt: openedAt, pinned: pinned, segment: segment
        )
        let direct = LibraryListSnapshot.make(
            deliverables: deliverables, query: query, sort: sort,
            openedAt: openedAt, pinned: pinned, segment: segment
        )
        XCTAssertEqual(
            viaCache.documents.map(\.entry.path),
            direct.documents.map(\.entry.path),
            file: file, line: line
        )
        XCTAssertEqual(
            viaCache.mediaItems.map(\.entry.path),
            direct.mediaItems.map(\.entry.path),
            file: file, line: line
        )
        XCTAssertEqual(
            viaCache.sortedDocuments.map(\.path),
            direct.sortedDocuments.map(\.path),
            file: file, line: line
        )
        XCTAssertEqual(
            viaCache.sortedMedia.map(\.path),
            direct.sortedMedia.map(\.path),
            file: file, line: line
        )
        XCTAssertEqual(
            viaCache.deliverableByPath.keys.sorted(),
            direct.deliverableByPath.keys.sorted(),
            file: file, line: line
        )
    }

    func testSnapshotCacheInvalidatesOnEveryInputChange() {
        let cache = LibrarySnapshotCache()
        var items = baseItems()
        assertCacheMatchesMake(
            cache, deliverables: items, query: "",
            sort: .lastOpened, openedAt: [:], pinned: [], segment: 0
        )
        // 名单变（改名）：快照须见新名、不许留旧名
        items[2] = deliverable("丁.docx", path: "/c", mtime: 100)
        assertCacheMatchesMake(
            cache, deliverables: items, query: "",
            sort: .title, openedAt: [:], pinned: [], segment: 0
        )
        let renamed = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        XCTAssertTrue(
            renamed.documents.contains { $0.entry.name == "丁.docx" }
        )
        XCTAssertFalse(
            renamed.documents.contains { $0.entry.name == "丙.docx" }
        )
        // 搜索词变：成员集须随之变
        let queried = cache.snapshot(
            deliverables: items, query: "乙", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        XCTAssertEqual(queried.documents.map(\.entry.path), ["/b"])
        assertCacheMatchesMake(
            cache, deliverables: items, query: "乙",
            sort: .title, openedAt: [:], pinned: [], segment: 0
        )
        // openedAt 变：上次打开序须把刚打开的顶到首位
        let opened = cache.snapshot(
            deliverables: items, query: "", sort: .lastOpened,
            openedAt: ["/c": 9_999], pinned: [], segment: 0
        )
        XCTAssertEqual(opened.sortedDocuments.first?.path, "/c")
        // pinned 变：置顶须整段在前
        let pinned = cache.snapshot(
            deliverables: items, query: "", sort: .lastOpened,
            openedAt: [:], pinned: ["/b"], segment: 0
        )
        XCTAssertEqual(pinned.sortedDocuments.first?.path, "/b")
        // 分段变：影音段出排序、文件段收起
        let media = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 1
        )
        XCTAssertTrue(media.sortedDocuments.isEmpty)
        XCTAssertEqual(media.sortedMedia.map(\.path), ["/v"])
        // 名单从无到有：nil 后喂真名单必须出真快照
        _ = cache.snapshot(
            deliverables: nil, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        assertCacheMatchesMake(
            cache, deliverables: items, query: "",
            sort: .title, openedAt: [:], pinned: [], segment: 0
        )
        let refilled = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        XCTAssertEqual(refilled.documents.count, 3)
    }

    // MARK: - 标题字典等价

    private func record(
        ledgerID: String, threadID: UUID?, title: String,
        index: Int
    ) -> SessionRecord {
        SessionRecord(
            ledgerID: ledgerID,
            localThreadID: threadID, serverSessionID: nil,
            origin: .mine, birthRule: "R0",
            title: title, archived: false,
            archiveSource: .local, isPendingDeletion: false,
            source: nil,
            activityAt: Date(
                timeIntervalSince1970: 1_700_000_000 - Double(index) * 60
            ),
            linkPhase: .linked, session: nil,
            segment: .none, segmentIndex: index, localIndex: index
        )
    }

    func testTitleDictionaryMatchesLinearScan() {
        let dupID = UUID()
        let records = [
            record(ledgerID: "l0", threadID: dupID, title: "首条", index: 0),
            record(ledgerID: "l1", threadID: UUID(), title: "乙", index: 1),
            record(ledgerID: "l2", threadID: dupID, title: "后来者", index: 2),
            record(ledgerID: "s0", threadID: nil, title: "服务端", index: 3),
        ]
        let dict = LedgerProjection.titleByLocalThreadID(records)
        // 逐行与旧线性扫描对账
        for record in records {
            guard let tid = record.localThreadID else { continue }
            XCTAssertEqual(
                dict[tid],
                records.first { $0.localThreadID == tid }?.title
            )
        }
        // 同 id 取首个；无本地线程不入字典
        XCTAssertEqual(dict[dupID], "首条")
        XCTAssertEqual(dict.count, 2)
    }

    func testTitleDictionaryReflectsTitleChange() {
        let tid = UUID()
        let before = [
            record(ledgerID: "l0", threadID: tid, title: "旧名", index: 0)
        ]
        XCTAssertEqual(
            LedgerProjection.titleByLocalThreadID(before)[tid], "旧名"
        )
        let after = [
            record(ledgerID: "l0", threadID: tid, title: "新名", index: 0)
        ]
        XCTAssertEqual(
            LedgerProjection.titleByLocalThreadID(after)[tid], "新名"
        )
        XCTAssertTrue(
            LedgerProjection.titleByLocalThreadID([]).isEmpty
        )
    }
}
