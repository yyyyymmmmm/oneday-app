import XCTest
@testable import OneDayCore

/// DisplayDate 相对档闸（0.36.7，铃铛页规格
/// §3.3）：五条边界逐一钉——59/60 秒、59/60 分、
/// 23:59/24:00、跨日界但 elapsed<24h 不许跳「昨
/// 天」、elapsed≥24h 但日差 1 落五档「昨天 HH:mm」。
/// 0.42.0：分/时档改走系统相对格式器（钉注入
/// locale），简体输出无空格（「1分钟前」——旧手
/// 拼「1 分钟前」的空格随系统格式器形态退役，本
/// 文件期望已同步）；断言钉 zh-Hans locale。
final class DisplayDateRelativeTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    /// 固定 now：2026-11-10（周二）15:00 上海
    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 15, minute: 0
        ))!
    }

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    private var zhHans: Locale { Locale(identifier: "zh-Hans") }

    private func rel(_ date: Date) -> String {
        DisplayDate.relative(date, now: now, calendar: calendar, locale: zhHans)
    }

    func testFutureAndJustNow() {
        XCTAssertEqual(rel(ago(-30)), "刚刚")
        XCTAssertEqual(rel(ago(0)), "刚刚")
        XCTAssertEqual(rel(ago(30)), "刚刚")
    }

    func testSecondBoundary() {
        XCTAssertEqual(rel(ago(59)), "刚刚")
        XCTAssertEqual(rel(ago(60)), "1分钟前")
    }

    func testMinutes() {
        XCTAssertEqual(rel(ago(45 * 60)), "45分钟前")
        XCTAssertEqual(rel(ago(59 * 60)), "59分钟前")
    }

    func testHourBoundary() {
        XCTAssertEqual(rel(ago(60 * 60)), "1小时前")
        XCTAssertEqual(rel(ago(5 * 3_600)), "5小时前")
        XCTAssertEqual(rel(ago(10 * 3_600)), "10小时前")
    }

    func testDayBoundaryStaysRelative() {
        // 23:59 已流逝仍在相对档
        XCTAssertEqual(rel(ago(86_340)), "23小时前")
    }

    func testCrossMidnightUnder24hStaysRelative() {
        // 昨 23:00 → 今 04:00 用例的等价构造：now 前
        // 推到 04:00，事件在前一日 23:00（流逝 5h、
        // 日差 1）——不许跳成「昨天」
        let earlyNow = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 4, minute: 0
        ))!
        let event = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 23, minute: 0
        ))!
        XCTAssertEqual(
            DisplayDate.relative(event, now: earlyNow, calendar: calendar, locale: zhHans),
            "5小时前"
        )
    }

    func testExactly24hHandsOffToDateTime() {
        // 流逝恰 24h、日差 1 → 五档「昨天 HH:mm」
        XCTAssertEqual(rel(ago(86_400)), "昨天 15:00")
    }

    func testOver24hWithDayDiffOneUsesDateTime() {
        XCTAssertEqual(rel(ago(25 * 3_600)), "昨天 14:00")
    }
}
