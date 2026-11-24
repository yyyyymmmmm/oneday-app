import OneDayCore
import XCTest

/// 目标分类流契约与关联拼装测试（0.40.0，规格
/// three-pages-mechanism-v2 第三章）：分类枚举与桥
/// GOAL_CATEGORIES 逐字对齐；BridgeGoal 类别宽容解码
/// （旧载荷/未知值→未分类，绝不推断）；创建/分类 PATCH
/// 请求体落键口径（清除分类必须显式 null）；关联段三路
/// 拼装（点子/监测按 goalId 过滤、任务经 links 反查
/// 任务板现值、取不到如实 nil）
final class GoalCategoryTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private func jsonObject<T: Encodable>(
        _ value: T
    ) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - 分类枚举本体

    func testCategoryRawValuesMatchBridgeEnum() {
        XCTAssertEqual(
            GoalCategory.creationOrder.map(\.rawValue),
            ["health", "relationships", "finance", "career",
             "interest", "efficiency", "other"]
        )
        XCTAssertEqual(
            GoalCategory.creationOrder.map { $0.title(locale: Locale(identifier: "zh-Hans")) },
            ["健康", "人际关系", "财务", "事业", "兴趣", "效率提升", "其他"]
        )
        XCTAssertEqual(
            GoalCategory.creationOrder.map(\.symbolName),
            ["heart", "person.2", "banknote", "briefcase",
             "paintpalette", "laptopcomputer", "ellipsis.circle"]
        )
    }

    func testCategoryFromIsTolerant() {
        XCTAssertEqual(GoalCategory.from("finance"), .finance)
        XCTAssertNil(GoalCategory.from("bogus"))
        XCTAssertNil(GoalCategory.from(""))
        XCTAssertNil(GoalCategory.from(nil))
    }

    // MARK: - BridgeGoal 类别解码

    func testGoalWithCategoryDecodes() throws {
        let json = """
        {"id": "g_1", "title": "存钱", "note": "",
         "milestones": [], "createdAt": 1794200000.0,
         "updatedAt": 1794200000.0, "status": "active",
         "completedAt": null, "parentId": null,
         "source": "manual", "category": "finance",
         "latestEntry": null}
        """
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(json.utf8)
        )
        XCTAssertEqual(goal.category, .finance)
    }

    func testGoalLegacyAndUnknownCategoryReadAsUncategorised() throws {
        let legacy = """
        {"id": "g_old", "title": "旧目标", "note": "",
         "milestones": [], "createdAt": 1794200000.0,
         "updatedAt": 1794200000.0}
        """
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(legacy.utf8)
        )
        XCTAssertNil(goal.category)

        let unknown = """
        {"id": "g_x", "title": "未知类别", "note": "",
         "milestones": [], "createdAt": 1794200000.0,
         "updatedAt": 1794200000.0, "category": "bogus"}
        """
        let goal2 = try decoder.decode(
            BridgeGoal.self, from: Data(unknown.utf8)
        )
        XCTAssertNil(goal2.category)
    }

    // MARK: - 请求体落键口径

    func testCreateRequestCarriesCategoryOnlyWhenSet() throws {
        let withCategory = try jsonObject(
            BridgeGoalCreateRequest.make(
                title: "跑步", note: "",
                category: .health
            )
        )
        XCTAssertEqual(withCategory["category"] as? String, "health")

        let without = try jsonObject(
            BridgeGoalCreateRequest.make(
                title: "跑步", note: ""
            )
        )
        XCTAssertNil(without["category"])
    }

    func testCategoryPatchEncodesExplicitNullForClear() throws {
        let set = try jsonObject(
            BridgeGoalCategoryPatchRequest(category: .career)
        )
        XCTAssertEqual(set["category"] as? String, "career")

        let cleared = try jsonObject(
            BridgeGoalCategoryPatchRequest(category: nil)
        )
        XCTAssertTrue(cleared["category"] is NSNull)
    }

    // MARK: - 关联拼装

    private func idea(_ id: String, goalId: String?) -> BridgeIdea {
        BridgeIdea(
            id: id, title: id, detail: "", goalId: goalId,
            createdAt: 0
        )
    }

    private func monitor(
        _ id: String, goalId: String?
    ) -> BridgeMonitor {
        BridgeMonitor(
            id: id, name: id, target: "", scheduleText: "",
            cronJobId: nil, enabled: true, lastCheckedAt: nil,
            lastResult: nil, lastError: nil, unreadChanges: 0,
            latestChangeSummary: nil, latestChangeAt: nil,
            createdAt: 0, updatedAt: 0, goalId: goalId
        )
    }

    func testAssociationsFilterByGoalId() {
        let ideas = [
            idea("i_1", goalId: "g_1"), idea("i_2", goalId: "g_2"),
            idea("i_3", goalId: nil),
        ]
        XCTAssertEqual(
            GoalAssociations.ideas(for: "g_1", in: ideas).map(\.id),
            ["i_1"]
        )
        let monitors = [
            monitor("m_1", goalId: "g_1"),
            monitor("m_2", goalId: nil),
        ]
        XCTAssertEqual(
            GoalAssociations.monitors(
                for: "g_1", in: monitors
            ).map(\.id),
            ["m_1"]
        )
    }

    func testLinkedTasksResolveAgainstBoard() {
        let rows = [
            BridgeGoalTask(
                taskId: "t_1", goalId: "g_1", title: "打印发言稿",
                status: "done", bucket: "done", updatedAt: nil,
                milestoneId: nil
            ),
            BridgeGoalTask(
                taskId: "t_gone", goalId: "g_1", title: "",
                status: nil, bucket: nil, updatedAt: nil,
                completionEntryAt: 3, milestoneId: "ms_1"
            ),
        ]
        let tasks = [
            KanbanTask(id: "t_1", title: "打印发言稿", status: "done")
        ]
        let resolved = GoalAssociations.linkedTasks(
            goalID: "g_1", rows: rows, tasks: tasks
        )
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].title, "打印发言稿")
        XCTAssertEqual(resolved[0].status, "done")
        // 任务板没取到/任务已不在：如实 nil，不脑补
        XCTAssertNil(resolved[1].task)
        XCTAssertNil(resolved[1].title)
        XCTAssertNil(resolved[1].status)
        XCTAssertEqual(resolved[1].row.milestoneId, "ms_1")
        XCTAssertEqual(resolved[1].row.completionEntryAt, 3)
    }

    func testAssociationsEmptyCheck() {
        XCTAssertTrue(
            GoalAssociations.isEmpty(ideas: [], tasks: [], monitors: [])
        )
        XCTAssertFalse(
            GoalAssociations.isEmpty(
                ideas: [idea("i_1", goalId: "g_1")],
                tasks: [], monitors: []
            )
        )
    }

    // MARK: - 归属字段与监测的解码

    func testTaskGoalAssignmentDecodesFullAndSparse() throws {
        let full = """
        {"taskId": "t_1", "goalId": "g_1",
         "milestoneId": "ms_1", "assignedAt": 1794200000.0}
        """
        let a = try decoder.decode(
            BridgeTaskGoalAssignment.self, from: Data(full.utf8)
        )
        // G-6：milestoneId 已自归属模型移除，旧载荷的
        // 同名键解码忽略（能解到这里即证明）
        XCTAssertEqual(a.assignedAt, 1794200000.0)

        let sparse = """
        {"taskId": "t_2", "goalId": null}
        """
        let b = try decoder.decode(
            BridgeTaskGoalAssignment.self, from: Data(sparse.utf8)
        )
        XCTAssertNil(b.goalId)
        XCTAssertNil(b.assignedAt)
    }

    func testMonitorGoalIdDecodes() throws {
        let json = """
        {"id": "mon_1", "name": "盯价", "target": "https://x",
         "scheduleText": "", "cronJobId": null, "enabled": true,
         "lastCheckedAt": null, "lastResult": null,
         "lastError": null, "unreadChanges": 0,
         "latestChangeSummary": null, "latestChangeAt": null,
         "createdAt": 1794200000.0, "updatedAt": 1794200000.0,
         "goalId": "g_1"}
        """
        let monitor = try decoder.decode(
            BridgeMonitor.self, from: Data(json.utf8)
        )
        XCTAssertEqual(monitor.goalId, "g_1")
    }
}
