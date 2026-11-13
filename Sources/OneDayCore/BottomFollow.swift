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

/// 回底滚动弹簧参数（手感 A 档，2026-11-13）：人发
/// 起的回底滚动（回底钮／键盘锚底）旧走 pageCross-
/// fade（easeInOut 固定 0.25s、与距离无关）——长线
/// 程数千 pt 也只给 0.25s，是一次高速甩动。本档按
/// WWDC18-803《Designing Fluid Interfaces》口径换
/// 弹簧：直接操纵类动画阻尼比 ζ＝1.0（无过冲、落
/// 点即目标、无回跳），响应时长按滚动距离线性放
/// 大封顶——短距保持利落、长距把峰值速度压下来，
/// 曲线全程减速而非匀速甩动。落点与旧路一致（同一
/// scrollTo 目标锚），变的只有运动曲线；距离取贴底
/// 执行时点的实测距底（视图层引用匣读数）。弹簧本
/// 体由 Design 层 MotionTokens 工厂按本档参数构造
/// （令牌纪律：动画只许出令牌册）。
public enum BottomScrollSpring {
    /// 阻尼比：ζ＝1.0 临界阻尼、无过冲（WWDC18-803
    /// 直接操纵档；与 selectionSpring 的 ζ＝1.0 同
    /// 口径——点按触发、无手势来源的位移零回弹）
    public static let dampingFraction: CGFloat = 1.0
    /// 响应下限（秒）：贴底距离≈0 时的响应（回底钮
    /// 在迟滞带内被点等短距场景保持利落）
    public static let minimumResponse: CGFloat = 0.30
    /// 响应上限（秒）：超长线程封顶，再长只靠弹簧本
    /// 身的距离自适应速度，不无限放慢
    public static let maximumResponse: CGFloat = 0.80
    /// 每 pt 距离增加的响应（秒/pt）：1000pt → +0.12
    public static let responsePerPoint: CGFloat = 0.00012

    /// 距底距离 → 弹簧响应：线性放大、双向封顶；距
    /// 离为负（橡皮筋越底）按零距取下限
    public static func response(forDistance distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return minimumResponse }
        return min(
            maximumResponse,
            minimumResponse + distance * responsePerPoint
        )
    }
}

/// 事实信号校准（手感 A 档，2026-11-13，Stream 对
/// 照）：§135 把显隐收成几何单源时如实记下风险——
/// 长线程估算距离驻留迟滞带、钮晚消失（用户 2026-
/// 11-13 15:42 真机兑现：「到底了有时箭头还不消
/// 失」）。Stream Chat 的显隐不用 pt 阈值、用「末
/// 行是否完全可见」的事实信号，对估算误差天然免
/// 疫。本校准把同型信号接回判定：内容末端（栈尾
/// 锚）已完整落在可视区内时，几何读数无论报多少
/// 都以「在底」为准——屏幕上已经没有看不见的内
/// 容，距底读数只剩估算残差与边距记账。
/// 与 §135 退役的旧事实链的区别（防重蹈覆辙）：
/// 旧链是 scrollTargetLayout 可见集逐帧回写多枚
/// @State＋全量重算，本信号只有一个布尔——栈尾锚
/// 一枚视图的几何回调经 §199 引用匣运输（写不失
/// 效任何视图），只在既有的单一派生点被读一次。
/// 锚的屏幕帧对估算免疫的原理：锚在内容坐标里的
/// 位置与滚动偏移同含视口上方未物化行的估算高，
/// 两者在屏幕帧里逐项抵消；视口内外的行都已物化
/// 量实，锚的在屏位置是渲染事实、不是总高推算。
/// 方向单向：事实只许证明「在底」（末端可见 ⇒ 无
/// 内容可再下翻），不许反证「离底」——末端不可见
/// 的成因含长条目未完整入屏等，不能推翻几何迟滞
/// 判定；几何报在底时事实缺位亦不改判。
public enum BottomFactCalibration {
    /// 几何判定与事实信号冲突时以事实为准：事实报
    /// 末端可见即在底；其余情形原样返回几何判定
    public static func isNearBottom(
        geometric: Bool, contentEndVisible: Bool
    ) -> Bool {
        geometric || contentEndVisible
    }
}

/// 回底钮显隐的定版判定（键盘整包 R2，2026-11-13）：
/// 旧口径是几何迟滞带（≤96 进、≥176 出）再叠事实
/// 覆盖——喂带宽的 contentSize 是 LazyVStack 估算
/// 总高，两带全被估算误差点亮/熄灭（症②：末条全
/// 文已在屏、估算距底仍报带外、箭头不消）。定版
/// 改事实优先（证据分级注记：此为本包对自家估
/// 算病的对症判定、非照搬某家原形——主报告 §1
/// 的四家形态里，或无此钮、或靠列表反转使距底
/// 恒为原点事实、或用距离阈值而其距离取自量实
/// 几何；正向列表＋回底钮＋事实信号三件同备者
/// 未见）：
/// - 尾条在屏（事实）∨ 距底 ≤ 7pt（§176 冻结阈
///   值）→ 在底、箭头消；
/// - 距底 ≥ 176pt（§27 迟滞退出值）→ 离底、箭
///   头显；
/// - 两者之间且尾条不在屏 → 保持上一判定（防中
///   段抖闪，迟滞只留这一段）。
/// 边界口径（评审合成条目 6）：「尾条在屏」按有
/// 效视口判——视口高扣除底留位遮挡带（尾锚落在
/// 舱后方不算在屏，判定在 ChatView 尾锚回调按记
/// 录的底 inset 收紧）；尾锚未被 Lazy 实例化时
/// 事实恒缺位、判定回落几何距底（未实例化只发
/// 生在内容未滚到尾部时，届时距底本就大、不误
/// 判在底）；短内容（内容高 ≤ 视口）距底恒 ≤0、
/// 恒在底；overscroll 橡皮筋段距底为负、同按
/// ≤7 在底。初始态由 ChatView 持 isNearBottom
/// 种子 true（新线程开在底部，与落点恢复同口径）
public enum BottomArrowVisibility {
    public static func isNearBottom(
        distance: CGFloat,
        contentEndVisible: Bool,
        wasNearBottom: Bool
    ) -> Bool {
        if contentEndVisible { return true }
        if BottomSettle.shouldRestick(distance: distance)
            == false {
            return true
        }
        if distance >= BottomProximity.exitDistance {
            return false
        }
        return wasNearBottom
    }
}

/// 键盘几何单一快照（键盘整包 R1，2026-11-13）：
/// 主报告 R1 的「持有者」值形态——键盘几何、动画
/// 参数与派生量同居一枚不可变快照、由持有者在键
/// 盘事件的同一拍整体替换，输入舱/列表/顶簇/坞只
/// 消费、不各自采样。旧形态是五个数五套机制五个
/// 时钟（舱走通知常量、列表留位走托管帧跨拍回报
/// 链、顶留位走另一条回报链、坞显隐走焦点状态、
/// 落定走定时器）——症③的记账分量与症④的落定尾
/// 巴皆出于此。派生 bottomSpace 与既有实测回报同
/// 义（舱顶→窗口底的距离）：键盘态舱底贴键盘
/// 顶、静息态舱底贴坞顶，两态同式。
public struct KeyboardGeometrySnapshot: Equatable, Sendable {
    /// 键盘顶（窗口坐标）；nil＝键盘不在场（静息）
    public var keyboardTopInWindow: CGFloat?
    /// 键盘动画时长（秒，取自通知 userInfo 原值）
    public var animationDuration: TimeInterval
    /// 键盘动画曲线原始值（UIView.AnimationCurve
    /// 的 rawValue，取自通知 userInfo 原值）
    public var animationCurveRawValue: Int
    /// 窗口高（窗口坐标系基准）
    public var windowHeight: CGFloat
    /// 坞顶（窗口坐标）：静息态输入舱底的落点
    public var dockTopInWindow: CGFloat
    /// 输入舱栈高（卡＋钮行＋错误排的全栈高）
    public var pocketHeight: CGFloat

    public init(
        keyboardTopInWindow: CGFloat? = nil,
        animationDuration: TimeInterval = 0,
        animationCurveRawValue: Int = 0,
        windowHeight: CGFloat,
        dockTopInWindow: CGFloat,
        pocketHeight: CGFloat
    ) {
        self.keyboardTopInWindow = keyboardTopInWindow
        self.animationDuration = animationDuration
        self.animationCurveRawValue = animationCurveRawValue
        self.windowHeight = windowHeight
        self.dockTopInWindow = dockTopInWindow
        self.pocketHeight = pocketHeight
    }

    /// 键盘是否在场（坞让位与留位分支的唯一读法）
    public var isKeyboardUp: Bool {
        keyboardTopInWindow != nil
    }

    /// 列表底部留位（不含行距）：舱顶→窗口底的距
    /// 离。锚点在窗口内时为锚点下段高＋舱栈高；
    /// 锚点报出窗外（异常帧）时下段高钳 0、不出
    /// 负数
    public var bottomSpace: CGFloat {
        let anchorTop = keyboardTopInWindow
            ?? dockTopInWindow
        return max(0, windowHeight - anchorTop)
            + pocketHeight
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
