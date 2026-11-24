import Foundation
import XCTest
@testable import OneDayCore

/// §452 文件呈现换代的 Core 钉测：紧凑大小文案
/// （微信式无空格）、大小排序档、最近在前默认档、
/// 资源库类别归片
final class FilePresentation452Tests: XCTestCase {

    private func entry(
        _ name: String, size: Int64? = nil,
        isDirectory: Bool = false, mime: String? = nil
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: "/opt/data/\(name)",
            isDirectory: isDirectory, size: size,
            mtime: nil, mimeType: mime
        )
    }

    // MARK: FileSizeText

    func testCompactSizeText() {
        XCTAssertEqual(FileSizeText.compact(0), "0B")
        XCTAssertEqual(FileSizeText.compact(178), "178B")
        XCTAssertEqual(FileSizeText.compact(1023), "1023B")
        XCTAssertEqual(FileSizeText.compact(1024), "1KB")
        XCTAssertEqual(FileSizeText.compact(328_704), "321KB")
        XCTAssertEqual(FileSizeText.compact(1536), "2KB")
        XCTAssertEqual(FileSizeText.compact(1_258_291), "1.2MB")
        XCTAssertEqual(FileSizeText.compact(1_048_576), "1MB")
        XCTAssertEqual(FileSizeText.compact(1_073_741_824), "1GB")
        XCTAssertEqual(FileSizeText.compact(2_684_354_560), "2.5GB")
    }

    // MARK: LibrarySort

    func testSizeSortDescendingUnknownLastPinnedFirst() {
        let small = entry("a.txt", size: 100)
        let big = entry("b.txt", size: 300)
        let unknown = entry("c.txt", size: nil)
        let sorted = LibraryOrdering.sorted(
            [small, big, unknown], by: .size,
            openedAt: [:], pinned: []
        )
        XCTAssertEqual(
            sorted.map(\.name), ["b.txt", "a.txt", "c.txt"]
        )
        let pinnedSorted = LibraryOrdering.sorted(
            [small, big, unknown], by: .size,
            openedAt: [:], pinned: [small.path]
        )
        XCTAssertEqual(pinnedSorted.first?.name, "a.txt")
    }

    func testSortResolvedDefaultsToLastModified() {
        XCTAssertEqual(LibrarySort.resolved(rawValue: nil), .lastModified)
        XCTAssertEqual(LibrarySort.resolved(rawValue: "bogus"), .lastModified)
        XCTAssertEqual(LibrarySort.resolved(rawValue: "size"), .size)
        XCTAssertEqual(
            LibrarySort.resolved(rawValue: "lastOpened"), .lastOpened
        )
    }

    // MARK: LibraryCategory

    func testCategoryBuckets() {
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.pdf")), .documents
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.md")), .documents
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.xlsx")), .documents
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.png")), .images
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.mp4")), .media
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.mp3")), .media
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.zip")), .other
        )
        XCTAssertEqual(
            LibraryCategory.bucket(for: entry("a.bin")), .other
        )
        XCTAssertEqual(
            LibraryCategory.bucket(
                for: entry("folder", isDirectory: true)
            ),
            .other
        )
    }

    func testCategoryIncludes() {
        XCTAssertTrue(
            LibraryCategory.all.includes(entry("a.zip"))
        )
        XCTAssertFalse(
            LibraryCategory.documents.includes(entry("a.png"))
        )
        XCTAssertTrue(
            LibraryCategory.media.includes(entry("a.m4a"))
        )
    }
}
