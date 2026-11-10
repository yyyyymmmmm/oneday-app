import XCTest
@testable import OneDayCore

/// 通知文案模板表闸（0.36.7，规格 notifications-
/// page-benchmark §3.2）：§1.2 全部实样＋M3 构造样
/// 本＋表外 op／空 summary／换行／超长各一条，钉
/// 死输出——解析不出禁止直出原文、降级通用句＋
/// 原文进次级详情。
final class NotificationSummaryTests: XCTestCase {

    private func decision(
        title: String, body: String
    ) -> NotificationPresentation {
        NotificationSummary.presentation(
            kind: "write_gate_decision", title: title, body: body
        , locale: Locale(identifier: "zh-Hans"))
    }

    // MARK: - 记忆类实样

    func testM1RejectedSample() {
        // 截图实样：驳回件走未执行语态
        let p = decision(
            title: "记忆写入已被驳回",
            body: "add to memory: P7TEST-reject-me"
        )
        XCTAssertEqual(p.summary, "「P7TEST-reject-me」未写入长期记忆")
        XCTAssertEqual(p.rawDetail, "add to memory: P7TEST-reject-me")
    }

    func testM1Approved() {
        let p = decision(
            title: "记忆写入已批准",
            body: "add to memory: P7TEST-reject-me"
        )
        XCTAssertEqual(p.summary, "「P7TEST-reject-me」已写入长期记忆")
    }

    func testM2UserProfileSample() {
        let p = decision(
            title: "记忆写入已批准",
            body: "remove from user profile: 用户指定的暗号：蓝莓山丘42"
        )
        XCTAssertEqual(
            p.summary, "「用户指定的暗号：蓝莓山丘42」已从用户档案删除"
        )
    }

    func testM2Rejected() {
        let p = decision(
            title: "记忆写入已被驳回",
            body: "remove from memory: 旧地址"
        )
        XCTAssertEqual(p.summary, "「旧地址」未从长期记忆删除")
    }

    func testM3ConstructedSample() {
        let body = "replace in memory: entry matching: 旧条目"
            + "\nwhole entry becomes: 新条目"
        let approved = decision(title: "记忆写入已批准", body: body)
        XCTAssertEqual(
            approved.summary, "长期记忆里的「旧条目」已改为「新条目」"
        )
        let rejected = decision(title: "记忆写入已被驳回", body: body)
        XCTAssertEqual(
            rejected.summary, "长期记忆里的「旧条目」未改为「新条目」"
        )
    }

    func testM4SingleOpSample() {
        let p = decision(
            title: "记忆写入已批准",
            body: "apply 1 op(s) to user profile:"
                + " - add: 用户指定的暗号：蓝莓山丘42"
        )
        XCTAssertEqual(
            p.summary,
            "对用户档案的 1 处改动已生效：新增「用户指定的暗号：蓝莓山丘42」"
        )
    }

    func testM4MultiOpsAggregation() {
        let body = "apply 3 op(s) to memory:"
            + " - add: 甲\n- remove: 乙\n- replace: 丙"
        let approved = decision(title: "记忆写入已批准", body: body)
        XCTAssertEqual(
            approved.summary,
            "对长期记忆的 3 处改动已生效：新增「甲」、删除「乙」等共 3 处"
        )
        let rejected = decision(title: "记忆写入已被驳回", body: body)
        XCTAssertEqual(
            rejected.summary,
            "对长期记忆的 3 处改动未生效：新增「甲」、删除「乙」等共 3 处"
        )
    }

    func testM4CountMismatchFallsBack() {
        let p = decision(
            title: "记忆写入已批准",
            body: "apply 2 op(s) to memory: - add: 只有一条"
        )
        XCTAssertEqual(p.summary, "一项记忆写入已批准")
        XCTAssertEqual(
            p.rawDetail, "apply 2 op(s) to memory: - add: 只有一条"
        )
    }

    func testM4UnknownVerbFallsBack() {
        let p = decision(
            title: "记忆写入已批准",
            body: "apply 1 op(s) to memory: - purge: 全部"
        )
        XCTAssertEqual(p.summary, "一项记忆写入已批准")
    }

    // MARK: - 技能类实样

    func testS1SinglePatchShortForm() {
        let p = decision(
            title: "技能写入已批准",
            body: "batch(1 ops: patch) on weekly-review-planning"
        )
        XCTAssertEqual(
            p.summary, "改了技能「weekly-review-planning」的内容"
        )
    }

    func testS2MultiSkillAggregation() {
        let p = decision(
            title: "技能写入已批准",
            body: "batch(6 ops: patch, patch, patch, patch, patch,"
                + " write_file) on hermes-agent, weekly-review-planning"
        )
        XCTAssertEqual(
            p.summary,
            "更新了技能「hermes-agent」「weekly-review-planning」"
                + "：改了 5 处内容、写了 1 个文件"
        )
    }

    func testS3CreateAndWriteFileCountedSeparately() {
        let p = decision(
            title: "技能写入已批准",
            body: "batch(2 ops: create, write_file) on work-retrospective"
        )
        XCTAssertEqual(
            p.summary,
            "更新了技能「work-retrospective」：新建了 1 个文件、写了 1 个文件"
        )
    }

    func testSkillRejectedUsesNotEffectiveForm() {
        let p = decision(
            title: "技能写入已被驳回",
            body: "batch(2 ops: create, write_file) on work-retrospective"
        )
        XCTAssertEqual(
            p.summary, "技能「work-retrospective」的 2 处改动未生效"
        )
    }

    func testSkillUnknownOpFallsBack() {
        let body = "batch(1 ops: delete_file) on some-skill"
        let p = decision(title: "技能写入已批准", body: body)
        XCTAssertEqual(p.summary, "一项技能写入已批准")
        XCTAssertEqual(p.rawDetail, body)
    }

    func testSkillThreeNamesSuffix() {
        let p = decision(
            title: "技能写入已批准",
            body: "batch(3 ops: patch, patch, patch) on a-one, b-two, c-three"
        )
        XCTAssertEqual(
            p.summary,
            "更新了技能「a-one」「b-two」等共 3 个技能：改了 3 处内容"
        )
    }

    // MARK: - 兜底与文本处理

    func testUnknownGrammarFallsBackWithoutRawLeak() {
        let body = "frobnicate the wombat: yesterday"
        let p = decision(title: "记忆写入已批准", body: body)
        XCTAssertEqual(p.summary, "一项记忆写入已批准")
        XCTAssertFalse(p.summary.contains("frobnicate"))
        XCTAssertEqual(p.rawDetail, body)
    }

    func testUnknownDecisionFallsBackEvenForValidGrammar() {
        // 桥兜底标题：语态不明，模板不得冒充已执行
        let body = "add to memory: 某条"
        let p = decision(title: "写入审批已处理", body: body)
        XCTAssertEqual(p.summary, "一项写入已处理")
        XCTAssertEqual(p.rawDetail, body)
    }

    func testEmptySummaryUsesGenericWithoutRawDetail() {
        let p = decision(title: "记忆写入已批准", body: "")
        XCTAssertEqual(p.summary, "一项记忆写入已批准")
        XCTAssertNil(p.rawDetail)
    }

    func testDetailNewlinesFolded() {
        let p = decision(
            title: "记忆写入已批准",
            body: "add to memory: 第一行\n第二行"
        )
        XCTAssertEqual(p.summary, "「第一行 第二行」已写入长期记忆")
    }

    func testDetailTruncatedAtSixty() {
        let long = String(repeating: "长", count: 70)
        let p = decision(
            title: "记忆写入已批准", body: "add to memory: \(long)"
        )
        let expected = "「" + String(repeating: "长", count: 60)
            + "…」已写入长期记忆"
        XCTAssertEqual(p.summary, expected)
    }

    // MARK: - 监测类直通

    func testMonitorBodyPassesThroughFolded() {
        let p = NotificationSummary.presentation(
            kind: "monitor_change", title: "监测有变化",
            body: "  监测目标\n有  新变化  "
        , locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(p.summary, "监测目标 有 新变化")
        XCTAssertNil(p.rawDetail)
    }

    // MARK: - 按日分组

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func item(
        id: String, createdAt: String
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: "monitor_change", title: "t", body: "b",
            createdAt: createdAt, read: false
        )
    }

    func testGroupingByDayDescending() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 15
        ))!
        let items = [
            item(id: "old", createdAt: "2026-11-08T09:00:00+08:00"),
            item(id: "today2", createdAt: "2026-11-10T14:00:00+08:00"),
            item(id: "yday", createdAt: "2026-11-09T10:00:00+08:00"),
            item(id: "today1", createdAt: "2026-11-10T09:00:00+08:00"),
        ]
        // locale 显式注入（0.42.0 CI 修复）：分组函
        // 数初版无注入点，组头语言随宿主环境漂移、
        // 英文环境下星期档漏出「Sunday」（run
        // 42919829466 实证）；期望形态不变
        let groups = NotificationGrouping.groups(
            notifications: items, now: now, calendar: calendar,
            locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertEqual(groups.map(\.title), ["今天", "昨天", "星期日"])
        XCTAssertEqual(groups[0].items.map(\.id), ["today2", "today1"])
        XCTAssertEqual(groups[1].items.map(\.id), ["yday"])
    }

    func testGroupingUnparseableGoesLastWithRawTitle() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 15
        ))!
        let items = [
            item(id: "bad", createdAt: "not-a-date"),
            item(id: "ok", createdAt: "2026-11-10T09:00:00.500+08:00"),
        ]
        let groups = NotificationGrouping.groups(
            notifications: items, now: now, calendar: calendar
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].items.map(\.id), ["ok"])
        XCTAssertEqual(groups[1].title, "not-a-date")
    }
}
