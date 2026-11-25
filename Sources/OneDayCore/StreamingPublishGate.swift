import Foundation

/// 流式发布门（§494，2026-11-24）：呈现侧节流的
/// 单点裁定——装配器（StreamSegmentAssembler）
/// 只管精确累积，本门把累积全文按拍发布为呈现
/// 快照。§409 步 A/E 当年把发布语义随呈现一并
/// 拆掉（装配器自注「纯累积器、无发布语义」），
/// 正文自此只在落定时整条上屏；本门只补回「发
/// 布」这一环，数据面（装配器/事件序/落定兜底）
/// 一字不动。
///
/// 节流口径（2026-11-25 all-8-issues 波次改判，
/// 全面对标 OpenBot stream-reveal-pool 词级尾
/// 窗；原 §494 Telegram 双触发口径 80 字／90ms
/// ／步进 120 退役，钉测已同日改钉）：
/// - 时间节拍 32ms：距上拍满一拍才推进
/// - 词级步进：英文落词边界、CJK 三字一拍，单
///   拍上限 24 字
/// - 积压 ≥64 字自动 skip 追平：跳至尾窗（全文
///   −16 字），长回复不拖尾
/// - 首拍直发：本轮首个快照不等节流、立即全
///   量发布（首字延迟 ≤1 拍；与第 104 条「首批
///   直显」同义）
///
/// 不变量（钉测把守）：
/// - 已发布快照恒为累积全文的前缀（按字符计，
///   切点恒落字符边界）；快照序列单调生长
/// - flush 后已发布 == 累积全文逐字相等（落定
///   对账：呈现快照与装配器兜底全文同文）
/// - 入参全文若与已发布不构成前缀关系（改写/
///   回滚等非追加形态），整门自重置后按首拍重
///   发——呈现宁可重起、不许拼错
///
/// 时刻由调用方注入（TimeInterval 单调值即可），
/// 本门不读时钟——节流判定纯函数化、可钉测
public struct StreamingPublishGate: Equatable {
    /// 词级尾窗节流口径（全面对标 OpenBot stream-reveal-pool）：
    /// - 时间节拍 32ms（STREAM_WORD_INTERVAL_MS），每拍推进词级步长
    /// - 积压超过 10 词（或 ~60 字符）自动 skip 追平，长回复绝不拖尾
    /// - 首拍直发，首字延迟 ≤1 拍；非追加形态自动重置
    public static let charThreshold = 60
    public static let intervalThreshold: TimeInterval = 0.032
    public static let minInterval: TimeInterval = 0.032
    public static let maxStep = 24
    private static let backlogSkipThreshold = 64

    /// 当前已发布快照（呈现侧唯一读口）
    public private(set) var publishedText = ""
    /// 已发布拍数（入场计划的批次判读输入）
    public private(set) var publishCount = 0
    /// 最新累积全文
    private var targetText = ""
    /// 上一拍发布时刻（注入时刻系）
    private var lastPublishAt: TimeInterval?

    public init() {}

    /// 是否还有未发布积压
    public var hasUnpublished: Bool {
        publishedText != targetText
    }

    /// 本轮是否已发布过任何快照
    public var hasPublished: Bool { publishCount > 0 }

    /// 喂入最新累积全文并按词级节拍裁定
    @discardableResult
    public mutating func offer(
        _ fullText: String, now: TimeInterval
    ) -> String? {
        if fullText != targetText {
            targetText = fullText
            if !fullText.hasPrefix(publishedText) {
                publishedText = ""
                lastPublishAt = nil
                publishCount = 0
            }
        }
        return publishIfDue(now: now)
    }

    /// 心跳排空积压
    @discardableResult
    public mutating func tick(
        now: TimeInterval
    ) -> String? {
        publishIfDue(now: now)
    }

    /// 终态/边界全量发布
    @discardableResult
    public mutating func flush() -> String? {
        guard publishedText != targetText else {
            return nil
        }
        publishedText = targetText
        publishCount += 1
        return publishedText
    }

    /// 新一轮流开始时归零
    public mutating func reset() {
        self = StreamingPublishGate()
    }

    // MARK: - OpenBot 词级尾窗推进

    private mutating func publishIfDue(
        now: TimeInterval
    ) -> String? {
        let backlog = targetText.count - publishedText.count
        guard backlog > 0 else { return nil }
        guard let last = lastPublishAt else {
            return commit(targetText, now: now)
        }
        let elapsed = now - last
        guard elapsed >= Self.intervalThreshold else { return nil }

        // OpenBot 积压保护（waiting.size > 10 → auto skip）：
        // 大段突发时直接跳到尾窗附近，不拖尾卡顿
        if backlog >= Self.backlogSkipThreshold {
            let keepTail = 16
            let targetCount = max(publishedText.count + Self.maxStep, targetText.count - keepTail)
            let end = targetText.index(
                targetText.startIndex,
                offsetBy: min(targetCount, targetText.count)
            )
            return commit(String(targetText[..<end]), now: now)
        }

        // 词级推进：英文尽量落词边界，中文按 2–4 字节奏丝滑吐出
        let startIdx = targetText.index(
            targetText.startIndex, offsetBy: publishedText.count
        )
        let nextIdx = nextWordBoundary(from: startIdx, in: targetText)
        return commit(String(targetText[..<nextIdx]), now: now)
    }

    private func nextWordBoundary(
        from start: String.Index, in text: String
    ) -> String.Index {
        var idx = start
        var stepped = 0
        let limit = min(Self.maxStep, text.distance(from: start, to: text.endIndex))
        while idx < text.endIndex && stepped < limit {
            let ch = text[idx]
            idx = text.index(after: idx)
            stepped += 1
            if ch.isWhitespace || ch.isNewline {
                break
            }
            // CJK 字符按 3 字一拍，兼顾流畅与词组感
            if let scalar = ch.unicodeScalars.first,
               scalar.value >= 0x4E00 && scalar.value <= 0x9FFF,
               stepped >= 3 {
                break
            }
        }
        return idx
    }

    private mutating func commit(
        _ snapshot: String, now: TimeInterval
    ) -> String {
        publishedText = snapshot
        lastPublishAt = now
        publishCount += 1
        return snapshot
    }
}
