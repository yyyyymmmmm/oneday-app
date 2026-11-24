import Foundation

/// 流式分段装配器（0.50.53，第 93 条；§409 步 E
/// 随闸瘦身）：一轮 run 的正文不是一条文本，而是
/// 被工具调用切开的若干助理段（服务端落库即一段
/// 一条消息：段 A 正文→工具→段 B 正文）。段的身
/// 份以服务端事件序为准：tool.started 是段边界信
/// 号，边界到达即封存当前段、下一段增量进新累积器。
///
/// 病根（第 93 条定案）：旧装配只有一只整轮单缓冲
/// 的发布闸，followRunEvents 的工具事件分支从不
/// 封段——跨工具边界后，新段增量继续拼进上一段的
/// 缓冲，直播呈现里上一段全文被带进下一段（半截
/// 落盘后再重挂 events 时更与已落盘条目同屏双份
/// 呈现）。修法不是呈现层去重，而是装配层按段分
/// 开：每段一只独立累积器，封段后旧段只读、新段
/// 从空起步。
///
/// §409 步 E：段内发布语义（窗口合并/快照/collect-
/// Due/flush）随 StreamPublishGate 瘦身一并删除，
/// 时刻参数全删；fullSegments/mergedFullText 口径
/// 与第 93 条账本逐字不变——半截落盘按段成条与
/// 落定兜底合并都读这里。
public struct StreamSegmentAssembler: Equatable {
    /// 已封存段的全文（按事件序，只读）：封段时取
    /// 当前段精确全文，非空才入列——空段不存在
    public private(set) var sealedSegments: [String] = []
    /// 当前打开段的累积器（本段增量在此入账）
    public private(set) var currentGate = StreamPublishGate()

    public init() {}

    /// 当前段精确全文：收尾判定与落盘走它
    public var currentFullText: String {
        currentGate.fullText
    }

    /// 当前段是否已有任何内容
    public var hasCurrentContent: Bool {
        currentGate.hasContent
    }

    /// 全部段的精确全文（事件序）：封存段＋当前段
    /// （有内容才计入）——半截落盘按段成条的源头
    public var fullSegments: [String] {
        var all = sealedSegments
        if currentGate.hasContent {
            all.append(currentGate.fullText)
        }
        return all
    }

    /// 落定合并口径的全文：各段以空行连接——与
    /// RunTranscriptSettle 对 transcript 各段正文的
    /// 拼接（"\n\n"）逐字同制，直播期的兜底落定与
    /// transcript 落定自此同文
    public var mergedFullText: String {
        fullSegments.joined(separator: "\n\n")
    }

    /// 喂入当前段一个增量（立即入账）
    public mutating func offer(_ delta: String) {
        currentGate.offer(delta)
    }

    /// 段边界（工具调用开始）：封存当前段——取精
    /// 确全文，非空才入封存列，随后当前累积器归
    /// 零，下一段增量从空起步。当前段为空时无段
    /// 可封（并行工具连发多次边界、工具先行轮次
    /// 都走此支），返回 nil 且不产空段。返回封存
    /// 的段全文（未封成时 nil）
    @discardableResult
    public mutating func sealCurrentSegment() -> String? {
        let text = currentGate.fullText
        guard !text.isEmpty else { return nil }
        sealedSegments.append(text)
        currentGate.reset()
        return text
    }

    /// 新一轮流开始时整器归零（封存列与当前段同清）
    public mutating func reset() {
        self = StreamSegmentAssembler()
    }

    /// 恢复回填（半截落盘后重进本轮）：封存段与打
    /// 开段按落盘原序装回——打开段整段入一只新累
    /// 积器，其后续增量只许拼进打开段、永不回流
    /// 封存段
    public mutating func restore(
        sealed: [String], current: String
    ) {
        reset()
        sealedSegments = sealed.filter { !$0.isEmpty }
        if !current.isEmpty {
            currentGate.offer(current)
        }
    }
}
