import Foundation
import XCTest
@testable import OneDayCore

/// §125 路由表＋行号锚点＋中间页落点列钉测：路由
/// 是 chat/文件页/中间页三面共用的纯函数分流——
/// 图片直达、其余可预览类一律 QuickLook 单轨
/// （§259 双轨合一：文本/表格并入）、QL 资格为
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

    func testRouteImageIgnoresPreviewGate() {
        // 图片直达查看器、不走 QL——资格门与它无关
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("图.png"), canPreview: false
            ),
            .imageViewer
        )
    }

    func testRouteTextToQuickLook() {
        for name in ["笔记.md", "表.csv", "数据.json", "日志.txt"] {
            XCTAssertEqual(
                FileOpenRoute.resolve(target: target(name)),
                .quickLook, name
            )
        }
    }

    func testRouteTextExtensionsToQuickLook() {
        // §259：文本类全扩展名一律 QL 单轨，不再按
        // 种类分阅读页/转码两轨
        for name in ["稿.markdown", "配置.yaml", "配置.yml",
                     "页.xml", "记录.log", "纯文.text"] {
            XCTAssertEqual(
                FileOpenRoute.resolve(target: target(name)),
                .quickLook, name
            )
        }
    }

    func testRouteAnchorDoesNotChangeRoute() {
        // §259：锚点解析保留、呈现忽略——带锚点的文
        // 本/表格与不带锚点同路由，不回自研阅读页
        let anchor = FileLineAnchor(startLine: 3, endLine: 9)
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("笔记.md", anchor: anchor)
            ),
            .quickLook
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("表.xlsx", anchor: anchor)
            ),
            .quickLook
        )
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

    func testRouteSpreadsheetToQuickLook() {
        // §259：表格不再走伴生转码呈现，原文件直接
        // QL 预览（服务端转码端点保留作降级）
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("表.xlsx")),
            .quickLook
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("表.xls")),
            .quickLook
        )
        // csv 同为文本档、一律 QL 单轨
        XCTAssertEqual(
            FileOpenRoute.resolve(target: target("表.csv")),
            .quickLook
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
        // §259 起文本/表格同入 QL 轨、同受资格门：
        // 资格为假一律降无预览行
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("笔记.md"), canPreview: false
            ),
            .infoOnly
        )
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("表.xlsx"), canPreview: false
            ),
            .infoOnly
        )
        // 非 QL 路不受资格门影响
        XCTAssertEqual(
            FileOpenRoute.resolve(
                target: target("包.zip"), canPreview: false
            ),
            .saveOnly
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
        // §259：文本主钮并入「预览」（原「阅读」退役）
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "笔记.md", mediaKind: nil
            ),
            .preview
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
        // §259：表格主钮并入「预览」（原「查看表格」退役）
        XCTAssertEqual(
            FileActionPolicy.landingPrimary(
                forFileName: "表.xlsx", mediaKind: nil
            ),
            .preview
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
            // 影音类靠扩展名推导（mediaKind=nil 时经
            // 合成条目取条目同表，不许落 .other）
            ("图.png", .image),
            ("片.mp4", .video),
            ("声.mp3", .audio),
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

    // MARK: 目标值

    func testTargetFromEntryAndPath() {
        let fromPath = FileOpenTarget(path: "/opt/data/attachments/表.xlsx")
        XCTAssertEqual(fromPath.name, "表.xlsx")
        XCTAssertNil(fromPath.size)
        XCTAssertEqual(fromPath.category, .office)
        let entry = fromPath.workspaceEntry
        XCTAssertEqual(entry.path, fromPath.path)
        XCTAssertFalse(entry.isDirectory)
    }
}

