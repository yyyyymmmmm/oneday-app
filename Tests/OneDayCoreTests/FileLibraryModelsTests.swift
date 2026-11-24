import OneDayCore
import XCTest

/// 文件库聚合读面（A-06，伴生 1.0.66 GET /file-library）
/// 回执解码：条目同 /api/files 形态＋source 下发、分页元
/// 数据如实解码。样本逐字对齐 oneday_seg_filelibrary.py
/// 的回执（未知扩展名 mime 为 null、total 报全量、
/// truncated 恒 false——无静默截断是契约的一部分）。
final class FileLibraryModelsTests: XCTestCase {

    func testDecodesServerPage() throws {
        let json = """
        {"items": [
          {"name": "photo.png",
           "path": "/opt/data/attachments/photo.png",
           "is_directory": false, "size": 123,
           "mtime": 5000.0, "mime_type": "image/png",
           "source": "聊天发送"},
          {"name": "中间稿.xyz",
           "path": "/opt/data/uploads/中间稿.xyz",
           "is_directory": false, "size": 1,
           "mtime": 500.0, "mime_type": null,
           "source": "App 上传"}
        ], "total": 2, "offset": 0, "limit": null,
         "truncated": false}
        """
        let page = try JSONDecoder().decode(
            FileLibraryPage.self, from: Data(json.utf8)
        )
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.offset, 0)
        XCTAssertNil(page.limit)
        XCTAssertFalse(page.truncated)
        XCTAssertEqual(page.items.count, 2)

        let photo = page.items[0]
        XCTAssertEqual(photo.source, "聊天发送")
        XCTAssertEqual(photo.entry.name, "photo.png")
        XCTAssertEqual(
            photo.entry.path, "/opt/data/attachments/photo.png"
        )
        XCTAssertFalse(photo.entry.isDirectory)
        XCTAssertEqual(photo.entry.size, 123)
        XCTAssertEqual(photo.entry.mtime, 5000.0)
        XCTAssertEqual(photo.entry.mimeType, "image/png")
        XCTAssertEqual(photo.entry.mediaKind, .image)

        let draft = page.items[1]
        XCTAssertEqual(draft.source, "App 上传")
        XCTAssertNil(draft.entry.mimeType)
    }

    func testDecodesPagedResponse() throws {
        let json = """
        {"items": [], "total": 9, "offset": 100,
         "limit": 2, "truncated": false}
        """
        let page = try JSONDecoder().decode(
            FileLibraryPage.self, from: Data(json.utf8)
        )
        XCTAssertEqual(page.items.count, 0)
        XCTAssertEqual(page.total, 9)
        XCTAssertEqual(page.offset, 100)
        XCTAssertEqual(page.limit, 2)
    }
}
