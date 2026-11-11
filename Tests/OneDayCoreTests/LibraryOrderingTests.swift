import Foundation
import XCTest
@testable import OneDayCore

/// 文件页 v2（0.36.31）资料库排序/分组/打开记录：三义
/// 排序（打开时刻缺失以 mtime 兜底）、7 天「最近」窗、
/// 分组单组回落、记录表序列化往返。条目按生产回执形
/// 状 JSON 解码构造（与 FileBrowserLogicTests 同法）。
final class LibraryOrderingTests: XCTestCase {
    private func entry(
        name: String, mtime: Double? = nil
    ) -> WorkspaceFileEntry {
        let mtimeJSON = mtime.map { "\($0)" } ?? "null"
        let json = """
        {"path": "/opt/data", "parent": null, "entries": [
            {"name": "\(name)", "path": "/opt/data/\(name)",
             "is_directory": false, "size": null,
             "mtime": \(mtimeJSON), "mime_type": null}
        ]}
        """
        let listing = try! JSONDecoder().decode(
            FilesListing.self, from: Data(json.utf8)
        )
        return listing.entries[0]
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: 排序

    func testSortByLastOpenedPrefersHistoryThenMtime() {
        let a = entry(name: "a.md", mtime: 100)
        let b = entry(name: "b.md", mtime: 300)
        let c = entry(name: "c.md", mtime: 200)
        // b 被最近打开 → 居首；a/c 无记录以 mtime 倒序兜底
        let sorted = LibraryOrdering.sorted(
            [a, b, c], by: .lastOpened,
            openedAt: [b.path: 500]
        )
        XCTAssertEqual(sorted.map(\.name), ["b.md", "c.md", "a.md"])
    }

    func testSortByLastModifiedIgnoresHistory() {
        let a = entry(name: "a.md", mtime: 100)
        let b = entry(name: "b.md", mtime: 300)
        let sorted = LibraryOrdering.sorted(
            [a, b], by: .lastModified,
            openedAt: [a.path: 999]
        )
        XCTAssertEqual(sorted.map(\.name), ["b.md", "a.md"])
    }

    func testSortByTitleUsesDisplayTitle() {
        let sorted = LibraryOrdering.sorted(
            [entry(name: "报告.docx"), entry(name: "alpha.pdf")],
            by: .title, openedAt: [:]
        )
        XCTAssertEqual(
            sorted.map(\.name), ["alpha.pdf", "报告.docx"]
        )
    }

    // MARK: 最近判定与分组

    func testIsRecentByOpenedOrModified() {
        let openedOld = entry(
            name: "old.md", mtime: 1_700_000_000 - 700_000
        )
        XCTAssertTrue(
            LibraryOrdering.isRecent(
                entry: openedOld,
                openedAt: [openedOld.path: 1_700_000_000 - 60],
                now: now
            )
        )
        let freshFile = entry(
            name: "fresh.md", mtime: 1_700_000_000 - 60
        )
        XCTAssertTrue(
            LibraryOrdering.isRecent(
                entry: freshFile, openedAt: [:], now: now
            )
        )
        let stale = entry(
            name: "stale.md", mtime: 1_700_000_000 - 700_000
        )
        XCTAssertFalse(
            LibraryOrdering.isRecent(
                entry: stale, openedAt: [:], now: now
            )
        )
    }

    func testGroupedSplitsRecentAndRest() {
        let fresh = entry(
            name: "fresh.md", mtime: 1_700_000_000 - 60
        )
        let stale = entry(
            name: "stale.md", mtime: 1_700_000_000 - 700_000
        )
        let sections = LibraryOrdering.grouped(
            [fresh, stale], openedAt: [:], now: now
        )
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "最近")
        XCTAssertEqual(sections[0].entries.map(\.name), ["fresh.md"])
        XCTAssertEqual(sections[1].title, "全部")
        XCTAssertEqual(sections[1].entries.map(\.name), ["stale.md"])
    }

    func testGroupedAllRecentFallsBackToSingleSection() {
        let fresh = entry(
            name: "fresh.md", mtime: 1_700_000_000 - 60
        )
        let sections = LibraryOrdering.grouped(
            [fresh], openedAt: [:], now: now
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
    }

    func testGroupedNoneRecentFallsBackToSingleSection() {
        let stale = entry(
            name: "stale.md", mtime: 1_700_000_000 - 700_000
        )
        let sections = LibraryOrdering.grouped(
            [stale], openedAt: [:], now: now
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
    }

    // MARK: 置顶（§127）

    func testSortedPinnedFirstWithinSortOrder() {
        let a = entry(name: "a.md", mtime: 100)
        let b = entry(name: "b.md", mtime: 300)
        let c = entry(name: "c.md", mtime: 200)
        // c 置顶 → 居首；余者仍按上次打开/mtime 序
        let sorted = LibraryOrdering.sorted(
            [a, b, c], by: .lastOpened,
            openedAt: [b.path: 500], pinned: [c.path]
        )
        XCTAssertEqual(sorted.map(\.name), ["c.md", "b.md", "a.md"])
    }

    func testSortedEmptyPinnedKeepsLegacyOrder() {
        let a = entry(name: "a.md", mtime: 100)
        let b = entry(name: "b.md", mtime: 300)
        let sorted = LibraryOrdering.sorted(
            [a, b], by: .lastOpened, openedAt: [:], pinned: []
        )
        XCTAssertEqual(sorted.map(\.name), ["b.md", "a.md"])
    }

    func testGroupedPinnedSectionLeads() {
        let pinnedOld = entry(
            name: "pin.md", mtime: 1_700_000_000 - 700_000
        )
        let fresh = entry(
            name: "fresh.md", mtime: 1_700_000_000 - 60
        )
        let stale = entry(
            name: "stale.md", mtime: 1_700_000_000 - 700_000
        )
        let ordered = LibraryOrdering.sorted(
            [stale, fresh, pinnedOld], by: .lastModified,
            openedAt: [:], pinned: [pinnedOld.path]
        )
        let sections = LibraryOrdering.grouped(
            ordered, openedAt: [:], now: now, pinned: [pinnedOld.path]
        )
        XCTAssertEqual(sections.map(\.title), ["置顶", "最近", "全部"])
        XCTAssertEqual(sections[0].entries.map(\.name), ["pin.md"])
        XCTAssertEqual(sections[1].entries.map(\.name), ["fresh.md"])
        XCTAssertEqual(sections[2].entries.map(\.name), ["stale.md"])
    }

    func testGroupedAllPinnedSinglePinnedSection() {
        let fresh = entry(
            name: "fresh.md", mtime: 1_700_000_000 - 60
        )
        let sections = LibraryOrdering.grouped(
            [fresh], openedAt: [:], now: now, pinned: [fresh.path]
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "置顶")
    }

    // MARK: 打开记录表

    func testOpenHistoryRecordAndSerializeRoundtrip() {
        var history = FileOpenHistory()
        history.record(path: "/opt/data/a.md", at: now)
        XCTAssertEqual(
            history.lastOpened(path: "/opt/data/a.md"), now
        )
        let restored = FileOpenHistory.deserialize(
            history.serialized()
        )
        XCTAssertEqual(restored, history)
    }

    func testOpenHistoryDeserializeGarbageFallsBackEmpty() {
        XCTAssertEqual(
            FileOpenHistory.deserialize(Data("junk".utf8)),
            FileOpenHistory()
        )
        XCTAssertEqual(
            FileOpenHistory.deserialize(nil), FileOpenHistory()
        )
    }
}
