import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// 手感快速项 F1/F2 探针（2026-11-23，feel-f1f2-quick）：
/// 修前/修后同口径对账专用——基线复刻沿审计探针口径
/// （热身 1 次＋5 次取最小、ContinuousClock、FEELPROBE
/// 前缀打印 µs）；分解探针为 test-local 实现，只量测、
/// 不代表生产落点。
final class FeelQuickProbeTests: XCTestCase {

    private func timeMinUs(
        warmup: Int = 1, reps: Int = 5,
        _ body: () -> Void
    ) -> Double {
        for _ in 0..<warmup { body() }
        var best = Double.greatestFiniteMagnitude
        let clock = ContinuousClock()
        for _ in 0..<reps {
            let start = clock.now
            body()
            let elapsed = start.duration(to: clock.now)
            let us = Double(elapsed.components.seconds) * 1_000_000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000
            best = min(best, us)
        }
        return best
    }

    private func report(_ name: String, _ us: Double) {
        print(String(format: "FEELPROBE %@ %.0f us", name, us))
    }

    // MARK: - 资源库夹具（与审计探针逐字同）

    private func docEntry(
        _ name: String, path: String, mtime: Double?,
        mime: String? = nil
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: path, isDirectory: false,
            size: 100, mtime: mtime, mimeType: mime
        )
    }

    private func docFixture(_ n: Int) -> [Deliverable] {
        let stems = ["会议记录", "项目方案", "数据报表", "合同审阅",
                     "需求说明", "截图", "财务流水", "产品原型"]
        let exts = [".docx", ".pdf", ".xlsx", ".md", ".txt"]
        return (0..<n).map { i in
            let name = "\(stems[i % stems.count])-\(i)\(exts[i % exts.count])"
            return Deliverable(
                entry: docEntry(
                    name, path: "/opt/data/\(i)/\(name)",
                    mtime: 1_700_000_000 - Double(i) * 137
                ),
                source: "产出"
            )
        }
    }

    // MARK: - F1 基线复刻（审计口径）

    func testProbeSnapshotTitle2000() {
        let items = docFixture(2000)
        let us = timeMinUs {
            _ = LibraryListSnapshot.make(
                deliverables: items, query: "", sort: .title,
                openedAt: [:], pinned: [], segment: 0
            )
        }
        report("snapshot_make_title_2000", us)
    }

    func testProbeSnapshotLastOpenedDistinct2000() {
        let items = docFixture(2000)
        var opened: [String: TimeInterval] = [:]
        for (i, item) in items.enumerated() {
            opened[item.entry.path] = 1_700_000_000 - Double(i) * 61
        }
        let us = timeMinUs {
            _ = LibraryListSnapshot.make(
                deliverables: items, query: "", sort: .lastOpened,
                openedAt: opened, pinned: [], segment: 0
            )
        }
        report("snapshot_make_lastOpened_distinct_2000", us)
    }

    func testProbeSnapshotSearch2000() {
        let items = docFixture(2000)
        var opened: [String: TimeInterval] = [:]
        for (i, item) in items.enumerated() {
            opened[item.entry.path] = 1_700_000_000 - Double(i) * 61
        }
        let us = timeMinUs {
            _ = LibraryListSnapshot.make(
                deliverables: items, query: "方案", sort: .lastOpened,
                openedAt: opened, pinned: [], segment: 0
            )
        }
        report("snapshot_make_search_2000", us)
    }

    func testProbeSortOnlyTitle2000() {
        let entries = docFixture(2000).map(\.entry)
        let us = timeMinUs {
            _ = LibraryOrdering.sorted(
                entries, by: .title, openedAt: [:], pinned: []
            )
        }
        report("sort_only_title_2000", us)
    }

    // MARK: - F1 排序分解（test-local）

    /// 键预计算版：displayTitle 每条目算一次入账，
    /// 比较器只读预计算标题走 localizedStandardCompare
    func testProbeSortPrecomputedTitles2000() {
        let entries = docFixture(2000).map(\.entry)
        let us = timeMinUs {
            let decorated = entries.map { entry in
                (entry: entry, title: DeliverableFileType
                    .displayTitle(forFileName: entry.name))
            }
            _ = decorated.sorted { a, b in
                a.title.localizedStandardCompare(b.title)
                    == .orderedAscending
            }
        }
        report("sort_precomputed_titles_2000", us)
    }

    /// 纯 collation 隔离：标题数组单独走
    /// localizedStandardCompare 全序
    func testProbeSortTitlesOnlyCollation2000() {
        let titles = docFixture(2000).map {
            DeliverableFileType.displayTitle(forFileName: $0.entry.name)
        }
        let us = timeMinUs {
            _ = titles.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
        report("sort_titles_only_collation_2000", us)
    }

    /// displayTitle 批量隔离：2000 条各算一次
    func testProbeDisplayTitleBuild2000() {
        let names = docFixture(2000).map(\.entry.name)
        var sink = 0
        let us = timeMinUs {
            for name in names {
                sink += DeliverableFileType
                    .displayTitle(forFileName: name).count
            }
        }
        XCTAssertGreaterThan(sink, 0)
        report("displayTitle_build_2000", us)
    }

    // MARK: - 抽屉夹具（与审计探针逐字同）

    private func recordFixture(
        locals: Int, unadopted: Int
    ) -> [SessionRecord] {
        var records: [SessionRecord] = []
        for i in 0..<locals {
            let uuid = UUID()
            records.append(SessionRecord(
                ledgerID: "local:\(uuid.uuidString)",
                localThreadID: uuid, serverSessionID: nil,
                origin: .mine, birthRule: "R0",
                title: "会话-\(i)", archived: false,
                archiveSource: .local, isPendingDeletion: false,
                source: nil,
                activityAt: Date(
                    timeIntervalSince1970: 1_700_000_000 - Double(i) * 60
                ),
                linkPhase: .linked, session: nil,
                segment: .none, segmentIndex: i, localIndex: i
            ))
        }
        for i in 0..<unadopted {
            records.append(SessionRecord(
                ledgerID: "server:s\(i)",
                localThreadID: nil, serverSessionID: "s\(i)",
                origin: .mine, birthRule: "R2",
                title: "服务端会话-\(i)", archived: false,
                archiveSource: .server, isPendingDeletion: false,
                source: "hermes",
                activityAt: Date(
                    timeIntervalSince1970: 1_700_000_000 - Double(i) * 90
                ),
                linkPhase: .unlinked, session: nil,
                segment: .visible, segmentIndex: i, localIndex: nil
            ))
        }
        return records
    }

    // MARK: - F2 基线复刻（审计口径）

    func testProbeDrawerPass500() {
        let records = recordFixture(locals: 350, unadopted: 150)
        let us = timeMinUs {
            let rows = LedgerProjection.drawerSideRows(records)
            var sink = 0
            for row in rows {
                if let tid = row.localThreadID {
                    sink += records.first {
                        $0.localThreadID == tid
                    }?.title.count ?? 0
                }
            }
            XCTAssertGreaterThan(sink, 0)
        }
        report("drawer_projection_titlescan_500", us)
    }

    func testProbeDrawerProjectionOnly500() {
        let records = recordFixture(locals: 350, unadopted: 150)
        let us = timeMinUs {
            _ = LedgerProjection.drawerSideRows(records)
        }
        report("drawer_projection_only_500", us)
    }

    /// 字典化预演（test-local 复刻目标形态）：投影＋
    /// 一趟建字典（首个命中优先、与 first(where:) 同
    /// 义）＋逐行 O(1) 查
    func testProbeDrawerPassDictLocal500() {
        let records = recordFixture(locals: 350, unadopted: 150)
        let us = timeMinUs {
            let rows = LedgerProjection.drawerSideRows(records)
            var titles: [UUID: String] = [:]
            titles.reserveCapacity(records.count)
            for record in records {
                if let tid = record.localThreadID,
                   titles[tid] == nil {
                    titles[tid] = record.title
                }
            }
            var sink = 0
            for row in rows {
                if let tid = row.localThreadID {
                    sink += titles[tid]?.count ?? 0
                }
            }
            XCTAssertGreaterThan(sink, 0)
        }
        report("drawer_projection_titledict_local_500", us)
    }
}

// MARK: - 修后路径（生产 API，同口径对账）

extension FeelQuickProbeTests {

    /// F1 修后：快照缓存命中趟——同入参重复调用只付
    /// 指纹逐值比对，不重算过滤/排序
    func testProbeSnapshotCacheHitTitle2000() {
        let items = docFixture(2000)
        let cache = LibrarySnapshotCache()
        _ = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        let us = timeMinUs {
            _ = cache.snapshot(
                deliverables: items, query: "", sort: .title,
                openedAt: [:], pinned: [], segment: 0
            )
        }
        report("snapshot_cache_hit_title_2000", us)
    }

    /// F1 修后对照：缓存未命中趟（openedAt 交替变更、
    /// 每趟整趟重算标题序）——验缓存层自身开销可忽略
    func testProbeSnapshotCacheMissTitle2000() {
        let items = docFixture(2000)
        var openedA: [String: TimeInterval] = [:]
        var openedB: [String: TimeInterval] = [:]
        for (i, item) in items.enumerated() {
            openedA[item.entry.path] = 1_700_000_000 - Double(i) * 61
            openedB[item.entry.path] = 1_700_000_000 - Double(i) * 67
        }
        let cache = LibrarySnapshotCache()
        var flip = false
        let us = timeMinUs {
            flip.toggle()
            _ = cache.snapshot(
                deliverables: items, query: "", sort: .title,
                openedAt: flip ? openedA : openedB,
                pinned: [], segment: 0
            )
        }
        report("snapshot_cache_miss_title_2000", us)
    }

    /// F2 修后：投影＋生产标题字典一趟建成＋逐行
    /// O(1) 查（与基线 titlescan 同口径对账）
    func testProbeDrawerPassDictProd500() {
        let records = recordFixture(locals: 350, unadopted: 150)
        let us = timeMinUs {
            let rows = LedgerProjection.drawerSideRows(records)
            let titles = LedgerProjection.titleByLocalThreadID(records)
            var sink = 0
            for row in rows {
                if let tid = row.localThreadID {
                    sink += titles[tid]?.count ?? 0
                }
            }
            XCTAssertGreaterThan(sink, 0)
        }
        report("drawer_projection_titledict_prod_500", us)
    }
}

extension FeelQuickProbeTests {

    /// F1 修后补充：缓存命中但入参是等值新数组（服
    /// 务端重拉回同内容、新缓冲）——指纹逐项比对的
    /// 真实成本（非同缓冲恒等快路）
    func testProbeSnapshotCacheHitCopiedTitle2000() {
        let items = docFixture(2000)
        let cache = LibrarySnapshotCache()
        _ = cache.snapshot(
            deliverables: items, query: "", sort: .title,
            openedAt: [:], pinned: [], segment: 0
        )
        let us = timeMinUs {
            _ = cache.snapshot(
                deliverables: items.map { $0 }, query: "",
                sort: .title,
                openedAt: [:], pinned: [], segment: 0
            )
        }
        report("snapshot_cache_hit_copied_title_2000", us)
    }
}
