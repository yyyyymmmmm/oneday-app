import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// §363（流畅度 S4）资源库派生快照钉测：
/// ①等价——快照（过滤/排序/字典）与 S4 前视图层旧口径
///   （本文件 old* 复刻：计算属性过滤＋LibraryOrdering
///   排序＋first(where:) 线性查）在排序×搜索×置顶×打开
///   记录全矩阵下逐值相等，排序结果一字不变；
/// ②成本——旧每趟口径（整表排序×3＋每行线性查）与新
///   口径（排序×1＋字典直达）在 N=2000 的实测对账；
/// ③结构——两列表面已懒化、线性扫描已退役（源码钉测）。
final class LibraryListSnapshotTests: XCTestCase {

    // MARK: - 构造

    private func entry(
        _ name: String, mtime: Double? = nil
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: "/opt/data/\(name)",
            isDirectory: false, size: 100, mtime: mtime,
            mimeType: nil
        )
    }

    private func item(
        _ name: String, mtime: Double? = nil, source: String = "产出"
    ) -> Deliverable {
        Deliverable(entry: entry(name, mtime: mtime), source: source)
    }

    private var fixture: [Deliverable] {
        [
            item("报告甲.md", mtime: 300),
            item("报告乙.pdf", mtime: 200),
            item("notes.txt", mtime: 100),
            item("方案.pptx", mtime: 400),
            item("data.json", mtime: nil),
            item("IMG_0001.png", mtime: 500),
            item("IMG_0002.jpg", mtime: 50),
            item("clip.mp4", mtime: 600),
            item("song.mp3", mtime: 150),
            item("截图甲.png", mtime: 350),
        ]
    }

    // MARK: - 旧口径复刻（S4 前 DeliverablesView 派生组）

    private func oldFiltered(
        _ all: [Deliverable], media: Bool, query: String
    ) -> [Deliverable] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return all.filter { item in
            (media
                ? item.entry.mediaKind != nil
                : item.entry.mediaKind == nil)
                && (trimmed.isEmpty
                    || item.entry.name
                        .localizedCaseInsensitiveContains(trimmed))
        }
    }

    private func oldSorted(
        _ all: [Deliverable], media: Bool, query: String,
        sort: LibrarySort,
        openedAt: [String: TimeInterval], pinned: Set<String>
    ) -> [WorkspaceFileEntry] {
        LibraryOrdering.sorted(
            oldFiltered(all, media: media, query: query).map(\.entry),
            by: sort, openedAt: openedAt, pinned: pinned
        )
    }

    private func oldDeliverable(
        for entry: WorkspaceFileEntry, in all: [Deliverable]
    ) -> Deliverable {
        all.first(where: { $0.entry.path == entry.path })
            ?? Deliverable(entry: entry, source: "")
    }

    // MARK: - ① 等价矩阵

    func testSnapshotMatchesLegacyDerivationAcrossMatrix() {
        let all = fixture
        let sorts: [LibrarySort] = [.lastOpened, .lastModified, .title]
        let queries = ["", "报告", "IMG", "甲", " 报告 "]
        let pinnedSets: [Set<String>] = [
            [], ["/opt/data/方案.pptx", "/opt/data/clip.mp4"],
        ]
        let openedSets: [[String: TimeInterval]] = [
            [:],
            ["/opt/data/报告甲.md": 1000, "/opt/data/IMG_0001.png": 900],
        ]
        for sort in sorts {
            for query in queries {
                for pinned in pinnedSets {
                    for openedAt in openedSets {
                        let ctx = "sort=\(sort) q=\(query) "
                            + "pin=\(pinned.count) open=\(openedAt.count)"
                        let snap0 = LibraryListSnapshot.make(
                            deliverables: all, query: query, sort: sort,
                            openedAt: openedAt, pinned: pinned,
                            segment: 0
                        )
                        XCTAssertEqual(
                            snap0.sortedDocuments,
                            oldSorted(
                                all, media: false, query: query,
                                sort: sort, openedAt: openedAt,
                                pinned: pinned
                            ), ctx
                        )
                        XCTAssertEqual(
                            snap0.documents.map(\.entry.path),
                            oldFiltered(
                                all, media: false, query: query
                            ).map(\.entry.path), ctx
                        )
                        XCTAssertEqual(snap0.sortedMedia, [], ctx)

                        let snap1 = LibraryListSnapshot.make(
                            deliverables: all, query: query, sort: sort,
                            openedAt: openedAt, pinned: pinned,
                            segment: 1
                        )
                        XCTAssertEqual(
                            snap1.sortedMedia,
                            oldSorted(
                                all, media: true, query: query,
                                sort: sort, openedAt: openedAt,
                                pinned: pinned
                            ), ctx
                        )
                        XCTAssertEqual(
                            snap1.mediaItems.map(\.entry.path),
                            oldFiltered(
                                all, media: true, query: query
                            ).map(\.entry.path), ctx
                        )
                        XCTAssertEqual(snap1.sortedDocuments, [], ctx)
                    }
                }
            }
        }
    }

    func testSnapshotHandlesNilDeliverables() {
        let snap = LibraryListSnapshot.make(
            deliverables: nil, query: "", sort: .lastOpened,
            openedAt: [:], pinned: [], segment: 0
        )
        XCTAssertTrue(snap.documents.isEmpty)
        XCTAssertTrue(snap.mediaItems.isEmpty)
        XCTAssertTrue(snap.sortedDocuments.isEmpty)
        XCTAssertTrue(snap.deliverableByPath.isEmpty)
    }

    // MARK: - ① 查找等价（首命中/缺失兜底）

    func testDeliverableLookupMatchesLegacyFirstHit() {
        var all = fixture
        // 同路径第二条（异源）：旧线性查取首个，字典须同义
        all.append(item("报告甲.md", mtime: 300, source: "重复源"))
        let snap = LibraryListSnapshot.make(
            deliverables: all, query: "", sort: .lastOpened,
            openedAt: [:], pinned: [], segment: 0
        )
        for probe in all {
            let got = snap.deliverable(for: probe.entry)
            let want = oldDeliverable(for: probe.entry, in: all)
            XCTAssertEqual(got.entry.path, want.entry.path)
            XCTAssertEqual(got.source, want.source)
        }
        // 缺失路径：回落兜底（source 空、条目原样）
        let ghost = entry("ghost.md", mtime: 1)
        let fallback = snap.deliverable(for: ghost)
        XCTAssertEqual(fallback.entry.path, ghost.path)
        XCTAssertEqual(fallback.source, "")
    }

    // MARK: - ② 成本对账（N=2000，模拟器相对值）

    func testPrepCostNewVsOld() {
        let n = 2000
        var all: [Deliverable] = []
        all.reserveCapacity(n)
        for i in 0..<n {
            let name = i % 2 == 0
                ? String(format: "IMG_%04d.png", i)
                : "doc_\(i).md"
            all.append(
                item(name, mtime: Double((i * 7919) % 100_000))
            )
        }

        func oldPass() -> Int {
            var acc = 0
            // 旧每趟：rotor＋内容＋列表共 3 次整表排序
            for _ in 0..<3 {
                acc += oldSorted(
                    all, media: false, query: "",
                    sort: .lastOpened, openedAt: [:], pinned: []
                ).count
            }
            // 旧每行：deliverable(for:) 线性扫描
            for d in all where d.entry.mediaKind == nil {
                acc += oldDeliverable(for: d.entry, in: all)
                    .source.count
            }
            return acc
        }

        func newPass() -> Int {
            let snap = LibraryListSnapshot.make(
                deliverables: all, query: "", sort: .lastOpened,
                openedAt: [:], pinned: [], segment: 0
            )
            var acc = snap.sortedDocuments.count
            for d in snap.documents {
                acc += snap.deliverable(for: d.entry).source.count
            }
            return acc
        }

        func bestMs(_ body: () -> Int) -> Double {
            var best = Double.greatestFiniteMagnitude
            for _ in 0..<3 {
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = body()
                best = min(best, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
            }
            return best
        }

        let oldMs = bestMs(oldPass)
        let newMs = bestMs(newPass)
        print(
            "S4-COST N=\(n) oldPassMs=\(String(format: "%.2f", oldMs)) "
                + "newPassMs=\(String(format: "%.2f", newMs)) "
                + "ratio=\(String(format: "%.1f", oldMs / newMs))x"
        )
        XCTAssertLessThan(newMs, oldMs * 0.6)
    }

    // MARK: - ③ 结构钉测

    func testListFacesLazyAndLinearScanRetired() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/OneDayApp/DeliverablesView.swift"
            )
        let src = try String(contentsOf: srcURL, encoding: .utf8)
        XCTAssertEqual(
            src.components(separatedBy: "LazyVStack(spacing: 0)")
                .count - 1,
            1, "§452.7③ 定版单列表：本面只应一处 LazyVStack"
        )
        XCTAssertFalse(
            src.contains("deliverables?.first(where:"),
            "deliverable(for:) 线性扫描应已退役"
        )
        XCTAssertFalse(
            src.contains("private var sortedDocuments"),
            "sortedDocuments 计算属性应已退役"
        )
        // §363 滑动死钉测（用户真机 2×2 矩阵定案）：带
        // DragGesture(minimumDistance: 0) 的按压修饰与点按
        // 手势行面不许回到本面——行/卡一律原生 Button
        // （.odPressable），那是本仓 ScrollView 里唯一与
        // 滚动共存的点按形态（目标面/本面影音网格同式）
        XCTAssertFalse(
            src.contains(".odPressFeedback()"),
            "§363：DragGesture(0) 按压修饰曾杀死本面滚动"
        )
        XCTAssertFalse(
            src.contains(".onTapGesture"),
            "§363：本面行/卡应为原生 Button、无点按手势"
        )
    }
}
