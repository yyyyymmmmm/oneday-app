import Foundation

/// 流式累积器（0.5.1 发布闸，§409 步 E 瘦身为纯累
/// 积器）：SSE 增量逐字入账，fullText 恒等于全部
/// 已喂增量的精确拼接——落盘与收尾判定走 fullText，
/// 节流概念已删、永不丢字。
///
/// 沿革：0.5.1 时本型是「发布合并闸」（§32：80ms
/// 窗/64 字阈值合并，把全文快照发布给视图状态），
/// 背景是旧 runStream 逐增量写 @State 引发下游逐
/// 增量重排。§409 简化模型取消流式逐字呈现（生成
/// 期只有固定高占位行、成型整条落定）后，快照发布
/// 失去消费方：步 A 先断呈现写（视图不再读快照），
/// 步 E 再删发布语义本体——时间窗/字符阈值/pub-
/// lishedText/pendingText/collectDue/flush 与时刻
/// 参数全删，只剩累积。类型名保留（调用方与账本
/// 沿革不断链），语义以本注为准。
public struct StreamPublishGate: Equatable {
    /// 已累积全文（＝全部已喂增量的精确拼接）
    public private(set) var text = ""

    public init() {}

    /// 本轮是否已产生任何内容
    public var hasContent: Bool { !text.isEmpty }
    /// 精确全文：落盘与收尾判定走它
    public var fullText: String { text }

    /// 喂入一个增量：立即入账。空增量不改变任何
    /// 状态
    public mutating func offer(_ delta: String) {
        guard !delta.isEmpty else { return }
        text += delta
    }

    /// 新一轮流开始时归零
    public mutating func reset() {
        self = StreamPublishGate()
    }
}
