import XCTest
@testable import OneDayCore

/// §123 闭环包的 Core 钉测：H1 回响规划、H2 通知落点、
/// M2 讨论预填、M3 点子角标增量、N2 定时任务原始值
/// 收口、N3 监测原文预览。纪律与各包一致：真源判定
/// 与文案口径全钉在纯函数层，View 不许各自拼。
final class ClosureLoopTests: XCTestCase {

    // MARK: - H1 GoalEcho

    /// §308 单轨后回响的输入是 GD-2 归属行：completion
    /// 戳在行上（桥回声账的投影），身份就是任务本身
    private func row(
        _ taskId: String, completionEntryAt: Double? = nil
    ) -> BridgeGoalTask {
        BridgeGoalTask(
            taskId: taskId, goalId: "g_1", title: "",
            status: nil, bucket: nil, updatedAt: nil,
            completionEntryAt: completionEntryAt,
            milestoneId: nil
        )
    }

    private func linked(
        _ row: BridgeGoalTask, _ task: KanbanTask?
    ) -> GoalAssociations.LinkedTask {
        GoalAssociations.LinkedTask(row: row, task: task)
    }

    func testEchoPlanDelegatedOnlyWhenStateUnknown() {
        // 任务在板上但还在排队：只落「已安排」，不脑补进展
        let plan = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1"),
                KanbanTask(id: "t_1", title: "打印发言稿", status: "ready")
            )],
            existingKeys: []
        )
        XCTAssertEqual(plan.map(\.kind), [.delegated])
        XCTAssertEqual(
            plan.first?.key, "goalTask:t_1:delegated"
        )
    }

    func testEchoPlanRunningNeedsInputFailed() {
        let running = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1"),
                KanbanTask(id: "t_1", title: "甲", status: "running")
            )],
            existingKeys: []
        )
        XCTAssertEqual(running.map(\.kind), [.delegated, .started])

        let needsInput = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1"),
                KanbanTask(
                    id: "t_1", title: "甲", status: "blocked",
                    blockKind: "needs_input"
                )
            )],
            existingKeys: []
        )
        XCTAssertEqual(
            needsInput.map(\.kind), [.delegated, .needsInput]
        )

        // 失败＝blocked+transient+错误在场的呈现判定
        let failed = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1"),
                KanbanTask(
                    id: "t_1", title: "甲", status: "blocked",
                    blockKind: "transient",
                    lastFailureError: "boom"
                )
            )],
            existingKeys: []
        )
        XCTAssertEqual(failed.map(\.kind), [.delegated, .failed])

        // 普通阻塞不是失败：不落失败回响
        let blocked = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1"),
                KanbanTask(
                    id: "t_1", title: "甲", status: "blocked",
                    blockKind: "dependency"
                )
            )],
            existingKeys: []
        )
        XCTAssertEqual(blocked.map(\.kind), [.delegated])
    }

    func testEchoPlanCompletedOnlyFromBridgeStamp() {
        // 完成只认桥戳：板上状态 done 但行无戳 → 不落完成
        let noStamp = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1"),
                KanbanTask(id: "t_1", title: "甲", status: "done")
            )],
            existingKeys: []
        )
        XCTAssertEqual(noStamp.map(\.kind), [.delegated])
        // 有戳（哪怕任务板没取到任务）→ 落完成
        let stamped = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_gone", completionEntryAt: 99),
                nil
            )],
            existingKeys: []
        )
        XCTAssertEqual(stamped.map(\.kind), [.delegated, .completed])
        XCTAssertEqual(stamped.last?.taskTitle, "")
    }

    func testEchoPlanSkipsExistingKeys() {
        let plan = GoalEcho.plan(
            linkedTasks: [linked(
                row("t_1", completionEntryAt: 5),
                KanbanTask(id: "t_1", title: "甲", status: "done")
            )],
            existingKeys: [
                "goalTask:t_1:delegated", "goalTask:t_1:completed",
            ]
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testEchoTextUsesTitleOrFallback() {
        XCTAssertEqual(
            GoalEcho.text(kind: .completed, taskTitle: "打印发言稿"),
            "《打印发言稿》办完了。"
        )
        XCTAssertEqual(
            GoalEcho.text(kind: .delegated, taskTitle: ""),
            "已安排这件事，进展会记在这里。"
        )
        XCTAssertEqual(
            GoalEcho.text(kind: .failed, taskTitle: "甲"),
            "《甲》执行失败了，详情在目标的关联任务里。"
        )
    }

    // MARK: - §308 归属字段契约

    func testTaskGoalAssignmentDecodesFullAndCleared() throws {
        let decoder = JSONDecoder()
        let full = """
        {"taskId": "t_1", "goalId": "g_1",
         "milestoneId": "ms_1", "assignedAt": 1794200000.0}
        """
        let a = try decoder.decode(
            BridgeTaskGoalAssignment.self, from: Data(full.utf8)
        )
        XCTAssertEqual(a.goalId, "g_1")
        // G-6：milestoneId 已自归属模型移除，旧载荷同
        // 名键解码忽略（能解到这里即证明）
        XCTAssertEqual(a.assignedAt, 1794200000.0)
        let cleared = """
        {"taskId": "t_1", "goalId": null,
         "milestoneId": null, "assignedAt": null}
        """
        let b = try decoder.decode(
            BridgeTaskGoalAssignment.self, from: Data(cleared.utf8)
        )
        XCTAssertNil(b.goalId)
        XCTAssertNil(b.assignedAt)
    }

    func testTaskGoalWriteEncodesExplicitNullGoalId() throws {
        // 清除归属必须显式送 null：桥靠键在不在区分
        // 「清除」与「漏传」（漏传 400），合成编码把
        // nil 键省略掉就会把清除写成漏传
        let data = try JSONEncoder().encode(
            BridgeTaskGoalWrite(goalId: nil)
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertTrue(json.keys.contains("goalId"))
        XCTAssertTrue(json["goalId"] is NSNull)
        let set = try JSONEncoder().encode(
            BridgeTaskGoalWrite(goalId: "g_1")
        )
        let setJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: set)
                as? [String: Any]
        )
        XCTAssertEqual(setJSON["goalId"] as? String, "g_1")
        // G-6：写体不再带 milestoneId 键
        XCTAssertNil(setJSON["milestoneId"])
    }

    func testGoalDelegateRequestEncodes() throws {
        let data = try JSONEncoder().encode(
            BridgeGoalDelegateRequest(
                title: "订场地",
                idempotencyKey: "k-1"
            )
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(json["title"] as? String, "订场地")
        XCTAssertEqual(json["idempotencyKey"] as? String, "k-1")
    }

    func testLinkedTasksOnlyTrustRowGoalId() {
        // 只认行自带的 goalId：混进别的目标的行不进本
        // 目标的关联段，同任务重复行只出一次
        let rows = [
            BridgeGoalTask(
                taskId: "t_1", goalId: "g_1", title: "甲",
                status: nil, bucket: nil, updatedAt: nil,
                milestoneId: nil
            ),
            BridgeGoalTask(
                taskId: "t_2", goalId: "g_2", title: "乙",
                status: nil, bucket: nil, updatedAt: nil,
                milestoneId: nil
            ),
            BridgeGoalTask(
                taskId: "t_1", goalId: "g_1", title: "甲",
                status: nil, bucket: nil, updatedAt: nil,
                milestoneId: nil
            ),
        ]
        let resolved = GoalAssociations.linkedTasks(
            goalID: "g_1", rows: rows, tasks: []
        )
        XCTAssertEqual(resolved.map(\.row.taskId), ["t_1"])
    }

    // MARK: - H2 NotificationDestination

    private func notification(
        kind: String, refId: String? = nil, changeId: String? = nil
    ) -> OverviewNotification {
        OverviewNotification(
            id: "n_1", kind: kind, title: "题", body: "文",
            createdAt: "2026-11-11T00:00:00Z", read: false,
            refId: refId, changeId: changeId
        )
    }

    func testDestinationDecisionReceipt() {
        XCTAssertEqual(
            NotificationDestination.resolve(
                notification(kind: "write_gate_decision", refId: "wg_1")
            ),
            .approvalDecision(id: "wg_1")
        )
        XCTAssertEqual(
            NotificationDestination.resolve(
                notification(kind: "write_gate_decision")
            ),
            .approvalHome
        )
    }

    func testDestinationMonitorChange() {
        XCTAssertEqual(
            NotificationDestination.resolve(
                notification(
                    kind: "monitor_change", refId: "mon_1",
                    changeId: "chg_1"
                )
            ),
            .monitorChange(monitorID: "mon_1", changeID: "chg_1")
        )
        // 存量通知无 refId：只达监测段，不猜具体监测
        let legacy = NotificationDestination.resolve(
            notification(kind: "monitor_change")
        )
        XCTAssertEqual(legacy, .monitorsHome)
        XCTAssertTrue(legacy.hasDestination)
        XCTAssertEqual(
            NotificationDestination.resolve(
                notification(kind: "something_else")
            ),
            .none
        )
    }

    func testNotificationChangeIdDecodes() throws {
        let json = """
        {"id":"mon-x","kind":"monitor_change","title":"t",\
        "body":"b","createdAt":"2026-11-11T00:00:00Z",\
        "read":false,"refId":"mon_1","changeId":"chg_9"}
        """
        let decoded = try JSONDecoder().decode(
            OverviewNotification.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.refId, "mon_1")
        XCTAssertEqual(decoded.changeId, "chg_9")
    }

    // MARK: - M2 FeedDiscussPrefill

    func testPrefillShortBodyFullTextWithBackReference() {
        let text = FeedDiscussPrefill.make(
            title: "短帖", body: "正文一共两句。就这样。"
        )
        XCTAssertTrue(text.hasPrefix("我们来聊聊这篇动态：《短帖》"))
        XCTAssertTrue(text.contains("正文一共两句。就这样。"))
        XCTAssertFalse(text.contains("以下为原帖节选"))
        XCTAssertTrue(text.hasSuffix("（原帖全文在动态页：《短帖》）"))
    }

    func testPrefillEmptyBodyIsTitleOnly() {
        XCTAssertEqual(
            FeedDiscussPrefill.make(title: "只有标题", body: "  "),
            "我们来聊聊这篇动态：《只有标题》"
        )
    }

    func testPrefillLongBodyMarkedExcerptAtSentenceBoundary() {
        let sentence = "这是一个完整的句子。"
        let body = String(repeating: sentence, count: 200) // 2000 字
        let text = FeedDiscussPrefill.make(title: "长帖", body: body)
        XCTAssertTrue(text.contains("（以下为原帖节选）"))
        XCTAssertTrue(text.hasSuffix("（原帖全文在动态页：《长帖》）"))
        // 节选段不切半句：节选以句号收尾
        let excerptPart = text
            .components(separatedBy: "（以下为原帖节选）\n").last?
            .components(separatedBy: "\n\n（原帖全文").first
        XCTAssertNotNil(excerptPart)
        XCTAssertTrue(excerptPart?.hasSuffix("。") == true)
        XCTAssertLessThanOrEqual(
            excerptPart?.count ?? 0, FeedDiscussPrefill.excerptLimit
        )
    }

    // MARK: - M3 IdeasBadge 已退役（§177）
    //
    // testBadgeCountsOnlyNewGeneratedPending 与
    // testBadgeWatermarkAdvancesToNewestGenerated 随
    // 点子底栏角标整套下线删除（用户 2026-11-12 亲
    // 定点子不出现「待阅」呈现——分区/状态字/角标）；
    // Core IdeasBadge 与 AppState 水位制已同步删除

    // MARK: - N2 CronPresentation

    func testEndReasonLabelsCoverProductionAndSourceSet() {
        XCTAssertEqual(
            CronPresentation.endReasonLabel("ws_orphan_reap"),
            "连接失效后被回收"
        )
        XCTAssertEqual(
            CronPresentation.endReasonLabel("completed"), "已完成"
        )
        XCTAssertEqual(
            CronPresentation.endReasonLabel("cron_complete"), "已完成"
        )
        XCTAssertEqual(
            CronPresentation.endReasonLabel("idle_timeout"),
            "空闲超时结束"
        )
        // 未知值落人话兜底，绝不直印原值
        XCTAssertEqual(
            CronPresentation.endReasonLabel("some_future_reason"),
            "已结束"
        )
        XCTAssertNil(CronPresentation.endReasonLabel(nil))
        XCTAssertNil(CronPresentation.endReasonLabel(""))
    }

    func testDeliverLabels() {
        XCTAssertEqual(CronPresentation.deliverLabel("origin"), "原对话")
        XCTAssertEqual(CronPresentation.deliverLabel("local"), "不投递")
        XCTAssertEqual(CronPresentation.deliverLabel("log"), "仅记日志")
        XCTAssertEqual(
            CronPresentation.deliverLabel("telegram:12345"),
            "telegram 对话"
        )
        XCTAssertEqual(
            CronPresentation.deliverLabel("carrier-pigeon"), "指定渠道"
        )
        XCTAssertNil(CronPresentation.deliverLabel(nil))
    }

    func testErrorSummaryFirstLineAndTruncation() {
        XCTAssertEqual(
            CronPresentation.errorSummary("连接超时\nstack line 2"),
            "连接超时"
        )
        XCTAssertEqual(
            CronPresentation.errorSummary("   "), "运行出错"
        )
        let long = String(repeating: "错", count: 200)
        let summary = CronPresentation.errorSummary(long, limit: 90)
        XCTAssertTrue(summary.hasSuffix("…"))
        XCTAssertEqual(summary.count, 91)
    }

    // MARK: - N3 MonitorChangeDetail 预览

    func testMonitorRowsPreviewTruncation() {
        let longText = (1...120)
            .map { "第\($0)行内容" }
            .joined(separator: "\n")
        let change = BridgeMonitorChange(
            id: "chg_1", monitorId: "mon_1", detectedAt: 0,
            summary: "摘要", before: longText, after: "短",
            read: false
        )
        let rows = MonitorChangeDetail.rows(for: change)
        XCTAssertEqual(rows.before, longText)
        XCTAssertTrue(rows.beforeTruncated)
        XCTAssertLessThan(
            rows.beforePreview?.count ?? 0, longText.count
        )
        XCTAssertTrue(rows.beforePreview?.hasSuffix("…") == true)
        XCTAssertFalse(rows.afterTruncated)
        XCTAssertEqual(rows.afterPreview, "短")
    }

    func testMonitorRowsShortTextNotTruncated() {
        let change = BridgeMonitorChange(
            id: "chg_2", monitorId: "mon_1", detectedAt: 0,
            summary: "摘要", before: nil, after: "就这些",
            read: false
        )
        let rows = MonitorChangeDetail.rows(for: change)
        XCTAssertNil(rows.beforePreview)
        XCTAssertFalse(rows.beforeTruncated)
        XCTAssertEqual(rows.afterPreview, "就这些")
    }
}
