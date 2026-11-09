import OneDayCore
import XCTest

/// soul 宽容解码＋正文分段（phase3-data-design §2）：
/// 回执 schema 未冻结，解码覆盖常见包络；分段只认结构
/// 标题，不许语义猜写、不许按段落数硬切冒充风格。
final class HubSoulTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> ProfileSoulDocument {
        try decoder.decode(ProfileSoulDocument.self, from: Data(json.utf8))
    }

    func testTopLevelStringBody() throws {
        let doc = try decoder.decode(
            ProfileSoulDocument.self, from: Data(#""纯正文""#.utf8)
        )
        XCTAssertEqual(doc.content, "纯正文")
        XCTAssertNil(doc.profileName)
    }

    func testContentKeyPriority() throws {
        let doc = try decode("""
        {"soul": "次选", "content": "首选", "name": "default",
         "extra_field": 42}
        """)
        XCTAssertEqual(doc.content, "首选")
        XCTAssertEqual(doc.profileName, "default")
        XCTAssertEqual(doc.rawMetadata["extra_field"], .number(42))
        XCTAssertNil(doc.rawMetadata["content"])
    }

    func testSoulKeyFallbackAndEmptyBodyIsLegal() throws {
        let doc = try decode(#"{"soul": ""}"#)
        XCTAssertEqual(doc.content, "")
    }

    func testMissingBodyKeysThrows() {
        XCTAssertThrowsError(try decode(#"{"name": "default"}"#))
    }

    func testUpdatedAtVariants() throws {
        let iso = try decode("""
        {"content": "x", "updated_at": "2026-11-09T03:00:00Z"}
        """)
        XCTAssertEqual(
            iso.updatedAt?.timeIntervalSince1970,
            ISO8601DateFormatter().date(from: "2026-11-09T03:00:00Z")?
                .timeIntervalSince1970
        )
        let epoch = try decode(#"{"content": "x", "mtime": 1762700000}"#)
        XCTAssertEqual(epoch.updatedAt?.timeIntervalSince1970, 1762700000)
        let epochMs = try decode(#"{"content": "x", "mtime": 1762700000000}"#)
        XCTAssertEqual(epochMs.updatedAt?.timeIntervalSince1970, 1762700000)
        let none = try decode(#"{"content": "x"}"#)
        XCTAssertNil(none.updatedAt)
    }

    func testSectionSplitByTitles() {
        let sections = SoulSectionParser.parse("""
        前言一句。
        # 人设
        我是管家。
        ## 风格
        说话简洁。
        """)
        XCTAssertEqual(sections.persona, "前言一句。\n我是管家。")
        XCTAssertEqual(sections.style, "说话简洁。")
    }

    func testEnglishTitlesAndUnknownTitleKept() {
        let sections = SoulSectionParser.parse("""
        # Persona
        Calm helper.
        # Notes
        Keep this.
        # Tone
        Short sentences.
        """)
        XCTAssertEqual(sections.persona, "Calm helper.\n# Notes\nKeep this.")
        XCTAssertEqual(sections.style, "Short sentences.")
    }

    func testNoKnownTitleWholeTextIsPersona() {
        let sections = SoulSectionParser.parse("第一段。\n\n第二段。")
        XCTAssertEqual(sections.persona, "第一段。\n\n第二段。")
        XCTAssertNil(sections.style)
        XCTAssertEqual(sections.displayedPersona, "第一段。\n\n第二段。")
    }
}
