import OneDayCore
import XCTest

/// 目标补深契约与呈现口径测试（P2，0.33.0）：桥 P2 全形
/// fixture 按 oneday-bridge P2 上线实测样本落形（status/
/// completedAt/parentId/source/latestEntry 五件＋条目与
/// 简报两集合）。红线：旧载荷（P2 前桥）必须按「active/
/// 顶层/manual/无条目」宽容收下；进展摘要只许来自事实
/// 层（最新条目→备注→里程碑计数），不许编造
final class GoalDepthTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// P2 全形：已完成的子目标，带最新条目嵌入
    private let goalP2JSON = """
    {"id": "g_sub1", "title": "子目标", "note": "",
     "milestones": [{"id": "m_1", "title": "一步", "done": true}],
     "createdAt": 1794200000.0, "updatedAt": 1794300000.0,
     "status": "completed", "completedAt": 1794290000.5,
     "parentId": "g_top1", "source": "chat",
     "latestEntry": {"id": "e_1", "goalId": "g_sub1",
                     "body": "最新进展", "source": "agent",
                     "createdAt": 1794280000.0}}
    """

    /// P2 前旧形：五件全缺
    private let goalLegacyJSON = """
    {"id": "g_old", "title": "旧目标", "note": "旧备注",
     "milestones": [], "createdAt": 1794200000.0,
     "updatedAt": 1794200000.0}
    """

    private func jsonObject<T: Encodable>(
        _ value: T
    ) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func goal(
        _ id: String, status: GoalStatus = .active,
        parentId: String? = nil, note: String = "",
        milestones: [BridgeMilestone] = [],
        latestEntry: BridgeGoalEntry? = nil
    ) -> BridgeGoal {
        BridgeGoal(
            id: id, title: id, note: note, milestones: milestones,
            createdAt: 0, updatedAt: 0, status: status,
            parentId: parentId, latestEntry: latestEntry
        )
    }

    // MARK: - 解码

    func testGoalP2FullShapeDecodes() throws {
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(goalP2JSON.utf8)
        )
        XCTAssertEqual(goal.status, .completed)
        XCTAssertEqual(goal.completedAt, 1794290000.5)
        XCTAssertEqual(goal.parentId, "g_top1")
        XCTAssertEqual(goal.source, .chat)
        XCTAssertEqual(goal.latestEntry?.body, "最新进展")
        XCTAssertEqual(goal.latestEntry?.source, .agent)
    }

    func testGoalLegacyShapeFallsBack() throws {
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(goalLegacyJSON.utf8)
        )
        XCTAssertEqual(goal.status, .active)
        XCTAssertNil(goal.completedAt)
        XCTAssertNil(goal.parentId)
        XCTAssertEqual(goal.source, .manual)
        XCTAssertNil(goal.latestEntry)
    }

    func testGoalUnknownStatusFallsBackToActive() throws {
        let json = """
        {"id": "g_x", "title": "t", "milestones": [],
         "createdAt": 0, "updatedAt": 0, "status": "paused"}
        """
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(json.utf8)
        )
        XCTAssertEqual(goal.status, .active)
    }

    func testEntryDecodesAndToleratesUnknownSource() throws {
        let json = """
        {"id": "e_9", "goalId": "g_1", "body": "推进了",
         "source": "cron", "createdAt": 1794280000.0}
        """
        let entry = try decoder.decode(
            BridgeGoalEntry.self, from: Data(json.utf8)
        )
        XCTAssertEqual(entry.body, "推进了")
        XCTAssertEqual(entry.source, .user)
    }

    func testBriefingDecodes() throws {
        let json = """
        {"id": "b_1", "goalId": "g_1", "period": "2026-W46",
         "title": "本周标题", "body": "正文", "createdAt": 1794300000.0}
        """
        let briefing = try decoder.decode(
            BridgeBriefing.self, from: Data(json.utf8)
        )
        XCTAssertEqual(briefing.period, "2026-W46")
        XCTAssertEqual(briefing.title, "本周标题")
    }

    // MARK: - 请求体

    func testCreateSubgoalCarriesParentAndManualSource() throws {
        let request = BridgeGoalCreateRequest.make(
            title: " 子目标 ", note: "", milestoneTitles: [],
            parentId: "g_top1"
        )
        let object = try jsonObject(request)
        XCTAssertEqual(object["parentId"] as? String, "g_top1")
        XCTAssertEqual(object["source"] as? String, "manual")
        XCTAssertEqual(object["title"] as? String, "子目标")
    }

    func testCreateTopLevelOmitsParentAndSource() throws {
        let request = BridgeGoalCreateRequest.make(
            title: "顶层", note: "", milestoneTitles: []
        )
        let object = try jsonObject(request)
        XCTAssertNil(object["parentId"])
        XCTAssertNil(object["source"])
    }

    func testStatusPatchBodyIsStatusOnly() throws {
        let object = try jsonObject(
            BridgeGoalStatusPatchRequest(status: .completed)
        )
        XCTAssertEqual(object.count, 1)
        XCTAssertEqual(object["status"] as? String, "completed")
    }

    func testUserNoteTrimsAndMarksUser() throws {
        let request = BridgeGoalEntryCreateRequest.userNote("  记一条  ")
        let object = try jsonObject(request)
        XCTAssertEqual(object["body"] as? String, "记一条")
        XCTAssertEqual(object["source"] as? String, "user")
    }

    // MARK: - GoalBoard 呈现口径

    func testGroupedSplitsTopLevelByStatus() {
        let goals = [
            goal("a"),
            goal("b", status: .completed),
            goal("c", parentId: "a"),
            goal("d"),
        ]
        let groups = GoalBoard.grouped(goals)
        XCTAssertEqual(groups.active.map(\.id), ["a", "d"])
        XCTAssertEqual(groups.completed.map(\.id), ["b"])
        XCTAssertEqual(
            GoalBoard.children(of: "a", in: goals).map(\.id), ["c"]
        )
    }

    func testFoldedCapsAtFour() {
        let items = Array(1...7)
        let folded = GoalBoard.folded(items, expanded: false)
        XCTAssertEqual(folded.visible, [1, 2, 3, 4])
        XCTAssertEqual(folded.hiddenCount, 3)
        let expanded = GoalBoard.folded(items, expanded: true)
        XCTAssertEqual(expanded.visible, items)
        XCTAssertEqual(expanded.hiddenCount, 0)
        let small = GoalBoard.folded([1, 2], expanded: false)
        XCTAssertEqual(small.hiddenCount, 0)
    }

    func testSummaryPrefersLatestEntryThenNoteThenMilestones() {
        let entry = BridgeGoalEntry(
            id: "e_1", goalId: "g", body: "最新条目",
            source: .user, createdAt: 1
        )
        let withEntry = goal(
            "g", note: "备注", latestEntry: entry
        )
        XCTAssertEqual(
            GoalBoard.summary(for: withEntry, latestEntry: entry),
            "最新条目"
        )
        let withNote = goal("g", note: "备注")
        XCTAssertEqual(
            GoalBoard.summary(for: withNote, latestEntry: nil), "备注"
        )
        let withMilestones = goal(
            "g",
            milestones: [
                BridgeMilestone(id: "m_1", title: "a", done: true),
                BridgeMilestone(id: "m_2", title: "b", done: false),
            ]
        )
        XCTAssertEqual(
            GoalBoard.summary(for: withMilestones, latestEntry: nil),
            "1/2 里程碑"
        )
        XCTAssertEqual(
            GoalBoard.summary(for: goal("g"), latestEntry: nil), ""
        )
    }

    func testAllMilestonesDone() {
        XCTAssertFalse(GoalBoard.allMilestonesDone(goal("g")))
        XCTAssertTrue(
            GoalBoard.allMilestonesDone(
                goal(
                    "g",
                    milestones: [
                        BridgeMilestone(id: "m", title: "a", done: true)
                    ]
                )
            )
        )
        XCTAssertFalse(
            GoalBoard.allMilestonesDone(
                goal(
                    "g",
                    milestones: [
                        BridgeMilestone(id: "m", title: "a", done: false)
                    ]
                )
            )
        )
    }
}
