import Foundation

/// 贴底单一所有者（§135，发送空屏诊断 A 案收口）：
/// 0.2.2–0.41.0 逐包叠出的贴底触发有六路（条目数变
/// 化／发送令牌／流式跟随／键盘两路／首帧定版／线程
/// 恢复），且发送令牌一路在 scrollToBottom 内置复贴
/// 之外自外加一层 120ms 复贴——一次发送可连发 3–5
/// 次强制跳底，每次都强迫 LazyVStack 对长线程尾部
/// 做一轮估算→量实的布局 churn（外部同型故障见诊
/// 断报告 §二：Tactic Remote 的 scrollTo livelock
/// 受控复现、Apple Developer Forums thread/741406）。
/// 本协调者把「要不要执行即时贴、复贴归谁」收成纯
/// 逻辑单点，视图层只剩一个执行口：
/// - 每次已执行贴底后全局只挂一笔复贴（代号制）：
///   新贴底顶替旧复贴、复贴至多消费一次、切线程作
///   废——复贴层数恒为一；
/// - 同帧合并：距上次已执行贴底不足合并窗、且其复
///   贴仍挂账的重复请求不再执行即时贴（内容落点由
///   挂账复贴在 120ms 处校正），杀同帧多路 onChange
///   的连发。
public struct BottomStickCoordinator: Equatable {
    /// 同帧合并窗（秒）：此窗内的重复请求合并
    public static let coalesceWindow: TimeInterval = 0.05
    /// 唯一复贴延迟（毫秒）：贴底后一拍复核距底的
    /// 时点（与 BottomSettle 的量实原理同口径）
    public static let restickDelayMilliseconds = 120

    /// 请求裁决：执行即时贴（带本代代号）／已合并
    public enum Decision: Equatable {
        case perform(generation: Int)
        case coalesced
    }

    /// 已执行贴底的代号（单调递增；作废旧复贴凭据）
    public private(set) var generation = 0
    /// 最近一次已执行贴底的时刻（请求方喂入的时钟）
    private var lastPerformedAt: TimeInterval?
    /// 挂账中的复贴归属代号（nil＝无复贴在途）
    private var restickArmedGeneration: Int?

    public init() {}

    /// 发起一次贴底请求。now 为单调时钟读数（秒，
    /// 请求方用 Date().timeIntervalSince1970 即可——
    /// 只比差值、不比绝对值）
    public mutating func requestStick(
        at now: TimeInterval
    ) -> Decision {
        if let last = lastPerformedAt,
           now - last < Self.coalesceWindow,
           restickArmedGeneration != nil {
            return .coalesced
        }
        generation += 1
        lastPerformedAt = now
        restickArmedGeneration = generation
        return .perform(generation: generation)
    }

    /// 消费复贴：仅当代号与挂账吻合才放行，且至多
    /// 放行一次——过期代号（已被更新的贴底顶替）与
    /// 重复消费一律拒绝
    public mutating func consumeRestick(
        generation candidate: Int
    ) -> Bool {
        guard restickArmedGeneration == candidate else {
            return false
        }
        restickArmedGeneration = nil
        return true
    }

    /// 作废一切在途状态（切线程）：代号推进、挂账
    /// 清空、合并窗重置
    public mutating func invalidate() {
        generation += 1
        lastPerformedAt = nil
        restickArmedGeneration = nil
    }
}
