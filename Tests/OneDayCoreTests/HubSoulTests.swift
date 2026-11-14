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

    // MARK: - 屏上呈现提炼（§218）

    /// 生产形态复刻：首行名标题＋整篇正文（无已知分段
    /// 标题）——名标题段须摘除、`#` 脚手架不许上屏、
    /// 正文按空行分段且一字不改
    func testPresentationDropsNameHeadingAndSplitsParagraphs() {
        let sections = SoulSectionParser.parse("""
        # 三狗
        You are Hermes Agent, built by Nous Research.

        Be direct: answer first.
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        XCTAssertEqual(presentation.introParagraphs, [
            "You are Hermes Agent, built by Nous Research.",
            "Be direct: answer first.",
        ])
        XCTAssertTrue(presentation.styleParagraphs.isEmpty)
        XCTAssertFalse(presentation.isEmpty)
    }

    /// 已知分段标题：人设与风格分别清洗；段内小标题剥
    /// `#` 留文本（不摘除，只有名标题摘除）
    func testPresentationCleansStyleAndInnerHeadings() {
        let sections = SoulSectionParser.parse("""
        # 人设
        ## 我是谁
        住在用户设备里的合伙人。
        # 风格
        直接、克制。
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        XCTAssertEqual(presentation.introParagraphs, ["我是谁\n住在用户设备里的合伙人。"])
        XCTAssertEqual(presentation.styleParagraphs, ["直接、克制。"])
    }

    /// 名标题只在「首段＋纯标题＋与显示名同文」时摘除：
    /// 正文里出现同名句子不动；显示名对不上也不摘
    func testPresentationNameDropIsConservative() {
        let sections = SoulSectionParser.parse("# 三狗\n三狗 是开头一句。")
        let kept = SoulPresentationBuilder.build(
            from: sections, displayName: "别的名"
        )
        XCTAssertEqual(kept.introParagraphs, ["三狗\n三狗 是开头一句。"])
    }

    func testPresentationEmptySoul() {
        let sections = SoulSectionParser.parse("")
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        XCTAssertTrue(presentation.isEmpty)
    }
}
