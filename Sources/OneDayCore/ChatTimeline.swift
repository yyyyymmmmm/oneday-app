import Foundation

/// 聊天时间系统（0.30.0，用户 2026-11-10 12:56 点名
/// 「对话页面没有时间显示不科学」）：消息流内时间分
/// 隔条的落点与文案，纯计算、单测把守，视图只渲染
/// （微信/iMessage 式分隔条，不是每条消息挂时间）。
///
/// 落点口径（2026-11-10 查证微信现行规则）：
/// - 微信官方帮助中心《WeChat訊息是如何顯示時間？》：
///   当天的讯息以每 5 分钟为一个跨度地显示时间；超
///   过一天、小于一周显示星期＋收发时间；大于一周
///   显示收发时间的日期。
/// - 腾讯云 IM 官方文档《聊天IM的时间戳显示规则》：
///   遍历消息时，与最后一次显示时间戳的间隔大于 5
///   分钟（300 秒）时再追加一条时间戳、并更新锚点。
/// 据此实现为锚点走查：首条恒挂；其后与上一条已挂
/// 分隔条的消息间隔 > 300 秒才再挂（恰 300 秒不
/// 挂），挂后锚点更新为该条。注意这与「只看相邻两
/// 条间隔」不同：4 分钟一条连发时，相邻口径全程只
/// 有首条；跨度（锚点）口径按约 5 分钟周期再挂，
/// 与微信体感一致——从其官方文档口径，不从字面猜。
///
/// 文案五档（相对优先，均按注入日历的本地时区）：
/// 今天（含未来漂移）HH:mm／昨天 HH:mm／7 天内
/// （日差 2...6）星期X HH:mm／本年 M月d日 HH:mm／
/// 跨年 yyyy年M月d日 HH:mm。跨年但仍在 7 天内的
/// 走相对档（昨天/星期），与微信相对优先一致。
public enum ChatTimeline {
    /// 分隔阈值：5 分钟（出处见文件头）
    public static let dividerThreshold: TimeInterval = 300

    /// 需要分隔条的消息下标（dates 须为升序——调用
    /// 方传 sortedEntries 的 createdAt 序列）
    public static func dividerIndices(
        dates: [Date], threshold: TimeInterval = dividerThreshold
    ) -> Set<Int> {
        var indices = Set<Int>()
        var anchor: Date?
        for (index, date) in dates.enumerated() {
            if let anchor, date.timeIntervalSince(anchor) <= threshold {
                continue
            }
            indices.insert(index)
            anchor = date
        }
        return indices
    }

    /// 分隔条文案（五档见文件头）
    public static func dividerText(
        for date: Date, now: Date, calendar: Calendar = .current
    ) -> String {
        let time = timeText(for: date, calendar: calendar)
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
        switch dayDiff {
        case ..<1:
            // 今天；日期晚于 now（时钟漂移/未来条目）
            // 同档，只给时刻不编造相对日
            return time
        case 1:
            return "昨天 \(time)"
        case 2...6:
            return "\(weekdayText(for: date, calendar: calendar)) \(time)"
        default:
            let parts = calendar.dateComponents(
                [.year, .month, .day], from: date
            )
            guard let year = parts.year, let month = parts.month,
                  let day = parts.day else { return time }
            if year == calendar.component(.year, from: now) {
                return "\(month)月\(day)日 \(time)"
            }
            return "\(year)年\(month)月\(day)日 \(time)"
        }
    }

    private static func timeText(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private static let weekdayNames = [
        "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六",
    ]

    private static func weekdayText(
        for date: Date, calendar: Calendar
    ) -> String {
        // Calendar.weekday：1＝周日 … 7＝周六
        let weekday = calendar.component(.weekday, from: date)
        guard (1...7).contains(weekday) else { return "" }
        return weekdayNames[weekday - 1]
    }
}
