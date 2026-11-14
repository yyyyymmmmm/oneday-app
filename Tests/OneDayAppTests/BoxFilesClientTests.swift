import XCTest
@testable import OneDayApp

final class BoxFilesClientTests: XCTestCase {

    /// M1 回归测试：parseDirectoryListing 应输出 snake_case 键名，能被 FilesListing 正确解码
    func testParseDirectoryListingKeys() throws {
        let client = BoxFilesClient()

        // 模拟厂商 list_dir 文本输出
        let sampleText = """
        /workspace/testdir:
        subdir/
        file.txt  (1024 bytes)
        image.png  (2048 bytes)
        """

        // 解析并验证（如果键名错误，FilesListing 解码会失败）
        let listing = try client.parseDirectoryListing(
            text: sampleText,
            requestedPath: "testdir",
            resolvedPath: "/workspace/testdir"
        )

        // 验证解码成功
        XCTAssertEqual(listing.path, "testdir")
        XCTAssertEqual(listing.entries.count, 3)

        // 验证目录条目
        let dirEntry = listing.entries.first { $0.name == "subdir" }
        XCTAssertNotNil(dirEntry)
        XCTAssertTrue(dirEntry?.isDirectory ?? false)

        // 验证文件条目
        let fileEntry = listing.entries.first { $0.name == "file.txt" }
        XCTAssertNotNil(fileEntry)
        XCTAssertFalse(fileEntry?.isDirectory ?? true)
        XCTAssertEqual(fileEntry?.size, 1024)

        // 验证 MIME 类型
        let imageEntry = listing.entries.first { $0.name == "image.png" }
        XCTAssertNotNil(imageEntry)
        XCTAssertEqual(imageEntry?.mimeType, "image/png")
    }
}
