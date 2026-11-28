import OneDayCore
import XCTest

/// 枢纽页定时段分类器（phase3-data-design §3）：schedule
/// 文法无完整公开样本，分类器必须保守——证据不足落
/// otherRecurring，不许为了迎合三组误分类。
final class HubCronTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func job(_ json: String) throws -> CronJob {
        try decoder.decode(CronJob.self, from: Data(json.utf8))
    }

    private func kind(of json: String) throws -> HubCronKind {
        CronHubClassifier.classify(try job(json)).kind
    }

    /// 对象型 interval（分钟）→ 间隔组＋秒数换算
    func testObjectIntervalMinutes() throws {
        let item = CronHubClassifier.classify(try job("""
        {"id": "a", "name": "巡检", "enabled": true,
         "schedule": {"kind": "interval", "minutes": 360}}
        """))
        XCTAssertEqual(item.kind, .interval)
        XCTAssertEqual(item.interval, 360 * 60)
        XCTAssertEqual(item.intervalText, "每 6 小时")
    }

    /// 对象型 interval：单位优先级毫秒先行（第一个有效正数）
    func testObjectIntervalUnitPriority() throws {
        let item = CronHubClassifier.classify(try job("""
        {"id": "a", "enabled": true,
         "schedule": {"kind": "interval", "seconds": 90, "minutes": 5}}
        """))
        XCTAssertEqual(item.kind, .interval)
        XCTAssertEqual(item.interval, 90)
    }

    /// 字符串 daily cron（分/时定值、日月周全 *）→ 每日
    func testStringDailyCron() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": "0 9 * * *"}
        """), .daily)
    }

    /// 6 段 cron（首段秒忽略）同样判每日
    func testSixFieldDailyCron() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": "30 0 9 * * *"}
        """), .daily)
    }

    /// ISO 一次性时刻串 → 提醒
    func testISOOnceString() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": "2026-11-13T09:00:00+08:00"}
        """), .reminder)
    }

    /// 对象型 once → 提醒；对象型 daily → 每日
    func testObjectOnceAndDaily() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": {"kind": "once", "at": "2026-11-13 09:00"}}
        """), .reminder)
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": {"kind": "daily", "time": "09:00"}}
        """), .daily)
    }

    /// 对象型 cron 表达式字段转字符串规则分类
    func testObjectCronExpression() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true,
         "schedule": {"kind": "cron", "expression": "15 8 * * *"}}
        """), .daily)
    }

    /// 每周 cron → 兜底组，绝不误标每日
    func testWeeklyCronFallsToOther() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": "0 9 * * 1"}
        """), .otherRecurring)
    }

    /// 定日 cron 有 next_run_at 对上 → 提醒；无 next 不归提醒
    func testDatedCronReminderNeedsNextRun() throws {
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": "0 9 13 11 *",
         "next_run_at": "2026-11-13T09:00:00+08:00"}
        """), .reminder)
        XCTAssertEqual(try kind(of: """
        {"id": "a", "enabled": true, "schedule": "0 9 13 11 *"}
        """), .otherRecurring)
    }

    /// every 间隔串
    func testEveryIntervalString() throws {
        let item = CronHubClassifier.classify(try job("""
        {"id": "a", "enabled": true, "schedule": "every 30m"}
        """))
        XCTAssertEqual(item.kind, .interval)
        XCTAssertEqual(item.interval, 30 * 60)
        XCTAssertEqual(item.intervalText, "每 30 分钟")
    }

    /// 空 schedule / 只有 schedule_display → 兜底组，
    /// 展示串仍可读出
    func testMissingScheduleFallsToOther() throws {
        let parsed = try job("""
        {"id": "a", "enabled": true, "schedule_display": "工作日早上"}
        """)
        XCTAssertEqual(CronHubClassifier.classify(parsed).kind, .otherRecurring)
        XCTAssertEqual(parsed.scheduleText, "工作日早上")
    }

    /// 间隔人话：整除取最大单位、不可整除保留原单位
    func testIntervalText() {
        XCTAssertEqual(CronHubClassifier.intervalText(86400), "每 1 天")
        XCTAssertEqual(CronHubClassifier.intervalText(7200), "每 2 小时")
        XCTAssertEqual(CronHubClassifier.intervalText(90), "每 90 秒")
        XCTAssertEqual(CronHubClassifier.intervalText(45), "每 45 秒")
    }

    /// 分组排序：enabled 在前 → nextRunAt 升序；空组不出现
    func testGroupingAndOrder() throws {
        let jobs = try [
            job("""
            {"id": "d2", "name": "晚报", "enabled": true, "schedule": "0 21 * * *",
             "next_run_at": "2026-11-09T21:00:00+08:00"}
            """),
            job("""
            {"id": "d1", "name": "晨报", "enabled": true, "schedule": "0 9 * * *",
             "next_run_at": "2026-11-10T09:00:00+08:00"}
            """),
            job("""
            {"id": "d0", "name": "已停", "enabled": false, "schedule": "0 6 * * *",
             "next_run_at": "2026-11-09T06:00:00+08:00"}
            """),
            job("""
            {"id": "w1", "name": "周会", "enabled": true, "schedule": "0 10 * * 1"}
            """),
        ]
        let groups = CronHubClassifier.grouped(jobs)
        XCTAssertEqual(groups.map(\.kind), [.daily, .otherRecurring])
        XCTAssertEqual(groups[0].items.map(\.id), ["d2", "d1", "d0"])
    }

    // MARK: - 系统任务过滤（C2 补全）

    /// 服务端 is_system 字段优先：true 时隐藏
    func testSystemTaskByServerField() throws {
        let jobs = try [
            job("""
            {"id": "u1", "name": "用户任务", "enabled": true, "schedule": "0 9 * * *",
             "is_system": false}
            """),
            job("""
            {"id": "s1", "name": "OneDay 系统轮询", "enabled": true, "schedule": "*/5 * * * *",
             "is_system": true}
            """),
        ]
        let groups = CronHubClassifier.grouped(jobs)
        // 只有用户任务可见
        XCTAssertEqual(groups.flatMap(\.items).map(\.id), ["u1"])
    }

    /// 启发式兜底：服务端字段缺失时按名字模式判定
    func testSystemTaskByNamePattern() throws {
        let jobs = try [
            job("""
            {"id": "u1", "name": "用户每日任务", "enabled": true, "schedule": "0 9 * * *"}
            """),
            job("""
            {"id": "s1", "name": "OneDay 系统轮询第 3 轮", "enabled": true,
             "schedule": "*/10 * * * *"}
            """),
            job("""
            {"id": "s2", "name": "OneDay 记忆日结", "enabled": true,
             "schedule": "0 2 * * *"}
            """),
            job("""
            {"id": "s3", "name": "OneDay 目标提炼", "enabled": true,
             "schedule": "0 3 * * *"}
            """),
        ]
        let groups = CronHubClassifier.grouped(jobs)
        // 只有用户任务可见，系统任务被过滤
        XCTAssertEqual(groups.flatMap(\.items).map(\.id), ["u1"])
    }

    // MARK: - Cron 表达式翻译器（C2 补全）

    /// 高频 cron：每小时固定分钟
    func testCronTranslatorHourly() {
        XCTAssertEqual(CronTranslator.translate("5 * * * *"), "每小时第 5 分")
        XCTAssertEqual(CronTranslator.translate("0 * * * *"), "每小时整点")
    }

    /// 每周 cron：单个星期
    func testCronTranslatorWeekly() {
        XCTAssertEqual(CronTranslator.translate("30 10 * * 0"), "每周日 10:30")
        XCTAssertEqual(CronTranslator.translate("0 9 * * 1"), "每周一 09:00")
    }

    /// 每周多个星期：列表形态
    func testCronTranslatorMultipleWeekdays() {
        XCTAssertEqual(CronTranslator.translate("0 10 * * 1,3,5"), "每周一、三、五 10:00")
    }

    /// OR 语义：日期和星期同时受限，翻译成并集人话
    func testCronTranslatorOrSemantics() {
        // 每月 1 日或每周一 09:00
        XCTAssertEqual(CronTranslator.translate("0 9 1 * 1"), "每月 1 日 或 每周一 09:00")
        // 每月 15 日或每周五 14:00
        XCTAssertEqual(CronTranslator.translate("0 14 15 * 5"), "每月 15 日 或 每周五 14:00")
    }

    /// 别名展开
    func testCronTranslatorAliases() {
        XCTAssertEqual(CronTranslator.translate("@hourly"), "每小时整点")
        XCTAssertEqual(CronTranslator.translate("@daily"), "每日 00:00")
        XCTAssertEqual(CronTranslator.translate("@weekly"), "每周日 00:00")
    }

    /// 译不出的形态返回 nil（调用方兜底「自定义周期」）
    func testCronTranslatorFallback() {
        // 复杂表达式译不出
        XCTAssertNil(CronTranslator.translate("*/5 9-17 * * 1-5"))
        XCTAssertNil(CronTranslator.translate("@reboot"))
    }

    func testCronTranslatorMinuteStepRange() {
        XCTAssertEqual(
            CronTranslator.translate("0-30/5 * * * *"),
            "每小时 0-30 分每 5 分钟一次"
        )
    }
}
