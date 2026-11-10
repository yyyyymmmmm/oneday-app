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

    /// 分隔条文案（五档见文件头；0.42.0 国际化包：
    /// 档位结构不变，各档文案改走 DisplayDate 同源
    /// 的系统格式化器与目录取词，locale 钉 App 界
    /// 面语言——简体输出与旧口径逐字一致）
    public static func dividerText(
        for date: Date, now: Date, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let time = DisplayDate.timeText(of: date, calendar: calendar, locale: locale)
        let dayDiff = DisplayDate.dayDifference(of: date, now: now, calendar: calendar)
        switch dayDiff {
        case ..<1:
            // 今天；日期晚于 now（时钟漂移/未来条目）
            // 同档，只给时刻不编造相对日
            return time
        case 1:
            return L10n.format("昨天 %@", locale: locale, time)
        case 2...6:
            let weekday = DisplayDate.weekdayText(of: date, calendar: calendar, locale: locale)
            return "\(weekday) \(time)"
        default:
            let absolute = DisplayDate.absoluteDate(of: date, now: now, calendar: calendar, locale: locale)
            return "\(absolute) \(time)"
        }
    }
}
