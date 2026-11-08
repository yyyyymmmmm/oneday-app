import Foundation

/// 人话标题的固定中文短格式（不随系统语言漂移）
private let sessionMonthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
}()

private let sessionTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter
}()

/// 服务端会话的屏上文案（0.3.6，DESIGN-V4 §21.4/§22 定
/// 义卡红线「数据先翻译」）：服务端原始命名永不上屏。
/// 反例（本轮修）：ServerSession.title 在 display_name
/// 缺失时拼 "\(source) 会话"，抽屉里多条同名
/// 「api_server 会话」无法区分。口径：
/// - 标题：display_name 是人话时用它；否则用开始时间
///   ＋消息条数生成区分标题（今天/昨天/M月d日＋HH:mm
///   ＋N 条）；首条消息/摘要标题由服务端以
///   display_name 承载，客户端不另抓消息列表。
/// - 来源：原始 source 标识一律译成人话标签，未知来
///   源只给「服务端」，原名只留设置详情页（原始字段
///   在详情里照原样展示）。
public extension ServerSession {
    /// 来源的人话标签（原始标识不上屏）
    var sourceLabel: String {
        switch source?.lowercased() {
        case "api_server": return "API 接口"
        case "dashboard": return "控制台"
        case "cli": return "命令行"
        case "cron", "cron_job", "scheduler": return "定时任务"
        default: return "服务端"
        }
    }

    /// display_name 是否人话标题：非空、且不是标识符
    /// 形态（纯 ASCII 单 token、字母数字下划线组成、
    /// 字母开头——如 api_server 一类实体名）
    var hasHumanName: Bool {
        guard let raw = displayName else { return false }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let identifierShaped = name.unicodeScalars.allSatisfy {
            $0.isASCII
                && (CharacterSet.alphanumerics.contains($0) || $0 == "_")
        } && name.first?.isLetter == true
        return !identifierShaped
    }

    /// 人话标题：人话 display_name 优先；否则时间＋
    /// 条数（拿不到时间时退「服务端会话＋条数」）。
    func humanTitle(now: Date, calendar: Calendar = .current) -> String {
        if hasHumanName, let raw = displayName {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let date = startedDate else {
            return "服务端会话" + countSuffix
        }
        // 今天/昨天按与 now 的自然日差判（startOfDay
        // 对齐，与 SidebarGrouping 同口径）——不许用
        // Calendar.isDateInToday：它锚真实系统时钟、
        // 忽略注入的 now（85 测首跑实证：CI 机真实日
        // 期与测试 now 不同日即错位）
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
        let day: String
        switch dayDiff {
        case 0:
            day = "今天"
        case 1:
            day = "昨天"
        default:
            day = sessionMonthDayFormatter.string(from: date)
        }
        return "\(day) \(sessionTimeFormatter.string(from: date))"
            + countSuffix
    }

    private var countSuffix: String {
        guard let messageCount else { return "" }
        return " · \(messageCount) 条"
    }
}
