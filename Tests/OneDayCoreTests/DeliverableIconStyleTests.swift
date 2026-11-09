import OneDayCore
import XCTest

/// 交付物类型图标样式（0.22.0，视觉审计 F2 图标规格）：
/// 扩展名→字形＋身份底色钉死，与 Muse 资源库的类型真
/// 图标对位（DOCX 蓝 W／PPTX 橙 P）。
final class DeliverableIconStyleTests: XCTestCase {

    func testOfficeLetters() {
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "账本.docx"),
            DeliverableIconStyle(
                glyph: .letter("W"), backgroundHex: "2B579A"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "讲稿.PPTX"),
            DeliverableIconStyle(
                glyph: .letter("P"), backgroundHex: "C43E1C"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "表.xlsx"),
            DeliverableIconStyle(
                glyph: .letter("X"), backgroundHex: "217346"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "数据.csv"),
            DeliverableIconStyle(
                glyph: .letter("X"), backgroundHex: "217346"
            )
        )
    }

    func testDocumentSymbols() {
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.pdf"),
            DeliverableIconStyle(
                glyph: .symbol("doc.richtext.fill"),
                backgroundHex: "D92D20"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.md"),
            DeliverableIconStyle(
                glyph: .symbol("doc.text.fill"),
                backgroundHex: "5B6B7A"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.html"),
            DeliverableIconStyle(
                glyph: .symbol("safari.fill"),
                backgroundHex: "1473C8"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.tar.gz"),
            DeliverableIconStyle(
                glyph: .symbol("archivebox.fill"),
                backgroundHex: "6E777D"
            )
        )
    }

    func testMediaSymbols() {
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.png").glyph,
            .symbol("photo.fill")
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.mp4").glyph,
            .symbol("film.fill")
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.mp3").glyph,
            .symbol("waveform")
        )
    }

    func testDirectoryAndFallback() {
        XCTAssertEqual(
            DeliverableIconStyle.style(
                forFileName: "文件夹", isDirectory: true
            ).glyph,
            .symbol("folder.fill")
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "a.unknownext"),
            DeliverableIconStyle(
                glyph: .symbol("doc.fill"), backgroundHex: "949B9F"
            )
        )
        XCTAssertEqual(
            DeliverableIconStyle.style(forFileName: "README").glyph,
            .symbol("doc.fill")
        )
    }
}
