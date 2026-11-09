import OneDayCore
import XCTest

/// oneday-bridge 契约测试（P4/P5，0.11.0）：fixture 按
/// oneday-bridge-rollout-20261109.md 的实测样本逐字落
/// 形（id 前缀 g_/m_/i_、时间 epoch 秒 float、PATCH
/// 后旧里程碑 id 保留且 done=true）。红线：勾选走
/// PATCH 全量替换（已有条 id 必原样带回、新条不带
/// id）；已转标记只进本地编解码、不进任何请求体。
final class OneDayBridgeModelsTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// 实测样本（rollout 记录原文）：POST /goals 201 全形
    private let goalJSON = """
    {"id": "g_735c0a39eb9e", "title": "验收目标", "note": "验收备注",
     "milestones": [{"id": "m_020af9aa0107", "title": "第一步", "done": false},
                    {"id": "m_d04190218c94", "title": "第二步", "done": false}],
     "createdAt": 1794217810.2546644, "updatedAt": 1794217810.2546644}
    """

    /// 实测样本：POST /ideas 201 全形
    private let ideaJSON = """
    {"id": "i_0b42bb7dd610", "title": "验收点子", "detail": "细节",
     "goalId": "g_735c0a39eb9e", "createdAt": 1794217810.2639737}
    """

    private func decodeGoal() throws -> BridgeGoal {
        try decoder.decode(BridgeGoal.self, from: Data(goalJSON.utf8))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - 解码（冻结契约全形）

    func testGoalsResponseDecodesMeasuredShape() throws {
        let data = Data("{\"items\": [\(goalJSON)]}".utf8)
        let response = try decoder.decode(BridgeGoalsResponse.self, from: data)
        XCTAssertEqual(response.items.count, 1)
        let goal = response.items[0]
        XCTAssertEqual(goal.id, "g_735c0a39eb9e")
        XCTAssertEqual(goal.title, "验收目标")
        XCTAssertEqual(goal.note, "验收备注")
        XCTAssertEqual(goal.milestones.count, 2)
        XCTAssertEqual(goal.milestones[0].id, "m_020af9aa0107")
        XCTAssertEqual(goal.milestones[0].done, false)
        XCTAssertEqual(goal.createdAt, 1794217810.2546644)
        XCTAssertEqual(goal.updatedAt, goal.createdAt)
    }

    func testGoalDecodesMissingNoteAndMilestonesAsEmpty() throws {
        let data = Data(
            "{\"id\": \"g_x\", \"title\": \"只有标题\", \"createdAt\": 1.5, \"updatedAt\": 2.5}".utf8
        )
        let goal = try decoder.decode(BridgeGoal.self, from: data)
        XCTAssertEqual(goal.note, "")
        XCTAssertEqual(goal.milestones, [])
    }

    func testIdeaDecodesLinkedAndUnlinked() throws {
        let linked = try decoder.decode(
            BridgeIdea.self, from: Data(ideaJSON.utf8)
        )
        XCTAssertEqual(linked.goalId, "g_735c0a39eb9e")
        XCTAssertEqual(linked.detail, "细节")

        let unlinkedJSON = """
        {"id": "i_1", "title": "不关联", "detail": "", "goalId": null, "createdAt": 3.0}
        """
        let unlinked = try decoder.decode(
            BridgeIdea.self, from: Data(unlinkedJSON.utf8)
        )
        XCTAssertNil(unlinked.goalId)
    }

    func testIdeasResponseAndOKResponseDecode() throws {
        let data = Data("{\"items\": [\(ideaJSON)]}".utf8)
        let response = try decoder.decode(BridgeIdeasResponse.self, from: data)
        XCTAssertEqual(response.items.map(\.id), ["i_0b42bb7dd610"])
        let ok = try decoder.decode(
            BridgeOKResponse.self, from: Data("{\"ok\": true}".utf8)
        )
        XCTAssertTrue(ok.ok)
    }

    // MARK: - 进度派生

    func testGoalProgressCountsAndFraction() throws {
        let goal = try decodeGoal()
        XCTAssertEqual(GoalProgress.counts(of: goal).done, 0)
        XCTAssertEqual(GoalProgress.counts(of: goal).total, 2)
        XCTAssertEqual(GoalProgress.fraction(of: goal), 0)
        XCTAssertEqual(GoalProgress.text(of: goal), "0/2")

        let half = BridgeGoal(
            id: "g_h", title: "半程", note: "",
            milestones: [
                BridgeMilestone(id: "m_1", title: "一", done: true),
                BridgeMilestone(id: "m_2", title: "二", done: false),
            ],
            createdAt: 0, updatedAt: 0
        )
        XCTAssertEqual(GoalProgress.fraction(of: half), 0.5)
        XCTAssertEqual(GoalProgress.text(of: half), "1/2")

        let empty = BridgeGoal(
            id: "g_e", title: "空", note: "", milestones: [],
            createdAt: 0, updatedAt: 0
        )
        // 0/0 不冒充完成：fraction 恒 0
        XCTAssertEqual(GoalProgress.fraction(of: empty), 0)
        XCTAssertEqual(GoalProgress.text(of: empty), "0/0")
    }

    // MARK: - 勾选 PATCH 体组装（全量替换＋id 原样带回）

    func testTogglePlanFlipsOneAndKeepsIDs() throws {
        let goal = try decodeGoal()
        let plan = try XCTUnwrap(
            GoalPatchPlan.toggle(goal: goal, milestoneID: "m_020af9aa0107")
        )
        XCTAssertEqual(plan.title, "验收目标")
        XCTAssertEqual(plan.note, "验收备注")
        XCTAssertEqual(plan.milestones.count, 2)
        // 勾选对齐靠 id：两条 id 都原样带回
        XCTAssertEqual(plan.milestones[0].id, "m_020af9aa0107")
        XCTAssertEqual(plan.milestones[0].done, true)
        XCTAssertEqual(plan.milestones[1].id, "m_d04190218c94")
        XCTAssertEqual(plan.milestones[1].done, false)

        let object = try jsonObject(plan)
        let milestones = try XCTUnwrap(object["milestones"] as? [[String: Any]])
        XCTAssertEqual(milestones[0]["id"] as? String, "m_020af9aa0107")
        XCTAssertEqual(milestones[0]["done"] as? Bool, true)
    }

    func testTogglePlanUnknownIDReturnsNil() throws {
        let goal = try decodeGoal()
        XCTAssertNil(GoalPatchPlan.toggle(goal: goal, milestoneID: "m_nope"))
    }

    func testUpdatePlanNewMilestoneOmitsIDAndDropsBlankTitles() throws {
        let plan = GoalPatchPlan.update(
            title: " 验收目标·改 ",
            note: " 验收备注 ",
            milestones: [
                MilestoneDraftState(id: "m_020af9aa0107", title: "第一步", done: true),
                MilestoneDraftState(id: nil, title: "第三步", done: false),
                MilestoneDraftState(id: nil, title: "  ", done: false),
            ]
        )
        XCTAssertEqual(plan.title, "验收目标·改")
        XCTAssertEqual(plan.note, "验收备注")
        // 空标题行剔除（服务端对空里程碑标题回 400，客户端先收口）
        XCTAssertEqual(plan.milestones.count, 2)

        let object = try jsonObject(plan)
        let milestones = try XCTUnwrap(object["milestones"] as? [[String: Any]])
        XCTAssertEqual(milestones[0]["id"] as? String, "m_020af9aa0107")
        XCTAssertEqual(milestones[0]["done"] as? Bool, true)
        // 新条不带 id 键（服务端据此新生成，契约定版语义 1）
        XCTAssertNil(milestones[1]["id"])
        XCTAssertEqual(milestones[1]["title"] as? String, "第三步")
        XCTAssertEqual(milestones[1]["done"] as? Bool, false)
    }

    // MARK: - 新建请求体收口

    func testGoalCreateRequestOmitsEmptyOptionals() throws {
        let bare = BridgeGoalCreateRequest.make(
            title: " 只有标题 ", note: " ", milestoneTitles: []
        )
        let object = try jsonObject(bare)
        XCTAssertEqual(object["title"] as? String, "只有标题")
        XCTAssertNil(object["note"])
        XCTAssertNil(object["milestones"])

        let full = BridgeGoalCreateRequest.make(
            title: "目标", note: "备注",
            milestoneTitles: [" 第一步 ", "", "第二步"]
        )
        let fullObject = try jsonObject(full)
        XCTAssertEqual(fullObject["note"] as? String, "备注")
        let milestones = try XCTUnwrap(
            fullObject["milestones"] as? [[String: Any]]
        )
        // 草稿里程碑只有 title 键（id/done 由服务端定）
        XCTAssertEqual(milestones.count, 2)
        XCTAssertEqual(milestones[0].keys.sorted(), ["title"])
        XCTAssertEqual(milestones[0]["title"] as? String, "第一步")
    }

    func testIdeaCreateRequestOmitsNilGoalAndEmptyDetail() throws {
        let bare = BridgeIdeaCreateRequest.make(
            title: "点子", detail: " ", goalId: nil
        )
        let object = try jsonObject(bare)
        XCTAssertNil(object["detail"])
        XCTAssertNil(object["goalId"])

        let linked = BridgeIdeaCreateRequest.make(
            title: "点子", detail: "细节", goalId: "g_735c0a39eb9e"
        )
        let linkedObject = try jsonObject(linked)
        XCTAssertEqual(linkedObject["detail"] as? String, "细节")
        XCTAssertEqual(linkedObject["goalId"] as? String, "g_735c0a39eb9e")
    }

    // MARK: - 转任务计划

    func testIdeaTaskPlanComposesBody() throws {
        let idea = try decoder.decode(
            BridgeIdea.self, from: Data(ideaJSON.utf8)
        )
        let plan = IdeaTaskPlan.make(idea: idea, goalTitle: "验收目标")
        XCTAssertEqual(plan.title, "验收点子")
        XCTAssertEqual(plan.body, "细节\n关联目标：验收目标\n来源：点子")

        // 目标名解析不到（已被删/未拉到）：不编名，只留来源行
        let unresolved = IdeaTaskPlan.make(idea: idea, goalTitle: nil)
        XCTAssertEqual(unresolved.body, "细节\n来源：点子")

        let bare = BridgeIdea(
            id: "i_2", title: "裸点子", detail: "", goalId: nil,
            createdAt: 0
        )
        let barePlan = IdeaTaskPlan.make(idea: bare, goalTitle: nil)
        XCTAssertEqual(barePlan.body, "来源：点子")
    }

    // MARK: - 已转标记本地编解码

    func testConversionMarksRoundTrip() {
        XCTAssertEqual(
            IdeaConversionMarks.encode(["i_b", "i_a", "i_b"]),
            ["i_a", "i_b"]
        )
        XCTAssertEqual(
            IdeaConversionMarks.decode(["i_a", "", "i_b"]),
            ["i_a", "i_b"]
        )
        XCTAssertEqual(IdeaConversionMarks.decode(nil), [])
        XCTAssertEqual(
            IdeaConversionMarks.decode(
                IdeaConversionMarks.encode(["i_x"])
            ),
            ["i_x"]
        )
    }
}
