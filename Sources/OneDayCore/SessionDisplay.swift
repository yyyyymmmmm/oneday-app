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

/// 「日 + 时刻」单段时间文本（今天/昨天 HH:mm、更早
/// M月d日 HH:mm）：服务端副题、本地副题与 0.17.0 抽
/// 屉单行行尾时间同源同口径，单一实现防三处漂移。
/// 今天/昨天按与 now 的自然日差判（startOfDay 对齐，
/// 与 SidebarGrouping 同口径；不许用 Calendar
/// .isDateInToday——它锚真实系统时钟、忽略注入的
/// now，0.3.6 单测实证）。
private func sessionDayTimeText(
    for date: Date, now: Date, calendar: Calendar
) -> String {
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
}

/// 服务端会话的屏上文案（0.3.6 立 §21.4，0.3.7 按卡
/// 16/18 完成标准收紧）：服务端原始命名永不上屏。
/// 0.3.6 的落点（无名时拿「时间＋条数」当标题）被用户
/// 真机纠正否决——时间条数是副信息、不配当标题。收
/// 紧后口径（抽屉/服务端会话页/会话详情/总览/状态屏
/// 同源同轮）：
/// - 标题只有内容名：人话 display_name，或调用方拿
///   得到的首条用户消息摘要（contentTitle）；都没有
///   就「未命名会话」，不许拿时间当标题。
/// - 副题承载全部副信息：时间 · 条数 · 来源人话
///   标签（0.3.8 第 18 条改序：来源退副题末尾、先给
///   时间与条数）。0.6.1 起副题不再写「进行中」：
///   Hermes 不写 ended_at，isActive 恒真、据此标进
///   行中是假数据（用户真机点名），状态只在状态行
///   以可证事实呈现（在线/待审批/联系不上）。
/// - 来源：原始 source 标识一律译成人话标签，未知
///   来源只给「服务端」；原名只留设置详情页元信息组。
public extension ServerSession {
    /// 来源的人话标签（原始标识不上屏）
    var sourceLabel: String {
        switch source?.lowercased() {
        // 0.4.1 第 10 修：「API 接口」仍是未翻译的
        // 实现口径（用户点名、违反数据先翻译红线）——
        // 经接口从别的应用/设备开的会话，人话说「其
        // 他应用」；ServerLabels.platformName 的同名
        // 词是平台管理面口径（命名服务端组件本身）、
        // 不在此列
        case "api_server": return "其他应用"
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
    /// 一切；摘要为空回落 humanTitle。0.18.0 起本方
    /// 法降为 resolvedTitle 的回落层（服务端标题在
    /// 其上），单独调用的口径不变。
    func contentTitle(firstUserMessage: String?) -> String {
        if let summary = Self.contentSummaryTitle(firstUserMessage) {
            return summary
        }
        return humanTitle
    }

    /// 服务端标题清洗值：title 字段去首尾空白、空串
    /// 归 nil（标题来源分层看 titleSource）
    var cleanedServerTitle: String? {
        guard let raw = serverTitle else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 是否已有服务端标题（user/llm/derived 任一）——
    /// 有则本地派生不再是标题来源（SessionTitle-
    /// Resolver 据此跳过无谓的消息拉取）
    var hasServerTitle: Bool { cleanedServerTitle != nil }

    /// 统一标题管线（0.18.0，旁聊立项档专题二方案
    /// 序①；抽屉行/管理页行/会话页标题全 App 同源）：
    /// 手动改名（title_source=user 的服务端标题）＞
    /// llm 标题 ＞ derived 占位（三者同存于 title 字
    /// 段、按 titleSource 区分，本层只认字段在场）＞
    /// 本地派生（首条消息摘要，contentTitle）＞
    /// display_name 人话名 ＞「未命名会话」。
    /// 红线：任一层不许拿空串或 id 前缀充标题；Qwen
    /// 会话的 llm 升级被 vLLM 拒后 title 为空——按本
    /// 管线落本地派生/未命名，派生摘要只是回落、不
    /// 冒充 AI 名（来源以 titleSource 为据可查）。
    func resolvedTitle(firstUserMessage: String?) -> String {
        if let title = cleanedServerTitle {
            return title
        }
        return contentTitle(firstUserMessage: firstUserMessage)
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

    /// 人话副题：时间 · 条数 · 来源标签——
    /// 0.3.6 当标题用的「时间＋条数」自 0.3.7 起只活
    /// 在这里；0.3.8 第 18 条把来源从首位移到末尾
    /// （出处信息垫后）；0.6.1 起不写状态段（见文件
    /// 头注：ended_at 缺失使「进行中」成假数据）。
    /// 今天/昨天按与 now 的自然日差判（startOfDay 对
    /// 齐，与 SidebarGrouping 同口径；不许用
    /// Calendar.isDateInToday——它锚真实系统时钟、忽
    /// 略注入的 now，0.3.6 单测实证）。
    func humanSubtitle(now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let date = startedDate {
            parts.append(
                sessionDayTimeText(for: date, now: now, calendar: calendar)
            )
        }
        if let messageCount {
            parts.append("\(messageCount) 条")
        }
        parts.append(sourceLabel)
        return parts.joined(separator: " · ")
    }

    /// 单行行尾时间（0.17.0 抽屉名单单行化）：只给时
    /// 间段（与副题首段逐字一致），条数/来源不上行；
    /// 无开始时间返回 nil（行尾留空，不编造）
    func listTimeText(
        now: Date, calendar: Calendar = .current
    ) -> String? {
        guard let date = startedDate else { return nil }
        return sessionDayTimeText(for: date, now: now, calendar: calendar)
    }

    /// 首条用户消息（0.6.1 立、0.18.0 降为回落层素
    /// 材）：服务端标题（title 字段）已直达后，本值
    /// 只在服务端无标题时作本地派生（resolvedTitle
    /// 的回落层）——按需拉单会话消息取首条 user 内容。
    /// 取数组序首条 role=user 且去空白后非空者（接口
    /// 返回即时序）；调用方负责请求预算与缓存，不许
    /// 逐行无界拉取。
    static func firstUserMessage(in messages: [SessionMessage]) -> String? {
        for message in messages where message.role.lowercased() == "user" {
            let content = message.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { return message.content }
        }
        return nil
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
        var parts = [
            sessionDayTimeText(for: updatedAt, now: now, calendar: calendar)
        ]
        if messageCount > 0 {
            parts.append("\(messageCount) 条")
        }
        return parts.joined(separator: " · ")
    }

    /// 单行行尾时间（0.17.0 抽屉名单单行化）：只有时
    /// 间段、条数不上行（与 text() 首段逐字一致）
    public static func timeText(
        updatedAt: Date,
        now: Date, calendar: Calendar = .current
    ) -> String {
        sessionDayTimeText(for: updatedAt, now: now, calendar: calendar)
    }
}
