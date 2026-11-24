import Foundation

/// 抽屉点行延迟导航（台账 147，学 OpenBot 抽屉机制
/// ——只学机制、不抄代码，2026-11-19 研读对位）：
/// 点会话行后不立即跳页，先记下待办、关抽屉，关的
/// 进度降到近闭合（≤5%）才真正执行线程切换——跳
/// 页与关抽屉动画不再抢同一帧。判定收进本纯逻辑
/// 单点，持有者（AppRouter）只喂事实、执行结果：
///
/// - 待办单槽：已有待办在位时新的置位被忽略（OB
///   原口径「关抽屉途中第二下点按不重复 push」，
///   首个待办为准，不许后点覆盖先点）；
/// - 置位时进度已 ≤ 阈值（抽屉本就关着/Reduce
///   Motion 瞬时关）：无可等，立即执行；
/// - 关动画被另一运动打断（用户中途抓回抽屉、或
///   新的开合令顶替）：待办即刻执行、不吞（OB 的
///   finishClosingAndNavigate 不看 finished 标记，
///   打断即推——点按表达的去意不许丢）；
/// - 关落定是最后兜底：进度采样万一漏过阈值（如
///   瞬时关的跳变），落定一到即 flush；
/// - 进度初值 1：置位只来自抽屉行、抽屉必开着，
///   未收到进度喂入前按开态处理、不许抢跑。
public struct DrawerDeferredNavigation: Equatable, Sendable {
    /// 触发导航的关进度阈值（呈现进度 1＝全开、
    /// 0＝全合；OB 常量 NAVIGATE_AT_PROGRESS 同值）
    public static let fireProgress: Double = 0.05

    /// 在位待办（nil＝无待办）
    public private(set) var pendingID: UUID?
    /// 最近一次进度事实（置位/采样喂入；初值 1 见
    /// 文件头）
    public private(set) var lastProgress: Double = 1

    public init() {}

    public var hasPending: Bool { pendingID != nil }

    /// 置位一次待办。返回非 nil＝立即执行该 id（进
    /// 度已近闭合）；返回 nil＝已入账待触发，或已
    /// 有待办在位、本次被忽略
    @discardableResult
    public mutating func stage(
        _ id: UUID, currentProgress: Double
    ) -> UUID? {
        lastProgress = currentProgress
        if pendingID != nil { return nil }
        if currentProgress <= Self.fireProgress {
            return id
        }
        pendingID = id
        return nil
    }

    /// 进度采样（关动画逐帧/落定拍喂入）：待办在
    /// 位且进度降到阈值即取出执行（只执行一次）
    @discardableResult
    public mutating func progressSample(
        _ progress: Double
    ) -> UUID? {
        lastProgress = progress
        guard let pendingID,
              progress <= Self.fireProgress
        else { return nil }
        self.pendingID = nil
        return pendingID
    }

    /// 关动画被打断：待办即刻执行（理由见文件头）
    @discardableResult
    public mutating func closeInterrupted() -> UUID? {
        guard let pendingID else { return nil }
        self.pendingID = nil
        return pendingID
    }

    /// 关落定兜底：采样漏过阈值时在此 flush
    @discardableResult
    public mutating func settledClosed() -> UUID? {
        guard let pendingID else { return nil }
        self.pendingID = nil
        return pendingID
    }
}
