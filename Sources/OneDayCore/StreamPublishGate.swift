import Foundation

/// 流式发布合并闸（0.5.1，DESIGN-V4 §32；B 案拆解清单
/// 1.1 照改）：SSE 增量先攒缓冲，按时间窗或字符阈值合
/// 并发布，不再逐增量写视图状态。
///
/// 背景：0.5.0 前 ChatView.runStream 每个 SSE 增量直接
/// 写 @State 发布（每秒数十次），下游 StreamingText 逐
/// 增量整串重分词＋视图重排。Enchanted（Throttler
/// 100ms 合并）与 Fullmoon（每 4 token 发布，注释带
/// 「逐 token 更新约损 15% 生成速度」实测账）两家独立
/// 收敛到同一结论，OneDay 补上这一层。
///
/// 与 StreamFollowGate（0.4.2，BottomFollow.swift）的
/// 分工：本闸管「何时把全文快照写进视图状态」（发布
/// 频率），FollowGate 管「何时放行一次贴底滚动」（滚
/// 动频率）；两者串联、互不替代——发布变稀后 Follow-
/// Gate 的 ≥40 字判定仍按已发布全文长度记账，口径不变。
///
/// 纯逻辑：时刻由调用方以单调时钟（秒）注入，不自读
/// 时钟，单测可钉死。收尾口径：fullText 恒等于全部喂
/// 入增量的精确拼接，落盘走 fullText、不经发布快照，
/// 节流永不丢字。
public struct StreamPublishGate: Equatable {
    /// 合并发布的时间窗（秒）：距上次发布满窗即发布
    public static let windowSeconds: TimeInterval = 0.08
    /// 字符阈值：待发布增量累计字符数达标即发布（与
    /// 时间窗先到为准）
    public static let characterThreshold = 64

    /// 已发布全文（视图当前应显示的快照）
    public private(set) var publishedText = ""
    /// 已攒下、尚未发布的增量拼接
    public private(set) var pendingText = ""
    /// 上次发布时刻（调用方单调时钟）；nil＝本轮未发布过
    private var lastPublishTime: TimeInterval?

    public init() {}

    /// 是否有攒着未发布的增量
    public var hasPending: Bool { !pendingText.isEmpty }
    /// 本轮是否已产生任何内容（已发布或待发布）
    public var hasContent: Bool {
        !publishedText.isEmpty || !pendingText.isEmpty
    }
    /// 精确全文（已发布＋待发布）：落盘与收尾判定走它
    public var fullText: String { publishedText + pendingText }

    /// 喂入一个增量。满足任一条件时发布并返回新的全文
    /// 快照，否则返回 nil（继续攒）：
    /// - 本轮首个非空增量立即发布（首字延迟不被窗口吞）；
    /// - 距上次发布 ≥ windowSeconds；
    /// - 待发布累计 ≥ characterThreshold 字符。
    /// 空增量永不触发发布、也不改变任何状态。
    @discardableResult
    public mutating func offer(
        _ delta: String, at now: TimeInterval
    ) -> String? {
        guard !delta.isEmpty else { return nil }
        pendingText += delta
        guard let last = lastPublishTime else {
            return publish(at: now)
        }
        if now - last >= Self.windowSeconds {
            return publish(at: now)
        }
        if pendingText.count >= Self.characterThreshold {
            return publish(at: now)
        }
        return nil
    }

    /// 定时巡查（视图侧 ticker 调用）：低速流的尾巴增量
    /// 靠它到期发布，不必等下一个增量到达。待发布非空
    /// 且距上次发布已满窗时返回全文快照，否则 nil。
    public mutating func collectDue(at now: TimeInterval) -> String? {
        guard hasPending else { return nil }
        guard let last = lastPublishTime else {
            return publish(at: now)
        }
        guard now - last >= Self.windowSeconds else { return nil }
        return publish(at: now)
    }

    /// 强制发布残余（流结束／用户取消的收尾）：有残余
    /// 返回全文快照；无残余返回 nil，不多发一次无变化
    /// 的发布。
    public mutating func flush(at now: TimeInterval) -> String? {
        guard hasPending else { return nil }
        return publish(at: now)
    }

    /// 新一轮流开始时归零
    public mutating func reset() {
        self = StreamPublishGate()
    }

    private mutating func publish(at now: TimeInterval) -> String {
        publishedText += pendingText
        pendingText = ""
        lastPublishTime = now
        return publishedText
    }
}
