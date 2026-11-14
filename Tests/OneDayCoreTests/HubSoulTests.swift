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

    // MARK: - 真提炼层（§253：系统提示词段收起）

    /// 生产形态复刻：规程段（我怎么工作/学到的伤疤）
    /// 整段收起，人设本体段（我是什么/关系/还不知
    /// 道）原样呈现，收起数如实报
    func testDistillationWithholdsSystemSections() {
        let sections = SoulSectionParser.parse("""
        # SOUL.md

        ## 我是什么
        我是常驻代理，住在用户自己的设备里。

        ## 我怎么工作
        - 结论先行、数字殿后。
        - 只写亲眼验证过的。

        ## 我学到的伤疤
        - 拿旧口径当现状至少三次。

        ## 我和用户的关系
        我是他的技术合伙人。

        ## 我还不知道的
        - 我的记忆是文件，不是亲历。
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        let joined = presentation.introParagraphs.joined(separator: "\n")
        XCTAssertTrue(joined.contains("我是常驻代理"))
        XCTAssertTrue(joined.contains("技术合伙人"))
        XCTAssertTrue(joined.contains("我的记忆是文件"))
        XCTAssertFalse(joined.contains("结论先行"))
        XCTAssertFalse(joined.contains("拿旧口径当现状"))
        XCTAssertEqual(presentation.withheldSegmentCount, 2)
    }

    /// 无标题前言与未登记标题段一律保留（宁可多呈、
    /// 不可错藏人设本体）
    func testDistillationKeepsPreambleAndUnknownSections() {
        let sections = SoulSectionParser.parse("""
        开头自述，没有标题。

        ## 我喜欢的东西
        喜欢下雨天。

        ## 工具
        只在工具段出现的话。
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        let joined = presentation.introParagraphs.joined(separator: "\n")
        XCTAssertTrue(joined.contains("开头自述"))
        XCTAssertTrue(joined.contains("喜欢下雨天"))
        XCTAssertFalse(joined.contains("只在工具段出现的话"))
        XCTAssertEqual(presentation.withheldSegmentCount, 1)
    }

    /// 全篇皆系统段：回落原文整篇呈现——身份段不许
    /// 被提炼成空白，收起数报 0（没有真的收起）
    func testDistillationAllSystemFallsBackToFullText() {
        let sections = SoulSectionParser.parse("""
        ## 我怎么工作

        守则一：先看证据。
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        let joined = presentation.introParagraphs.joined(separator: "\n")
        XCTAssertTrue(joined.contains("守则一：先看证据。"))
        XCTAssertEqual(presentation.withheldSegmentCount, 0)
        XCTAssertFalse(presentation.isEmpty)
    }

    /// 英文模板的指令性章节同收（How I Work/
    /// Boundaries），本体自述（Core Truths）保留
    func testDistillationEnglishSystemSections() {
        let sections = SoulSectionParser.parse("""
        ## Core Truths
        Be genuinely helpful, not performatively helpful.

        ## How I Work
        Check first, act second.

        ## Boundaries
        Ask before external actions.
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "Hermes"
        )
        let joined = presentation.introParagraphs.joined(separator: "\n")
        XCTAssertTrue(joined.contains("genuinely helpful"))
        XCTAssertFalse(joined.contains("Check first"))
        XCTAssertFalse(joined.contains("Ask before external"))
        XCTAssertEqual(presentation.withheldSegmentCount, 2)
    }

    /// 风格块是呈现本体、不在收起面：人设侧收起系
    /// 统段不影响风格段原文呈现
    func testDistillationLeavesStyleUntouched() {
        let sections = SoulSectionParser.parse("""
        # 人设
        ## 我是什么
        正经人设一句。
        ## 我怎么工作
        守则正文。
        # 风格
        直接、克制。
        """)
        let presentation = SoulPresentationBuilder.build(
            from: sections, displayName: "三狗"
        )
        XCTAssertEqual(
            presentation.introParagraphs, ["我是什么\n正经人设一句。"]
        )
        XCTAssertEqual(presentation.styleParagraphs, ["直接、克制。"])
        XCTAssertEqual(presentation.withheldSegmentCount, 1)
    }
}
