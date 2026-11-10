import Foundation

/// 全 App 日期时间呈现的唯一格式器（0.36.0，宪法审
/// 计 C11／设计宪法 §8）：此前 `.formatted(date:
/// .abbreviated, …)` 散落 9 处、随系统 locale 漂
/// 移，真机漏出英文「Nov 10, 2026 at 17:02」。自
/// 本版起所有面向用户的日期时间只许走本格式器，
/// 口径与聊天时间系统（ChatTimeline 五档）完全一
/// 致：相对优先、中文写定、不随 locale 变脸。
public enum DisplayDate {
    /// 全形（日期＋时刻）：今天 HH:mm／昨天 HH:mm
    /// ／7 天内星期X HH:mm／本年 M月d日 HH:mm／跨
    /// 年 yyyy年M月d日 HH:mm——与 ChatTimeline 分
    /// 隔条文案同源同档，直接转调不另立第二套口径
    public static func dateTime(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        ChatTimeline.dividerText(for: date, now: now, calendar: calendar)
    }

    /// 日期档（无时刻）：今天／昨天／明天／7 天内
    /// 星期X／本年 M月d日／跨年 yyyy年M月d日。未
    /// 来侧补「明天」一档（过期日等未来日期消费点
    /// 用；ChatTimeline 的过去向口径不含此档，故本
    /// 档独立实现、日差算法与之同源）
    public static func dateOnly(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        let diff = dayDifference(of: date, now: now, calendar: calendar)
        switch diff {
        case ..<0:
            // 明天单独成档；再远的未来落日期本形
            if diff == -1 { return "明天" }
            return absoluteDate(of: date, now: now, calendar: calendar)
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2...6:
            return weekdayText(of: date, calendar: calendar)
        default:
            return absoluteDate(of: date, now: now, calendar: calendar)
        }
    }

    /// 相对全形（点子「上次生成」旧 dayTimeText 口
    /// 径收编）：今天/昨天带时刻，再远只给日期
    public static func relativeDateTime(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        let diff = dayDifference(of: date, now: now, calendar: calendar)
        switch diff {
        case 0:
            return "今天 \(timeText(of: date, calendar: calendar))"
        case 1:
            return "昨天 \(timeText(of: date, calendar: calendar))"
        default:
            return dateOnly(date, now: now, calendar: calendar)
        }
    }

    /// 相对档（0.36.7，铃铛页规格 §3.3）：新鲜度语
    /// 义——按流逝时长分档：<60 秒（时钟偏差的负值
    /// 同档）「刚刚」／<60 分钟「{N} 分钟前」／<24
    /// 小时「{N} 小时前」（均向下取整）；满 24 小
    /// 时整档让渡五档 dateTime（底层日差算法同源、
    /// 不另立第二套口径）。聊天分隔条是时刻锚点、
    /// 不用本档
    public static func relative(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60)) 分钟前" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600)) 小时前" }
        return dateTime(date, now: now, calendar: calendar)
    }

    /// 时刻档：HH:mm（24 小时、零填充，与
    /// ChatTimeline.timeText 同式）
    public static func timeOnly(
        _ date: Date, calendar: Calendar = .current
    ) -> String {
        timeText(of: date, calendar: calendar)
    }

    // MARK: - 内部（与 ChatTimeline 同源算法）

    private static func dayDifference(
        of date: Date, now: Date, calendar: Calendar
    ) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
    }

    private static func absoluteDate(
        of date: Date, now: Date, calendar: Calendar
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month,
              let day = parts.day else { return "" }
        if year == calendar.component(.year, from: now) {
            return "\(month)月\(day)日"
        }
        return "\(year)年\(month)月\(day)日"
    }

    private static func timeText(of date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private static let weekdayNames = [
        "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六",
    ]

    private static func weekdayText(of date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        guard (1...7).contains(weekday) else { return "" }
        return weekdayNames[weekday - 1]
    }
}
