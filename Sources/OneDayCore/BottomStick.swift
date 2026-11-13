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
    /// 时点（与 BottomSettle 的量实原理同口径）；
    /// 手感 A 档起复核改短窗序列（BottomSettle-
    /// Recheck），其首检时点与本值对齐（120ms）
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

    /// 解除挂账复贴（手感 A 档，复核序列收官）：复核
    /// 序列走完而未消费复贴（落定达标／事实校准／用
    /// 户已离底放弃）时凭代号解挂——不留陈账给后续
    /// 请求的合并判定误读；代号不符（已被新贴底顶
    /// 替）不动
    public mutating func disarmRestick(
        generation candidate: Int
    ) {
        guard restickArmedGeneration == candidate else {
            return
        }
        restickArmedGeneration = nil
    }

    /// 作废一切在途状态（切线程）：代号推进、挂账
    /// 清空、合并窗重置
    public mutating func invalidate() {
        generation += 1
        lastPerformedAt = nil
        restickArmedGeneration = nil
    }
}

/// 落定复核序列（手感 A 档，2026-11-13）：旧复核是
/// 贴底后 120ms 单次读数定生死——两类漏网：①高度
/// 后变（审批卡落定、直播行换落盘行）在那一读之后
/// 才发生，距底被顶出迟滞带无自愈（自家审计 S2）；
/// ②人发起的回底滚动改弹簧后（响应按距缩放、最长
/// 0.8），120ms 时弹簧还在途中，读数必大、无动画
/// 复贴一插就把弹簧从中截断。本序列把单次复核改
/// 成短窗多次（120／320／640／1100ms 累计），每检
/// 按纯判定裁决：
/// - 距底 ≤ 复贴阈值（BottomSettle）→ 已落定；
/// - 内容末端事实可见 → 校准在底（不复贴：末端已
///   在屏内，复贴只会把内容无谓上顶）；
/// - 距底 ≥ 退出阈值（176）→ 用户已离底（点钮后
///   反悔上滑、跟随途中改主意），按 §135「离底不
///   打扰」整序放弃，绝不把用户拽回；
/// - 运动已落定（无动画贴底恒落定；动画贴底看相
///   邻两检读数差 ≤ 稳定 epsilon）且距底仍超阈
///   → 执行那一贴无动画复贴（消费归协调者）；
/// - 其余（弹簧仍在途中）→ 继续等下一检；末检仍
///   在动 → 放弃（几何派生链仍在逐帧工作，显隐自
///   行收敛，不留尾巴）。
public enum BottomSettleRecheck {
    /// 各检的累计时点（毫秒，距贴底执行时点）：首
    /// 检沿 0.36.13 的 120ms 量实时点，其后加密到
    /// 约 1.1s 短窗收官——覆盖弹簧最长响应的落定段
    /// 与常见高度后变的落定拍
    public static let checkDelaysMilliseconds: [Int] = [
        120, 320, 640, 1100,
    ]
    /// 动画落定判据：相邻两检距底读数差 ≤ 本值视为
    /// 运动已停（pt）——弹簧尾段的亚 pt 级蠕动不算
    /// 还在动，估算收敛的跳变远大于本值、不误判
    public static let stabilityEpsilon: CGFloat = 1

    /// 一检的裁决
    public enum Decision: Equatable {
        /// 已落定（距底达标），序列收官
        case settled
        /// 事实校准在底，序列收官（不复贴）
        case calibrated
        /// 运动已停而距底未达标：执行无动画复贴
        case restick
        /// 运动未停，等下一检
        case wait
        /// 放弃（用户已离底／短窗耗尽），序列收官
        case exhausted
    }

    /// 运动是否已落定：无动画贴底在执行时点即已落
    /// 定（偏移一步到位、尾行随即量实）；动画贴底
    /// 须有上一检读数可比且差 ≤ epsilon——首检无前
    /// 值恒判未落定，弹簧途中不误伤
    public static func motionSettled(
        wasAnimated: Bool,
        distance: CGFloat,
        previousDistance: CGFloat?
    ) -> Bool {
        if !wasAnimated { return true }
        guard let previousDistance else { return false }
        return abs(distance - previousDistance)
            <= stabilityEpsilon
    }

    /// 单检裁决（入参全为读时点事实，判定纯函数）：
    /// 顺序即优先级——达标 > 事实 > 离底放弃 > 复
    /// 贴 > 等待
    public static func decision(
        distance: CGFloat,
        motionSettled: Bool,
        contentEndVisible: Bool,
        isLastCheck: Bool
    ) -> Decision {
        if BottomSettle.shouldRestick(distance: distance)
            == false {
            return .settled
        }
        if contentEndVisible {
            return .calibrated
        }
        if distance >= BottomProximity.exitDistance {
            return .exhausted
        }
        if motionSettled {
            return .restick
        }
        return isLastCheck ? .exhausted : .wait
    }
}
