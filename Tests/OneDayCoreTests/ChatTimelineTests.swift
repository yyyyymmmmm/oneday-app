import XCTest
@testable import OneDayCore

/// 聊天时间系统闸（0.30.0）：ChatTimeline 分隔落点
/// （锚点跨度口径：首条恒挂、与上一分隔锚点间隔 >
/// 300 秒再挂）与五档相对文案（今天/昨天/星期/本
/// 年/跨年，含昨天跨月、跨年相对优先边界）。日历钉
/// 死 Asia/Shanghai（UTC+8 无夏令时），now 注入。
final class ChatTimelineTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!
    }

    private func text(_ date: Date, now: Date) -> String {
        ChatTimeline.dividerText(for: date, now: now, calendar: calendar)
    }

    // MARK: - 落点：锚点走查

    func testEmptyAndSingleEntry() {
        XCTAssertEqual(ChatTimeline.dividerIndices(dates: []), [])
        XCTAssertEqual(
            ChatTimeline.dividerIndices(dates: [date(2026, 11, 10, 9)]),
            [0]
        )
    }

    /// 阈值边界：恰 300 秒不挂（须「超过」）、301 秒挂
    func testThresholdBoundaryIsStrictlyGreater() {
        let base = date(2026, 11, 10, 9, 0, 0)
        XCTAssertEqual(
            ChatTimeline.dividerIndices(dates: [
                base, base.addingTimeInterval(300),
            ]),
            [0]
        )
        XCTAssertEqual(
            ChatTimeline.dividerIndices(dates: [
                base, base.addingTimeInterval(301),
            ]),
            [0, 1]
        )
        XCTAssertEqual(
            ChatTimeline.dividerIndices(dates: [
                base, base.addingTimeInterval(299),
            ]),
            [0]
        )
    }

    /// 跨度（锚点）口径钉死：4 分钟一条连发——相邻间
    /// 隔恒 < 300 秒，但距首条锚点 480 秒处必须再挂
    /// （微信「以每 5 分钟为一个跨度」＋腾讯 IM 官方
    /// 文档的锚点算法，见 ChatTimeline 文件头）
    func testAnchorSpanRuleForContinuousChat() {
        let base = date(2026, 11, 10, 9, 0, 0)
        let dates = [0, 240, 480, 720].map {
            base.addingTimeInterval(TimeInterval($0))
        }
        XCTAssertEqual(ChatTimeline.dividerIndices(dates: dates), [0, 2])
    }

    /// 长间隔后锚点重置：挂条以新锚重新计跨度
    func testAnchorResetsAfterDivider() {
        let base = date(2026, 11, 10, 9, 0, 0)
        let dates = [0, 600, 700, 1000].map {
            base.addingTimeInterval(TimeInterval($0))
        }
        // 600 与锚点 0 差 600>300 挂条、锚点移 600；
        // 700 差 100 不挂；1000 差 400>300 挂条
        XCTAssertEqual(ChatTimeline.dividerIndices(dates: dates), [0, 1, 3])
    }

    func testCustomThresholdRespected() {
        let base = date(2026, 11, 10, 9, 0, 0)
        let dates = [base, base.addingTimeInterval(120)]
        XCTAssertEqual(
            ChatTimeline.dividerIndices(dates: dates, threshold: 60),
            [0, 1]
        )
        XCTAssertEqual(
            ChatTimeline.dividerIndices(dates: dates, threshold: 300),
            [0]
        )
    }

    // MARK: - 文案五档

    /// 2026-11-10 是星期二（用户当日实况锚点）
    private var now: Date { date(2026, 11, 10, 12, 0) }

    func testTodayShowsTimeOnly() {
        XCTAssertEqual(text(date(2026, 11, 10, 9, 5), now: now), "09:05")
        XCTAssertEqual(text(date(2026, 11, 10, 0, 0), now: now), "00:00")
    }

    func testYesterday() {
        XCTAssertEqual(
            text(date(2026, 11, 9, 23, 40), now: now), "昨天 23:40"
        )
    }

    /// 昨天跨月：3 月 1 日看 2 月 28 日仍是「昨天」
    func testYesterdayAcrossMonthBoundary() {
        XCTAssertEqual(
            text(
                date(2026, 2, 28, 22, 15),
                now: date(2026, 3, 1, 8, 0)
            ),
            "昨天 22:15"
        )
    }

    /// 7 天内（日差 2...6）走星期档：11-08 周日（差
    /// 2）、11-05 周四（差 5）、11-04 周三（差 6）
    func testWeekdayTierWithinSevenDays() {
        XCTAssertEqual(
            text(date(2026, 11, 8, 10, 0), now: now), "星期日 10:00"
        )
        XCTAssertEqual(
            text(date(2026, 11, 5, 18, 30), now: now), "星期四 18:30"
        )
        XCTAssertEqual(
            text(date(2026, 11, 4, 7, 45), now: now), "星期三 07:45"
        )
    }

    /// 日差 7 起退出星期档、本年内走月日档
    func testSeventhDayFallsToMonthDay() {
        XCTAssertEqual(
            text(date(2026, 11, 3, 9, 0), now: now), "11月3日 09:00"
        )
        XCTAssertEqual(
            text(date(2026, 3, 2, 9, 43), now: now), "3月2日 09:43"
        )
    }

    func testCrossYearShowsFullDate() {
        XCTAssertEqual(
            text(date(2025, 6, 9, 6, 52), now: now), "2025年6月9日 06:52"
        )
    }

    /// 跨年但仍在相对窗口内：相对档优先于年份档——
    /// 2027-01-02 看 2026-12-31（日差 2）走星期档、
    /// 看 2027-01-01（日差 1）走昨天档
    func testCrossYearWithinRelativeWindowPrefersRelative() {
        let newYearNow = date(2027, 1, 2, 10, 0)
        XCTAssertEqual(
            text(date(2026, 12, 31, 23, 59), now: newYearNow),
            "星期四 23:59"
        )
        XCTAssertEqual(
            text(date(2027, 1, 1, 0, 30), now: newYearNow),
            "昨天 00:30"
        )
        // 同一 now 下、跨年且日差已过 7 天：回全日期档
        XCTAssertEqual(
            text(date(2026, 12, 20, 12, 0), now: newYearNow),
            "2026年12月20日 12:00"
        )
    }

    /// 未来条目（时钟漂移）：不编造相对日、只给时刻
    func testFutureDateShowsTimeOnly() {
        XCTAssertEqual(text(date(2026, 11, 10, 12, 30), now: now), "12:30")
        XCTAssertEqual(text(date(2026, 11, 11, 8, 0), now: now), "08:00")
    }
}
