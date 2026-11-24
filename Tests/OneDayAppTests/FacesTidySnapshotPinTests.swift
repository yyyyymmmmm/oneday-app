import OneDayCore
import XCTest
@testable import OneDayApp

/// 四面收口钉测（§415）：三面派生快照在大数据量
/// 下「同入参反复取不重算、任一入参变才重算」——
/// 以快照修订号断言（呈现侧 body 求值零重付的接
/// 缝钉法，与 FeelQuickCachePinTests 的缓存等价
/// 对账互补：那边钉「缓存结果＝直算」，这边钉
/// 「不重算」本身）
@MainActor
final class FacesTidySnapshotPinTests: XCTestCase {

    // MARK: - 文件面（FilesBrowserSnapshotCache）

    private func fileEntry(
        _ index: Int, image: Bool = false
    ) -> WorkspaceFileEntry {
        let name = image ? "图\(index).png" : "文件\(index).txt"
        return WorkspaceFileEntry(
            name: name,
            path: "/d/\(name)",
            isDirectory: false,
            size: Int64(index * 10),
            mtime: Double(index),
            mimeType: image ? "image/png" : "text/plain"
        )
    }

    func testFilesSnapshotRecomputesOnlyOnInputChange() {
        let cache = FilesBrowserSnapshotCache()
        // 大目录：3,000 条（每 10 条一张图）
        let entries = (0..<3000).map {
            fileEntry($0, image: $0 % 10 == 0)
        }
        let first = cache.snapshot(
            entries: entries, query: "",
            sortKey: .name, ascending: true
        )
        XCTAssertEqual(cache.revision, 1)
        // 与旧 shownEntries 直算逐项同（先过滤后排序）
        XCTAssertEqual(
            first.entries,
            FileBrowserLogic.sorted(
                FileBrowserLogic.filtered(entries, query: ""),
                by: .name, ascending: true
            )
        )
        XCTAssertEqual(first.imageEntries.count, 300)
        XCTAssertEqual(first.paths, first.entries.map(\.path))
        // 同入参反复取（body 重跑的钉法）：零重算
        for _ in 0..<8 {
            _ = cache.snapshot(
                entries: entries, query: "",
                sortKey: .name, ascending: true
            )
        }
        XCTAssertEqual(cache.revision, 1)
        // 搜索词变 → 重算，且与直算同果
        let queried = cache.snapshot(
            entries: entries, query: "文件29",
            sortKey: .name, ascending: true
        )
        XCTAssertEqual(cache.revision, 2)
        XCTAssertEqual(
            queried.entries,
            FileBrowserLogic.sorted(
                FileBrowserLogic.filtered(
                    entries, query: "文件29"
                ),
                by: .name, ascending: true
            )
        )
        // 排序键变 → 重算
        _ = cache.snapshot(
            entries: entries, query: "文件29",
            sortKey: .size, ascending: true
        )
        XCTAssertEqual(cache.revision, 3)
        // 方向变 → 重算
        _ = cache.snapshot(
            entries: entries, query: "文件29",
            sortKey: .size, ascending: false
        )
        XCTAssertEqual(cache.revision, 4)
        // 名单变 → 重算
        _ = cache.snapshot(
            entries: entries + [fileEntry(3000)], query: "文件29",
            sortKey: .size, ascending: false
        )
        XCTAssertEqual(cache.revision, 5)
        // 未加载（nil）与空目录分开记：各算一次、
        // 之后命中
        _ = cache.snapshot(
            entries: nil, query: "",
            sortKey: .name, ascending: true
        )
        XCTAssertEqual(cache.revision, 6)
        _ = cache.snapshot(
            entries: [], query: "",
            sortKey: .name, ascending: true
        )
        XCTAssertEqual(cache.revision, 7)
        _ = cache.snapshot(
            entries: [], query: "",
            sortKey: .name, ascending: true
        )
        XCTAssertEqual(cache.revision, 7)
    }

    // MARK: - 动态面（FeedSnapshotCache）

    private func feedPost(_ index: Int) -> BridgeFeedPost {
        BridgeFeedPost(
            id: "p\(index)", kind: .research,
            title: "帖\(index)", body: "正文\(index)",
            createdAt: Double(index), readAt: nil, likedAt: nil
        )
    }

    func testFeedSnapshotRecomputesOnlyOnInputChange() {
        let cache = FeedSnapshotCache()
        // 多帖：600 条；入参序故意非时间序（§459：
        // 服务端序即呈现序——轮转一段后入参，快照
        // 必须原样保序，旧时间重排口径下此断言必红）
        let base = (0..<600).map { feedPost($0) }
        let posts = Array(base[300...]) + Array(base[..<300])
        let first = cache.snapshot(
            posts: posts, searchText: "", isSearching: false
        )
        XCTAssertEqual(cache.revision, 1)
        XCTAssertEqual(
            first.visiblePosts.map(\.id),
            posts.map(\.id)
        )
        // 同入参反复取：零重算
        for _ in 0..<8 {
            _ = cache.snapshot(
                posts: posts, searchText: "", isSearching: false
            )
        }
        XCTAssertEqual(cache.revision, 1)
        // 搜索态变（词仍空、过滤不生效）→ 指纹含搜
        // 索态，重算一次且与直算同果
        let searching = cache.snapshot(
            posts: posts, searchText: "", isSearching: true
        )
        XCTAssertEqual(cache.revision, 2)
        XCTAssertEqual(
            searching.visiblePosts.map(\.id),
            posts.map(\.id)
        )
        // 搜索词变 → 重算，过滤与旧谓词同（标题或
        // 正文命中即留）、过滤只删不挪（保序）
        let queried = cache.snapshot(
            posts: posts, searchText: "帖42", isSearching: true
        )
        XCTAssertEqual(cache.revision, 3)
        let expected = posts.filter {
            $0.title.localizedCaseInsensitiveContains("帖42")
                || $0.body.localizedCaseInsensitiveContains("帖42")
        }
        XCTAssertEqual(
            queried.visiblePosts.map(\.id), expected.map(\.id)
        )
        // 名单变 → 重算
        _ = cache.snapshot(
            posts: posts + [feedPost(600)],
            searchText: "帖42", isSearching: true
        )
        XCTAssertEqual(cache.revision, 4)
    }

    // MARK: - 点子面（IdeasStore 存储快照）

    func testIdeasDomainSectionsStoredSnapshotRevision() {
        let store = IdeasStore()
        let now = Date().timeIntervalSince1970
        let categories = [
            "health", "relationships", "finance", "career",
            "interest", "efficiency", "other",
        ]
        // 多卡：1,500 条待阅、七类轮转（全待阅＝30
        // 天窗不介入，与直算对账无时刻边界风险）
        let ideas = (0..<1500).map { i in
            BridgeIdea(
                id: "i\(i)", title: "点子\(i)", detail: "",
                goalId: nil, createdAt: now - Double(i % 500),
                status: .pending,
                category: categories[i % categories.count]
            )
        }
        store.installLoadedIdeas(ideas)
        XCTAssertEqual(store.domainSectionsRevision, 1)
        // 存储快照与 Core 直算逐项同
        XCTAssertEqual(
            store.domainSections,
            IdeaBoard.domainSections(
                ideas, now: Date().timeIntervalSince1970
            )
        )
        XCTAssertEqual(
            store.domainSections.flatMap(\.ideas).count, 1500
        )
        // 呈现侧反复读（含 hasVisibleIdeas 的二次访
        // 问）：零重算
        for _ in 0..<8 {
            _ = store.domainSections
            _ = store.hasVisibleIdeas
        }
        XCTAssertEqual(store.domainSectionsRevision, 1)
        // 乐观离场（数据变更漏斗）→ 重算
        let removed = store.applyOptimisticDismiss(ideaID: "i0")
        XCTAssertNotNil(removed)
        XCTAssertEqual(store.domainSectionsRevision, 2)
        XCTAssertEqual(
            store.domainSections.flatMap(\.ideas).count, 1499
        )
        // 失败恢复（数据变更漏斗）→ 再重算
        store.restoreDismissed(removed!)
        XCTAssertEqual(store.domainSectionsRevision, 3)
        XCTAssertEqual(
            store.domainSections.flatMap(\.ideas).count, 1500
        )
        // 恢复幂等：已在名单不重复插＝数据未变、不
        // 重算
        store.restoreDismissed(removed!)
        XCTAssertEqual(store.domainSectionsRevision, 3)
    }
}
