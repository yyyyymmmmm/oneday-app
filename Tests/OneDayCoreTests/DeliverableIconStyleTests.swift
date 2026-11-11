import OneDayCore
import XCTest

/// 文件类型图标解析（§128，C8 定版）：扩展名→资产
/// slug 钉死。分组沿 0.22.0 旧字形表逐项对齐＋四处
/// 增补（code 组／app 组／archive 补 rar／document
/// 文档类通用回落）；字母块字形表已整套退役，本文件
/// 不再有 glyph／backgroundHex 断言。
final class DeliverableIconStyleTests: XCTestCase {

    private func slug(_ name: String) -> String {
        DeliverableIconStyle.style(forFileName: name).slug
    }

    func testOfficeSlugs() {
        XCTAssertEqual(slug("账本.docx"), "word")
        XCTAssertEqual(slug("说明.doc"), "word")
        XCTAssertEqual(slug("讲稿.PPTX"), "slides")
        XCTAssertEqual(slug("表.xlsx"), "sheet")
        XCTAssertEqual(slug("旧表.xls"), "sheet")
        XCTAssertEqual(slug("数据.csv"), "sheet")
    }

    func testDocumentSlugs() {
        XCTAssertEqual(slug("a.pdf"), "pdf")
        XCTAssertEqual(slug("a.md"), "text")
        XCTAssertEqual(slug("a.txt"), "text")
        XCTAssertEqual(slug("a.rtf"), "text")
    }

    func testCodeGroup() {
        // html/htm 自旧表 safari 符号改归 code（§128）
        XCTAssertEqual(slug("a.html"), "code")
        XCTAssertEqual(slug("a.htm"), "code")
        // 源码类扩展名（旧表无组、原落 default）
        XCTAssertEqual(slug("main.swift"), "code")
        XCTAssertEqual(slug("tool.py"), "code")
        XCTAssertEqual(slug("app.ts"), "code")
        XCTAssertEqual(slug("config.json"), "code")
        XCTAssertEqual(slug("config.yaml"), "code")
        XCTAssertEqual(slug("build.toml"), "code")
        XCTAssertEqual(slug("style.css"), "code")
        XCTAssertEqual(slug("query.sql"), "code")
    }

    func testArchiveSlugs() {
        XCTAssertEqual(slug("a.zip"), "archive")
        XCTAssertEqual(slug("a.tar.gz"), "archive")
        XCTAssertEqual(slug("a.7z"), "archive")
        XCTAssertEqual(slug("a.rar"), "archive")
    }

    func testMediaSlugs() {
        XCTAssertEqual(slug("a.png"), "image")
        XCTAssertEqual(slug("a.JPG"), "image")
        XCTAssertEqual(slug("a.heic"), "image")
        XCTAssertEqual(slug("a.mp4"), "video")
        XCTAssertEqual(slug("a.mov"), "video")
        XCTAssertEqual(slug("a.mp3"), "audio")
        XCTAssertEqual(slug("a.m4a"), "audio")
    }

    func testAppGroup() {
        XCTAssertEqual(slug("OneDay.ipa"), "app")
        XCTAssertEqual(slug("a.apk"), "app")
        XCTAssertEqual(slug("a.dmg"), "app")
        XCTAssertEqual(slug("a.pkg"), "app")
        XCTAssertEqual(slug("setup.exe"), "app")
        XCTAssertEqual(slug("a.msi"), "app")
    }

    func testDocumentFallback() {
        // text/office 类未命中专属组 → 通用文档枚
        XCTAssertEqual(slug("a.odt"), "document")
        XCTAssertEqual(slug("a.ods"), "document")
        XCTAssertEqual(slug("宏.docm"), "document")
        XCTAssertEqual(slug("a.xlsm"), "document")
        XCTAssertEqual(slug("a.pages"), "document")
        XCTAssertEqual(slug("书.epub"), "document")
        XCTAssertEqual(slug("run.log"), "document")
    }

    func testDirectoryAndUnknown() {
        XCTAssertEqual(
            DeliverableIconStyle.style(
                forFileName: "文件夹", isDirectory: true
            ).slug,
            "folder"
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(
                forFileName: "文件夹",
                isDirectory: true, isExpanded: true
            ).slug,
            "folder-open"
        )
        XCTAssertEqual(slug("a.unknownext"), "unknown")
        XCTAssertEqual(slug("README"), "unknown")
        XCTAssertEqual(slug("EA.ex5"), "unknown")
    }

    func testAssetNamesAndFamilyCompleteness() {
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.pdf")
                .assetName,
            "fileicon-pdf"
        )
        XCTAssertEqual(
            DeliverableIconStyle.fallbackSlug, "unknown"
        )
        XCTAssertEqual(
            DeliverableIconStyle.fallbackAssetName,
            "fileicon-unknown"
        )
        XCTAssertEqual(DeliverableIconStyle.allSlugs.count, 15)
        XCTAssertEqual(
            Set(DeliverableIconStyle.allSlugs).count, 15
        )
        // 样本全集产出的 slug 必须都在家族表内（资产
        // 查表不许产出表外名）
        let samples = [
            "a.docx", "a.pptx", "a.xlsx", "a.pdf", "a.md",
            "a.html", "a.swift", "a.zip", "a.png", "a.mp4",
            "a.mp3", "a.ipa", "a.odt", "a.bin",
        ]
        for sample in samples {
            XCTAssertTrue(
                DeliverableIconStyle.allSlugs.contains(
                    slug(sample)
                ),
                "\(sample) 产出表外 slug"
            )
        }
    }
}
