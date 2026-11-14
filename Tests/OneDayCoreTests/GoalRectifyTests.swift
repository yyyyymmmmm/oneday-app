import OneDayCore
import XCTest

/// 目标整改包契约测试（§233，2026-11-14）：GD-1 活动
/// 派生解码（全形/缺失/未知状态词）、GD-1b 关联记录
/// stoppedEntryAt 解码、GA-1/GA-2 目标创建引用
/// （GoalQuote）的拼装口径——块在亲笔前、分类与落桥
/// 约定齐全、不代发（空亲笔只剩块）
final class GoalRectifyTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let zh = Locale(identifier: "zh-Hans")

    /// GD-1 全形：桥 _goal_view.activity 实测样本落形
    private let goalActivityJSON = """
    {"id": "g_1", "title": "目标", "note": "",
     "milestones": [], "createdAt": 1794200000.0,
     "updatedAt": 1794300000.0, "status": "active",
     "completedAt": null, "parentId": null,
     "source": "manual", "category": "health",
     "latestEntry": null,
     "activity": {
       "state": "blocked", "label": "1 件关联任务被阻塞",
       "since": 1794290000.0,
       "focusTask": {"id": "t_1", "title": "写周报",
                     "status": "blocked"},
       "runningCount": 0, "blockedCount": 1,
       "failedCount": 0, "waitingCount": 2,
       "doneCount": 3, "cancelledCount": 0,
       "linkedCount": 6, "missingCount": 1,
       "latestProgress": {"text": "推进了一步",
                          "at": 1794280000.0},
       "lastActivityAt": 1794290000.0,
       "polledAt": 1794295000.0,
       "note": "1 件关联任务不在当前任务板上"}}
    """

    // MARK: - GD-1 活动解码

    func testGoalActivityFullShapeDecodes() throws {
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(goalActivityJSON.utf8)
        )
        let activity = try XCTUnwrap(goal.activity)
        XCTAssertEqual(activity.state, .blocked)
        XCTAssertEqual(activity.label, "1 件关联任务被阻塞")
        XCTAssertEqual(activity.since, 1794290000.0)
        XCTAssertEqual(activity.focusTask?.id, "t_1")
        XCTAssertEqual(activity.focusTask?.title, "写周报")
        XCTAssertEqual(activity.focusTask?.status, "blocked")
        XCTAssertEqual(activity.blockedCount, 1)
        XCTAssertEqual(activity.waitingCount, 2)
        XCTAssertEqual(activity.doneCount, 3)
        XCTAssertEqual(activity.linkedCount, 6)
        XCTAssertEqual(activity.missingCount, 1)
        XCTAssertEqual(activity.latestProgress?.text, "推进了一步")
        XCTAssertEqual(activity.latestProgress?.at, 1794280000.0)
        XCTAssertEqual(activity.polledAt, 1794295000.0)
        XCTAssertEqual(activity.note, "1 件关联任务不在当前任务板上")
    }

    func testGoalWithoutActivityReadsNil() throws {
        let json = """
        {"id": "g_old", "title": "旧目标", "note": "",
         "milestones": [], "createdAt": 1794200000.0,
         "updatedAt": 1794200000.0}
        """
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(json.utf8)
        )
        XCTAssertNil(goal.activity)
    }

    func testGoalActivityUnknownStateFallsBackToIdle() throws {
        let json = """
        {"id": "g_2", "title": "目标", "note": "",
         "milestones": [], "createdAt": 1794200000.0,
         "updatedAt": 1794200000.0,
         "activity": {"state": "flying", "label": "?"}}
        """
        let goal = try decoder.decode(
            BridgeGoal.self, from: Data(json.utf8)
        )
        let activity = try XCTUnwrap(goal.activity)
        XCTAssertEqual(activity.state, .idle)
        XCTAssertEqual(activity.linkedCount, 0)
        XCTAssertNil(activity.focusTask)
        XCTAssertNil(activity.note)
    }

    func testActivityStateTitlesAreSpecWords() {
        XCTAssertEqual(GoalActivityState.running.title, "正在办")
        XCTAssertEqual(GoalActivityState.waiting.title, "等着")
        XCTAssertEqual(GoalActivityState.blocked.title, "卡住了")
        XCTAssertEqual(GoalActivityState.idle.title, "闲置")
    }

    // MARK: - GD-1b 关联记录解码

    func testTaskLinkStoppedEntryDecodes() throws {
        let full = """
        {"id": "gl_1", "goalId": "g_1", "taskId": "t_1",
         "milestoneId": null, "createdAt": 1794200000.0,
         "completionEntryAt": null,
         "stoppedEntryAt": 1794290000.0}
        """
        let link = try decoder.decode(
            BridgeGoalTaskLink.self, from: Data(full.utf8)
        )
        XCTAssertEqual(link.stoppedEntryAt, 1794290000.0)
        let sparse = """
        {"id": "gl_2", "goalId": "g_1", "taskId": "t_2",
         "createdAt": 1794200000.0}
        """
        let old = try decoder.decode(
            BridgeGoalTaskLink.self, from: Data(sparse.utf8)
        )
        XCTAssertNil(old.stoppedEntryAt)
    }

    // MARK: - GA-1/GA-2 目标创建引用

    func testGoalQuoteOutgoingPutsBlockBeforeUserText() {
        let quote = GoalQuote(category: .health)
        let out = GoalQuote.outgoingContent(
            userText: "我想先减重", goalQuote: quote
        )
        XCTAssertTrue(out.hasPrefix("[新建目标：健康]"), out)
        XCTAssertTrue(out.hasSuffix("我想先减重"), out)
        // 落桥约定齐全：分类 rawValue 与 goals_create 都在块里
        XCTAssertTrue(out.contains("health"), out)
        XCTAssertTrue(out.contains("goals_create"), out)
    }

    func testGoalQuoteOutgoingWithoutUserTextIsBlockOnly() {
        let quote = GoalQuote(category: .career)
        let out = GoalQuote.outgoingContent(
            userText: "", goalQuote: quote
        )
        XCTAssertTrue(out.hasPrefix("[新建目标：事业]"), out)
        XCTAssertFalse(out.contains("\n\n"), out)
    }

    func testGoalQuoteOutgoingNilQuoteReturnsUserText() {
        XCTAssertEqual(
            GoalQuote.outgoingContent(
                userText: "亲笔", goalQuote: nil
            ),
            "亲笔"
        )
    }

    func testGoalQuoteDispatchRoutesByCase() {
        let quote = GoalQuote(category: .finance)
        XCTAssertEqual(
            SourceQuote.goal(quote).outgoingContent(
                userText: "问"
            ),
            GoalQuote.outgoingContent(
                userText: "问", goalQuote: quote
            )
        )
    }

    func testEveryCategoryHasIntroLead() {
        for category in GoalCategory.allCases {
            XCTAssertFalse(
                category.introLead(locale: zh).isEmpty,
                "\(category.rawValue) 缺介绍卡首句"
            )
        }
    }
}
