import Foundation
import XCTest
@testable import OneDayCore

/// §125 路由表＋行号锚点＋中间页落点列钉测：路由
/// 是 chat/文件页/中间页三面共用的纯函数分流——
/// 图片直达、文本进阅读页、表格走转码、QL 资格为
/// 假一律降无预览、敏感恒锁定，逐格钉死防漂移。
final class FileOpenRouteTests: XCTestCase {
    private func target(
        _ name: String, anchor: FileLineAnchor? = nil
    ) -> FileOpenTarget {
        FileOpenTarget(
            name: name, path: "/opt/data/\(name)", anchor: anchor
        )
    }

    // MARK: 路由矩阵

    func testRouteImageDirect() {
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("图.png")),
            .imageViewer
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("图.jpg")),
            .imageViewer
        )
    }

    func testRouteTextToReader() {
        for name in ["笔记.md", "表.csv", "数据.json", "日志.txt"] {
            XCTAssertEqual(
                FileOpenRoute.resolve(target: target(name)),
                .reader, name
            )
        }
    }

    func testRouteQuickLookFamily() {
        for name in ["报告.pdf", "稿.docx", "页.html",
                     "片.mp4", "声.mp3", "稿.pptx"] {
            XCTAssertEqual(
                FileOpenRoute.resolve(target: target(name)),
                .quickLook, name
            )
        }
    }

    func testRouteSpreadsheetSpecial() {
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("表.xlsx")),
            .spreadsheet
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("表.xls")),
            .spreadsheet
        )
        // csv 不走转码：文本档进阅读页（阅读页表格块
        // 已有框线/横滚，规格 §5.4 口径）
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("表.csv")),
            .reader
        )
    }

    func testRouteNoPreviewFamily() {
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("包.zip")),
            .saveOnly
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("包.rar")),
            .saveOnly
        )
        // .ipa 等未知类：中间页说明行，无预览无主钮
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("OneDay.ipa")),
            .infoOnly
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("程序.exe")),
            .infoOnly
        )
    }

    func testRouteCanPreviewFalseDowngrades() {
        // §121 资格门：QL 无资格一律降无预览行，不许
        // 硬呈空白 QL
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("报告.pdf"), canPreview: false
            ),
            .infoOnly
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("片.mp4"), canPreview: false
            ),
            .infoOnly
        )
        // 非 QL 路不受资格门影响
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("笔记.md"), canPreview: false
            ),
            .reader
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("表.xlsx"), canPreview: false
            ),
            .spreadsheet
        )
    }

    func testRouteSensitiveLocked() {
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("auth.json")),
            .locked
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target(".env")),
            .locked
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("token.md")),
            .locked
        )
    }

    // MARK: 中间页落点列

    func testLandingPrimaryMapping() {
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "笔记.md", mediaKind: nil
            ),
            .read
        )
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "报告.pdf", mediaKind: nil
            ),
            .preview
        )
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "片.mp4", mediaKind: nil
            ),
            .play
        )
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "表.xlsx", mediaKind: nil
            ),
            .viewTable
        )
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "包.zip", mediaKind: nil
            ),
            .saveToFiles
        )
        XCTAssertNil(
            FileActionPolicy.landingPrimary(
                forFileName: "OneDay.ipa", mediaKind: nil
            )
        )
        XCTAssertNil(
            FileActionPolicy.landingPrimary(
                forFileName: "auth.json", mediaKind: nil
            )
        )
    }

    func testCategoryNameParityWithEntry() {
        // 名称口径与条目口径同果（抽查关键档）
        for (name, expected) in [
            ("笔记.md", FileItemCategory.text),
            ("报告.pdf", .pdf),
            ("稿.docx", .office),
            ("页.html", .html),
            ("包.zip", .archive),
            ("数据.xyz", .other),
        ] {
            XCTAssertEqual(
                FileActionPolicy.category(
                    forFileName: name, mediaKind: nil
                ),
                expected, name
            )
        }
    }

    // MARK: 行号锚点

    func testAnchorParseForms() {
        XCTAssertEqual(
            FileLineAnchor.parse("L12"),
            FileLineAnchor(startLine: 12, endLine: 12)
        )
        XCTAssertEqual(
            FileLineAnchor.parse("#L12-L20"),
            FileLineAnchor(startLine: 12, endLine: 20)
        )
        XCTAssertEqual(
            FileLineAnchor.parse("L12-20"),
            FileLineAnchor(startLine: 12, endLine: 20)
        )
        XCTAssertNil(FileLineAnchor.parse("L0"))
        XCTAssertNil(FileLineAnchor.parse("L20-L12"))
        XCTAssertNil(FileLineAnchor.parse("L"))
        XCTAssertNil(FileLineAnchor.parse("12-20"))
        XCTAssertNil(FileLineAnchor.parse("L1-L2-L3"))
    }

    func testAnchorSplit() {
        let split = FileLineAnchor.split(
            pathWithAnchor: "/opt/data/a.py#L3-L9"
        )
        XCTAssertEqual(split.path, "/opt/data/a.py")
        XCTAssertEqual(
            split.anchor, FileLineAnchor(startLine: 3, endLine: 9)
        )
        let plain = FileLineAnchor.split(
            pathWithAnchor: "/opt/data/a.py"
        )
        XCTAssertEqual(plain.path, "/opt/data/a.py")
        XCTAssertNil(plain.anchor)
    }

    func testDetectAnchored() {
        let refs = FileRefDetector.detectAnchored(
            in: "见 /opt/data/notes/报告.md#L12-L20 与 "
                + "/opt/data/x.zip，还有 /opt/data/a.py#L5"
        )
        XCTAssertEqual(refs.count, 3)
        XCTAssertEqual(refs[0].path, "/opt/data/notes/报告.md")
        XCTAssertEqual(
            refs[0].anchor,
            FileLineAnchor(startLine: 12, endLine: 20)
        )
        XCTAssertEqual(refs[1].path, "/opt/data/x.zip")
        XCTAssertNil(refs[1].anchor)
        XCTAssertEqual(
            refs[2].anchor, FileLineAnchor(startLine: 5, endLine: 5)
        )
        // detect 旧口径不变：路径干净、无锚点残留
        XCTAssertEqual(
            FileRefDetector.detect(
                in: "见 /opt/data/a.py#L5"
            ),
            ["/opt/data/a.py"]
        )
    }

    // MARK: 目标值与转码失败分型

    func testTargetFromEntryAndPath() {
        let fromPath = FileOpenTarget(path: "/opt/data/attachments/表.xlsx")
        XCTAssertEqual(fromPath.name, "表.xlsx")
        XCTAssertNil(fromPath.size)
        XCTAssertEqual(fromPath.category, .office)
        let entry = fromPath.workspaceEntry
        XCTAssertEqual(entry.path, fromPath.path)
        XCTAssertFalse(entry.isDirectory)
    }

    func testPlainParagraphLineRanges() {
        let text = "第一段一\n第一段二\n\n第二段\n\n\n第三段"
        XCTAssertEqual(
            DocumentReading.plainParagraphLineRanges(for: text),
            [1...2, 4...4, 7...7]
        )
        // 与 plainBlocks 段数恒一致
        XCTAssertEqual(
            DocumentReading.plainParagraphLineRanges(for: text).count,
            DocumentReading.plainBlocks(for: text).count
        )
        XCTAssertEqual(
            DocumentReading.plainParagraphLineRanges(for: ""),
            []
        )
    }

    func testAnchorExcerpt() {
        let text = "a\nb\nc\nd"
        XCTAssertEqual(
            DocumentReading.excerpt(
                for: text,
                anchor: FileLineAnchor(startLine: 2, endLine: 3)!
            ),
            "b\nc"
        )
        // 止行越界收敛到文本末行
        XCTAssertEqual(
            DocumentReading.excerpt(
                for: text,
                anchor: FileLineAnchor(startLine: 3, endLine: 99)!
            ),
            "c\nd"
        )
        // 整段落在文本外回 nil
        XCTAssertNil(
            DocumentReading.excerpt(
                for: text,
                anchor: FileLineAnchor(startLine: 9, endLine: 10)!
            )
        )
    }

    func testSpreadsheetFailureClassify() {
        XCTAssertEqual(
            FileOpenFailure.classifySpreadsheet(
                error: .unexpectedStatus(
                    endpoint: "表格转换", status: 422
                )
            ),
            .transcodeFailed
        )
        XCTAssertEqual(
            FileOpenFailure.classifySpreadsheet(
                error: .unexpectedStatus(
                    endpoint: "表格转换", status: 404
                )
            ),
            .notFound
        )
        XCTAssertEqual(
            FileOpenFailure.classifySpreadsheet(
                error: .unexpectedStatus(
                    endpoint: "表格转换", status: 413
                )
            ),
            .tooLarge
        )
    }
}
