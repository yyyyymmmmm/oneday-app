import XCTest
@testable import OneDayCore

/// 国际化钉测（0.42.0）：格式化器三语形态与取词
/// 口的确定性。逻辑测试宿主无字符串目录——目录取
/// 词回落键本身（＝简体源串），故本文件对「词」的
/// 断言只钉回落恒等式；日期/相对时间的语言形态由
/// 系统格式化器（FormatStyle/RelativeDateTime-
/// Formatter）纯函数产出，与宿主目录无关、三语可
/// 钉。目录真值（繁体/英文译文）在 App 宿主内由
/// validate_i18n.py 与目录校验另行把守。
final class I18nFormattingTests: XCTestCase {

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
    private var zhHans: Locale { Locale(identifier: "zh-Hans") }
    private var zhHant: Locale { Locale(identifier: "zh-Hant") }
    private var en: Locale { Locale(identifier: "en") }

    // MARK: - 取词口回落恒等式

    func testL10nFallsBackToSourceKey() {
        XCTAssertEqual(L10n.string("今天", locale: zhHans), "今天")
        XCTAssertEqual(
            L10n.format("昨天 %@", locale: zhHans, "09:41"), "昨天 09:41"
        )
        XCTAssertEqual(
            L10n.string("不存在的键-0.42.0", locale: en), "不存在的键-0.42.0"
        )
    }

    func testLocalizationCandidates() {
        XCTAssertEqual(
            AppLocale.localizationCandidates(for: zhHans).first, "zh-Hans"
        )
        XCTAssertEqual(
            AppLocale.localizationCandidates(for: en), ["en"]
        )
        let tw = AppLocale.localizationCandidates(
            for: Locale(identifier: "zh-Hant-TW")
        )
        XCTAssertEqual(tw.first, "zh-Hant-TW")
        XCTAssertTrue(tw.contains("zh-Hant"))
    }

    // MARK: - 英文形态（系统格式化器产出）

    func testEnglishAbsoluteDates() {
        // 英文绝对日期定版形态＝缩写月名式（主线裁
        // 决）：FormatStyle 月 abbreviated 档在英文
        // 落「Mar」、中文落数字式「3月」，同一拼装
        // 两语各得其形。本测试初版字面误写数字式
        // （「3/5」等），CI run 42919829466 实证实
        // 现产出即缩写月名式——错在字面、已按定版
        // 形态改正，实现未动
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 3, 5), now: now, calendar: calendar, locale: en),
            "Mar 5"
        )
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2025, 12, 31), now: now, calendar: calendar, locale: en),
            "Dec 31, 2025"
        )
        XCTAssertEqual(
            ChatTimeline.dividerText(
                for: date(2026, 3, 5, 12, 30), now: now,
                calendar: calendar, locale: en
            ),
            "Mar 5 12:30"
        )
    }

    func testEnglishWeekdayTier() {
        // 2026-11-07 是星期六（日差 3）
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 11, 7), now: now, calendar: calendar, locale: en),
            "Saturday"
        )
        XCTAssertEqual(
            ChatTimeline.dividerText(
                for: date(2026, 11, 7, 8, 0), now: now,
                calendar: calendar, locale: en
            ),
            "Saturday 08:00"
        )
    }

    func testEnglishRelative() {
        XCTAssertEqual(
            DisplayDate.relative(
                now.addingTimeInterval(-3 * 60), now: now,
                calendar: calendar, locale: en
            ),
            "3 minutes ago"
        )
        XCTAssertEqual(
            DisplayDate.relative(
                now.addingTimeInterval(-60), now: now,
                calendar: calendar, locale: en
            ),
            "1 minute ago"
        )
        let approval = ApprovalTimeText.relative(
            now.addingTimeInterval(-44 * 60), now: now, locale: en
        )
        XCTAssertTrue(approval.contains("minutes"), "实际输出：\(approval)")
    }

    // MARK: - 繁体形态

    func testTraditionalChineseForms() {
        // 星期全称：繁体与简体同为「星期六」——初版
        // 期望误写缩写形「週六」，CI run 42919829466
        // 实证 .weekday(.wide) 在 zh-Hant 下产出
        // 「星期六」，据实证改期望（格式器形态无误）
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 11, 7), now: now, calendar: calendar, locale: zhHant),
            "星期六"
        )
        XCTAssertEqual(
            DisplayDate.dateOnly(date(2026, 3, 5), now: now, calendar: calendar, locale: zhHant),
            "3月5日"
        )
        XCTAssertEqual(
            DisplayDate.relative(
                now.addingTimeInterval(-3 * 60), now: now,
                calendar: calendar, locale: zhHant
            ),
            "3分鐘前"
        )
    }

    // MARK: - 简体相对档新形态（系统格式器无空格）

    func testSimplifiedRelativeUsesSystemFormatterShape() {
        XCTAssertEqual(
            DisplayDate.relative(
                now.addingTimeInterval(-3 * 60), now: now,
                calendar: calendar, locale: zhHans
            ),
            "3分钟前"
        )
        XCTAssertEqual(
            DisplayDate.relative(
                now.addingTimeInterval(-2 * 3600), now: now,
                calendar: calendar, locale: zhHans
            ),
            "2小时前"
        )
    }

    // MARK: - 侧栏月组标题随语言

    func testSidebarMonthLabelsFollowLocale() {
        typealias Item = SidebarGrouping.Item<String>
        let items = [Item(key: "old", updatedAt: date(2026, 9, 15), isPinned: false)]
        let enGroups = SidebarGrouping.groups(
            items: items, now: now, calendar: calendar, locale: en
        )
        XCTAssertEqual(enGroups.map(\.label), ["September"])
        let hansGroups = SidebarGrouping.groups(
            items: items, now: now, calendar: calendar, locale: zhHans
        )
        XCTAssertEqual(hansGroups.map(\.label), ["9月"])
    }
}
