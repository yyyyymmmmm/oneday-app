import Foundation

/// 顶部任务进展胶囊（0.37.0 模型包）：独立悬浮 pill，
/// 与身份胶囊并存、不合并（model-provider-status-
/// design-20261110 §4 定版）。数据源唯一＝工作台账的
/// 进行中集合（与台账同 payload、同已耗时算法），不
/// 另建第二套运行状态。呈现边界：
/// - 只报「当前屏没有正在呈现的运行」：本聊自己的
///   运行（sessionId 命中当前会话）不进胶囊——本页
///   消息区已有呈现；本聊生成中胶囊为他聊/后台而设。
/// - 「正在做什么」只有台账标题（服务端标题规则链的
///   产物）＋件数，工具级以下不编、无 AI 摘要。
/// - 结束/失败/取消即消失（留痕归台账，胶囊不承担）。
public enum ProgressCapsule {

    /// 胶囊内容：件数＋领衔条目（最近开始的一件）
    public struct Content: Equatable, Sendable {
        /// 进行中件数（已剔除当前会话的）
        public var count: Int
        /// 领衔条目标题（台账标题原文）
        public var headlineTitle: String
        /// 领衔条目 id（点击下钻用）
        public var headlineItemID: String
        /// 领衔条目开始时刻（服务端时间轴，已耗时由
        /// 视图以 LedgerElapsed 同算法逐秒算）
        public var headlineStartedAt: Double

        /// 主行文案：单件＝标题本身；多件＝「正在进行
        /// N 件 · 最近：标题」（§4.2 收敛式）
        public var headlineText: String {
            if count <= 1 { return headlineTitle }
            return "正在进行 \(count) 件 · \(headlineTitle)"
        }
    }

    /// 自台账条目派生胶囊：取状态为 running/queued 的
    /// 条目，剔除当前会话名下的（currentSessionID 为
    /// nil 时不剔除），按 startedAt 取最近一件领衔。
    /// 空集返回 nil＝胶囊不出现。blockedApproval 不进
    /// 胶囊（那是审批角标与台账页首的事，不重复占位）。
    public static func derive(
        items: [LedgerItem], currentSessionID: String?
    ) -> Content? {
        let active = items.filter { item in
            switch item.status {
            case .running, .queued:
                break
            default:
                return false
            }
            if let currentSessionID, !currentSessionID.isEmpty,
               item.sessionId == currentSessionID {
                return false
            }
            return true
        }
        guard let headline = active.max(by: {
            $0.startedAt < $1.startedAt
        }) else { return nil }
        return Content(
            count: active.count,
            headlineTitle: headline.title,
            headlineItemID: headline.id,
            headlineStartedAt: headline.startedAt
        )
    }
}
