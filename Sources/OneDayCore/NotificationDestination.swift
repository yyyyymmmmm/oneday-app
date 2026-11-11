import Foundation

/// 通知条目的落点解析（§123 H2，闭环包）：通知中心保留
/// 汇集定位（C3 定版），但条目必须点达对象本身，不再是
/// 点开只展开机器原文的死胡同。落点按类型与联动键解析
/// （纯函数，View 只消费结果）：
///
/// - 审批裁决回执：回枢纽审批段。**不回「原会话」**——
///   write-gate 记录契约里没有 thread/session 字段
///   （ChatApprovalCards 文件头注为据），裁决可能来自
///   后台审查/其他端，根本不存在「原会话」；记录的家
///   就是审批段的已决历史，带 refId 时聚焦到那一条，
///   无 refId（旧桥回执）只达段；
/// - 监测变化：带 refId（伴生 1.0.14 起 monitor 通知带
///   监测 id、changeId 带变化 id）直达监测详情、再达
///   具体变化；存量通知无 refId，只能达监测段——如实
///   降级，不拿标题文本等弱信号猜是哪条监测；
/// - 其余类型：无落点（.none），行面不带去向箭头。
public enum NotificationDestination: Equatable, Sendable {
    /// 枢纽审批段，并聚焦这条已决记录
    case approvalDecision(id: String)
    /// 枢纽审批段（无具体记录可聚焦）
    case approvalHome
    /// 监测详情页，并继续达具体变化（changeID 为 nil
    /// 时只达监测详情）
    case monitorChange(monitorID: String, changeID: String?)
    /// 枢纽监测段
    case monitorsHome
    case none

    public static func resolve(
        _ notification: OverviewNotification
    ) -> NotificationDestination {
        if notification.isDecisionReceipt {
            if let refId = notification.refId, !refId.isEmpty {
                return .approvalDecision(id: refId)
            }
            return .approvalHome
        }
        if notification.isMonitorChange {
            if let refId = notification.refId, !refId.isEmpty {
                return .monitorChange(
                    monitorID: refId,
                    changeID: notification.changeId
                )
            }
            return .monitorsHome
        }
        return .none
    }

    /// 是否有落点（行面据此决定带不带去向箭头）
    public var hasDestination: Bool {
        self != .none
    }
}
