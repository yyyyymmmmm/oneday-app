import Foundation

/// 工作台账呈现口径（规格 work-ledger-design-
/// 20261110.md §2.5/§3/§4）：人话映射、已耗时格
/// 式、新鲜度分档、增量合并、按天分组、页首计数与
/// 行副题——全部纯函数收口于此，视图只渲染。状态
/// 文案零行话：原始枚举只许进下钻详情的「技术信
/// 息」区，列表与副题一律走本文件的人话。

// MARK: - 人话映射（单点维护）

public enum LedgerText {
    /// 七态人话（规格 §3.1 的界面词）
    public static func statusWord(_ status: LedgerStatus) -> String {
        switch status {
        case .queued: return "排队中"
        case .running: return "进行中"
        case .blockedApproval: return "等待审批"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        case .stale: return "失联待核"
        case .other: return "状态未知"
        }
    }

    /// 类别人话（详情面用）
    public static func kindWord(_ kind: LedgerKind) -> String {
        switch kind {
        case .run: return "对话运行"
        case .kanban: return "看板任务"
        case .job: return "定时作业"
        case .approval: return "审批"
        case .device: return "设备调用"
        case .other(let raw): return raw.isEmpty ? "其他" : raw
        }
    }

    /// 来源人话（与现行活动段来源标同族口径）
    public static func sourceWord(_ source: LedgerSource) -> String {
        switch source {
        case .app: return "OneDay 发起"
        case .dashboard: return "控制台"
        case .cron: return "定时任务"
        case .api: return "其他应用"
        case .bridge: return "自动作业"
        case .device: return "设备"
        case .other(let raw): return raw.isEmpty ? "其他来源" : raw
        }
    }

    /// 记账来源人话（origin 诚实位，详情可见；列表面
    /// 的「补记」小标判据在 LedgerItem.isReconciled）
    public static func originWord(_ raw: String) -> String {
        switch raw {
        case "reported": return "实时上报"
        case "bridge_self": return "自动记录"
        case "reconciled": return "对账补记"
        default: return raw.isEmpty ? "—" : raw
        }
    }

    /// 标题来源人话（防编造审计位，详情可见）
    public static func titleSourceWord(_ raw: String) -> String {
        switch raw {
        case "server_llm": return "智能标题"
        case "user_excerpt": return "你的原话"
        case "job_name": return "作业名称"
        case "task_title": return "任务原题"
        case "record_excerpt": return "记录摘要"
        case "fallback": return "自动命名"
        default: return raw.isEmpty ? "—" : raw
        }
    }

    /// 流水记录者人话（history.by）
    public static func actorWord(_ raw: String?) -> String {
        switch raw {
        case "app": return "App 上报"
        case "collector": return "对账"
        case "bridge": return "自动作业"
        default: return raw ?? "系统"
        }
    }
}

// MARK: - 已耗时

public enum LedgerElapsed {
    /// 已耗时格式（规格 §4.1）：<1 小时 M:SS（2:13），
    /// ≥1 小时 H:MM:SS（1:02:13）；负值归 0。tabular
    /// 呈现由视图字体承担，本处只管位数口径
    public static func format(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        if total < 3600 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(
            format: "%d:%02d:%02d",
            total / 3600, (total % 3600) / 60, total % 60
        )
    }

    /// 已流逝秒数（服务端时刻同轴相减，负值归 0）
    public static func elapsed(
        startedAt: Double, serverNow: Double
    ) -> Double {
        max(0, serverNow - startedAt)
    }
}

// MARK: - 新鲜度（§2.5）

/// 台账新鲜度三档：心跳龄 ≤30 秒＝实时（不标注）；
/// 30 秒–5 分钟＝迟滞（弱标注「台账更新于…」）；
/// >5 分钟或无心跳＝停更（顶部明示，旧数据降陈旧
/// 呈现）。采集器死了与桥断了是两种状态：本档只管
/// 「桥在、心跳老」，断桥由拉取失败单独露面
public enum LedgerFreshness: Equatable, Sendable {
    case live
    case lagging
    case stalled

    public static func evaluate(heartbeatAge: Double?) -> LedgerFreshness {
        guard let age = heartbeatAge else { return .stalled }
        if age <= 30 { return .live }
        if age <= 300 { return .lagging }
        return .stalled
    }

    /// 新鲜度标注文案（live 无标注）；时刻取台账最后
    /// 入账时刻，缺失时只给状态词不编时刻
    public func note(
        ledgerUpdatedAt: Double?, calendar: Calendar = .current
    ) -> String? {
        switch self {
        case .live:
            return nil
        case .lagging:
            guard let at = ledgerUpdatedAt else { return "台账更新稍有延迟" }
            return "台账更新于 \(LedgerClock.time(at, calendar: calendar))"
        case .stalled:
            guard let at = ledgerUpdatedAt else { return "台账已停更" }
            return "台账已停更 · 最后更新 \(LedgerClock.time(at, calendar: calendar))"
        }
    }
}

/// 台账专用钟面格式（HH:mm／HH:mm:ss，数字 POSIX
/// 口径不随地区变体漂移；日历时区随入参）
public enum LedgerClock {
    public static func time(
        _ epoch: Double, calendar: Calendar = .current
    ) -> String {
        formatter("HH:mm", calendar: calendar)
            .string(from: Date(timeIntervalSince1970: epoch))
    }

    public static func timeWithSeconds(
        _ epoch: Double, calendar: Calendar = .current
    ) -> String {
        formatter("HH:mm:ss", calendar: calendar)
            .string(from: Date(timeIntervalSince1970: epoch))
    }

    private static func formatter(
        _ format: String, calendar: Calendar
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - 合并与排序

public enum LedgerMerge {
    /// 列表定序：开始时刻倒序，同刻以 id 兜底稳定序
    public static func sorted(_ items: [LedgerItem]) -> [LedgerItem] {
        items.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id < rhs.id
        }
    }

    /// 增量合并（?since 回执只含变更条目）：按 id 替
    /// 换旧条、插入新条、未变更条目原样保留，结果重
    /// 排定序。条目消失（桥侧压实清理）靠整页重拉对
    /// 账，不在本函数处理——增量面看不见删除是契约
    /// 本性，不许假装
    public static func merge(
        existing: [LedgerItem], changes: [LedgerItem]
    ) -> [LedgerItem] {
        guard !changes.isEmpty else { return existing }
        var byID: [String: LedgerItem] = [:]
        for item in existing { byID[item.id] = item }
        for item in changes { byID[item.id] = item }
        return sorted(Array(byID.values))
    }
}

// MARK: - 分组／页首／副题

public struct LedgerDayGroup: Equatable, Identifiable {
    public let title: String
    public let items: [LedgerItem]

    public var id: String { title }

    public init(title: String, items: [LedgerItem]) {
        self.title = title
        self.items = items
    }
}

public enum LedgerBoard {
    /// 按天分组（入参须已定序）：组头口径与动态页同
    /// 源（FeedBoard.groupTitle：今天/昨天/星期X/M月
    /// d日/yyyy年M月d日），不另立第二套日期口径
    public static func dayGroups(
        _ items: [LedgerItem], now: Date,
        calendar: Calendar = .current
    ) -> [LedgerDayGroup] {
        var groups: [LedgerDayGroup] = []
        for item in items {
            let date = Date(timeIntervalSince1970: item.startedAt)
            let title = FeedBoard.groupTitle(
                for: date, now: now, calendar: calendar
            )
            if let last = groups.last, last.title == title {
                groups[groups.count - 1] = LedgerDayGroup(
                    title: last.title, items: last.items + [item]
                )
            } else {
                groups.append(LedgerDayGroup(title: title, items: [item]))
            }
        }
        return groups
    }

    /// 页首计数（规格 §4.2）：优先用与列表同一 payload
    /// 的桥侧 counts（同快照，不许另拉一个计数接口打
    /// 架）；counts 缺失时才从条目现算兜底。口径＝
    /// 正在进行（queued＋running）、待审批单列
    public static func headerCounts(
        items: [LedgerItem], summary: LedgerSummary?
    ) -> (inProgress: Int, blockedApproval: Int) {
        if let summary {
            return (summary.inProgress, summary.blockedApproval)
        }
        var inProgress = 0
        var blocked = 0
        for item in items {
            switch item.status {
            case .queued, .running: inProgress += 1
            case .blockedApproval: blocked += 1
            default: break
            }
        }
        return (inProgress, blocked)
    }

    /// 页首总览行文案：「正在进行 N 件 · 待审批 M 件」
    /// （M＝0 不显后半）；全静止时如实给「现在没有进行
    /// 中的工作」，不拿 0 件凑行
    public static func headerText(
        inProgress: Int, blockedApproval: Int
    ) -> String {
        if inProgress == 0 && blockedApproval == 0 {
            return "现在没有进行中的工作"
        }
        var text = "正在进行 \(inProgress) 件"
        if blockedApproval > 0 {
            text += " · 待审批 \(blockedApproval) 件"
        }
        return text
    }

    /// 行副题（状态词＋真信息，规格 §3/§4）：进行中
    /// 带已耗时秒级值（由视图每秒重算喂 serverNow）；
    /// 证据迟滞加「最后确认 HH:mm:ss」标龄；失败／
    /// 取消带原因分类；失联带最后确认时刻。状态词只
    /// 走 LedgerText 人话，原始枚举不进副题
    public static func subtitle(
        for item: LedgerItem, serverNow: Double,
        calendar: Calendar = .current
    ) -> String {
        let word = LedgerText.statusWord(item.status)
        switch item.status {
        case .running:
            var text = "\(word) · 已运行 \(LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow)))"
            if item.evidenceLagging, let at = item.lastEvidenceAt {
                text += " · 最后确认 \(LedgerClock.timeWithSeconds(at, calendar: calendar))"
            }
            return text
        case .queued:
            return "\(word) · 已等 \(LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow)))"
        case .blockedApproval:
            return "\(word) · 已等 \(LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow)))"
        case .completed:
            guard let ended = item.endedAt else { return word }
            return "\(word) · \(LedgerClock.time(ended, calendar: calendar))"
        case .failed, .cancelled:
            guard let category = item.failReason?.category,
                  !category.isEmpty else { return word }
            return "\(word) · \(category)"
        case .stale:
            guard let at = item.lastEvidenceAt else {
                return "已失去联系"
            }
            return "已失去联系 · 最后确认 \(LedgerClock.time(at, calendar: calendar))"
        case .other:
            return word
        }
    }

    /// 详情时长行：活跃态＝已运行／已等时长，终态＝
    /// 总用时（起止同轴相减）；缺结束时刻的终态不编
    /// 时长、返回 nil 由视图不显该行
    public static func durationText(
        for item: LedgerItem, serverNow: Double
    ) -> String? {
        switch item.status {
        case .running:
            return "已运行 \(LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow)))"
        case .queued, .blockedApproval:
            return "已等 \(LedgerElapsed.format(seconds: LedgerElapsed.elapsed(startedAt: item.startedAt, serverNow: serverNow)))"
        case .completed, .failed, .cancelled:
            guard let ended = item.endedAt else { return nil }
            return "用时 \(LedgerElapsed.format(seconds: ended - item.startedAt))"
        case .stale, .other:
            return nil
        }
    }
}
