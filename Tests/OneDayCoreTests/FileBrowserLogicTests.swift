import Foundation
import XCTest
@testable import OneDayCore

/// P8（0.14.0）文件浏览纯逻辑测试：排序/过滤/面包屑/
/// 路径拼装/文件夹名校验/MIME 推断/data URL/上传上限/
/// 图标盒轮换。条目按生产回执形状 JSON 解码构造。
final class FileBrowserLogicTests: XCTestCase {
    private func entry(
        name: String, isDirectory: Bool = false,
        size: Int64? = nil, mtime: Double? = nil,
        mime: String? = nil
    ) -> WorkspaceFileEntry {
        let sizeJSON = size.map { "\($0)" } ?? "null"
        let mtimeJSON = mtime.map { "\($0)" } ?? "null"
        let mimeJSON = mime.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"path": "/opt/data", "parent": null, "entries": [
            {"name": "\(name)", "path": "/opt/data/\(name)",
             "is_directory": \(isDirectory), "size": \(sizeJSON),
             "mtime": \(mtimeJSON), "mime_type": \(mimeJSON)}
        ]}
        """
        let listing = try! JSONDecoder().decode(
            FilesListing.self, from: Data(json.utf8)
        )
        return listing.entries[0]
    }

    // MARK: 排序

    func testSortDirectoriesFirstThenName() {
        let entries = [
            entry(name: "b.txt", size: 1, mtime: 3),
            entry(name: "zeta", isDirectory: true),
            entry(name: "a.txt", size: 9, mtime: 9),
            entry(name: "alpha", isDirectory: true),
        ]
        let sorted = FileBrowserLogic.sorted(entries, by: .name)
        XCTAssertEqual(
            sorted.map(\.name), ["alpha", "zeta", "a.txt", "b.txt"]
        )
    }

    func testSortByModifiedDescending() {
        let entries = [
            entry(name: "old.txt", mtime: 100),
            entry(name: "new.txt", mtime: 300),
            entry(name: "mid.txt", mtime: 200),
        ]
        let sorted = FileBrowserLogic.sorted(entries, by: .modified)
        XCTAssertEqual(
            sorted.map(\.name), ["new.txt", "mid.txt", "old.txt"]
        )
    }

    func testSortBySizeDescendingNilLast() {
        let entries = [
            entry(name: "nosize.bin"),
            entry(name: "small.bin", size: 10),
            entry(name: "big.bin", size: 999),
        ]
        let sorted = FileBrowserLogic.sorted(entries, by: .size)
        XCTAssertEqual(
            sorted.map(\.name), ["big.bin", "small.bin", "nosize.bin"]
        )
    }

    // MARK: 过滤

    func testFilterCaseInsensitiveAndEmpty() {
        let entries = [
            entry(name: "Report.PDF"), entry(name: "notes.md"),
            entry(name: "report-2.txt"),
        ]
        XCTAssertEqual(
            FileBrowserLogic.filtered(entries, query: "report").map(\.name),
            ["Report.PDF", "report-2.txt"]
        )
        XCTAssertEqual(
            FileBrowserLogic.filtered(entries, query: "  ").count, 3
        )
        XCTAssertTrue(
            FileBrowserLogic.filtered(entries, query: "zzz").isEmpty
        )
    }

    // MARK: 面包屑

    func testBreadcrumbsRootOnly() {
        let crumbs = FileBrowserLogic.breadcrumbs(
            root: "/opt/data", path: "/opt/data"
        )
        XCTAssertEqual(crumbs.count, 1)
        XCTAssertEqual(crumbs[0].name, "data")
        XCTAssertEqual(crumbs[0].path, "/opt/data")
    }

    func testBreadcrumbsNested() {
        let crumbs = FileBrowserLogic.breadcrumbs(
            root: "/opt/data", path: "/opt/data/cache/images"
        )
        XCTAssertEqual(crumbs.map(\.name), ["data", "cache", "images"])
        XCTAssertEqual(
            crumbs.map(\.path),
            ["/opt/data", "/opt/data/cache", "/opt/data/cache/images"]
        )
    }

    func testBreadcrumbsOutsideRootFallsBack() {
        let crumbs = FileBrowserLogic.breadcrumbs(
            root: "/opt/data", path: "/elsewhere/x"
        )
        XCTAssertEqual(crumbs.count, 1)
        XCTAssertEqual(crumbs[0].path, "/elsewhere/x")
    }

    func testRelativeBreadcrumbs() {
        XCTAssertEqual(
            FileBrowserLogic.relativeBreadcrumbs(
                rootName: "电脑工作区", path: ""
            ).map(\.name),
            ["电脑工作区"]
        )
        let crumbs = FileBrowserLogic.relativeBreadcrumbs(
            rootName: "电脑工作区", path: "out/report"
        )
        XCTAssertEqual(
            crumbs.map(\.name), ["电脑工作区", "out", "report"]
        )
        XCTAssertEqual(crumbs.map(\.path), ["", "out", "out/report"])
    }

    // MARK: 路径与名称

    func testJoinPath() {
        XCTAssertEqual(
            FileBrowserLogic.joinPath(directory: "/opt/data", name: "a.txt"),
            "/opt/data/a.txt"
        )
        XCTAssertEqual(
            FileBrowserLogic.joinPath(directory: "/opt/data/", name: "a.txt"),
            "/opt/data/a.txt"
        )
    }

    func testFolderNameValidation() {
        XCTAssertTrue(FileBrowserLogic.isValidFolderName("新文件夹"))
        XCTAssertTrue(FileBrowserLogic.isValidFolderName("  docs  "))
        XCTAssertFalse(FileBrowserLogic.isValidFolderName(""))
        XCTAssertFalse(FileBrowserLogic.isValidFolderName("   "))
        XCTAssertFalse(FileBrowserLogic.isValidFolderName("a/b"))
        XCTAssertFalse(FileBrowserLogic.isValidFolderName("."))
        XCTAssertFalse(FileBrowserLogic.isValidFolderName(".."))
    }

    // MARK: 上传要素

    func testMimeTypeInference() {
        XCTAssertEqual(
            FileBrowserLogic.mimeType(forFileName: "a.PNG"), "image/png"
        )
        XCTAssertEqual(
            FileBrowserLogic.mimeType(forFileName: "a.pdf"),
            "application/pdf"
        )
        XCTAssertEqual(
            FileBrowserLogic.mimeType(forFileName: "a.unknownext"),
            "application/octet-stream"
        )
    }

    func testDataURLRoundTrip() {
        let data = Data("hello".utf8)
        let url = FileBrowserLogic.makeDataURL(data: data, fileName: "a.txt")
        XCTAssertTrue(url.hasPrefix("data:text/plain;base64,"))
        let base64 = String(url.dropFirst("data:text/plain;base64,".count))
        XCTAssertEqual(Data(base64Encoded: base64), data)
    }

    func testUploadSizeLimit() {
        XCTAssertTrue(FileBrowserLogic.isUploadSizeAllowed(byteCount: 1))
        XCTAssertTrue(FileBrowserLogic.isUploadSizeAllowed(
            byteCount: FileBrowserLogic.uploadByteLimit
        ))
        XCTAssertFalse(FileBrowserLogic.isUploadSizeAllowed(
            byteCount: FileBrowserLogic.uploadByteLimit + 1
        ))
        XCTAssertFalse(FileBrowserLogic.isUploadSizeAllowed(byteCount: 0))
    }

    // MARK: 图标盒轮换

    func testTintIndexByCategory() {
        XCTAssertEqual(
            FileBrowserLogic.tintIndex(for: entry(name: "d", isDirectory: true)),
            3
        )
        XCTAssertEqual(
            FileBrowserLogic.tintIndex(for: entry(name: "a.png", mime: "image/png")),
            0
        )
        XCTAssertEqual(
            FileBrowserLogic.tintIndex(for: entry(name: "a.mp3", mime: "audio/mpeg")),
            1
        )
        XCTAssertEqual(
            FileBrowserLogic.tintIndex(for: entry(name: "a.mp4", mime: "video/mp4")),
            2
        )
        // 未分类：稳定落 0...3（同名重复调用同值）
        let other = entry(name: "blob.bin")
        XCTAssertEqual(
            FileBrowserLogic.tintIndex(for: other),
            FileBrowserLogic.tintIndex(for: other)
        )
        XCTAssertTrue((0...3).contains(FileBrowserLogic.tintIndex(for: other)))
    }

    // MARK: 排序方向（0.36.31：系统文件页排序行方向钮）

    func testSortNameDescendingReversesNameOnly() {
        let entries = [
            entry(name: "b.txt", size: 1, mtime: 3),
            entry(name: "zeta", isDirectory: true),
            entry(name: "a.txt", size: 9, mtime: 9),
            entry(name: "alpha", isDirectory: true),
        ]
        let sorted = FileBrowserLogic.sorted(
            entries, by: .name, ascending: false
        )
        // 目录恒在前（方向只翻文件/目录各自组内的名称序）
        XCTAssertEqual(
            sorted.map(\.name),
            ["zeta", "alpha", "b.txt", "a.txt"]
        )
    }

    func testSortModifiedAscendingPutsOldestFirst() {
        let entries = [
            entry(name: "new.txt", mtime: 30),
            entry(name: "old.txt", mtime: 10),
            entry(name: "mid.txt", mtime: 20),
        ]
        let sorted = FileBrowserLogic.sorted(
            entries, by: .modified, ascending: true
        )
        XCTAssertEqual(
            sorted.map(\.name),
            ["old.txt", "mid.txt", "new.txt"]
        )
    }
}
