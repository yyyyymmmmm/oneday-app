import XCTest
@testable import OneDayCore

/// 通知详情派生闸（§166）：图标类/类别/结果标签/
/// 变更行/落点文案/筛选与副标题。核心纪律钉：变更
/// 行只从文法结构解析派生、不命中即空；技能批多技
/// 能时不许把全批计数摊到单个技能头上。
final class NotificationDetailTests: XCTestCase {

    private let zh = Locale(identifier: "zh-Hans")

    private func item(
        kind: String, title: String, body: String = "",
        read: Bool = true, refId: String? = nil,
        changeId: String? = nil
    ) -> OverviewNotification {
        OverviewNotification(
            id: "n1", kind: kind, title: title, body: body,
            createdAt: "2026-11-11T19:21:00+08:00", read: read,
            refId: refId, changeId: changeId
        )
    }

    // MARK: - 图标类与类别

    func testIconKindByKind() {
        XCTAssertEqual(
            NotificationDetail.iconKind(for: item(
                kind: "write_gate_decision", title: "技能写入已批准")),
            .decision)
        XCTAssertEqual(
            NotificationDetail.iconKind(for: item(
                kind: "monitor_change", title: "监测变化")),
            .monitor)
        XCTAssertEqual(
            NotificationDetail.iconKind(for: item(
                kind: "task_completed", title: "任务完成")),
            .task)
        XCTAssertEqual(
            NotificationDetail.iconKind(for: item(
                kind: "something_else", title: "其他")),
            .other)
    }

    func testCategoryName() {
        XCTAssertEqual(
            NotificationDetail.categoryName(for: item(
                kind: "write_gate_decision", title: "技能写入已批准"),
                locale: zh),
            "审批结果")
        XCTAssertEqual(
            NotificationDetail.categoryName(for: item(
                kind: "monitor_change", title: "监测"), locale: zh),
            "监测变化")
        XCTAssertEqual(
            NotificationDetail.categoryName(for: item(
                kind: "task_completed", title: "任务"), locale: zh),
            "任务结果")
    }

    // MARK: - 结果标签

    func testOutcomeDecision() {
        XCTAssertEqual(
            NotificationDetail.outcome(for: item(
                kind: "write_gate_decision", title: "技能写入已批准")),
            .approved)
        XCTAssertEqual(
            NotificationDetail.outcome(for: item(
                kind: "write_gate_decision", title: "记忆写入已被驳回")),
            .rejected)
        // 语态不明（桥兜底标题）不给标签，不许冒充
        XCTAssertNil(
            NotificationDetail.outcome(for: item(
                kind: "write_gate_decision", title: "写入审批已处理")))
    }

    func testOutcomeMonitorRecovery() {
        XCTAssertEqual(
            NotificationDetail.outcome(for: item(
                kind: "monitor_change", title: "监测恢复",
                body: "健康检查由异常恢复为正常")),
            .recovered)
        XCTAssertNil(
            NotificationDetail.outcome(for: item(
                kind: "monitor_change", title: "监测变化",
                body: "CPU 使用率超过阈值")))
    }

    // MARK: - 变更行：技能批

    func testSkillBatchSingleNameAttribution() {
        let lines = NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "技能写入已批准",
            body: "batch(1 ops: create) on weather-forecast"
        ), locale: zh)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.name, "天气预报")
        XCTAssertEqual(lines.first?.identifier, "weather-forecast")
        XCTAssertEqual(lines.first?.changeDescription, "新建了 1 个文件")
    }

    func testSkillBatchMultiNameNoFalseAttribution() {
        // 三技能 7 处 patch：逐名只列名、描述必须为空
        // ——全批计数摊到单个技能头上即造假
        let lines = NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "技能写入已批准",
            body: "batch(7 ops: patch, patch, patch, patch, patch, patch, patch) "
                + "on phone-bridge, blocked-page-recovery, home-appliance-vetting"
        ), locale: zh)
        XCTAssertEqual(lines.map(\.name), ["设备连接", "页面恢复", "家电审查"])
        XCTAssertEqual(
            lines.map(\.identifier),
            ["phone-bridge", "blocked-page-recovery", "home-appliance-vetting"])
        XCTAssertTrue(lines.allSatisfy { $0.changeDescription.isEmpty })
    }

    func testSkillBatchUnknownIDPassesThrough() {
        let lines = NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "技能写入已批准",
            body: "batch(2 ops: patch, patch) on some-new-skill"
        ), locale: zh)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.name, "some-new-skill")
        XCTAssertNil(lines.first?.identifier)
        XCTAssertEqual(lines.first?.changeDescription, "改了 2 处内容")
    }

    // MARK: - 变更行：记忆类

    func testMemorySimpleOpLine() {
        let lines = NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "记忆写入已批准",
            body: "add to memory: 偏好中文回答"
        ), locale: zh)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.name, "偏好中文回答")
        XCTAssertEqual(lines.first?.changeDescription, "已新增")
    }

    func testMemoryApplyLines() {
        let lines = NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "记忆写入已被驳回",
            body: "apply 2 op(s) to memory: - add: 条目甲\n- remove: 条目乙"
        ), locale: zh)
        XCTAssertEqual(lines.map(\.name), ["条目甲", "条目乙"])
        XCTAssertEqual(lines.map(\.changeDescription), ["未新增", "未删除"])
    }

    func testMemoryReplaceLine() {
        let lines = NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "记忆写入已批准",
            body: "replace in memory: entry matching: 旧称呼\nwhole entry becomes: 新称呼"
        ), locale: zh)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.name, "旧称呼")
        XCTAssertEqual(lines.first?.changeDescription, "已改为「新称呼」")
    }

    func testChangeLinesEmptyWhenGrammarMisses() {
        // 文法不命中 → 空行集，详情只显摘要，绝不编造
        XCTAssertTrue(NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "技能写入已批准",
            body: "some free-form summary"
        ), locale: zh).isEmpty)
        // 非裁决类恒空（监测变化明细无结构源）
        XCTAssertTrue(NotificationDetail.changeLines(for: item(
            kind: "monitor_change", title: "监测变化",
            body: "健康检查由异常恢复为正常"
        ), locale: zh).isEmpty)
        // 语态不明不落行
        XCTAssertTrue(NotificationDetail.changeLines(for: item(
            kind: "write_gate_decision", title: "写入审批已处理",
            body: "batch(1 ops: create) on weather-forecast"
        ), locale: zh).isEmpty)
    }

    // MARK: - 固定提示与落点文案

    func testApprovalNoteOnlyForDecisions() {
        XCTAssertEqual(
            NotificationDetail.approvalNote(for: item(
                kind: "write_gate_decision", title: "技能写入已批准"),
                locale: zh),
            "审批已结束，不需要再次批准。已批准不等于已执行成功，请核对执行记录。")
        XCTAssertNil(NotificationDetail.approvalNote(for: item(
            kind: "monitor_change", title: "监测变化"), locale: zh))
    }

    func testDestinationLabel() {
        XCTAssertEqual(
            NotificationDetail.destinationLabel(
                destination: .approvalDecision(id: "r1"),
                hasAnchorRoute: false, locale: zh),
            "查看审批记录")
        XCTAssertEqual(
            NotificationDetail.destinationLabel(
                destination: .approvalHome,
                hasAnchorRoute: false, locale: zh),
            "查看审批记录")
        XCTAssertEqual(
            NotificationDetail.destinationLabel(
                destination: .monitorChange(monitorID: "m1", changeID: nil),
                hasAnchorRoute: false, locale: zh),
            "查看监测详情")
        XCTAssertNil(
            NotificationDetail.destinationLabel(
                destination: .none,
                hasAnchorRoute: false, locale: zh))
        // 锚点落点（合并接线后）优先给原对话文案
        XCTAssertEqual(
            NotificationDetail.destinationLabel(
                destination: .approvalDecision(id: "r1"),
                hasAnchorRoute: true, locale: zh),
            "返回关联会话")
    }

    // MARK: - 筛选与副标题

    func testFilter() {
        let items = [
            item(kind: "monitor_change", title: "甲", read: false),
            item(kind: "monitor_change", title: "乙", read: true),
        ]
        XCTAssertEqual(
            NotificationDetail.filtered(items, filter: .all).count, 2)
        XCTAssertEqual(
            NotificationDetail.filtered(items, filter: .unread)
                .map(\.title), ["甲"])
    }

    func testSubtitle() {
        XCTAssertEqual(
            NotificationDetail.subtitle(unreadCount: 3, locale: zh),
            "3 条未读 · 按时间排列")
        XCTAssertEqual(
            NotificationDetail.subtitle(unreadCount: 0, locale: zh),
            "已全部读过 · 按时间排列")
    }
}
