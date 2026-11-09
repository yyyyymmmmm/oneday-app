import XCTest
@testable import OneDayCore

/// 智能体身份名解析（0.6.1）：soul 一级标题是唯一来
/// 源，结构标题/过长/带句读者一律回落 Hermes——标
/// 题位（胶囊/抽屉/活动页）不许出现「默认档案」式
/// 的实体错位名，也不许把 soul 的结构词当名字。
final class AgentIdentityTests: XCTestCase {
    func testSoulHeadingBecomesName() {
        XCTAssertEqual(
            AgentName.resolve(soulContent: "# 三狗\n\n我是常驻代理。"),
            "三狗"
        )
        XCTAssertEqual(
            AgentName.resolve(soulContent: "前言一行\n# Hermes 助手\n正文"),
            "Hermes 助手"
        )
    }

    func testStructuralHeadingsFallBack() {
        XCTAssertEqual(AgentName.resolve(soulContent: "# SOUL.md\n正文"), "Hermes")
        XCTAssertEqual(AgentName.resolve(soulContent: "# 灵魂\n正文"), "Hermes")
        XCTAssertEqual(AgentName.resolve(soulContent: "# Identity\n正文"), "Hermes")
        XCTAssertEqual(AgentName.resolve(soulContent: "## 二级标题不算\n正文"), "Hermes")
    }

    func testSentenceOrOverlongHeadingsFallBack() {
        XCTAssertEqual(
            AgentName.resolve(soulContent: "# 我是住在服务器里的代理。\n正文"),
            "Hermes"
        )
        XCTAssertEqual(
            AgentName.resolve(soulContent: "# 这是一个非常非常长的标题超过二十字上限不会被采用的"),
            "Hermes"
        )
    }

    func testMissingContentFallsBack() {
        XCTAssertEqual(AgentName.resolve(soulContent: nil), "Hermes")
        XCTAssertEqual(AgentName.resolve(soulContent: ""), "Hermes")
        XCTAssertEqual(AgentName.resolve(soulContent: "没有标题的正文"), "Hermes")
        XCTAssertEqual(AgentName.fallback, "Hermes")
    }
}
