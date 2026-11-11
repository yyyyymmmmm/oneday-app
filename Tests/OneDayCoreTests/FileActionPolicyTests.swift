import Foundation
import XCTest
@testable import OneDayCore

/// 文件页 v2 附记硬规矩（0.36.31）：菜单/工具栏/失败
/// 页按文件类型出项。钉：分类映射、文本类专属项（复
/// 制文字＋导出 PDF）、PDF 只给复制文字、Office 不摆
/// 读不出文字的灰项、敏感文件全收回、失败页按类型收
/// 敛。条目按生产回执形状 JSON 解码构造。
final class FileActionPolicyTests: XCTestCase {
    private func entry(
        name: String, mime: String? = nil
    ) -> WorkspaceFileEntry {
        let mimeJSON = mime.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"path": "/opt/data", "parent": null, "entries": [
            {"name": "\(name)", "path": "/opt/data/\(name)",
             "is_directory": false, "size": null,
             "mtime": null, "mime_type": \(mimeJSON)}
        ]}
        """
        let listing = try! JSONDecoder().decode(
            FilesListing.self, from: Data(json.utf8)
        )
        return listing.entries[0]
    }

    // MARK: 分类

    func testCategoryMapping() {
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "笔记.md")),
            .text
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "表.csv")),
            .text
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "报告.pdf")),
            .pdf
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "稿.docx")),
            .office
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "页.html")),
            .html
        )
        XCTAssertEqual(
            FileActionPolicy.category(
                of: entry(name: "图.bin", mime: "image/png")
            ),
            .image
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "片.mp4")),
            .video
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "声.mp3")),
            .audio
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "包.zip")),
            .archive
        )
        XCTAssertEqual(
            FileActionPolicy.category(of: entry(name: "数据.xyz")),
            .other
        )
    }

    // MARK: 条目菜单

    func testMenuActionsTextHasCopyAndExport() {
        XCTAssertEqual(
            FileActionPolicy.menuActions(for: entry(name: "笔记.md")),
            [.preview, .copyText, .exportPDF, .share, .download, .delete]
        )
    }

    func testMenuActionsPDFCopyOnly() {
        XCTAssertEqual(
            FileActionPolicy.menuActions(for: entry(name: "报告.pdf")),
            [.preview, .copyText, .share, .download, .delete]
        )
    }

    func testMenuActionsOfficeHasNoTextActions() {
        // DOCX 在 iOS 无系统文字提取通道：不给复制文字、
        // 不给导出 PDF，不摆不能用的灰项充数（附记硬规矩）
        XCTAssertEqual(
            FileActionPolicy.menuActions(for: entry(name: "稿.docx")),
            [.preview, .share, .download, .delete]
        )
    }

    func testMenuActionsImagePlainSet() {
        XCTAssertEqual(
            FileActionPolicy.menuActions(for: entry(name: "图.png")),
            [.preview, .share, .download, .delete]
        )
    }

    func testMenuActionsSensitiveWithdrawn() {
        XCTAssertEqual(
            FileActionPolicy.menuActions(for: entry(name: "auth.json")),
            []
        )
        XCTAssertEqual(
            FileActionPolicy.menuActions(for: entry(name: "token.md")),
            []
        )
    }

    // MARK: 阅读面工具栏

    func testReadingActionsTextNoDelete() {
        XCTAssertEqual(
            FileActionPolicy.readingActions(for: entry(name: "笔记.md")),
            [.copyText, .exportPDF, .share, .download]
        )
    }

    func testReadingActionsPDF() {
        XCTAssertEqual(
            FileActionPolicy.readingActions(for: entry(name: "报告.pdf")),
            [.copyText, .share, .download]
        )
    }

    // MARK: 失败页

    func testFailureActionsRenderableRetryAndDownload() {
        XCTAssertEqual(
            FileActionPolicy.failureActions(for: entry(name: "报告.pdf")),
            [.retry, .download]
        )
        XCTAssertEqual(
            FileActionPolicy.failureActions(for: entry(name: "图.png")),
            [.retry, .download]
        )
    }

    func testFailureActionsArchiveDownloadOnly() {
        XCTAssertEqual(
            FileActionPolicy.failureActions(for: entry(name: "包.zip")),
            [.download, .dismiss]
        )
    }

    func testFailureActionsSensitiveDismissOnly() {
        XCTAssertEqual(
            FileActionPolicy.failureActions(for: entry(name: ".env")),
            [.dismiss]
        )
    }

    // MARK: 打开页动作集（§127，D8）

    func testOpenPageActionsTextUnpinned() {
        XCTAssertEqual(
            FileActionPolicy.openPageActions(
                for: entry(name: "笔记.md"), isPinned: false
            ),
            [.pin, .copyText, .exportPDF, .share, .download,
             .rename, .openInFiles]
        )
    }

    func testOpenPageActionsPinnedShowsUnpin() {
        XCTAssertEqual(
            FileActionPolicy.openPageActions(
                for: entry(name: "报告.pdf"), isPinned: true
            ),
            [.unpin, .copyText, .share, .download,
             .rename, .openInFiles]
        )
    }

    func testOpenPageActionsNeverOffersDelete() {
        // 打开页守阅读面克制：删除只归列表面（D8 口径）
        for name in ["笔记.md", "报告.pdf", "图.png", "包.zip"] {
            XCTAssertFalse(
                FileActionPolicy.openPageActions(
                    for: entry(name: name), isPinned: false
                ).contains(.delete),
                "\(name) 不应含删除"
            )
        }
    }

    func testOpenPageActionsSensitiveWithdrawn() {
        XCTAssertEqual(
            FileActionPolicy.openPageActions(
                for: entry(name: "auth.json"), isPinned: false
            ),
            []
        )
    }

    func testNewActionLabelsAndSymbols() {
        XCTAssertEqual(FileItemAction.pin.label, "置顶")
        XCTAssertEqual(FileItemAction.unpin.label, "取消置顶")
        XCTAssertEqual(FileItemAction.rename.label, "重命名")
        XCTAssertEqual(FileItemAction.openInFiles.label, "在文件页中打开")
        XCTAssertEqual(FileItemAction.pin.systemImage, "pin")
        XCTAssertEqual(FileItemAction.unpin.systemImage, "pin.slash")
        XCTAssertEqual(FileItemAction.rename.systemImage, "pencil")
        XCTAssertEqual(FileItemAction.openInFiles.systemImage, "folder")
    }

    // MARK: 阅读页分流

    func testOpensInReader() {
        XCTAssertTrue(
            FileActionPolicy.opensInReader(entry(name: "笔记.md"))
        )
        XCTAssertFalse(
            FileActionPolicy.opensInReader(entry(name: "报告.pdf"))
        )
        // 敏感文本不进阅读页（凭据不经阅读面外带）
        XCTAssertFalse(
            FileActionPolicy.opensInReader(entry(name: "token.md"))
        )
    }
}
