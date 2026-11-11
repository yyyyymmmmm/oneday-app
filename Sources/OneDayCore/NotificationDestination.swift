import Foundation

/// 通知条目的落点解析（§123 H2，闭环包）：通知中心保留
/// 汇集定位（C3 定版），但条目必须点达对象本身，不再是
/// 点开只展开机器原文的死胡同。落点按类型与联动键解析
/// （纯函数，View 只消费结果）：
///
/// - 审批裁决回执：默认回枢纽审批段。§123 当时的定案
///   「**不回原会话**」依据是 write-gate 契约无会话字
///   段——契约事实不变（记录本体确实无 session 字段），
///   但 §165（锚点包）起归属由伴生时序关联在契约之外
///   补出：本机已落锚的回执改走 approvalAnchor 点达原
///   对话的锚定行（解析见 ApprovalNotificationRouting，
///   本 resolve 只管无锚时的现行落点）；未关联的记录
///   仍以审批段为家，带 refId 时聚焦到那一条，无
///   refId（旧桥回执）只达段；
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
    /// 原对话的锚定行（§165）：切到该线程并滚动定位＋
    /// 点亮——记录已在本机落锚时优先于枢纽落点
    case approvalAnchor(threadID: UUID, approvalKey: String)
    /// 原对话（§165）：锚会话有本地线程但条目还没物
    /// 化——只切线程、不定位，不许假定位
    case approvalThread(threadID: UUID)
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
