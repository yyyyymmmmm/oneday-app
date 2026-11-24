import Foundation

/// 台账 154／G-04 发件箱自动重发策略（DESIGN §336）：
/// 纯判定层——给定条目的发送状态与本条的自动重试
/// 记账，回答「现在能不能自动再发」。网络与落盘动
/// 作在 App 层（ChatView 的 drain 与 OutboxRetry-
/// Store），本文件只算账、可单测钉死。
///
/// 与 §237 的分工（单一判定源在本策略）：ChatSend-
/// State.mayAutoResume 只述「未落定瞬态可由恢复逻
/// 辑无条件接管」这一状态事实；失败态在 §237 当时
/// 定为只许手点，G-04（大厂差距审计，2026-11-18）
/// 改判为补自动重发——本策略承接改判：失败态可自
/// 动重试，但必须有界（次数上限＋指数退避），耗尽
/// 后回落手点，不许无限敲服务端。
public struct OutboxRetryRecord: Codable, Equatable, Sendable {
    /// 已执行的自动重试次数（手点重发不计、不清——
    /// 清零只发生在投递成功/撤回/编辑回收时，由
    /// App 层在落定点清账）
    public var attempts: Int
    /// 最近一次自动重试的发起时刻（退避起算点）
    public var lastAttemptAt: Date?
    /// 人工接管标记：本条只许用户手点，自动链永不
    /// 碰。落点＝「提交段孤儿」（状态 sending 但 run
    /// 账本无此轮——极小窗口内进程身亡，服务端是否
    /// 已受理不可知）：自动重发有重复投递风险，先
    /// 浮现为可见待发、交用户裁决
    public var manualOnly: Bool

    public init(
        attempts: Int = 0,
        lastAttemptAt: Date? = nil,
        manualOnly: Bool = false
    ) {
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.manualOnly = manualOnly
    }
}

public enum OutboxAutoRetryPolicy {
    /// 失败态自动重试上限：3 次（首发不算自动重试；
    /// 3 次自动重试仍失败即回落手点，红叹号与动作
    /// 面的手动入口恒在）
    public static let maxAutoAttempts = 3
    /// 退避基数：第 n 次自动重试失败后，下一次须等
    /// base × 2^(n-1)（30s／60s／120s），封顶 300s
    public static let baseBackoffSeconds: TimeInterval = 30
    public static let maxBackoffSeconds: TimeInterval = 300

    public enum Decision: Equatable, Sendable {
        /// 不在发件箱内（无状态/已投递）
        case notInQueue
        /// 提交段在飞：run 账本与对账链管辖，自动链
        /// 不许插手（§58 铁律：结果未知永不自动重发）
        case ownedByRunLedger
        /// 现在可自动再发
        case autoNow
        /// 退避未满，等到该时刻后可再发
        case backoff(until: Date)
        /// 只许手点（次数耗尽或人工接管标记）
        case manualOnly
    }

    public static func decision(
        state: ChatSendState?,
        record: OutboxRetryRecord?,
        now: Date
    ) -> Decision {
        guard let state, state.remainsInQueue else {
            return .notInQueue
        }
        if state == .sending {
            return .ownedByRunLedger
        }
        if record?.manualOnly == true {
            return .manualOnly
        }
        switch state {
        case .queued, .uploading, .linking:
            // 准备段瞬态（上传/链接中被进程中断）：从
            // 未抵达提交段，恢复逻辑无条件接管（§237
            // mayAutoResume 的消费点在此）
            return .autoNow
        case .failed:
            let attempts = record?.attempts ?? 0
            if attempts >= maxAutoAttempts {
                return .manualOnly
            }
            guard attempts > 0, let last = record?.lastAttemptAt
            else {
                // 从未自动重试过：首次自动重试不等退避
                // （失败本身已经历过一轮网络往返与用户
                // 可见的失败呈现，不必再罚等）
                return .autoNow
            }
            let until = last.addingTimeInterval(
                backoffSeconds(afterAttempts: attempts)
            )
            return now >= until ? .autoNow : .backoff(until: until)
        case .sending, .delivered:
            // .sending 已在上方裁决；.delivered 被
            // remainsInQueue 守卫挡下，两臂不可达，
            // 为穷尽 switch 而留
            return .notInQueue
        }
    }

    /// 第 n 次自动重试失败后的退避秒数（n 从 1 起）
    public static func backoffSeconds(afterAttempts attempts: Int) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        let scaled = baseBackoffSeconds
            * pow(2.0, Double(attempts - 1))
        return min(scaled, maxBackoffSeconds)
    }
}
