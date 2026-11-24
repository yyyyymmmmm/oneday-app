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

/// 改名写口（§383 包一）：校验与标题行手术与桥
/// _validate_new_name/_find_title_line 逐条同
/// 口径的把守——迁直连后规则在 App 侧，漂移即
/// 服务端行为变化
final class AgentNameWriteTests: XCTestCase {

    func testValidatedNewNameAcceptsAndTrims() throws {
        XCTAssertEqual(
            try AgentName.validatedNewName(" 三狗 "), "三狗"
        )
        XCTAssertEqual(
            try AgentName.validatedNewName("Hermes 助手"),
            "Hermes 助手"
        )
        let twenty = String(repeating: "名", count: 20)
        XCTAssertEqual(
            try AgentName.validatedNewName(twenty), twenty
        )
    }

    func testValidatedNewNameRejects() {
        XCTAssertThrowsError(
            try AgentName.validatedNewName("  ")
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError, .empty
            )
        }
        XCTAssertThrowsError(
            try AgentName.validatedNewName(
                String(repeating: "名", count: 21)
            )
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError, .tooLong
            )
        }
        XCTAssertThrowsError(
            try AgentName.validatedNewName("小赫。")
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError, .punctuation
            )
        }
        XCTAssertThrowsError(
            try AgentName.validatedNewName("Soul")
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError, .structural
            )
        }
        XCTAssertThrowsError(
            try AgentName.validatedNewName("灵魂")
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError, .structural
            )
        }
        XCTAssertThrowsError(
            try AgentName.validatedNewName("a#b")
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError,
                .illegalCharacter
            )
        }
        XCTAssertThrowsError(
            try AgentName.validatedNewName("a\u{01}b")
        ) { error in
            XCTAssertEqual(
                error as? AgentNameWriteError,
                .illegalCharacter
            )
        }
    }

    func testApplyingNewNameReplacesTitleInWindow() {
        let soul = "# 旧名\n\n正文第一行\n## 小节\n正文"
        XCTAssertEqual(
            AgentName.applyingNewName("新名", to: soul),
            "# 新名\n\n正文第一行\n## 小节\n正文"
        )
    }

    func testApplyingNewNameInsertsWhenNoTitle() {
        let soul = "开头没有标题\n第二行"
        XCTAssertEqual(
            AgentName.applyingNewName("新名", to: soul),
            "# 新名\n开头没有标题\n第二行"
        )
    }

    func testApplyingNewNameTitleBeyondWindowInserts() {
        // 前 3 个非空行之外才出现的一级标题不在窗
        // 口内——按桥口径视为无标题、首行插入
        let soul = "一\n二\n三\n# 远处标题\n正文"
        XCTAssertEqual(
            AgentName.applyingNewName("新名", to: soul),
            "# 新名\n一\n二\n三\n# 远处标题\n正文"
        )
    }

    func testHasIdentityTitleWindow() {
        XCTAssertTrue(
            AgentName.hasIdentityTitle(in: "\n\n# 名\n正文")
        )
        XCTAssertFalse(
            AgentName.hasIdentityTitle(in: "一\n二\n三\n# 名")
        )
        XCTAssertFalse(
            AgentName.hasIdentityTitle(in: "## 二级标题\n正文")
        )
    }
}
