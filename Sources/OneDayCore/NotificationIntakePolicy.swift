import Foundation

/// 通知入账分级（§454，用户 2026-11-24 03:50 亲点
/// 「为什么每一次回复消息都有运行完成的提示」）：
/// 铃铛只装「需要用户知道或处理」的东西——回复本
/// 身即通知（§426 已在聊天侧定版），前台会话的正
/// 常完成不进铃铛；失败与待批永远逐条在账；背景事
/// 件留底，但同类短时窗内聚合为一条计数行，不许
/// 刷屏。本文件是入账判定的唯一落点：分类只认条
/// 目自带的结构信号（kind 与 refId），失败信号与
/// NotificationTier 的分类口径同源（kind 含 fail/
/// error）；View 与 Store 不许各自拼判定。
///
/// §459 修订（用户 2026-11-24 05:53/05:59 连点，
/// 上段「失败永远逐条在账」对自有会话作废）：自
/// 有会话的失败与完成同档不入账——§454 把失败一
/// 律列一级、吞掉了 §426 老口径（在场会话的完成
/// 与失败都不弹、只留底）；且 §454 的完成侧判据
/// 在真机漏判（用户本人会话完成漏成二级留底、
/// 铃铛总数 +1）。定因（生产实查）：服务端 run
/// 通知 refId＝网关 runs.session_id、与 App 会话
/// id 同键形（oneday-side-<uuid>，失败与完成两例
/// 均实证），漏点不在键形而在判据只认本地线程表
/// 快照的精确成员资格——快照缺一条即漏，实验室
/// 测试自带完整集合、结构上测不出。自有识别自
/// 此归一为两键任一命中（见 isOwnSessionRef）。
public enum NotificationIntakePolicy {

    public enum Disposition: Equatable, Sendable {
        /// 一级：即时＋留底，逐条呈现（待批/裁决回
        /// 执/失败与异常终态）
        case immediate
        /// 二级：留底，同类短窗可聚合（后台与定时任
        /// 务完成、监测变化、系统类）
        case aggregatable
        /// 三级：不进铃铛——不入名单、不入存档、不
        /// 进提醒规划（前台会话的正常完成）
        case suppressed
    }

    /// 二级聚合窗（秒，常量单源、不设用户开关）：
    /// 同类事件相邻间隔在此窗内链式合并。桥轮询
    /// 30 秒、cron/kanban 批量完成以分钟计——600
    /// 秒覆盖一波突发，又不把相隔久远的同类事件
    /// 误并成一行
    public static let aggregationWindow: TimeInterval = 600

    /// 自有会话识别（§459 归一）：两键任一命中即
    /// 自有——①refId 命中本机线程会话集（调用方
    /// 现取的 ChatThread.serverSessionID 全集）；
    /// ②refId 带 App 自铸会话 id 前缀（SideChat-
    /// Link.ownSessionPrefix：主线 oneday-main-／
    /// 旁聊 oneday-side-，与删除归档闸的自有判定
    /// 同源）。②锚在 App 实际持有/铸造的会话标
    /// 识上、不依赖本地线程表快照的完整度；服务
    /// 端自跑 run 的 session_id 为 run id 自指形、
    /// cron/外部会话为 api- 等外来形，都不带此前
    /// 缀，不受影响。无 refId 恒非自有（认不出不
    /// 压、宁可多留不可错杀的底线不变）
    static func isOwnSessionRef(
        _ refId: String?, userSessionIDs: Set<String>
    ) -> Bool {
        guard let refId, !refId.isEmpty else { return false }
        return userSessionIDs.contains(refId)
            || SideChatLink.isOwnSessionID(refId)
    }

    /// 条目 → 级。先判会话归属再判终态：自有会话
    /// 的完成与失败同档三级（不即时、不计未读、
    /// 只在入账口拦下并向桥确认已读）；非自有会
    /// 话的失败维持一级；待批与回执恒一级
    public static func disposition(
        for item: OverviewNotification,
        userSessionIDs: Set<String>
    ) -> Disposition {
        let own = isOwnSessionRef(
            item.refId, userSessionIDs: userSessionIDs
        )
        let kind = item.kind.lowercased()
        if kind.contains("fail") || kind.contains("error") {
            return own ? .suppressed : .immediate
        }
        // 待批请求与裁决回执恒一级：要用户处理或
        // 知晓结果的，不许聚合、不许压（其 refId
        // 为写闸请求 id、永不命中自有会话键）
        if item.kind == "approval_pending" || item.isDecisionReceipt {
            return .immediate
        }
        if item.kind == "task_completed" {
            return own ? .suppressed : .aggregatable
        }
        // 监测变化与未知 kind（系统类兜底）：二级
        return .aggregatable
    }

    /// 一批条目里要压下的 id（入账口收口用）：自
    /// 有识别含条目自带的前缀键，会话集为空也不
    /// 再整体失效（§454 的空集恒空守卫随归一退
    /// 役——它正是真机漏判的放大器之一）
    public static func suppressedIDs(
        notifications: [OverviewNotification],
        userSessionIDs: Set<String>
    ) -> [String] {
        notifications.compactMap { item in
            disposition(
                for: item, userSessionIDs: userSessionIDs
            ) == .suppressed ? item.id : nil
        }
    }

    // MARK: - 聚合行

    /// 铃铛列表行：单条，或同类二级事件的聚合
    /// （items 新→旧，lead＝最新一条，行面以它
    /// 为准、计数在元信息行申报）
    public struct Row: Equatable, Sendable, Identifiable {
        public let items: [OverviewNotification]

        public init(items: [OverviewNotification]) {
            self.items = items
        }

        public var lead: OverviewNotification { items[0] }
        public var id: String { lead.id }
        public var isAggregate: Bool { items.count > 1 }
        public var hasUnread: Bool {
            items.contains { !$0.read }
        }
    }

    /// 把一日的条目（新→旧序，NotificationGrouping
    /// 组内序）折成行：只有二级条目参与聚合，键＝
    /// kind；与上一条同键且间隔不超过聚合窗才并
    /// 入（链式）；一级条目恒单行并截断聚合链；
    /// 时间解析不出的条目不参与聚合（证不了窗）
    public static func rows(
        items: [OverviewNotification]
    ) -> [Row] {
        var result: [Row] = []
        var openKind: String?
        var openItems: [OverviewNotification] = []
        var openLastDate: Date?

        func flush() {
            guard !openItems.isEmpty else { return }
            result.append(Row(items: openItems))
            openItems = []
            openKind = nil
            openLastDate = nil
        }

        for item in items {
            // 行折叠只分一级/二级：三级条目入账口已
            // 拦下、不该到这；此处以空会话链判定——
            // 集合识别不在呈现层重演，但条目自带的
            // 自有前缀是结构信号、随条目同判：已入
            // 账存量里的自有终态以单行呈现（不回溯
            // 删除、不再并入聚合计数行）
            let level = disposition(
                for: item, userSessionIDs: []
            )
            let date = NotificationGrouping.parseCreatedAt(
                item.createdAt
            )
            guard level == .aggregatable, let date else {
                flush()
                result.append(Row(items: [item]))
                continue
            }
            if openKind == item.kind, let last = openLastDate,
               last.timeIntervalSince(date) <= aggregationWindow {
                openItems.append(item)
                openLastDate = date
            } else {
                flush()
                openKind = item.kind
                openItems = [item]
                openLastDate = date
            }
        }
        flush()
        return result
    }
}
