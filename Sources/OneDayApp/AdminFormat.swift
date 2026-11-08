import Foundation

/// 管理面通用格式：日期/计数/金额的呈现口径全 App 一处定死，
/// 避免各页各写一套（0.1.3 抽屉时间格式漂移的教训）。
enum AdminFormat {
    /// 固定中文短格式（11月8日 13:43），不随系统语言漂移
    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

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

    static func short(_ date: Date?) -> String {
        guard let date else { return "—" }
        return shortFormatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// 服务端 ISO 串（cron 的 last/next_run_at）→ Date，两种精度都认
    static func iso(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    /// 用量日串（yyyy-MM-dd）→ 短日格式，解析不了原样返回
    static func usageDay(_ string: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: string) else { return string }
        return dayFormatter.string(from: date)
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
