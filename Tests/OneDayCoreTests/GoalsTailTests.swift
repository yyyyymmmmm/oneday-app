import OneDayCore
import XCTest

/// GD-3/GD-2 契约与呈现口径测试：简报新字段宽容解码
/// （GD-3 前旧信两键缺失读 nil）、两个新读面解码，
/// 列表摘要（首句≤40 字）与第 N 周（首封＝第 1 周）
final class GoalsTailTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(
        _ type: T.Type, _ json: String
    ) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - GD-3 简报新字段

    func testBriefingDecodesNoteAndOpenedStamp() throws {
        let b = try decode(BridgeBriefing.self, """
        {"id":"b_1","goalId":"g_1","period":"2026-W46",
         "title":"本周信","body":"正文。",
         "createdAt":1700000000.0,
         "note":"依据近 7 天2 条进展、1 项任务变化",
         "lastOpenedAt":1700003600.0}
        """)
        XCTAssertEqual(b.note, "依据近 7 天2 条进展、1 项任务变化")
        XCTAssertEqual(b.lastOpenedAt, 1_700_003_600.0)
    }

    func testPreGD3BriefingDecodesNewFieldsAsNil() throws {
        // GD-3 前落盘的旧信没有两个新键：宽容解码
        // 读 nil，不回填、不编造
        let b = try decode(BridgeBriefing.self, """
        {"id":"b_old","goalId":"g_1","period":"2026-W45",
         "title":"旧信","body":"旧正文。","createdAt":1699900000.0}
        """)
        XCTAssertNil(b.note)
        XCTAssertNil(b.lastOpenedAt)
    }

    func testBriefingNullNoteDecodesAsNil() throws {
        let b = try decode(BridgeBriefing.self, """
        {"id":"b_2","goalId":"g_1","period":"2026-W46",
         "title":"无注信","body":"正文。","createdAt":1700000000.0,
         "note":null,"lastOpenedAt":null}
        """)
        XCTAssertNil(b.note)
        XCTAssertNil(b.lastOpenedAt)
    }

    // MARK: - GD-2 读面解码

    func testGoalTasksDecodeLiveAndOffBoardRows() throws {
        let r = try decode(BridgeGoalTasksResponse.self, """
        {"items":[
          {"taskId":"t_1","linkId":"gl_1","title":"关联任务",
           "status":"running","bucket":"running",
           "updatedAt":1700000800.0,"linkedAt":1700000000.0,
           "milestoneId":null},
          {"taskId":"t_gone","linkId":"gl_2","title":"已下板任务",
           "status":null,"bucket":null,"updatedAt":null,
           "linkedAt":1699990000.0,"milestoneId":"m_1"}
        ]}
        """)
        XCTAssertEqual(r.items.count, 2)
        XCTAssertEqual(r.items[0].status, "running")
        XCTAssertEqual(r.items[0].updatedAt, 1_700_000_800.0)
        XCTAssertEqual(r.items[0].id, "gl_1")
        XCTAssertNil(r.items[1].status)
        XCTAssertNil(r.items[1].updatedAt)
        XCTAssertEqual(r.items[1].milestoneId, "m_1")
    }

    func testUngroupedTasksDecodeBothOrigins() throws {
        let r = try decode(BridgeUngroupedTasksResponse.self, """
        {"items":[
          {"taskId":"t_a","title":"采纳任务","status":"todo",
           "bucket":"waiting","origin":"adopted",
           "ideaId":"i_1","ownerSessionId":null,
           "createdAt":1700000000.0,"updatedAt":null},
          {"taskId":"t_c","title":"对话任务","status":"blocked",
           "bucket":"blocked","origin":"chat",
           "ideaId":null,"ownerSessionId":"s_1",
           "createdAt":1700001000.0,"updatedAt":1700002000.0}
        ],"polledAt":1700003000.0}
        """)
        XCTAssertEqual(r.items.count, 2)
        XCTAssertEqual(r.items[0].origin, .adopted)
        XCTAssertEqual(r.items[0].ideaId, "i_1")
        XCTAssertEqual(r.items[1].origin, .chat)
        XCTAssertEqual(r.items[1].ownerSessionId, "s_1")
        XCTAssertEqual(r.items[1].id, "t_c")
        XCTAssertEqual(r.polledAt, 1_700_003_000.0)
    }

    // MARK: - GD-3 摘要

    func testSummaryTakesFirstSentenceOnly() {
        let body = "第一句说完。第二句不该出现，第三句更不该。"
        XCTAssertEqual(BriefingPresentation.summary(of: body), "第一句说完。")
    }

    func testSummarySkipsBlankParagraphs() {
        let body = "\n\n  本周先做了甲。后面还有很多话，很多很多话。\n\n第二段。"
        XCTAssertEqual(BriefingPresentation.summary(of: body), "本周先做了甲。")
    }

    func testSummaryTruncatesLongSentenceAtLimit() {
        let long = String(repeating: "长", count: 55) + "。"
        let s = BriefingPresentation.summary(of: long)
        XCTAssertEqual(s.count, 41)
        XCTAssertTrue(s.hasSuffix("…"))
    }

    func testSummaryOfEmptyBodyIsEmpty() {
        XCTAssertEqual(BriefingPresentation.summary(of: ""), "")
        XCTAssertEqual(BriefingPresentation.summary(of: "\n \n"), "")
    }

    func testSummaryWithoutTerminatorReturnsWholeUnderLimit() {
        XCTAssertEqual(
            BriefingPresentation.summary(of: "没有句号的一行"),
            "没有句号的一行")
    }

    // MARK: - GD-3 第 N 周

    private func briefing(_ id: String, _ at: Double) -> BridgeBriefing {
        BridgeBriefing(
            id: id, goalId: "g_1", period: "2026-W46",
            title: id, body: "", createdAt: at
        )
    }

    func testWeekIndexCountsFromFirstLetter() {
        // 桥下发降序（最新在前）：首封仍是第 1 周
        let list = [briefing("b_3", 300), briefing("b_2", 200), briefing("b_1", 100)]
        XCTAssertEqual(BriefingPresentation.weekIndex(of: "b_1", in: list), 1)
        XCTAssertEqual(BriefingPresentation.weekIndex(of: "b_2", in: list), 2)
        XCTAssertEqual(BriefingPresentation.weekIndex(of: "b_3", in: list), 3)
    }

    func testWeekIndexUnknownIDIsNil() {
        let list = [briefing("b_1", 100)]
        XCTAssertNil(BriefingPresentation.weekIndex(of: "b_x", in: list))
        XCTAssertNil(BriefingPresentation.weekIndex(of: "b_1", in: []))
    }

    func testWeekIndexSingleLetterIsWeekOne() {
        let list = [briefing("b_1", 100)]
        XCTAssertEqual(BriefingPresentation.weekIndex(of: "b_1", in: list), 1)
    }
}
