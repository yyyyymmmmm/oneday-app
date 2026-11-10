import Foundation

/// 全 App 日期时间呈现的唯一格式器（0.36.0，宪法审
/// 计 C11／设计宪法 §8；0.42.0 国际化包续编）：此
/// 前 `.formatted(date: .abbreviated, …)` 散落 9
/// 处、随系统 locale 漂移，真机漏出英文「Nov 10,
/// 2026 at 17:02」。自 0.36.0 起所有面向用户的日
/// 期时间只许走本格式器，口径与聊天时间系统
/// （ChatTimeline 五档）完全一致：相对优先。
///
/// 0.42.0 口径调和（与 C11 的关系）：C11 当年定
/// 「中文写定、不随 locale 变脸」，防的是界面中文
/// 时日期漏英文的混排。国际化后本格式器的 locale
/// 一律钉 AppLocale.uiLocale（App 实际解析出的界
/// 面语言）——界面语言与日期/数字语言恒一致，混
/// 排在简体/繁体/英文三语下都不发生；实现全部走
/// 系统格式化器（FormatStyle／RelativeDateTime-
/// Formatter／本地化模板），不许再手拼「M月d日」
/// 式格式串。简体下输出与旧口径逐字一致（单测钉
/// 死），唯一例外：相对档分/时改走系统相对格式器，
/// 简体输出为「3分钟前」（旧手拼为「3 分钟前」，
/// 无空格是系统格式器的既定形态，本包有意接受）。
public enum DisplayDate {
    /// 全形（日期＋时刻）：今天 HH:mm／昨天 HH:mm
    /// ／7 天内星期X HH:mm／本年 M月d日 HH:mm／跨
    /// 年 yyyy年M月d日 HH:mm——与 ChatTimeline 分
    /// 隔条文案同源同档，直接转调不另立第二套口径
    public static func dateTime(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        ChatTimeline.dividerText(for: date, now: now, calendar: calendar, locale: locale)
    }

    /// 日期档（无时刻）：今天／昨天／明天／7 天内
    /// 星期X／本年 M月d日／跨年 yyyy年M月d日。未
    /// 来侧补「明天」一档（过期日等未来日期消费点
    /// 用；ChatTimeline 的过去向口径不含此档，故本
    /// 档独立实现、日差算法与之同源）
    public static func dateOnly(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let diff = dayDifference(of: date, now: now, calendar: calendar)
        switch diff {
        case ..<0:
            // 明天单独成档；再远的未来落日期本形
            if diff == -1 { return L10n.string("明天", locale: locale) }
            return absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
        case 0:
            return L10n.string("今天", locale: locale)
        case 1:
            return L10n.string("昨天", locale: locale)
        case 2...6:
            return weekdayText(of: date, calendar: calendar, locale: locale)
        default:
            return absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
        }
    }

    /// 相对全形（点子「上次生成」旧 dayTimeText 口
    /// 径收编）：今天/昨天带时刻，再远只给日期
    public static func relativeDateTime(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let diff = dayDifference(of: date, now: now, calendar: calendar)
        switch diff {
        case 0:
            return L10n.format("今天 %@", locale: locale, timeText(of: date, calendar: calendar, locale: locale))
        case 1:
            return L10n.format("昨天 %@", locale: locale, timeText(of: date, calendar: calendar, locale: locale))
        default:
            return dateOnly(date, now: now, calendar: calendar, locale: locale)
        }
    }

    /// 相对档（0.36.7，铃铛页规格 §3.3）：新鲜度语
    /// 义——按流逝时长分档：<60 秒（时钟偏差的负值
    /// 同档）「刚刚」／<60 分钟「{N} 分钟前」／<24
    /// 小时「{N} 小时前」（均向下取整）；满 24 小
    /// 时整档让渡五档 dateTime（底层日差算法同源、
    /// 不另立第二套口径）。聊天分隔条是时刻锚点、
    /// 不用本档。分/时两档 0.42.0 起走系统相对格式
    /// 器（RelativeDateTimeFormatter，钉 locale、
    /// 全形单位），向下取整语义与旧手拼一致
    public static func relative(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return L10n.string("刚刚", locale: locale) }
        if elapsed < 86_400 {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: now)
        }
        return dateTime(date, now: now, calendar: calendar, locale: locale)
    }

    /// 绝对日期档（无相对档）：本年「M月d日」／跨
    /// 年「yyyy年M月d日」——分组标题、用量日等「就
    /// 是那一天」的消费点用，不许落今天/昨天档
    public static func monthDay(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
    }

    /// 绝对日期＋时刻（无相对档）：「M月d日 HH:mm」
    /// ——管理面短格式与提醒到期行等消费点用
    public static func absoluteDateTime(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let day = absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
        let time = timeText(of: date, calendar: calendar, locale: locale)
        return "\(day) \(time)"
    }

    /// 时刻档：HH:mm（24 小时、零填充，与
    /// ChatTimeline.timeText 同式）
    public static func timeOnly(
        _ date: Date, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        timeText(of: date, calendar: calendar, locale: locale)
    }

    // MARK: - 内部（与 ChatTimeline 同源共用）

    static func dayDifference(
        of date: Date, now: Date, calendar: Calendar
    ) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
    }

    /// 绝对日期：本年「M月d日」／跨年「yyyy年M月
    /// d日」——走 FormatStyle 字段拼装（钉 locale
    /// 与日历时区），英文下自然成「3/5」「12/31/
    /// 2025」形，不手拼格式串
    static func absoluteDate(
        of date: Date, now: Date, calendar: Calendar, locale: Locale
    ) -> String {
        let style = Date.FormatStyle(
            locale: locale, calendar: calendar, timeZone: calendar.timeZone
        )
        if calendar.component(.year, from: date)
            == calendar.component(.year, from: now) {
            return date.formatted(style.month().day())
        }
        return date.formatted(style.year().month().day())
    }

    /// 时刻：本地化模板「HH:mm」（24 小时、零填充，
    /// 三语一致——聊天分隔条与状态行的时刻锚点不
    /// 随语言换制式，与旧手拼口径逐字一致）
    static func timeText(of date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "HH:mm", options: 0, locale: locale
        )
        return formatter.string(from: date)
    }

    /// 星期全名：FormatStyle .weekday(.wide)——简
    /// 体「星期六」／繁体「週六」／英文「Saturday」
    static func weekdayText(of date: Date, calendar: Calendar, locale: Locale) -> String {
        let style = Date.FormatStyle(
            locale: locale, calendar: calendar, timeZone: calendar.timeZone
        )
        return date.formatted(style.weekday(.wide))
    }
}
