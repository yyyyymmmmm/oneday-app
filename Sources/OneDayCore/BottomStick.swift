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
///   挂账复贴在落定评估的事件里校正），杀同帧多
///   路 onChange 的连发。落定评估自键盘整包 R4
///   （2026-11-13）起为事件驱动（BottomSettle-
///   Evaluation），旧 120ms 定时点与定时复核序列
///   一并退役——协调者自此不持任何时间常数。
public struct BottomStickCoordinator: Equatable {
    /// 同帧合并窗（秒）：此窗内的重复请求合并
    public static let coalesceWindow: TimeInterval = 0.05

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

    /// 复贴是否仍挂账（键盘整包 R4，2026-11-13）：
    /// 事件化落定评估每到一个几何事件先窥挂账再裁
    /// 决——只读不消费，消费仍走 consumeRestick 的
    /// 一次性纪律
    public func isRestickArmed(
        generation candidate: Int
    ) -> Bool {
        restickArmedGeneration == candidate
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

/// 落定评估（键盘整包 R4，2026-11-13，取代手感
/// A 档的定时复核序列 BottomSettleRecheck）：旧
/// 序列按 [120, 320, 640, 1100]ms 定时醒来逐检
/// ——四个异步时钟与内容/键盘事件全无关系，落定
/// 的尾巴（≥1.1s 起＋四程串行）即症④；且「运动
/// 已停」的判读靠定时采样，估算收敛不动时根本无
/// 从触发。本评估改为事件驱动：贴底执行后挂账一
/// 笔观察，此后每个几何事实事件（距底读数变化／
/// 尾锚事实翻转／条目数变化／键盘落定）到场即评
/// 一次，判定纯函数、无计时器、无睡眠：
/// - 距底 ≤ 复贴阈值（BottomSettle，§176 冻结
///   的 7pt）→ 已落定，收官；
/// - 内容末端事实可见 → 校准在底，收官（不复
///   贴：末端已在屏内，复贴只会把内容无谓上顶）；
/// - 距底 ≥ 退出阈值（176）且读数已停或正在
///   远离 → 用户已离底，按 §135「离底不打扰」
///   收官，绝不把用户拽回（仍在快速收敛的途中
///   读数不算离底——那是动画贴底的 transit）；
/// - 相邻两事件读数差 ≤ 稳定 epsilon（运动已
///   停）且复贴仍挂账且调用方放行（动画贴底须先
///   观测到运动在途，防首事件误截弹簧）→ 执行
///   唯一一次无动画复贴，收官；
/// - 其余 → 继续等下一事件（不设超时：事件停
///   即静默，新贴底/切线程自会顶替或作废挂账）。
/// 大厂对标：Telegram 的「到底」是几何事实而非
/// 轮询结论（主报告 §1 形态对标）；本评估只消费
/// 几何事件、不生产时钟，与该口径同构。
public enum BottomSettleEvaluation {
    /// 运动落定判据：相邻两事件距底读数差 ≤ 本
    /// 值视为运动已停（pt）——弹簧尾段的亚 pt 级
    /// 蠕动不算还在动，估算收敛的跳变远大于本
    /// 值、不误判
    public static let stabilityEpsilon: CGFloat = 1

    /// 一次事件评估的裁决
    public enum Decision: Equatable {
        /// 已落定（距底达标），观察收官
        case settled
        /// 事实校准在底，观察收官（不复贴）
        case calibrated
        /// 运动已停而距底未达标：执行无动画复贴
        case restick
        /// 尚无定论，等下一事件
        case wait
        /// 用户已离底，观察收官（不打扰）
        case exhausted
    }

    /// 单次事件裁决（入参全为事件时点事实，判定
    /// 纯函数）：顺序即优先级——达标 > 事实 >
    /// 离底放弃 > 复贴 > 等待。restickArmed 由调
    /// 用方合成：协调者挂账在位且运动门已放行
    /// （无动画贴底恒放行；动画贴底须已观测到读
    /// 数大幅变化＝运动确在途）
    public static func decision(
        distance: CGFloat,
        contentEndVisible: Bool,
        previousDistance: CGFloat?,
        restickArmed: Bool
    ) -> Decision {
        if BottomSettle.shouldRestick(distance: distance)
            == false {
            return .settled
        }
        if contentEndVisible {
            return .calibrated
        }
        if distance >= BottomProximity.exitDistance {
            // 离底收官只认「已停在远处／正在远离」：
            // 读数仍在快速收敛（动画贴底途中路过远
            // 区）是 transit、不是用户意图——等运动
            // 自己表态；无前值同理（运动未声明；
            // 真卡死由宿主兜底步进以对齐前值收官）
            guard let previousDistance,
                  distance
                    >= previousDistance - stabilityEpsilon
            else { return .wait }
            return .exhausted
        }
        if restickArmed,
           let previousDistance,
           abs(distance - previousDistance)
            <= stabilityEpsilon {
            return .restick
        }
        return .wait
    }
}

/// 落定状态机（键盘整包 R4 显式状态机，评审合成
/// 条目 4）：BottomSettleEvaluation 是单次裁决核，
/// 本机管跨事件的状态与转移——五个量的事件源逐
/// 量钉死：
/// ① 键盘转换：键盘 Will/Did 帧通知（宿主订阅）
///    ——决定贴底是否带动画，经 begin(animated:)
///    入机；动画「结束」在 iOS 16 无 completion
///    回调可捕获，落定不靠它、靠 ②③ 的读数事实；
/// ② 布局提交：滚动几何回调的距底读数（con-
///    tentSize/offset/container 提交结果）——
///    step 的 distance 入参，主事件源；
/// ③ 滚动 idle：平台无独立回调——由相邻两次布
///    局提交的读数差 ≤ epsilon 内生推导（motion-
///    Observed/stableStreak）；
/// ④ 用户意图：距底 ≥176 的布局提交＝用户上滑
///    离底（exhausted）；切线程＝cancel；
/// ⑤ 尾锚可见性：尾锚几何回调（有效视口口径：
///    视口高扣除底留位遮挡带）——step 的 con-
///    tentEndVisible 入参。
/// 状态仅两态：未观察（isWatching=false）与观
/// 察中；任一收官裁决（settled/calibrated/re-
/// stick/exhausted）即回未观察。固定延时序列禁
/// 充当落定机制（评审口径）；唯一时间件是宿主
/// 的有界单发兜底——它只把当前读数经 stepTime-
/// out 喂回同一判定（仍动以「无事件即静止」为
/// 证据），不自成机制、不循环改 offset。
public struct BottomSettleMachine: Equatable, Sendable {
    public private(set) var isWatching = false
    private var animated = false
    private var previousDistance: CGFloat?
    private var motionObserved = false
    private var stableStreak = 0

    public init() {}

    /// 一次已执行贴底后入观察（新贴底顶替旧观察：
    /// 状态全量重置）
    public mutating func begin(animated: Bool) {
        isWatching = true
        self.animated = animated
        previousDistance = nil
        motionObserved = false
        stableStreak = 0
    }

    /// 作废观察（切线程/宿主拆除）
    public mutating func cancel() {
        isWatching = false
    }

    /// 一步转移的结果（收官四值与判定核一一对应）
    public enum Step: Equatable {
        /// 继续观察（未观察态恒此值）
        case `continue`
        case settled
        case calibrated
        case restick
        case exhausted
    }

    /// 喂一个几何事件：推进运动内生量、以判定核
    /// 裁决、收官即离观察态。restickArmed 由宿主
    /// 合成（协调者挂账窥视结果）；运动门在本机
    /// 内合成（动画贴底须先观测到运动在途、或连
    /// 稳两拍的迟到兜底；无动画恒开）
    @discardableResult
    public mutating func step(
        distance: CGFloat,
        contentEndVisible: Bool,
        restickArmed: Bool
    ) -> Step {
        guard isWatching else { return .continue }
        if let previous = previousDistance {
            if abs(distance - previous)
                > BottomSettleEvaluation.stabilityEpsilon {
                motionObserved = true
                stableStreak = 0
            } else {
                stableStreak += 1
            }
        }
        let gateOpen = !animated || motionObserved
            || stableStreak >= 2
        let decision = BottomSettleEvaluation.decision(
            distance: distance,
            contentEndVisible: contentEndVisible,
            previousDistance: previousDistance,
            restickArmed: restickArmed && gateOpen
        )
        previousDistance = distance
        switch decision {
        case .settled:
            isWatching = false
            return .settled
        case .calibrated:
            isWatching = false
            return .calibrated
        case .restick:
            isWatching = false
            return .restick
        case .exhausted:
            isWatching = false
            return .exhausted
        case .wait:
            return .continue
        }
    }

    /// 有界兜底的单发喂入：观察期内零几何事件到
    /// 场时，宿主在有界时限后以当前读数喂一次——
    /// 「无事件」本身即静止证据：把上一读数对齐
    /// 当前值并视运动已观测，余下全走同一 step
    /// 判定（不另设规则、不重复触发）
    @discardableResult
    public mutating func stepTimeout(
        distance: CGFloat,
        contentEndVisible: Bool,
        restickArmed: Bool
    ) -> Step {
        guard isWatching else { return .continue }
        previousDistance = distance
        motionObserved = true
        return step(
            distance: distance,
            contentEndVisible: contentEndVisible,
            restickArmed: restickArmed
        )
    }
}
