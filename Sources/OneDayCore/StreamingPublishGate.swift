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
/// 节流口径（抄 Telegram 官方批处理口径，见定
/// 因报告 streaming-alignment-20261124 §三/§七）：
/// 「每 N 字符或每 M 秒、先到为准」双触发——
/// - N（字符触发）＝80 字：积压达 N 且距上拍
///   ≥50ms（渲染 ≤20Hz 下限）即发布
/// - M（时间触发）＝90ms：距上拍达 M 且有积
///   压即发布
/// - 单拍步进上限 120 字：突发积压（回放补发
///   除外，flush 全量直发）按拍追赶、不许整段
///   瞬现（验收口径 §八.2）；常态增量速率下积
///   压恒小于上限、每拍即全量，步进只在突发时
///   生效
/// - 首拍直发：本轮首个快照不等节流、立即全
///   量发布（首字延迟 ≤1 拍，验收口径 §八.1；
///   与第 104 条「首批直显」同义）
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
    /// 字符触发阈值 N
    public static let charThreshold = 80
    /// 时间触发阈值 M（秒）
    public static let intervalThreshold: TimeInterval = 0.09
    /// 渲染下限间隔（秒）：任何两拍之间至少隔
    /// 此值——≤20Hz 提交批（定因报告件 3 客户
    /// 端层）
    public static let minInterval: TimeInterval = 0.05
    /// 单拍步进上限（字符）：突发积压的追赶速
    /// 率封顶
    public static let maxStep = 120

    /// 当前已发布快照（呈现侧唯一读口）
    public private(set) var publishedText = ""
    /// 已发布拍数（入场计划的批次判读输入）
    public private(set) var publishCount = 0
    /// 最新累积全文（装配器 mergedFullText 的
    /// 镜像，只进不出——落定兜底仍读装配器本
    /// 体，本门不作第二真源）
    private var targetText = ""
    /// 上一拍发布时刻（注入时刻系）；nil＝本轮
    /// 尚未发布（首拍直发判据）
    private var lastPublishAt: TimeInterval?

    public init() {}

    /// 是否还有未发布积压
    public var hasUnpublished: Bool {
        publishedText != targetText
    }

    /// 本轮是否已发布过任何快照（首批判读：入
    /// 场计划 isFirstBatchOfGeneration 的取数口）
    public var hasPublished: Bool { publishCount > 0 }

    /// 喂入最新累积全文并按拍裁定：返回应即刻
    /// 上屏的新快照（未到拍/无变化返回 nil，调
    /// 用方保持现快照不动）
    @discardableResult
    public mutating func offer(
        _ fullText: String, now: TimeInterval
    ) -> String? {
        if fullText != targetText {
            targetText = fullText
            // 非追加形态（已发布不是新全文的前
            // 缀）：整门重置、本拍按首拍重发
            if !fullText.hasPrefix(publishedText) {
                publishedText = ""
                lastPublishAt = nil
                publishCount = 0
            }
        }
        return publishIfDue(now: now)
    }

    /// 心跳（无新数据时排空积压）：调用方以
    /// ≤minInterval 的周期驱动，返回值同 offer
    @discardableResult
    public mutating func tick(
        now: TimeInterval
    ) -> String? {
        publishIfDue(now: now)
    }

    /// 强制发布全部已累积（段封存边界可调、终
    /// 态/收尾必调）：返回全量快照（与已发布相
    /// 同返回 nil）
    @discardableResult
    public mutating func flush() -> String? {
        guard publishedText != targetText else {
            return nil
        }
        publishedText = targetText
        publishCount += 1
        return publishedText
    }

    /// 新一轮流开始时整门归零
    public mutating func reset() {
        self = StreamingPublishGate()
    }

    // MARK: - 节流裁定

    private mutating func publishIfDue(
        now: TimeInterval
    ) -> String? {
        let backlog = targetText.count - publishedText.count
        guard backlog > 0 else { return nil }
        guard let last = lastPublishAt else {
            // 首拍直发：全量（首个增量块的常态尺
            // 寸远小于步进上限；回放补发的整段直
            // 显是验收口径的明示例外）
            return commit(targetText, now: now)
        }
        let elapsed = now - last
        let dueByChars = backlog >= Self.charThreshold
            && elapsed >= Self.minInterval
        let dueByTime = elapsed >= Self.intervalThreshold
        guard dueByChars || dueByTime else { return nil }
        let step = min(backlog, Self.maxStep)
        let end = targetText.index(
            targetText.startIndex,
            offsetBy: publishedText.count + step
        )
        return commit(
            String(targetText[..<end]), now: now
        )
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
