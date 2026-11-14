import Foundation

/// 会话页换代包 3·承载层 Core（DESIGN §257，蓝图
/// native-list-migration-blueprint §1.1/§1.2/§2 包 3）：
/// 新承载（UIKit 容器＋UIScrollView 语义）的全部判定
/// 与记账收在本文件——锚点模型、几何供数适配、行高
/// 组合模型、承载特性开关。判定逻辑与旧承载共用同
/// 一批 Core 政策（BottomStickCoordinator／Stream-
/// FollowGate／BottomArrowVisibility／BottomProximity
/// 零改），本文件只做「新几何来源 → 既有政策输入」
/// 的适配与对拍，绝不另立第二套判定。

// MARK: - 承载特性开关

/// 承载特性开关（蓝图 §2 包 3：聊天格根在新旧两承
/// 载间切换、默认旧；几何真机门不过不许转默认，包
/// 6 收官时处置）。UserDefaults 布尔键，缺省 false
/// ＝旧承载——键不存在与显式 false 同义，防脏值。
public enum ChatCarrierFeature {
    public static let defaultsKey = "chat.carrier.gen3"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}

// MARK: - 锚点模型（条目 id ＋ 条内偏移）

/// 滚动锚（蓝图 §1.2 锚定语义）：恢复的单位不是裸
/// offset——内容高在锚上下变化（产物落盘定点修正、
/// 条目增删）时裸 offset 指向的早已不是同一行。本
/// 锚＝「锚定条目 id ＋ 视口顶距该条目顶边的条内偏
/// 移」，恢复时按当前帧表重算 offset，条目上方的
/// 高变化被帧表吸收、不动锚定行在屏位置。
/// atBottom 与旧 SideChatScrollAnchor 同义（在底时
/// 只记事实、不记条目），两形态互斥：atBottom 为真
/// 时 entryID/intraEntryOffset 不参与恢复。
public struct ChatListAnchor: Equatable, Sendable {
    public var entryID: UUID?
    public var intraEntryOffset: Double
    public var atBottom: Bool

    public init(
        entryID: UUID?,
        intraEntryOffset: Double,
        atBottom: Bool
    ) {
        self.entryID = entryID
        self.intraEntryOffset = intraEntryOffset
        self.atBottom = atBottom
    }

    /// 在底锚（恢复＝贴底）
    public static let bottom = ChatListAnchor(
        entryID: nil, intraEntryOffset: 0, atBottom: true
    )

    /// 一行在当前帧表中的落位（内容坐标，含顶 inset
    /// 之前的纯内容系：y 自内容首行顶边起算）
    public struct RowFrame: Equatable, Sendable {
        public var id: UUID
        public var y: Double
        public var height: Double

        public init(id: UUID, y: Double, height: Double) {
            self.id = id
            self.y = y
            self.height = height
        }

        public var maxY: Double { y + height }
    }

    /// 捕获：给定当前帧表与视口顶（纯内容坐标＝
    /// contentOffset.y＋顶 inset−内容顶 padding，
    /// 换算在调用方），找出
    /// 视口顶命中的第一行并记其条内偏移。视口顶落在
    /// 行间间距带内时归下一行（偏移钳 0）——锚只认
    /// 条目本体、不认间距。帧表为空/视口顶越过末行
    /// 底边→nil（调用方回落在底锚或首屏定版路）。
    public static func capture(
        frames: [RowFrame],
        viewportTop: Double
    ) -> ChatListAnchor? {
        for frame in frames {
            if viewportTop < frame.y {
                return ChatListAnchor(
                    entryID: frame.id,
                    intraEntryOffset: 0,
                    atBottom: false
                )
            }
            if viewportTop < frame.maxY {
                return ChatListAnchor(
                    entryID: frame.id,
                    intraEntryOffset: viewportTop - frame.y,
                    atBottom: false
                )
            }
        }
        return nil
    }

    /// 恢复：按（可能已变化的）帧表算目标 content-
    /// Offset.y（UIKit 口径：顶 inset 之上为负值域，
    /// 顶静止位＝-topInset）。帧表是纯内容系（首行
    /// 顶边 y＝0），contentOriginY 是首行顶边在滚动
    /// 内容坐标中的实际 y（内容顶 padding），换算在
    /// 本函数内一次完成。锚定条目已删→nil（调用方
    /// 静默回落，不强滚）。结果钳进合法滚动域
    /// [−topInset, max(−topInset, contentHeight +
    /// bottomInset − viewportHeight)]（content-
    /// Height 为滚动内容总高、含上下 padding），短
    /// 内容不可滚时恒回顶静止位。
    public static func restoredOffsetY(
        frames: [RowFrame],
        anchor: ChatListAnchor,
        contentOriginY: Double,
        topInset: Double,
        bottomInset: Double,
        contentHeight: Double,
        viewportHeight: Double
    ) -> Double? {
        if anchor.atBottom {
            return max(
                -topInset,
                contentHeight + bottomInset - viewportHeight
            )
        }
        guard let entryID = anchor.entryID,
              let frame = frames.first(where: { $0.id == entryID })
        else { return nil }
        let raw = contentOriginY + frame.y
            + anchor.intraEntryOffset - topInset
        let maxOffset = max(
            -topInset,
            contentHeight + bottomInset - viewportHeight
        )
        return min(max(raw, -topInset), maxOffset)
    }
}

// MARK: - 几何供数适配（新旧对拍面）

/// 几何供数适配：旧承载的距底读数出自 SwiftUI
/// ScrollGeometry 的代数式（contentSize.height −
/// contentOffset.y − containerSize.height），新承载
/// 的原始读数是 UIScrollView 的（contentOffset/
/// contentSize/adjustedContentInset/bounds）——两式
/// 必须在同一滚动状态下给出同一个距底值，跟随判定
/// （BottomArrowVisibility／BottomStickCoordinator）
/// 才许零改切消费端。本枚举钉死两式的代数与互换关
/// 系，回放测试（ChatListCarrierCoreTests）以规范化
/// 轨迹逐点对拍两路判定序列。
///
/// 规范化状态（两路共同的地面真值）：H＝纯内容高
/// （不含 inset）、T＝顶 inset、B＝底 inset、V＝视
/// 口高（滚动视图帧高）、s＝自顶静止位起的滚动行
/// 程。两路原始读数的导出关系（平台语义，苹果文档
/// 口径＋本仓实测行为互证，残差归真机 B 组裁决）：
/// - UIKit：contentOffset.y＝s−T（顶静止位＝−T）、
///   contentSize.height＝H、bounds.height＝V；
/// - SwiftUI：contentSize.height＝H＋T＋B（scroll-
///   Content 边距计入内容尺寸）、contentOffset.y＝s
///   （自含边距的内容原点起算）、containerSize.
///   height＝V。
/// 两式代入后同为 H＋T＋B−V−s，逐点恒等。
public enum ChatScrollSupply {
    /// 旧式（SwiftUI ScrollGeometry 代数，现行
    /// ChatView onScrollGeometryChange 的原式）
    public static func legacyDistance(
        contentHeight: Double,
        offsetY: Double,
        containerHeight: Double
    ) -> Double {
        contentHeight - offsetY - containerHeight
    }

    /// 新式（UIScrollView 原始读数）：距底＝最大合
    /// 法 offset（内容底＋底 inset−视口高）−当前
    /// offset。contentHeight 为 UIScrollView 的
    /// contentSize.height（不含 inset）
    public static func uiKitDistance(
        contentHeight: Double,
        offsetY: Double,
        viewportHeight: Double,
        bottomInset: Double
    ) -> Double {
        (contentHeight + bottomInset - viewportHeight) - offsetY
    }

    /// 规范化轨迹一点：两路供数的共同输入
    public struct CanonicalState: Equatable, Sendable {
        public var contentHeight: Double
        public var topInset: Double
        public var bottomInset: Double
        public var viewportHeight: Double
        public var travel: Double
        public var contentEndVisible: Bool

        public init(
            contentHeight: Double,
            topInset: Double,
            bottomInset: Double,
            viewportHeight: Double,
            travel: Double,
            contentEndVisible: Bool
        ) {
            self.contentHeight = contentHeight
            self.topInset = topInset
            self.bottomInset = bottomInset
            self.viewportHeight = viewportHeight
            self.travel = travel
            self.contentEndVisible = contentEndVisible
        }

        /// 本状态的距底地面真值
        public var distance: Double {
            contentHeight + topInset + bottomInset
                - viewportHeight - travel
        }
    }

    /// 轨迹回放（对拍）：同一规范化轨迹分别经旧式与
    /// 新式供数喂 BottomArrowVisibility（现行单一派
    /// 生点），返回两路 isNearBottom 序列——包 3 的
    /// B7 门：两序列须逐点相等、且每点距底与地面真
    /// 值相等（容差 0.001）
    public static func replayNearBottom(
        trace: [CanonicalState]
    ) -> (legacy: [Bool], uiKit: [Bool], distancesMatch: Bool) {
        var legacyNear = false
        var uiKitNear = false
        var legacyOut: [Bool] = []
        var uiKitOut: [Bool] = []
        var distancesMatch = true
        for state in trace {
            let legacyRaw = legacyDistance(
                contentHeight: state.contentHeight
                    + state.topInset + state.bottomInset,
                offsetY: state.travel,
                containerHeight: state.viewportHeight
            )
            let uiKitRaw = uiKitDistance(
                contentHeight: state.contentHeight,
                offsetY: state.travel - state.topInset,
                viewportHeight: state.viewportHeight,
                bottomInset: state.bottomInset
            )
            if abs(legacyRaw - state.distance) > 0.001
                || abs(uiKitRaw - state.distance) > 0.001 {
                distancesMatch = false
            }
            legacyNear = BottomArrowVisibility.isNearBottom(
                distance: CGFloat(legacyRaw),
                contentEndVisible: state.contentEndVisible,
                wasNearBottom: legacyNear
            )
            uiKitNear = BottomArrowVisibility.isNearBottom(
                distance: CGFloat(uiKitRaw),
                contentEndVisible: state.contentEndVisible,
                wasNearBottom: uiKitNear
            )
            legacyOut.append(legacyNear)
            uiKitOut.append(uiKitNear)
        }
        return (legacyOut, uiKitOut, distancesMatch)
    }
}

// MARK: - 行高组合模型（消费排版产物）

/// 行高组合（包 2 口径差的承载侧落法）：LayoutPro-
/// duct 的 textTotalHeight 是**文本段总高、不是整行
/// 高**——整行高在本包承载侧定：行高＝分隔条（有则
/// 条高＋条下间距）＋气泡纵向内边距（上下两笔）＋
/// 内容高；内容高＝文本段总高＋结构段高＋段间间距
/// ×（总段数−1）。结构段（代码/表格/任务列表/分隔
/// 线）在包 2 无 TextKit 量测可对拍、高留承载侧
/// 定：本模型给**暂定段高**（interimStructuralSeg-
/// mentHeight），行一旦被托管量实，量实值经
/// measuredOverride 覆盖本模型的组合值（承载侧记
/// 账、键＝条目 id＋内容哈希＋宽＋样式键，与产物键
/// 同构）——暂定只决定未量实行在滚动几何中的占位，
/// 不冒充量实。
/// 空文本：产物对空串无字形可量回 0（包 2 已知口
/// 径差、定义差非引擎差）——组合时文本高以行高下
/// 限（lineHeightFloor，App 侧以当前字体行高喂入）
/// 兜底，行不塌成零高。
public enum ChatRowHeightModel {
    /// 结构段暂定高（pt）：代码块/表格的量级中位，
    /// 只作未量实占位；量实到达即被覆盖（见类注）
    public static let interimStructuralSegmentHeight: Double = 48

    public struct Input: Equatable, Sendable {
        /// 产物文本段总高；nil＝产物未就绪（整行走
        /// 暂定估算）
        public var textTotalHeight: Double?
        public var textSegmentCount: Int
        public var structuralSegmentCount: Int
        /// 托管量实的内容高（不含气泡内边距/分隔
        /// 条）：在场时优先于一切组合值
        public var measuredContentHeight: Double?
        public var hasDivider: Bool
        /// 气泡纵向内边距单侧（App 喂 OneDayMetrics
        /// .bubblePaddingV）
        public var bubblePaddingV: Double
        /// 段间间距（App 喂呈现层段栈间距）
        public var segmentSpacing: Double
        /// 分隔条高（App 喂实测/字体行高）
        public var dividerHeight: Double
        /// 分隔条与气泡间距（App 喂 OneDayMetrics
        /// .spacingS）
        public var dividerSpacing: Double
        /// 空文本行高下限（App 喂当前字体行高）
        public var lineHeightFloor: Double
        /// 产物未就绪时的整行暂定高（App 按文本长度
        /// 粗估或给常数）：仅 textTotalHeight 与
        /// measuredContentHeight 皆缺时用
        public var provisionalHeight: Double

        public init(
            textTotalHeight: Double?,
            textSegmentCount: Int,
            structuralSegmentCount: Int,
            measuredContentHeight: Double?,
            hasDivider: Bool,
            bubblePaddingV: Double,
            segmentSpacing: Double,
            dividerHeight: Double,
            dividerSpacing: Double,
            lineHeightFloor: Double,
            provisionalHeight: Double
        ) {
            self.textTotalHeight = textTotalHeight
            self.textSegmentCount = textSegmentCount
            self.structuralSegmentCount = structuralSegmentCount
            self.measuredContentHeight = measuredContentHeight
            self.hasDivider = hasDivider
            self.bubblePaddingV = bubblePaddingV
            self.segmentSpacing = segmentSpacing
            self.dividerHeight = dividerHeight
            self.dividerSpacing = dividerSpacing
            self.lineHeightFloor = lineHeightFloor
            self.provisionalHeight = provisionalHeight
        }
    }

    /// 内容高（气泡内边距之内）：量实 > 产物组合 >
    /// 不适用（返 nil，调用方用整行暂定高）
    public static func contentHeight(
        _ input: Input
    ) -> Double? {
        if let measured = input.measuredContentHeight {
            return measured
        }
        guard let textTotal = input.textTotalHeight else {
            return nil
        }
        // 空文本下限：文本高为 0（或负的脏值）且确
        // 有文本段时以行高下限兜底
        let textHeight = (textTotal <= 0
            && input.textSegmentCount > 0)
            ? input.lineHeightFloor
            : max(0, textTotal)
        let structuralHeight = Double(
            input.structuralSegmentCount
        ) * interimStructuralSegmentHeight
        let totalSegments = input.textSegmentCount
            + input.structuralSegmentCount
        let spacingHeight = totalSegments > 1
            ? Double(totalSegments - 1) * input.segmentSpacing
            : 0
        return textHeight + structuralHeight + spacingHeight
    }

    /// 整行高（不含行间间距——间距是列表记账、不是
    /// 行高）：分隔条段＋气泡内边距×2＋内容高；组
    /// 合不出内容高时回整行暂定高（暂定高已是整行
    /// 口径、不再叠内边距/分隔条）
    public static func rowHeight(_ input: Input) -> Double {
        guard let content = contentHeight(input) else {
            return input.provisionalHeight
        }
        var height = content + input.bubblePaddingV * 2
        if input.hasDivider {
            height += input.dividerHeight + input.dividerSpacing
        }
        return height
    }

    /// 帧表组装：按行高序列自内容顶边起逐行落位
    /// （行间间距 rowSpacing 只在行与行之间、尾行
    /// 之后不收——与旧承载 §176「行距只在消息之间
    /// 生效、列表尾与行距脱钩」同口径）；返回帧表
    /// 与纯内容总高（不含顶/底 padding 与 inset）
    public static func frames(
        ids: [UUID],
        heights: [Double],
        rowSpacing: Double
    ) -> (frames: [ChatListAnchor.RowFrame], totalHeight: Double) {
        var result: [ChatListAnchor.RowFrame] = []
        var y: Double = 0
        for (index, id) in ids.enumerated() {
            let height = index < heights.count ? heights[index] : 0
            result.append(
                ChatListAnchor.RowFrame(
                    id: id, y: y, height: height
                )
            )
            y += height
            if index < ids.count - 1 {
                y += rowSpacing
            }
        }
        return (result, y)
    }
}
