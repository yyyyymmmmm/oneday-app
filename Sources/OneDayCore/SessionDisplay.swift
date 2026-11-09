import Foundation

/// 人话时间的固定中文短格式（不随系统语言漂移）
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

/// 服务端会话的屏上文案（0.3.6 立 §21.4，0.3.7 按卡
/// 16/18 完成标准收紧）：服务端原始命名永不上屏。
/// 0.3.6 的落点（无名时拿「时间＋条数」当标题）被用户
/// 真机纠正否决——时间条数是副信息、不配当标题。收
/// 紧后口径（抽屉/服务端会话页/会话详情/总览/状态屏
/// 同源同轮）：
/// - 标题只有内容名：人话 display_name，或调用方拿
///   得到的首条用户消息摘要（contentTitle）；都没有
///   就「未命名会话」，不许拿时间当标题。
/// - 副题承载全部副信息：时间 · 条数 · 进行中（活
///   跃时）· 来源人话标签（0.3.8 第 18 条改序：来源
///   退副题末尾、先给时间与条数；状态只写属实的）。
/// - 来源：原始 source 标识一律译成人话标签，未知
///   来源只给「服务端」；原名只留设置详情页元信息组。
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

    /// 人话标题：只有内容名——人话 display_name 优先；
    /// 无内容可名时「未命名会话」（时间条数在副题，
    /// 不许当标题，0.3.7 卡 18 钉死）。
    var humanTitle: String {
        if hasHumanName, let raw = displayName {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未命名会话"
    }

    /// 内容总结标题：首条用户消息摘要（详情页等已拉
    /// 到消息的调用方用）优先于 display_name 之外的
    /// 一切；摘要为空回落 humanTitle。
    func contentTitle(firstUserMessage: String?) -> String {
        if let summary = Self.contentSummaryTitle(firstUserMessage) {
            return summary
        }
        return humanTitle
    }

    /// 首条用户消息 → 单行摘要：取首个非空行、压平
    /// 空白、剥行首 Markdown 标记，超 24 字截断加省略号。
    /// 空/纯空白返回 nil（调用方回落未命名会话）。
    static func contentSummaryTitle(_ message: String?) -> String? {
        guard let message else { return nil }
        let firstLine = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard var line = firstLine else { return nil }
        // 剥行首标记（标题/引用/列表符），只剥一层语义
        while let first = line.first, "#>-*•".contains(first) {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        // 压平内部连续空白
        let collapsed = line
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count > 24 {
            return String(collapsed.prefix(24)) + "…"
        }
        return collapsed
    }

    /// 人话副题：时间 · 条数 · 进行中 · 来源标签——
    /// 0.3.6 当标题用的「时间＋条数」自 0.3.7 起只活
    /// 在这里；0.3.8 第 18 条把来源从首位移到末尾
    /// （出处信息垫后），状态只在真活跃时写「进行中」。
    /// 今天/昨天按与 now 的自然日差判（startOfDay 对
    /// 齐，与 SidebarGrouping 同口径；不许用
    /// Calendar.isDateInToday——它锚真实系统时钟、忽
    /// 略注入的 now，0.3.6 单测实证）。
    func humanSubtitle(now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let date = startedDate {
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
            parts.append("\(day) \(sessionTimeFormatter.string(from: date))")
        }
        if let messageCount {
            parts.append("\(messageCount) 条")
        }
        if isActive {
            parts.append("进行中")
        }
        parts.append(sourceLabel)
        return parts.joined(separator: " · ")
    }
}

/// 本地会话副题（0.3.8 第 19 条：抽屉名单全员两行制，
/// 本地会话与服务端会话同行型）：时间 · 条数。时间口
/// 径与服务端副题同源（今天/昨天 HH:mm、更早 M月d日）。
public enum LocalThreadSubtitle {
    public static func text(
        updatedAt: Date, messageCount: Int,
        now: Date, calendar: Calendar = .current
    ) -> String {
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: updatedAt),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
        let day: String
        switch dayDiff {
        case 0:
            day = "今天"
        case 1:
            day = "昨天"
        default:
            day = sessionMonthDayFormatter.string(from: updatedAt)
        }
        var parts = ["\(day) \(sessionTimeFormatter.string(from: updatedAt))"]
        if messageCount > 0 {
            parts.append("\(messageCount) 条")
        }
        return parts.joined(separator: " · ")
    }
}
