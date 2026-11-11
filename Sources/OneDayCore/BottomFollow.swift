import Foundation

/// 底部跟随判定（0.4.2，DESIGN-V4 §27）：消息列表
/// 「是否贴近底部」的迟滞判定与流式跟随滚动节流。
/// 0.4.1 前 isNearBottom 是单阈值（距底 <140）即时判
/// 定：距离在阈值附近游走时判定逐帧翻转，连带「回到
/// 底部」钮显隐（底部 inset 高度随之动画）与自动贴
/// 底滚动反复触发——划到底抖动的放大器之一。本版
/// 判定与节流收进纯逻辑钉死：迟滞双阈值（进入 <96／
/// 退出 ≥176，中间带保持原态）；流式跟随按字符增量
/// 节流（每 ≥40 字至多放行一次），不再逐 token 追
/// 逐移动中的底部。
public enum BottomProximity {
    /// 进入「贴近底部」的距底阈值（pt）
    public static let enterDistance: CGFloat = 96
    /// 退出「贴近底部」的距底阈值（pt）；与进入阈值
    /// 之间是迟滞带，带内保持上一判定
    public static let exitDistance: CGFloat = 176

    /// 距底距离＝内容高 − 滚动偏移 − 容器高；橡皮筋
    /// 越过底部时为负（仍算贴底）
    public static func update(
        distance: CGFloat, wasNearBottom: Bool
    ) -> Bool {
        if wasNearBottom {
            return distance < exitDistance
        }
        return distance < enterDistance
    }
}

/// 底部跟随策略（0.36.5，聊天细节审计双修）：发送
/// 贴底与回底钮显隐的决策收进纯逻辑钉死，视图层只
/// 执行——
/// - 自己发送是「离底不打扰」的唯一例外：发送落盘
///   成功后无条件进贴底态（聊天 UI 通则 onNewMes-
///   sage＝atBottom || isOwnMessage）。旧实现 send()
///   无任何贴底动作、跟随又被 isNearBottom 门控，用
///   户上滑回看时发送，自己的消息与整段回复全被挡
///   在视外（审计 bug 1）。
/// - 回底钮显隐（§135 改判，发送空屏诊断 A 案）：
///   0.36.5 曾并入事实信号「最后一条条目已在可见
///   集内」纠偏几何估算（审计 bug 2）——该信号的
///   代价是 scrollTargetLayout 可见集每次滚动都回
///   写多枚 @State、与条目变化两路全量重算事实信
///   号，是发送空屏的成因链之一。§135 按外部实证
///   （成熟 SwiftUI 客户端不用 scrollTargetLayout
///   ＋可见集回写）把信号链整条退役：钮显隐只由距
///   底几何（BottomProximity 迟滞双阈值）单源派
///   生，「钮不显即在底」成为唯一口径。如实记风
///   险：长线程估算距离驻留迟滞带时钮可能晚消失，
///   以尾行量实后几何收敛＋复贴校正兜底，真机复验
///   见 DESIGN §135 待验条。
public enum BottomFollowPolicy {
    /// 发送落盘成功后 isNearBottom 的目标值：恒真
    /// ——置真后流式跟随与落定跟随自动接续，发送路
    /// 径只需再补一步即时贴底（复贴归 BottomStick-
    /// Coordinator 单点，视图层）
    public static func nearBottomAfterOwnSend() -> Bool { true }

    /// 回底钮显隐（§135 几何单源）：几何判定离底即
    /// 显示——钮不显即在底，回底钮与未读计数的
    /// 「在底」事实共用本派生、永不分叉
    public static func showsScrollToBottomButton(
        isNearBottom: Bool
    ) -> Bool {
        !isNearBottom
    }
}

/// 流式跟随滚动节流闸（0.4.2，§27）：流式文本每个
/// 增量都变化一次，逐次触发贴底滚动等于让滚动动画
/// 无限追逐随文本生长移动的底部。本闸按已跟随到的
/// 字符数记账：新增 ≥40 字才放行一次跟随；流结束的
/// 最后一贴由落盘条目变化事件承担，不经本闸。
public struct StreamFollowGate: Equatable {
    /// 放行一次跟随所需的最小新增字符数
    public static let minimumGrowth = 40
    /// 已跟随到的流式全文长度
    public private(set) var followedCount = 0

    public init() {}

    /// currentCount 为当前流式全文长度。放行时记账
    /// 到当前长度并返回 true；增量不足返回 false。
    /// 长度比已跟随数还小（新一轮流未经 reset 直接
    /// 开始）按从零计，不卡死
    public mutating func shouldFollow(currentCount: Int) -> Bool {
        let baseline = currentCount >= followedCount ? followedCount : 0
        guard currentCount - baseline >= Self.minimumGrowth else {
            return false
        }
        followedCount = currentCount
        return true
    }

    /// 一轮流结束／切换会话时归零
    public mutating func reset() {
        followedCount = 0
    }
}

/// 最后一个渲染项的滚动目标 id（0.36.13，诊断
/// chat-bottom-geometry §2.3 事实路堵洞；§135 起
/// App 侧消费退役——事实信号链随发送空屏诊断 A 案
/// 拆除，本函数与钉测保留在 Core 备查）：回底钮的
/// 事实信号「最后一条已可见」旧实现拿条目数组的末
/// 条 id 去比可见集——但渲染经成组分流：末条若是
/// ≥2 条连续工具条目组的成员，该组的滚动目标 id
/// 是组首条 id，contains(末条 id) 永假、事实信号恒
/// 报离底。本函数按与渲染同构的成组规则算目标 id：
/// 末条非工具条目→其本身；末条在尾部工具连段内→
/// 连段长 ≥2 取连段首条、连段长 1 取其本身；空数
/// 组→nil。视图层把条目映射成 EntryStub（id＋是否
/// 工具卡）后只消费本函数，判定口径单点钉死。
public enum LastScrollTarget {
    /// 条目的最小投影：判定只需要 id 与是否工具卡
    public struct EntryStub: Equatable {
        public let id: UUID
        public let isToolCard: Bool

        public init(id: UUID, isToolCard: Bool) {
            self.id = id
            self.isToolCard = isToolCard
        }
    }

    public static func lastScrollTargetID(
        entries: [EntryStub]
    ) -> UUID? {
        guard let last = entries.last else { return nil }
        guard last.isToolCard else { return last.id }
        // 尾部工具连段的起点：自末条向前走完连续的
        // 工具条目——连段即渲染层的最后一个成组单元
        var runStart = entries.count - 1
        while runStart > 0, entries[runStart - 1].isToolCard {
            runStart -= 1
        }
        let runLength = entries.count - runStart
        return runLength >= 2 ? entries[runStart].id : last.id
    }
}

/// 贴底落定复贴判定（0.36.13，诊断 chat-bottom-
/// geometry 修法 1）：LazyVStack 的程式化贴底按估
/// 算总高落点、单发无收尾，长线程落点离真底可差
/// 数十 pt。修法是贴底后一拍复核实测距底：仍大于
/// 本阈值才再贴一次（尾部行在第一贴后已被量实、
/// 第二贴落点才准——vellum PR #30693 的量实原理）。
/// 阈值取小：正常落定误差（尾锚 1＋栈底 padding 8
/// ＋contentMargins 4 ≈13pt；contentMargins 原 8、
/// 0.36.27 §97 件二收一档）不触发复贴，估算误差
/// （实测 ≈57pt 起）必触发。
/// §176 收紧（2026-11-12，气泡间距收口）：24 → 7。
/// 间距链写死部分已压到 17pt（见 §176 九环对账），
/// 本阈值即残差带上限——取 7 使稳态总量封顶
/// 17＋7＝24（与 Muse 实测 24 齐平），且诊断截图
/// 实测残差 8.3 自此必被复贴收掉（旧值 24 时放行、
/// 正是 65.3 量值里残差一项的来源）；取 8 则带顶
/// 破 25 出带，取 6 则 7–13pt 的寻常落定误差几乎
/// 每贴必补、晚跳过频。代价如实记：落定误差落在
/// 7–13pt 的贴底会多补一贴无动画校正（尾行已量
/// 实、第二贴落点准），以观感换紧凑，真机 AB 列
/// §176 待验。
public enum BottomSettle {
    /// 复贴触发的实测距底阈值（pt）：大于才补贴
    public static let restickThreshold: CGFloat = 7

    public static func shouldRestick(distance: CGFloat) -> Bool {
        distance > restickThreshold
    }
}

/// 离底未读计数（0.41.0，全局收口批·聊天细节余项正
/// 修，台账 H 节）：用户上翻离开底部后，新到条目计在
/// 回底钮的角标上；回到底部、自发发送、切换线程即清
/// 零。判定全在本结构体（呈现层只喂事实、读计数）：
/// · 在底部（atBottom）时计数恒 0，并把「水位」推进
///   到当前末条——其后离底新增的条目才计；
/// · 离底时水位冻结，计数＝水位之后的新条目数；
/// · 条目被删/列表回退时水位若已不在列表内，计数回
///   落为 0 并以当前末条重立水位（不虚报）；
/// · 自发发送（noteOwnSend）无条件清零——发送路径本
///   就无条件贴底（BottomFollowPolicy 同口径）。
/// 流式条目在列表里是同一条的原地生长（id 不变），
/// 不产生新 id、不计数——计数只认新条目 id。
public struct AwayUnreadCounter: Equatable, Sendable {
    /// 显示封顶：超过此数角标显「99+」
    public static let displayCap = 99

    /// 水位：已计入「看过」的最后一条 id；在底时随末
    /// 条推进，离底时冻结
    private var watermark: UUID?
    public private(set) var count = 0

    public init() {}

    /// 喂入当前有序条目 id 全表与在底事实，回新计数
    @discardableResult
    public mutating func ingest(
        entryIDs: [UUID], isAtBottom: Bool
    ) -> Int {
        guard let last = entryIDs.last else {
            watermark = nil
            count = 0
            return count
        }
        if isAtBottom {
            watermark = last
            count = 0
            return count
        }
        guard let mark = watermark,
              let markIndex = entryIDs.firstIndex(of: mark)
        else {
            // 无水位（刚离底首帧）或水位条目已删：以当
            // 前末条立水位、本帧不计——宁少计不虚报
            watermark = last
            count = 0
            return count
        }
        count = entryIDs.count - markIndex - 1
        return count
    }

    /// 自发发送：清零并把水位推到当前末条（发送后贴
    /// 底跟随接续，见 BottomFollowPolicy）
    public mutating func noteOwnSend(entryIDs: [UUID]) {
        watermark = entryIDs.last
        count = 0
    }

    /// 回到底部（点回底钮）：计数清零；水位由下一帧
    /// ingest 的在底事实推进
    public mutating func reset() {
        count = 0
    }

    /// 切换线程：水位与计数全清，新线程从零起算
    public mutating func resetAll() {
        watermark = nil
        count = 0
    }

    /// 角标文案：0 不显；超封顶显「99+」
    public var displayText: String? {
        guard count > 0 else { return nil }
        return count > Self.displayCap ? "\(Self.displayCap)+" : "\(count)"
    }
}
