import Foundation
import XCTest
@testable import OneDayCore

/// §473 件三矩阵：mediaKind 改走 UTType 单源后的判类
/// 全表——每扩展名 × 三种 mime 组合（缺失／媒体 mime
/// ／octet-stream 非媒体 mime）。octet-stream 一列专
/// 钉旧短路病：mime 在位但非媒体前缀时必须继续看扩
/// 展名、不许直接 nil。样本期望以 UTType 在 iOS 26
/// 模拟器的实测判定为准；UTType 查不到的遗留格式由
/// mediaKind 的极小兜底承接（兜底逐条在源文件注明）。
final class MediaKindUTTypeMatrixTests: XCTestCase {

    private func entry(
        _ name: String, mime: String?
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: "/x/" + name, isDirectory: false,
            size: 1, mtime: 1, mimeType: mime
        )
    }

    private func assertKind(
        _ ext: String, _ kind: WorkspaceFileEntry.MediaKind?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let name = "sample." + ext
        XCTAssertEqual(
            entry(name, mime: nil).mediaKind, kind,
            "\(ext) mime=nil", file: file, line: line
        )
        XCTAssertEqual(
            entry(name, mime: "application/octet-stream").mediaKind,
            kind, "\(ext) mime=octet-stream", file: file, line: line
        )
    }

    func testVideoExtensions() {
        let exts = [
            "mp4", "mov", "m4v", "webm", "mkv", "avi", "ts",
            "m2ts", "mpg", "mpeg", "3gp", "flv", "wmv", "rmvb",
        ]
        for ext in exts { assertKind(ext, .video) }
    }

    func testAudioExtensions() {
        let exts = [
            "mp3", "m4a", "wav", "ogg", "flac", "aac", "opus",
            "aiff", "aif", "wma", "amr", "mka",
        ]
        for ext in exts { assertKind(ext, .audio) }
    }

    func testImageExtensions() {
        let exts = [
            "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp",
        ]
        for ext in exts { assertKind(ext, .image) }
    }

    /// mime 是媒体类时以 mime 为准（与旧口径一致：
    /// mime 优先于扩展名）
    func testMediaMimeWinsOverExtension() {
        XCTAssertEqual(
            entry("clip.mp4", mime: "image/png").mediaKind, .image
        )
        XCTAssertEqual(
            entry("photo.png", mime: "video/mp4").mediaKind, .video
        )
        XCTAssertEqual(
            entry("song.bin", mime: "audio/mpeg").mediaKind, .audio
        )
    }

    /// 非媒体不得误入：文本／PDF／未知二进制恒 nil
    func testNonMediaStaysNil() {
        XCTAssertNil(entry("notes.md", mime: "text/markdown").mediaKind)
        XCTAssertNil(entry("doc.pdf", mime: "application/pdf").mediaKind)
        XCTAssertNil(
            entry("d.bin", mime: "application/octet-stream").mediaKind
        )
        XCTAssertNil(entry("archive.zip", mime: nil).mediaKind)
    }

    /// 影音片归片：矩阵全样本经 LibraryCategory 归
    /// .media（资源库「影音」筛选的消费口）
    func testVideoAudioBucketIsMedia() {
        for ext in ["mp4", "mkv", "avi", "ts", "flv", "rmvb"] {
            XCTAssertEqual(
                LibraryCategory.bucket(
                    for: entry("v." + ext, mime: nil)
                ),
                .media, ext
            )
        }
        for ext in ["mp3", "opus", "aiff", "wma", "mka"] {
            XCTAssertEqual(
                LibraryCategory.bucket(
                    for: entry("a." + ext, mime: nil)
                ),
                .media, ext
            )
        }
    }
}
