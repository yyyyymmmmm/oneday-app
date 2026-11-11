import Foundation

/// 通知详情与列表呈现派生（§166，通知页按用户亲递原
/// 型 oneday-notifications.html 重塑）：列表行与详情页
/// 需要的全部结构化派生集中在此——图标类、类别词、
/// 结果标签、「涉及的变更」行、落点按钮文案、筛选与
/// 副标题。View 只消费，不许各自拼判定。
///
/// 数据纪律（与 NotificationSummary 同源）：变更行只
/// 能从 body 文法的结构解析派生（共用 Notification-
/// Summary 的 parse* 入口）；文法不命中 → 变更行为
/// 空，详情只显人话摘要＋技术记录，**不许编造行**。
/// 技能批文法只给全批 op 清单、不给逐技能归属：多
/// 技能时逐名只列名（描述留空），计数描述只在单技
/// 能（归属确凿）时落行，不许把全批计数摊到单个技
/// 能头上。
public enum NotificationDetail {

    // MARK: - 图标类（按 kind 取符号）

    public enum IconKind: Equatable, Sendable {
        /// 审批裁决回执：文档符号
        case decision
        /// 监测变化：波形符号
        case monitor
        /// 任务结果：清单符号
        case task
        /// 其余/未知：铃铛符号
        case other
    }

    public static func iconKind(for item: OverviewNotification) -> IconKind {
        if item.isDecisionReceipt { return .decision }
        if item.isMonitorChange { return .monitor }
        if item.kind == "task_completed" { return .task }
        return .other
    }

    // MARK: - 类别词（元信息行/详情时间行共用）

    public static func categoryName(
        for item: OverviewNotification,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        if item.isDecisionReceipt {
            return L10n.string("审批结果", locale: locale)
        }
        if item.isMonitorChange {
            return L10n.string("监测变化", locale: locale)
        }
        if item.kind == "task_completed" {
            return L10n.string("任务结果", locale: locale)
        }
        return L10n.string("通知", locale: locale)
    }

    // MARK: - 结果标签（详情页）

    public enum Outcome: Equatable, Sendable {
        case approved, rejected, recovered, completed

        public func label(locale: Locale = AppLocale.uiLocale) -> String {
            switch self {
            case .approved: return L10n.string("已批准", locale: locale)
            case .rejected: return L10n.string("已被驳回", locale: locale)
            case .recovered: return L10n.string("已恢复", locale: locale)
            case .completed: return L10n.string("已完成", locale: locale)
            }
        }
    }

    /// 结果标签派生：只认事件自带的结构信号——裁决
    /// 类认标题语态（与摘要层同一派生入口）；监测类
    /// 正文/标题明说「恢复」才给已恢复（引擎成形文
    /// 案、非猜测）；任务完成 kind 给已完成。其余无
    /// 标签（nil），不许拿弱信号凑
    public static func outcome(
        for item: OverviewNotification
    ) -> Outcome? {
        if item.isDecisionReceipt {
            switch NotificationSummary.decision(forTitle: item.title) {
            case .approved: return .approved
            case .rejected: return .rejected
            case .unknown: return nil
            }
        }
        if item.isMonitorChange {
            return (item.title.contains("恢复") || item.body.contains("恢复"))
                ? .recovered : nil
        }
        if item.kind == "task_completed" { return .completed }
        return nil
    }

    // MARK: - 「涉及的变更」行

    public struct ChangeLine: Equatable, Sendable, Identifiable {
        /// 主行：对象显示名（技能显示名/记忆条目摘录）
        public let name: String
        /// 副行：标识（技能 id 等机器标识；无则 nil）
        public let identifier: String?
        /// 右侧/下行：变更描述（归属不确凿时为空串，
        /// 视图不显——只列名、不编造计数）
        public let changeDescription: String

        public var id: String {
            name + "\u{1}" + (identifier ?? "") + "\u{1}" + changeDescription
        }

        public init(name: String, identifier: String?, changeDescription: String) {
            self.name = name
            self.identifier = identifier
            self.changeDescription = changeDescription
        }
    }

    /// 技能 id → 显示名（用户原型亲定的叫法，仅收原
    /// 型与生产回执里出现过的 id；表外 id 原样呈现为
    /// 名、标识留空，不许自创译名）
    private static let skillDisplayNames: [String: String] = [
        "phone-bridge": "设备连接",
        "blocked-page-recovery": "页面恢复",
        "home-appliance-vetting": "家电审查",
        "weather-forecast": "天气预报",
        "claude-design": "Claude Design",
        "maps": "地图",
    ]

    public static func changeLines(
        for item: OverviewNotification,
        locale: Locale = AppLocale.uiLocale
    ) -> [ChangeLine] {
        guard item.isDecisionReceipt else { return [] }
        let decision = NotificationSummary.decision(forTitle: item.title)
        guard decision != .unknown else { return [] }
        if item.body.hasPrefix("batch(") {
            return skillChangeLines(body: item.body, locale: locale)
        }
        return memoryChangeLines(
            body: item.body, decision: decision, locale: locale
        )
    }

    /// 技能批变更行：单技能归属确凿 → 名＋标识＋全批
    /// 聚合描述；多技能 → 逐名只列名（描述空），全批
    /// 计数由详情正文（摘要层聚合句）承载
    private static func skillChangeLines(
        body: String, locale: Locale
    ) -> [ChangeLine] {
        guard let batch = NotificationSummary.parseSkillBatch(body)
        else { return [] }
        let aggregate = batch.order.map { op -> String in
            let n = batch.counts[op] ?? 0
            switch op {
            case "patch":
                return L10n.format("改了 %@ 处内容", locale: locale, String(n))
            case "write_file":
                return L10n.format("写了 %@ 个文件", locale: locale, String(n))
            default:
                return L10n.format("新建了 %@ 个文件", locale: locale, String(n))
            }
        }.joined(separator: L10n.string("、", locale: locale))
        return batch.names.map { id in
            let display = skillDisplayNames[id]
            return ChangeLine(
                name: display ?? id,
                identifier: display == nil ? nil : id,
                changeDescription: batch.names.count == 1 ? aggregate : ""
            )
        }
    }

    /// 记忆类变更行：逐 op 本体（名＝条目摘录折叠
    /// 60 字，描述＝按语态的完成式短句）
    private static func memoryChangeLines(
        body: String,
        decision: NotificationSummary.Decision,
        locale: Locale
    ) -> [ChangeLine] {
        let approved = decision == .approved
        if body.hasPrefix("apply ") {
            guard let parsed = NotificationSummary.parseApply(body, locale: locale)
            else { return [] }
            return parsed.ops.map { op in
                let name = NotificationSummary.foldDetail(op.detail)
                let description: String
                switch op.verb {
                case "add":
                    description = L10n.string(
                        approved ? "已新增" : "未新增", locale: locale)
                case "remove":
                    description = L10n.string(
                        approved ? "已删除" : "未删除", locale: locale)
                default:
                    description = L10n.string(
                        approved ? "已替换" : "未替换", locale: locale)
                }
                return ChangeLine(
                    name: name, identifier: nil,
                    changeDescription: description
                )
            }
        }
        if let (_, detail) = NotificationSummary.parseSimpleOp(
            body, verb: "add to ", locale: locale
        ) {
            let name = NotificationSummary.foldDetail(detail)
            guard !name.isEmpty else { return [] }
            return [ChangeLine(
                name: name, identifier: nil,
                changeDescription: L10n.string(
                    approved ? "已新增" : "未新增", locale: locale)
            )]
        }
        if let (_, detail) = NotificationSummary.parseSimpleOp(
            body, verb: "remove from ", locale: locale
        ) {
            let name = NotificationSummary.foldDetail(detail)
            guard !name.isEmpty else { return [] }
            return [ChangeLine(
                name: name, identifier: nil,
                changeDescription: L10n.string(
                    approved ? "已删除" : "未删除", locale: locale)
            )]
        }
        if let parsed = NotificationSummary.parseReplace(body, locale: locale) {
            return [ChangeLine(
                name: parsed.old, identifier: nil,
                changeDescription: L10n.format(
                    approved ? "已改为「%@」" : "未改为「%@」",
                    locale: locale, parsed.new
                )
            )]
        }
        return []
    }

    /// 变更区段标题：监测类叫「变化详情」（与原型同
    /// 词、目录已有键），任务类「任务结果」，其余
    /// 「涉及的变更」
    public static func changeSectionTitle(
        for item: OverviewNotification,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        if item.isMonitorChange {
            return L10n.string("变化详情", locale: locale)
        }
        if item.kind == "task_completed" {
            return L10n.string("任务结果", locale: locale)
        }
        return L10n.string("涉及的变更", locale: locale)
    }

    // MARK: - 审批固定提示与落点按钮

    /// 审批类详情的固定提示（任务简报逐字文案）：裁
    /// 决回执一律带；非裁决类不带
    public static func approvalNote(
        for item: OverviewNotification,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        guard item.isDecisionReceipt else { return nil }
        return L10n.string(
            "审批已结束，不需要再次批准。已批准不等于已执行成功，请核对执行记录。",
            locale: locale
        )
    }

    /// 落点按钮文案：按落点类型定（审批记录/原对话/
    /// 监测详情三形与原型 destination 同构）。锚点落
    /// 点（§165 approvalAnchor/approvalThread）由视
    /// 图以 hasAnchorRoute 申报；§166 合裁后落点枚举
    /// 本身亦直达同文案，两路同口径、不另建第二套
    /// 跳转
    public static func destinationLabel(
        destination: NotificationDestination,
        hasAnchorRoute: Bool,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        if hasAnchorRoute {
            return L10n.string("返回关联会话", locale: locale)
        }
        switch destination {
        case .approvalAnchor, .approvalThread:
            return L10n.string("返回关联会话", locale: locale)
        case .approvalDecision, .approvalHome:
            return L10n.string("查看审批记录", locale: locale)
        case .monitorChange, .monitorsHome:
            return L10n.string("查看监测详情", locale: locale)
        case .none:
            return nil
        }
    }

    // MARK: - 筛选与副标题（列表面）

    public enum Filter: Equatable, Sendable {
        case all, unread
    }

    public static func filtered(
        _ items: [OverviewNotification], filter: Filter
    ) -> [OverviewNotification] {
        switch filter {
        case .all: return items
        case .unread: return items.filter { !$0.read }
        }
    }

    /// 副标题（列表态）：未读数出自桥数据实算，不许
    /// 写死；零未读给「已全部读过」形（与原型同口径）
    public static func subtitle(
        unreadCount: Int,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        unreadCount > 0
            ? L10n.format(
                "%lld 条未读 · 按时间排列",
                locale: locale, unreadCount
            )
            : L10n.string("已全部读过 · 按时间排列", locale: locale)
    }
}
