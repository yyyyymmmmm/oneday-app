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
}
