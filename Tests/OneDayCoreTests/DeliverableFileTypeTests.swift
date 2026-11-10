import OneDayCore
import XCTest

/// 交付物行类型小字（0.20.0 第七条，照 Muse 资源库
/// Files 图）：扩展名大写即类型词；无扩展名给「文件」。
final class DeliverableFileTypeTests: XCTestCase {

    func testUppercasesExtension() {
        XCTAssertEqual(DeliverableFileType.label(forFileName: "复盘.docx"), "DOCX")
        XCTAssertEqual(DeliverableFileType.label(forFileName: "deck.Pptx"), "PPTX")
        XCTAssertEqual(DeliverableFileType.label(forFileName: "报告.pdf"), "PDF")
        XCTAssertEqual(DeliverableFileType.label(forFileName: "a.tar.gz"), "GZ")
    }

    func testMissingExtensionFallsBack() {
        XCTAssertEqual(DeliverableFileType.label(forFileName: "README"), "文件")
        XCTAssertEqual(DeliverableFileType.label(forFileName: ".env"), "文件")
    }

    // MARK: 展示标题（0.36.31 §4.3：去扩展名、尾巴进类型签）

    func testDisplayTitleStripsExtension() {
        XCTAssertEqual(
            DeliverableFileType.displayTitle(forFileName: "复盘.docx"),
            "复盘"
        )
        XCTAssertEqual(
            DeliverableFileType.displayTitle(forFileName: "报告.pdf"),
            "报告"
        )
        // 双扩展只去末段，与类型签 GZ 对位
        XCTAssertEqual(
            DeliverableFileType.displayTitle(forFileName: "a.tar.gz"),
            "a.tar"
        )
    }

    func testDisplayTitleKeepsExtensionlessAndDotfiles() {
        XCTAssertEqual(
            DeliverableFileType.displayTitle(forFileName: "README"),
            "README"
        )
        XCTAssertEqual(
            DeliverableFileType.displayTitle(forFileName: ".env"),
            ".env"
        )
    }
}
