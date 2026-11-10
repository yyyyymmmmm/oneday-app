import XCTest
@testable import OneDayCore

/// 统一日期格式器闸（0.36.0，审计 C11）：全 App
/// 日期时间只许走 DisplayDate，口径与聊天时间系
/// 统五档一致、英文不漏出。固定日历（公历＋上海
/// 时区）与 now（2026-11-10 周二 15:00）做确定性
/// 断言。
final class DisplayDateFormattingTests: XCTestCase {

    /// 0.42.0：断言钉简体（格式化器 locale 显式注入，
    /// 不随测试运行环境语言漂移）
    private var zhHans: Locale { Locale(identifier: "zh-Hans") }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }

    private var now: Date { date(2026, 11, 10, 15, 0) }

    // MARK: - 全形五档

    func testDateTimeTodayShowsTimeOnly() {
        XCTAssertEqual(
            DisplayDate.dateTime(date(2026, 11, 10, 9, 5), now: now, calendar: calendar, locale: zhHans),
            "09:05"
        )
    }

    func testDateTimeYesterday() {
        XCTAssertEqual(
            DisplayDate.dateTime(date(2026, 11, 9, 23, 40), now: now, calendar: calendar, locale: zhHans),
            "昨天 23:40"
        )
    }

    func testDateTimeWithinWeekShowsWeekday() {
        // 2026-11-07 是星期六（日差 3）
        XCTAssertEqual(
            DisplayDate.dateTime(date(2026, 11, 7, 8, 0), now: now, calendar: calendar, locale: zhHans),
            "星期六 08:00"
        )
    }

    func testDateTimeSameYearShowsMonthDay() {
        XCTAssertEqual(
            DisplayDate.dateTime(date(2026, 3, 5, 12, 30), now: now, calendar: calendar, locale: zhHans),
            "3月5日 12:30"
        )
    }

    func testDateTimeCrossYearShowsFullDate() {
        XCTAssertEqual(
            DisplayDate.dateTime(date(2025, 12, 31, 12, 30), now: now, calendar: calendar, locale: zhHans),
            "2025年12月31日 12:30"
        )
    }

    /// 与聊天时间系统同源：任意日期上两处文案必须逐字一致
    func testDateTimeMatchesChatTimeline() {
        let samples = [
            date(2026, 11, 10, 0, 1), date(2026, 11, 9, 12, 0),
            date(2026, 11, 5, 18, 45), date(2026, 1, 1, 7, 7),
            date(2024, 2, 29, 20, 20),
        ]
        for sample in samples {
            XCTAssertEqual(
                DisplayDate.dateTime(sample, now: now, calendar: calendar, locale: zhHans),
                ChatTimeline.dividerText(for: sample, now: now, calendar: calendar, locale: zhHans),
                "日期 \(sample) 两处口径漂移"
            )
        }
    }

    // MARK: - 日期档

    func testDateOnlyRelativeDays() {
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 11, 10, 9, 0), now: now, calendar: calendar, locale: zhHans),
            "今天"
        )
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 11, 9, 9, 0), now: now, calendar: calendar, locale: zhHans),
            "昨天"
        )
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 11, 11, 9, 0), now: now, calendar: calendar, locale: zhHans),
            "明天"
        )
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 11, 7, 9, 0), now: now, calendar: calendar, locale: zhHans),
            "星期六"
        )
    }

    func testDateOnlyAbsolute() {
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 3, 5), now: now, calendar: calendar, locale: zhHans),
            "3月5日"
        )
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2025, 12, 31), now: now, calendar: calendar, locale: zhHans),
            "2025年12月31日"
        )
        // 未来远期（过期日场景）：落日期本形，不编相对日
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 12, 10), now: now, calendar: calendar, locale: zhHans),
            "12月10日"
        )
    }

    // MARK: - 相对全形与时刻档

    func testRelativeDateTime() {
        XCTAssertEqual(
            DisplayDate.relativeDateTime(date(2026, 11, 10, 9, 5), now: now, calendar: calendar, locale: zhHans),
            "今天 09:05"
        )
        XCTAssertEqual(
            DisplayDate.relativeDateTime(date(2026, 11, 9, 23, 40), now: now, calendar: calendar, locale: zhHans),
            "昨天 23:40"
        )
        XCTAssertEqual(
            DisplayDate.relativeDateTime(date(2026, 11, 7, 8, 0), now: now, calendar: calendar, locale: zhHans),
            "星期六"
        )
        XCTAssertEqual(
            DisplayDate.relativeDateTime(date(2026, 3, 5, 12, 30), now: now, calendar: calendar, locale: zhHans),
            "3月5日"
        )
    }

    func testTimeOnlyZeroPadded() {
        XCTAssertEqual(
            DisplayDate.timeOnly(date(2026, 11, 10, 9, 5), calendar: calendar, locale: zhHans),
            "09:05"
        )
        XCTAssertEqual(
            DisplayDate.timeOnly(date(2026, 11, 10, 23, 59), calendar: calendar, locale: zhHans),
            "23:59"
        )
    }
}
