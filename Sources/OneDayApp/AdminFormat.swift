import Foundation
import OneDayCore

/// 管理面通用格式：日期/计数/金额的呈现口径全 App 一处定死，
/// 避免各页各写一套（0.1.3 抽屉时间格式漂移的教训）。
/// 0.42.0 国际化包：日期口径收编 DisplayDate（系统
/// 格式器、钉界面语言），旧版钉 zh_CN 的固定中文格
/// 式器退役——格式仍一处定死，只是不再写死语言。
enum AdminFormat {

    // ISO8601DateFormatter 非 Sendable，Swift 6 下不许做静态
    // 存储属性；解析频次低，按需构造即可。
    private static var isoFractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static var isoPlain: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    /// 短格式（11月8日 13:43）：绝对月日＋时刻，无相对档
    static func short(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DisplayDate.absoluteDateTime(date)
    }

    static func day(_ date: Date) -> String {
        DisplayDate.monthDay(date)
    }

    /// 服务端 ISO 串（cron 的 last/next_run_at）→ Date，两种精度都认
    static func iso(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    /// 仅时间（HH:mm），指标行等窄格用
    static func timeOnly(_ date: Date) -> String {
        DisplayDate.timeOnly(date)
    }

    /// 日志行展示清洗：去掉行首的 ISO 时间戳 token，日志页保留原文
    static func cleanLogLine(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let first = parts.first,
              first.contains("T"), first.first?.isNumber == true else { return line }
        return String(parts[1])
    }

    /// 用量日串（yyyy-MM-dd）→ 短日格式，解析不了原样返回
    /// （yyyy-MM-dd 是服务端日串的解析格式、非呈现格式，保留）
    static func usageDay(_ string: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: string) else { return string }
        return day(date)
    }

    /// 千分位计数（Token、请求数）：等宽读数口径
    static func count(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func count(_ value: Int) -> String {
        count(Double(value))
    }

    /// 估算费用（美元，两位小数；极小值给 <0.01 而不是 0.00 的假精确）
    static func cost(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", value)
    }
}
