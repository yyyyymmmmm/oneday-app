import Foundation

// MARK: - 枢纽页定时段：jobs 分类与组装（纯函数）

/// 判定任务是否为系统任务（双轨，对齐服务端 cron_projection.py
/// 判定口径）：服务端 is_system 字段优先（2.8.0 起下发），字段
/// 缺失时回落启发式（名字模式＋来源脚本名匹配服务端正则）
private func isSystemTask(_ job: CronJob) -> Bool {
    // 服务端字段优先（2.8.0 起）
    if let isSystem = job.isSystem {
        return isSystem
    }

    // 启发式兜底：对齐服务端 _SYSTEM_NAME_PATTERNS
    guard let name = job.name else { return false }

    // 模式 1: "OneDay 系统轮" 开头（服务端 "^OneDay\s+系统轮"）
    if name.hasPrefix("OneDay 系统轮") {
        return true
    }

    // 模式 2: "OneDay 记忆" 或 "OneDay memory" 开头（大小写不敏感）
    let lowerName = name.lowercased()
    if lowerName.hasPrefix("oneday 记忆") || lowerName.hasPrefix("oneday memory") {
        return true
    }

    // 模式 3: "OneDay 目标" 开头且含 "提炼" 或 "distill"
    // （服务端 "^OneDay\s+(?:目标|goal).*(?:提炼|distill)"）
    if (name.hasPrefix("OneDay 目标") || lowerName.hasPrefix("oneday goal")) &&
       (name.contains("提炼") || lowerName.contains("distill")) {
        return true
    }

    return false
}

/// 定时任务在枢纽页的分组（phase3-data-design §3.3）：
/// 规格只定义提醒/每日/间隔三组；otherRecurring 是数据
/// 完整性的兜底组——真实出现周任务时落此组显示「其他
/// 周期」，不许为了迎合三组把周任务误标成每日。
public enum HubCronKind: String, Equatable, Sendable, CaseIterable {
    case reminder
    case daily
    case interval
    case otherRecurring

    /// 分组组头（屏上文案）
    public var groupTitle: String {
        switch self {
        case .reminder: return "提醒"
        case .daily: return "每日"
        case .interval: return "时间间隔"
        case .otherRecurring: return "其他周期"
        }
    }

    /// 组间顺序：提醒 → 每日 → 时间间隔 → 其他周期
    public var sortOrder: Int {
        switch self {
        case .reminder: return 0
        case .daily: return 1
        case .interval: return 2
        case .otherRecurring: return 3
        }
    }
}

/// 枢纽页定时行组装结果：标题/行文案的字段口径见
/// phase3-data-design §3.4。时间一律以 nextRunAt 的绝对
/// 时刻展示（cron 分/时是服务端时区还是设备时区无字段
/// 可证，不做二次换算）。
public struct HubCronItem: Identifiable, Sendable {
    public let job: CronJob
    public let kind: HubCronKind
    public let nextRunAt: Date?
    public let lastRunAt: Date?
    /// 间隔秒数（仅 kind == .interval 时有值）
    public let interval: TimeInterval?

    public var id: String { job.id }

    public init(
        job: CronJob, kind: HubCronKind,
        nextRunAt: Date?, lastRunAt: Date?, interval: TimeInterval?
    ) {
        self.job = job
        self.kind = kind
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.interval = interval
    }

    /// 间隔人话（§3.4）：优先取可整除的最大单位（天→
    /// 小时→分钟→秒），如 360 分钟写「每 6 小时」；不能
    /// 整除时保留原单位数值，不做近似。
    public var intervalText: String? {
        guard let interval else { return nil }
        return CronHubClassifier.intervalText(interval)
    }
}

public enum CronHubClassifier {
    /// 单任务分类。lastRunOverride 来自补拉的 runs（仅
    /// 间隔型且 job 自带 lastRunAt 缺失时由调用方注入），
    /// 有值时优先于 job.lastRunAt。
    public static func classify(
        _ job: CronJob, lastRunOverride: Date? = nil
    ) -> HubCronItem {
        let nextRun = HubCronDate.parse(job.nextRunAt)
        let lastRun = lastRunOverride ?? HubCronDate.parse(job.lastRunAt)
        let (kind, interval) = classifySchedule(job, nextRunAt: nextRun)
        return HubCronItem(
            job: job, kind: kind,
            nextRunAt: nextRun, lastRunAt: lastRun, interval: interval
        )
    }

    /// 全量组装＋分组＋组内排序（§3.6）：enabled 在前 →
    /// nextRunAt 升序（无值垫底）→ 标题字典序 → id。
    /// 只返回非空组，组序按 HubCronKind.sortOrder。
    /// 系统任务过滤：先按 isSystemTask 过滤系统任务，只保留
    /// 用户可见任务进入分组。
    public static func grouped(
        _ jobs: [CronJob], lastRuns: [String: Date] = [:]
    ) -> [(kind: HubCronKind, items: [HubCronItem])] {
        // 过滤系统任务：只保留用户任务
        let userJobs = jobs.filter { !isSystemTask($0) }
        let items = userJobs.map { job in
            classify(job, lastRunOverride: lastRuns[job.id])
        }
        var byKind: [HubCronKind: [HubCronItem]] = [:]
        for item in items {
            byKind[item.kind, default: []].append(item)
        }
        return HubCronKind.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { kind in
                guard let group = byKind[kind], !group.isEmpty else {
                    return nil
                }
                return (kind: kind, items: group.sorted(by: itemOrder))
            }
    }

    private static func itemOrder(_ a: HubCronItem, _ b: HubCronItem) -> Bool {
        if a.job.enabled != b.job.enabled { return a.job.enabled }
        switch (a.nextRunAt, b.nextRunAt) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.job.title != b.job.title { return a.job.title < b.job.title }
        return a.job.id < b.job.id
    }

    // MARK: - schedule 分类

    private static func classifySchedule(
        _ job: CronJob, nextRunAt: Date?
    ) -> (HubCronKind, TimeInterval?) {
        switch job.scheduleRaw {
        case .object(let object):
            return classifyObject(object, job: job, nextRunAt: nextRunAt)
        case .string(let raw):
            return classifyString(raw, nextRunAt: nextRunAt)
        default:
            return (.otherRecurring, nil)
        }
    }

    private static func classifyObject(
        _ object: [String: JSONValue], job: CronJob, nextRunAt: Date?
    ) -> (HubCronKind, TimeInterval?) {
        let kind = object["kind"]?.stringValue?.lowercased()
        switch kind {
        case "interval":
            if let seconds = intervalSeconds(from: object) {
                return (.interval, seconds)
            }
            return (.otherRecurring, nil)
        case "daily":
            return (.daily, nil)
        case "once", "one_time", "at":
            return (.reminder, nil)
        case "cron":
            for key in ["expression", "expr", "cron"] {
                if let expression = object[key]?.stringValue {
                    return classifyCronExpression(expression, nextRunAt: nextRunAt)
                }
            }
            return (.otherRecurring, nil)
        default:
            return (.otherRecurring, nil)
        }
    }

    /// 对象型 interval：按毫秒→秒→分→时→天顺序取第一个
    /// 有效正数，统一换算为秒（§3.3）
    private static func intervalSeconds(
        from object: [String: JSONValue]
    ) -> TimeInterval? {
        let units: [(key: String, factor: TimeInterval)] = [
            ("milliseconds", 0.001),
            ("seconds", 1),
            ("minutes", 60),
            ("hours", 3600),
            ("days", 86400),
        ]
        for unit in units {
            if case .number(let value)? = object[unit.key], value > 0 {
                return value * unit.factor
            }
        }
        return nil
    }

    private static func classifyString(
        _ raw: String, nextRunAt: Date?
    ) -> (HubCronKind, TimeInterval?) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (.otherRecurring, nil) }

        // 1. ISO / 日期时间串 → 一次性提醒
        if HubCronDate.parse(text) != nil {
            return (.reminder, nil)
        }
        // 2. 间隔串（every <n><unit> 或单独 <n><unit>）
        if let seconds = parseIntervalString(text) {
            return (.interval, seconds)
        }
        // 3. cron 表达式
        if isCronShaped(text) {
            return classifyCronExpression(text, nextRunAt: nextRunAt)
        }
        // 4. 其余 → 兜底组
        return (.otherRecurring, nil)
    }

    private static func parseIntervalString(_ text: String) -> TimeInterval? {
        let lowered = text.lowercased()
        let body = lowered.hasPrefix("every ")
            ? String(lowered.dropFirst("every ".count))
                .trimmingCharacters(in: .whitespaces)
            : lowered
        let pattern = #"^(\d+(?:\.\d+)?)\s*(ms|s|m|h|d|milliseconds?|seconds?|minutes?|hours?|days?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: body, range: NSRange(body.startIndex..., in: body)
              ),
              let numberRange = Range(match.range(at: 1), in: body),
              let unitRange = Range(match.range(at: 2), in: body),
              let value = Double(body[numberRange]), value > 0 else {
            return nil
        }
        let unit = String(body[unitRange])
        let factor: TimeInterval
        switch unit {
        case "ms", "millisecond", "milliseconds": factor = 0.001
        case "s", "second", "seconds": factor = 1
        case "m", "minute", "minutes": factor = 60
        case "h", "hour", "hours": factor = 3600
        case "d", "day", "days": factor = 86400
        default: return nil
        }
        return value * factor
    }

    /// cron 字段形态：5 或 6 段、每段只含 0-9*/,- 字符
    private static func isCronShaped(_ text: String) -> Bool {
        let fields = text.split(separator: " ").map(String.init)
        guard fields.count == 5 || fields.count == 6 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789*/,-")
        return fields.allSatisfy { field in
            !field.isEmpty
                && field.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    private static func classifyCronExpression(
        _ expression: String, nextRunAt: Date?
    ) -> (HubCronKind, TimeInterval?) {
        var fields = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map(String.init)
        if fields.count == 6 {
            // 6 段时首段为秒，分类时忽略
            fields.removeFirst()
        }
        guard fields.count == 5 else { return (.otherRecurring, nil) }
        let (minute, hour, dayOfMonth, month, dayOfWeek) =
            (fields[0], fields[1], fields[2], fields[3], fields[4])

        func isFixedNumber(_ field: String) -> Bool {
            !field.isEmpty && field.allSatisfy { $0.isNumber }
        }
        // 分、时为确定数值且日/月/星期全 * → 每日
        if isFixedNumber(minute), isFixedNumber(hour),
           dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            return (.daily, nil)
        }
        // 日或月为确定值且有 nextRunAt 可对上一次性日期
        // → 提醒；仅凭 cron 串不能证明一次性，证据不足
        // 时不归提醒（§3.3）
        if (isFixedNumber(dayOfMonth) || isFixedNumber(month)),
           nextRunAt != nil {
            return (.reminder, nil)
        }
        return (.otherRecurring, nil)
    }

    // MARK: - 间隔人话

    public static func intervalText(_ seconds: TimeInterval) -> String {
        let units: [(name: String, size: TimeInterval)] = [
            ("天", 86400), ("小时", 3600), ("分钟", 60), ("秒", 1),
        ]
        for unit in units {
            let quotient = seconds / unit.size
            if quotient >= 1, quotient == quotient.rounded() {
                return "每 \(Int(quotient)) \(unit.name)"
            }
        }
        // 亚秒/不可整除：保留秒数原值，不做近似
        let text = seconds == seconds.rounded()
            ? String(Int(seconds))
            : String(seconds)
        return "每 \(text) 秒"
    }
}

/// cron 面日期解析（App 层 AdminFormat.iso 的 Core 版：
/// ISO8601 两种精度＋ yyyy-MM-dd HH:mm 兜底）
enum HubCronDate {
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.dateFormat = "yyyy-MM-dd HH:mm"
        return plain.date(from: string)
    }
}

// MARK: - Cron 表达式翻译器（用户可见化）

/// Cron 表达式翻译为人话（review-checklists.md §1）：
/// 覆盖用户亲报实例 `5 * * * *` → 每小时第 5 分、
/// `30 10 * * 0` → 每周日 10:30，永不裸露原始表达式。
/// 返回 nil 时调用方应显示「自定义周期」兜底。
public enum CronTranslator {
    /// 翻译 cron 表达式为人话，失败返回 nil（调用方兜底）
    public static func translate(_ expression: String) -> String? {
        let normalized = normalize(expression)
        guard let fields = parseFields(normalized) else { return nil }

        // 别名展开后重新解析
        if let alias = expandAlias(normalized) {
            return translate(alias)
        }

        // 只接受 5 段式（6 段式兜底）
        guard fields.count == 5 else { return nil }

        let (minute, hour, dom, month, dow) =
            (fields[0], fields[1], fields[2], fields[3], fields[4])

        // 高频：每分钟
        if minute == "*" && hour == "*" && dom == "*" && month == "*" && dow == "*" {
            return "每分钟"
        }

        // 步进分钟：*/n 或 a-b/n
        if let stepText = translateMinuteStep(minute),
           hour == "*" && dom == "*" && month == "*" && dow == "*" {
            return stepText
        }

        // 每小时：分钟固定、小时为 *
        if isFixedNumber(minute) && hour == "*" && dom == "*" && month == "*" && dow == "*" {
            if minute == "0" {
                return "每小时整点"
            }
            return "每小时第 \(minute) 分"
        }

        // 步进小时：0 */n
        if minute == "0" && hour.hasPrefix("*/") && dom == "*" && month == "*" && dow == "*" {
            if let n = Int(hour.dropFirst(2)) {
                return "每 \(n) 小时（整点起）"
            }
        }

        // 每日：分时固定、日月周为 *
        if isFixedNumber(minute) && isFixedNumber(hour) &&
           dom == "*" && month == "*" && dow == "*" {
            return "每日 \(formatTime(hour, minute))"
        }

        // 工作日：1-5 或 1,2,3,4,5
        if isFixedNumber(minute) && isFixedNumber(hour) &&
           dom == "*" && month == "*" && isWeekdays(dow) {
            return "工作日 \(formatTime(hour, minute))"
        }

        // 周末：0,6 或 6,0
        if isFixedNumber(minute) && isFixedNumber(hour) &&
           dom == "*" && month == "*" && isWeekend(dow) {
            return "周末 \(formatTime(hour, minute))"
        }

        // 每周：星期受限
        if isFixedNumber(minute) && isFixedNumber(hour) &&
           dom == "*" && month == "*" && dow != "*" {
            if let dayText = translateDayOfWeek(dow) {
                return "\(dayText) \(formatTime(hour, minute))"
            }
        }

        // 每月：日期受限、星期为 *
        if isFixedNumber(minute) && isFixedNumber(hour) &&
           dom != "*" && month == "*" && dow == "*" {
            if let dayText = translateDayOfMonth(dom) {
                return "每月 \(dayText) \(formatTime(hour, minute))"
            }
        }

        // 每年：日期和月份受限
        if isFixedNumber(minute) && isFixedNumber(hour) &&
           dom != "*" && month != "*" && dow == "*" {
            if let monthText = translateMonth(month),
               let dayText = translateDayOfMonth(dom) {
                return "每年 \(monthText) \(dayText) \(formatTime(hour, minute))"
            }
        }

        // OR 语义：日期和星期同时受限（Vixie cron 任一命中即触发）
        // 组合翻译为并集人话
        if dom != "*" && dow != "*" {
            var parts: [String] = []
            if let domText = translateDayOfMonth(dom) {
                parts.append("每月 \(domText)")
            }
            if let dowText = translateDayOfWeek(dow) {
                parts.append(dowText)
            }
            if parts.count == 2 {
                return "\(parts[0]) 或 \(parts[1]) \(formatTime(hour, minute))"
            }
            // 部分翻译失败时仍兜底
            return nil
        }

        // 其余形态兜底
        return nil
    }

    // MARK: - 辅助函数

    private static func normalize(_ expr: String) -> String {
        expr.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func parseFields(_ expr: String) -> [String]? {
        let fields = expr.split(separator: " ").map(String.init)
        // 只接受 5 或 6 段
        guard fields.count == 5 || fields.count == 6 else { return nil }
        // 6 段式：忽略首段（秒）
        return fields.count == 6 ? Array(fields.dropFirst()) : fields
    }

    private static func expandAlias(_ expr: String) -> String? {
        switch expr.lowercased() {
        case "@yearly", "@annually": return "0 0 1 1 *"
        case "@monthly": return "0 0 1 * *"
        case "@weekly": return "0 0 * * 0"
        case "@daily", "@midnight": return "0 0 * * *"
        case "@hourly": return "0 * * * *"
        default: return nil
        }
    }

    private static func isFixedNumber(_ field: String) -> Bool {
        !field.isEmpty && field.allSatisfy { $0.isNumber }
    }

    private static func formatTime(_ hour: String, _ minute: String) -> String {
        let h = Int(hour) ?? 0
        let m = Int(minute) ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    private static func translateMinuteStep(_ minute: String) -> String? {
        // */n
        if minute.hasPrefix("*/") {
            if let n = Int(minute.dropFirst(2)) {
                return "每 \(n) 分钟"
            }
        }
        // a-b/n
        if let range = minute.range(of: #"^(\d+)-(\d+)/(\d+)$"#, options: .regularExpression) {
            let parts = minute[range].split(separator: "/")
            if parts.count == 2, let n = Int(parts[1]) {
                let rangeText = parts[0]
                return "每小时 \(rangeText) 分每 \(n) 分钟一次"
            }
        }
        return nil
    }

    private static func isWeekdays(_ dow: String) -> Bool {
        let normalized = dow.replacingOccurrences(of: " ", with: "")
        return normalized == "1-5" || normalized == "1,2,3,4,5"
    }

    private static func isWeekend(_ dow: String) -> Bool {
        let normalized = dow.replacingOccurrences(of: " ", with: "")
        return normalized == "0,6" || normalized == "6,0"
    }

    private static func translateDayOfWeek(_ dow: String) -> String? {
        // 单个数字
        if let day = Int(dow) {
            let normalized = day == 7 ? 0 : day
            switch normalized {
            case 0: return "每周日"
            case 1: return "每周一"
            case 2: return "每周二"
            case 3: return "每周三"
            case 4: return "每周四"
            case 5: return "每周五"
            case 6: return "每周六"
            default: return nil
            }
        }
        // 列表：1,3,5 → 每周一、三、五
        if dow.contains(",") {
            let days = dow.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !days.isEmpty else { return nil }
            let names = days.map { day -> String in
                let normalized = day == 7 ? 0 : day
                switch normalized {
                case 0: return "日"
                case 1: return "一"
                case 2: return "二"
                case 3: return "三"
                case 4: return "四"
                case 5: return "五"
                case 6: return "六"
                default: return ""
                }
            }.filter { !$0.isEmpty }
            guard !names.isEmpty else { return nil }
            return "每周" + names.joined(separator: "、")
        }
        return nil
    }

    private static func translateDayOfMonth(_ dom: String) -> String? {
        // 单个数字
        if let day = Int(dom) {
            return "\(day) 日"
        }
        // 列表：1,15 → 1 日和 15 日
        if dom.contains(",") {
            let days = dom.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !days.isEmpty, days.count <= 3 else { return nil }
            if days.count == 2 {
                return "\(days[0]) 日和 \(days[1]) 日"
            }
            return days.map { "\($0) 日" }.joined(separator: "、")
        }
        return nil
    }

    private static func translateMonth(_ month: String) -> String? {
        if let m = Int(month) {
            return "\(m) 月"
        }
        return nil
    }
}
