import OneDayCore
import XCTest

/// Kanban 契约测试（P3，0.10.0）：fixture 按
/// kanban-spike-20261109.md 记录的真实形状落字——
/// 列集合八列、dispatch 回执 spawned 数组形态、
/// done 任务 latest_summary＝"SPIKE OK"（spike
/// 实测原文）、字段名用 db 列名 snake_case。红线：
/// 失败只许由 blocked＋transient＋失败原文翻译、
/// pause 不存在（动作集无暂停）、接管只闸派发类。
final class KanbanModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    // GET /board 按列分组形（columns 数组＋列内 tasks）
    private let boardGroupedJSON = """
    {"board": {"slug": "oneday", "name": "OneDay"},
     "columns": [
       {"key": "ready", "tasks": [
         {"id": "t_que1", "title": "检查某网页有没有更新",
          "body": "打开页面比对标题", "status": "ready",
          "assignee": "default", "priority": 0,
          "created_at": 1794150000}
       ]},
       {"key": "running", "tasks": [
         {"id": "t_run1", "title": "整理下载目录文件清单",
          "body": "", "status": "running", "assignee": "default",
          "current_run_id": 12, "created_at": 1794151000,
          "started_at": 1794151060}
       ]},
       {"key": "blocked", "tasks": [
         {"id": "t_ask1", "title": "归档旧截图", "body": "",
          "status": "blocked", "block_kind": "needs_input",
          "block_reason": "目标目录是哪一个？",
          "assignee": "default", "created_at": 1794152000}
       ]},
       {"key": "done", "tasks": [
         {"id": "t_09ba947b", "title": "SPIKE 测试任务（验后删除）",
          "body": "", "status": "done", "assignee": "default",
          "latest_summary": "SPIKE OK", "result": "SPIKE OK",
          "completion_contract": "local-only",
          "created_at": 1794149212, "completed_at": 1794149235}
       ]}
     ],
     "latest_event_id": 42}
    """

    // GET /board 平铺形（{tasks:[...]} 兜底形状）
    private let boardFlatJSON = """
    {"tasks": [
       {"id": "t_sch1", "title": "明早九点汇总", "status": "scheduled",
        "assignee": "default", "created_at": "2026-11-09T01:00:00Z"}
     ], "latest_event_id": 7}
    """

    // GET /board 列字典形（{columns:{列名:[...]}}）
    private let boardDictJSON = """
    {"columns": {
       "triage": [
         {"id": "t_tri1", "title": "随手记的想法", "status": "triage",
          "created_at": 1794153000}
       ]
     }, "latest_event_id": 3}
    """

    // MARK: - 板快照解码（三形＋游标）

    func testBoardGroupedShapeDecodes() throws {
        let snapshot = try decoder.decode(
            KanbanBoardSnapshot.self, from: Data(boardGroupedJSON.utf8)
        )
        XCTAssertEqual(snapshot.tasks.count, 4)
        XCTAssertEqual(snapshot.latestEventId, 42)
        let byId = Dictionary(
            uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0) }
        )
        XCTAssertEqual(byId["t_run1"]?.presentation, .running)
        XCTAssertEqual(byId["t_run1"]?.currentRunId, 12)
        XCTAssertEqual(byId["t_ask1"]?.presentation, .needsInput)
        XCTAssertEqual(byId["t_que1"]?.presentation, .queued)
        // spike 实测原文：done 任务摘要就是 worker 真回复
        XCTAssertEqual(byId["t_09ba947b"]?.latestSummary, "SPIKE OK")
        XCTAssertEqual(byId["t_09ba947b"]?.summaryText, "SPIKE OK")
        XCTAssertNotNil(byId["t_09ba947b"]?.completedAt)
    }

    func testBoardFlatShapeAndISOTime() throws {
        let snapshot = try decoder.decode(
            KanbanBoardSnapshot.self, from: Data(boardFlatJSON.utf8)
        )
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.latestEventId, 7)
        XCTAssertEqual(snapshot.tasks[0].presentation, .scheduled)
        // ISO8601 串与纪元秒同认（时间口径宽容）
        XCTAssertNotNil(snapshot.tasks[0].createdAt)
    }

    func testBoardDictColumnsShape() throws {
        let snapshot = try decoder.decode(
            KanbanBoardSnapshot.self, from: Data(boardDictJSON.utf8)
        )
        XCTAssertEqual(snapshot.tasks.map(\.id), ["t_tri1"])
        XCTAssertEqual(snapshot.tasks[0].presentation, .triage)
    }

    func testBoardUnknownShapeYieldsEmptyNotCrash() throws {
        let snapshot = try decoder.decode(
            KanbanBoardSnapshot.self, from: Data(#"{"nope": 1}"#.utf8)
        )
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertNil(snapshot.latestEventId)
    }

    // MARK: - 状态译名（spike 冻结表）

    func testPresentationMapping() {
        let cases: [(String, String?, String?, KanbanStatusPresentation)] = [
            ("ready", nil, nil, .queued),
            ("running", nil, nil, .running),
            ("review", nil, nil, .review),
            ("done", nil, nil, .done),
            ("scheduled", nil, nil, .scheduled),
            ("todo", nil, nil, .triage),
            ("triage", nil, nil, .triage),
            ("archived", nil, nil, .archived),
            ("blocked", "needs_input", nil, .needsInput),
            ("blocked", "transient", "spawn failed", .failed),
            ("blocked", "transient", nil, .blocked),
            ("blocked", "dependency", nil, .blocked),
            ("blocked", nil, "some error", .blocked),
            ("weird", nil, nil, .unknown("weird")),
        ]
        for (status, kind, error, expected) in cases {
            XCTAssertEqual(
                KanbanStatusPresentation.resolve(
                    status: status, blockKind: kind,
                    lastFailureError: error
                ),
                expected, "status=\(status) kind=\(kind ?? "nil")"
            )
        }
    }

    func testFailedTaskCarriesErrorText() throws {
        let json = """
        {"id": "t_f1", "title": "跑不动的任务", "status": "blocked",
         "block_kind": "transient", "consecutive_failures": 3,
         "last_failure_error": "spawn failed: profile missing"}
        """
        let task = try decoder.decode(
            KanbanTask.self, from: Data(json.utf8)
        )
        XCTAssertEqual(task.presentation, .failed)
        XCTAssertEqual(task.consecutiveFailures, 3)
        XCTAssertEqual(
            task.lastFailureError, "spawn failed: profile missing"
        )
    }

    // MARK: - 分组序

    func testGroupingOrderAndWithinGroupSort() throws {
        let snapshot = try decoder.decode(
            KanbanBoardSnapshot.self, from: Data(boardGroupedJSON.utf8)
        )
        let groups = KanbanBoardGrouping.group(snapshot.tasks)
        XCTAssertEqual(
            groups.map(\.presentation),
            [.needsInput, .running, .queued, .done]
        )
    }

    // MARK: - 板清单与版本探针

    func testBoardListSlugsBothShapes() throws {
        let wrapped = try decoder.decode(
            JSONValue.self,
            from: Data(#"{"boards": [{"slug": "default"}, {"slug": "oneday"}]}"#.utf8)
        )
        XCTAssertEqual(
            KanbanBoardList.slugs(from: wrapped), ["default", "oneday"]
        )
        let bare = try decoder.decode(
            JSONValue.self,
            from: Data(#"[{"slug": "oneday"}]"#.utf8)
        )
        XCTAssertEqual(KanbanBoardList.slugs(from: bare), ["oneday"])
    }

    func testWorkflowProbe() throws {
        let full = try decoder.decode(
            KanbanWorkflow.self,
            from: Data(#"{"columns": ["triage", "todo", "scheduled", "ready", "running", "blocked", "review", "done"]}"#.utf8)
        )
        XCTAssertFalse(KanbanProbe.isDrifted(full))

        let drifted = try decoder.decode(
            KanbanWorkflow.self,
            from: Data(#"{"columns": ["ready", "running", "done"]}"#.utf8)
        )
        XCTAssertTrue(KanbanProbe.isDrifted(drifted))

        // 形状未认出：不判漂移、不硬崩（spike 缺口 5）
        let unknown = try decoder.decode(
            KanbanWorkflow.self, from: Data(#"{"nope": 1}"#.utf8)
        )
        XCTAssertNil(unknown.statusNames)
        XCTAssertFalse(KanbanProbe.isDrifted(unknown))

        // 对象形列元素（{key: ...}）同样提取
        let objects = try decoder.decode(
            KanbanWorkflow.self,
            from: Data(#"{"statuses": [{"key": "ready"}, {"key": "running"}, {"key": "blocked"}, {"key": "review"}, {"key": "done"}]}"#.utf8)
        )
        XCTAssertFalse(KanbanProbe.isDrifted(objects))
    }

    // MARK: - 详情（问题提取＋证据拼装）

    /// 验收实案形状（P3 生产验收 2026-11-09，任务
    /// t_e62a9001）：task 对象**没有** block_reason
    /// 字段；问题原文在 blocked 事件的 payload.
    /// reason（{reason, kind:"needs_input"}）与
    /// blocked run 的 summary，两处同文。
    private let detailNeedsInputJSON = """
    {"task": {"id": "t_e62a9001", "title": "P3TEST needs_input 链验收任务",
              "status": "blocked",
              "block_kind": "needs_input",
              "assignee": "default", "created_at": 1794152000},
     "comments": [
       {"id": 1, "author": "default", "body": "我先确认一个数",
        "created_at": 1794152050}
     ],
     "events": [
       {"id": 3, "kind": "created", "created_at": 1794152000},
       {"id": 9, "kind": "blocked",
        "payload": {"reason": "你的幸运数字是多少？", "kind": "needs_input"},
        "created_at": 1794152100}
     ],
     "runs": [
       {"id": 7, "status": "blocked", "outcome": "blocked",
        "summary": "你的幸运数字是多少？", "started_at": 1794152010,
        "ended_at": 1794152100}
     ]}
    """

    func testDetailDecodeAndPendingQuestion() throws {
        let detail = try decoder.decode(
            KanbanTaskDetail.self, from: Data(detailNeedsInputJSON.utf8)
        )
        XCTAssertEqual(detail.task.id, "t_e62a9001")
        XCTAssertEqual(detail.task.presentation, .needsInput)
        XCTAssertEqual(detail.comments.count, 1)
        XCTAssertEqual(detail.runs.count, 1)
        // 事件 payload 单独解出（问题原文的真实存放处）
        let blocked = detail.events.first { $0.kind == "blocked" }
        XCTAssertEqual(blocked?.payloadReason, "你的幸运数字是多少？")
        XCTAssertEqual(blocked?.payloadKind, "needs_input")
        // 问题取 blocked 事件 payload.reason（优先于评论）
        XCTAssertEqual(detail.pendingQuestion, "你的幸运数字是多少？")
        XCTAssertEqual(detail.blockDetailText, "你的幸运数字是多少？")
    }

    /// 0.18.0 定案回归：即便 task 上宽容解出了
    /// block_reason，也不许用它冒充问题原文——事件
    /// 在场时以事件为准；多条 blocked 事件取最新。
    func testPendingQuestionIgnoresTaskBlockReasonWhenEventsExist() throws {
        let json = """
        {"task": {"id": "t_ask9", "title": "某任务", "status": "blocked",
                  "block_kind": "needs_input",
                  "block_reason": "不该被采用的旧字段",
                  "assignee": "default", "created_at": 1794152000},
         "events": [
           {"id": 8, "kind": "blocked",
            "payload": {"reason": "先前的问题", "kind": "needs_input"},
            "created_at": 1794152050},
           {"id": 9, "kind": "blocked",
            "payload": {"reason": "最新的问题", "kind": "needs_input"},
            "created_at": 1794152100}
         ],
         "runs": []}
        """
        let detail = try decoder.decode(
            KanbanTaskDetail.self, from: Data(json.utf8)
        )
        XCTAssertEqual(detail.pendingQuestion, "最新的问题")
    }

    /// 事件无 payload 时第二来源＝blocked run 的
    /// summary（验收实查同文）；run 也没有才落评论。
    func testPendingQuestionFallsBackToBlockedRunSummary() throws {
        let json = """
        {"task": {"id": "t_ask8", "title": "某任务", "status": "blocked",
                  "block_kind": "needs_input",
                  "assignee": "default", "created_at": 1794152000},
         "comments": [
           {"id": 1, "author": "default", "body": "评论里的话",
            "created_at": 1794152200}
         ],
         "events": [
           {"id": 9, "kind": "blocked", "created_at": 1794152100}
         ],
         "runs": [
           {"id": 7, "status": "blocked", "outcome": "blocked",
            "summary": "运行摘要里的问题", "started_at": 1794152010,
            "ended_at": 1794152100}
         ]}
        """
        let detail = try decoder.decode(
            KanbanTaskDetail.self, from: Data(json.utf8)
        )
        XCTAssertEqual(detail.pendingQuestion, "运行摘要里的问题")
    }

    func testPendingQuestionFallsBackToWorkerComment() throws {
        let json = """
        {"id": "t_ask2", "title": "整理照片", "status": "blocked",
         "block_kind": "needs_input", "created_at": 1794152000,
         "comments": [
           {"id": 1, "author": "oneday", "body": "先放着",
            "created_at": 1794152001},
           {"id": 2, "author": "default", "body": "按年份还是按地点分？",
            "created_at": 1794152200}
         ]}
        """
        let detail = try decoder.decode(
            KanbanTaskDetail.self, from: Data(json.utf8)
        )
        // 裸行形 detail（task 字段在顶层）同样可解；
        // 问题取最近一条非人工评论，不许取到用户自己的话
        XCTAssertEqual(detail.pendingQuestion, "按年份还是按地点分？")
    }

    func testEvidenceAssemblyOrder() throws {
        let json = """
        {"task": {"id": "t_d1", "title": "已完成任务", "status": "done",
                  "result": "清单已生成，共 12 个文件",
                  "created_at": 1794150000,
                  "completed_at": 1794150900},
         "runs": [
           {"id": 1, "status": "done", "outcome": "failed",
            "summary": "第一次超时", "started_at": 1794150100,
            "ended_at": 1794150200},
           {"id": 2, "status": "done", "outcome": "completed",
            "summary": "第二次完成", "started_at": 1794150300,
            "ended_at": 1794150900}
         ],
         "events": [
           {"id": 1, "kind": "created", "created_at": 1794150000},
           {"id": 8, "kind": "completed", "created_at": 1794150900}
         ],
         "attachments": [{"filename": "list.txt"}]}
        """
        let detail = try decoder.decode(
            KanbanTaskDetail.self, from: Data(json.utf8)
        )
        let items = detail.evidenceItems(locale: Locale(identifier: "zh-Hans"))
        // 结果置顶 → 运行新→旧 → 事件新→旧
        XCTAssertEqual(items.first?.kind, .result)
        XCTAssertEqual(items.first?.detail, "清单已生成，共 12 个文件")
        XCTAssertEqual(
            items.filter { $0.kind == .run }.map(\.id), ["run-2", "run-1"]
        )
        XCTAssertEqual(
            items.filter { $0.kind == .event }.map(\.id),
            ["event-8", "event-1"]
        )
        XCTAssertEqual(detail.attachmentNames, ["list.txt"])
        XCTAssertEqual(
            KanbanRunOutcome.label(for: detail.runs[0], locale: Locale(identifier: "zh-Hans")), "失败"
        )
    }

    // MARK: - 派发回执（spike 实测形态）

    func testDispatchReceipt() throws {
        let receipt = try decoder.decode(
            KanbanDispatchReceipt.self,
            from: Data(#"{"spawned": [["t_09ba947b", "default", "/opt/data/kanban/boards/oneday/workspaces/t_09ba947b"]]}"#.utf8)
        )
        XCTAssertEqual(receipt.spawnedCount, 1)
        let empty = try decoder.decode(
            KanbanDispatchReceipt.self,
            from: Data(#"{"spawned": []}"#.utf8)
        )
        XCTAssertEqual(empty.spawnedCount, 0)
    }

    // MARK: - 控制计划（spike 映射逐条）

    private func task(
        status: String, blockKind: String? = nil,
        runId: Int? = nil, failureError: String? = nil
    ) -> KanbanTask {
        KanbanTask(
            id: "t_x", title: "样本", status: status,
            blockKind: blockKind, lastFailureError: failureError,
            currentRunId: runId
        )
    }

    func testControlPlanStop() {
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .stop, task: task(status: "running", runId: 12)
            ),
            [.terminateRun(12)]
        )
        // 无当前 run：退 reclaim 释放 claim（spike 5a）
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .stop, task: task(status: "running")
            ),
            [.reclaim(taskID: "t_x")]
        )
    }

    func testControlPlanCancel() {
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .cancel, task: task(status: "running", runId: 3)
            ),
            [.terminateRun(3), .deleteTask(taskID: "t_x")]
        )
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .cancel, task: task(status: "ready")
            ),
            [.deleteTask(taskID: "t_x")]
        )
    }

    func testControlPlanPatchVerbs() {
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .approve, task: task(status: "review")
            ),
            [.patchStatus(taskID: "t_x", status: "done")]
        )
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .requestChanges, task: task(status: "review")
            ),
            [.patchStatus(taskID: "t_x", status: "ready")]
        )
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .answer,
                task: task(status: "blocked", blockKind: "needs_input")
            ),
            [
                .comment(taskID: "t_x"),
                .patchStatus(taskID: "t_x", status: "ready"),
            ]
        )
        XCTAssertEqual(
            KanbanControlPlan.steps(
                action: .retry,
                task: task(
                    status: "blocked", blockKind: "transient",
                    failureError: "boom"
                )
            ),
            [.patchStatus(taskID: "t_x", status: "ready")]
        )
    }

    // MARK: - 动作策略与闸门

    func testActionSetsPerState() {
        XCTAssertEqual(
            KanbanActionPolicy.actions(for: task(status: "running")),
            [.stop, .cancel]
        )
        XCTAssertEqual(
            KanbanActionPolicy.actions(for: task(status: "review")),
            [.approve, .requestChanges, .cancel]
        )
        XCTAssertEqual(
            KanbanActionPolicy.actions(
                for: task(status: "blocked", blockKind: "needs_input")
            ),
            [.answer, .cancel]
        )
        XCTAssertEqual(
            KanbanActionPolicy.actions(for: task(status: "done")), []
        )
        // 红线：任何状态都不许出现「暂停」（kanban 无此动词）
        for status in ["ready", "running", "blocked", "review", "done"] {
            let titles = KanbanActionPolicy
                .actions(for: task(status: status)).map { $0.title(locale: Locale(identifier: "zh-Hans")) }
            XCTAssertFalse(titles.contains("暂停"), "status=\(status)")
        }
    }

    func testTakeoverGateOnlyBlocksDispatchClass() {
        // 接管中：派发类禁用＋人话原因
        let resume = KanbanActionPolicy.gate(
            action: .resume, takeoverActive: true, readOnly: false
        )
        XCTAssertFalse(resume.enabled)
        XCTAssertEqual(resume.reason, KanbanContract.takeoverReason)
        let create = KanbanActionPolicy.gate(
            action: .create, takeoverActive: true, readOnly: false
        )
        XCTAssertFalse(create.enabled)
        // 收束类照常可用（停止是接管中更该能按的钮）
        let stop = KanbanActionPolicy.gate(
            action: .stop, takeoverActive: true, readOnly: false
        )
        XCTAssertTrue(stop.enabled)
        XCTAssertNil(stop.reason)
        // 无接管：全开
        let free = KanbanActionPolicy.gate(
            action: .retry, takeoverActive: false, readOnly: false
        )
        XCTAssertTrue(free.enabled)
    }

    func testReadOnlyGateBlocksEverything() {
        for action in KanbanAction.allCases {
            let gate = KanbanActionPolicy.gate(
                action: action, takeoverActive: false, readOnly: true
            )
            XCTAssertFalse(gate.enabled, "action=\(action)")
            XCTAssertEqual(gate.reason, KanbanContract.readOnlyReason)
        }
    }

    // MARK: - 创建回执包裹形

    func testTaskWrappedCreateReceipt() throws {
        let task = try decoder.decode(
            KanbanTask.self,
            from: Data(#"{"task": {"id": "t_new1", "title": "新任务", "status": "ready"}}"#.utf8)
        )
        XCTAssertEqual(task.id, "t_new1")
        XCTAssertEqual(task.presentation, .queued)
        XCTAssertEqual(task.displayTitle(locale: Locale(identifier: "zh-Hans")), "新任务")
    }
}
