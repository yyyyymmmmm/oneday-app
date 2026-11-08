import Foundation
import XCTest
@testable import OneDayCore

/// 0.2.1 新增模型解码测试：文件列表与系统状态样本按
/// 2026-11-08 生产实查回执脱敏改写；多模态消息验 OpenAI
/// 编码形态（content 数组 + image_url 部分）。
final class FilesModelsDecodeTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testFilesListingRoot() throws {
        let listing = try decode(FilesListing.self, """
        {"path": "/opt/data", "parent": null, "root": "/opt/data",
         "locked_root": "/opt/data", "can_change_path": false,
         "entries": [
            {"name": ".local", "path": "/opt/data/.local",
             "is_directory": true, "size": null,
             "mtime": 1794141188.88, "mime_type": null},
            {"name": "notes.md", "path": "/opt/data/notes.md",
             "is_directory": false, "size": 2048,
             "mtime": 1794141188.88, "mime_type": "text/markdown"}
         ]}
        """)
        XCTAssertEqual(listing.path, "/opt/data")
        XCTAssertNil(listing.parent)
        XCTAssertEqual(listing.lockedRoot, "/opt/data")
        XCTAssertEqual(listing.entries.count, 2)
        XCTAssertTrue(listing.entries[0].isDirectory)
        XCTAssertNil(listing.entries[0].size)
        let file = listing.entries[1]
        XCTAssertEqual(file.size, 2048)
        XCTAssertTrue(file.isTextLike)
        XCTAssertNil(file.mediaKind)
        XCTAssertNotNil(file.modifiedAt)
    }

    func testMediaKindByMimeAndExtension() throws {
        let listing = try decode(FilesListing.self, """
        {"path": "/opt/data/images", "parent": "/opt/data", "entries": [
            {"name": "a.png", "path": "/opt/data/images/a.png",
             "is_directory": false, "size": 10, "mtime": 1,
             "mime_type": "image/png"},
            {"name": "b.mp4", "path": "/opt/data/images/b.mp4",
             "is_directory": false, "size": 10, "mtime": 1,
             "mime_type": null},
            {"name": "c.mp3", "path": "/opt/data/images/c.mp3",
             "is_directory": false, "size": 10, "mtime": 1,
             "mime_type": "audio/mpeg"},
            {"name": "d.bin", "path": "/opt/data/images/d.bin",
             "is_directory": false, "size": 10, "mtime": 1,
             "mime_type": "application/octet-stream"}
         ]}
        """)
        XCTAssertEqual(listing.entries[0].mediaKind, .image)
        XCTAssertEqual(listing.entries[1].mediaKind, .video)
        XCTAssertEqual(listing.entries[2].mediaKind, .audio)
        XCTAssertNil(listing.entries[3].mediaKind)
    }

    func testSystemStats() throws {
        let stats = try decode(SystemStats.self, """
        {"os": "Linux", "os_release": "3.10.0-1160.el7.x86_64",
         "platform": "Linux-x86_64", "arch": "x86_64",
         "hostname": "host-1", "python_version": "3.14.9",
         "hermes_version": "0.23.0", "cpu_count": 4,
         "cpu_percent": 2.5, "load_avg": [0.07, 0.09, 0.12],
         "uptime_seconds": 2358766,
         "memory": {"total": 8101019648, "available": 4321755136,
                    "used": 3779264512, "percent": 46.7},
         "disk": {"total": 126691618816, "used": 54956441600,
                  "free": 66478796800, "percent": 45.3},
         "process": {"pid": 155, "rss": 301142016,
                     "create_time": 1794142047, "num_threads": 11}}
        """)
        XCTAssertEqual(stats.hermesVersion, "0.23.0")
        XCTAssertEqual(stats.cpuCount, 4)
        XCTAssertEqual(stats.memory?.percent, 46.7)
        XCTAssertEqual(stats.disk?.free, 66478796800)
        XCTAssertEqual(stats.process?.numThreads, 11)
        XCTAssertEqual(stats.loadAvg?.count, 3)
    }

    func testChatMessageMultimodalEncoding() throws {
        let message = ChatMessage(
            role: "user", text: "看这张图",
            imageDataURLs: ["data:image/jpeg;base64,QUJD"]
        )
        let data = try JSONEncoder().encode(message)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let parts = object?["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?.first?["type"] as? String, "text")
        XCTAssertEqual(parts?.first?["text"] as? String, "看这张图")
        XCTAssertEqual(parts?.last?["type"] as? String, "image_url")
        let imageBody = parts?.last?["image_url"] as? [String: Any]
        XCTAssertEqual(imageBody?["url"] as? String, "data:image/jpeg;base64,QUJD")
    }

    func testChatMessagePlainEncodingStaysString() throws {
        let data = try JSONEncoder().encode(ChatMessage.user("你好"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["content"] as? String, "你好")
    }

    func testChatMessageDecodePartsArray() throws {
        let message = try decode(ChatMessage.self, """
        {"role": "user", "content": [
            {"type": "text", "text": "看图"},
            {"type": "image_url", "image_url": {"url": "https://x/y.png"}}
        ]}
        """)
        XCTAssertEqual(message.content, "看图")
        XCTAssertEqual(message.parts?.count, 2)
    }
}
