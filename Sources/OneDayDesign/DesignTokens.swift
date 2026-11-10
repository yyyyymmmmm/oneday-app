import OneDayCore
import SwiftUI

// MARK: - 设计令牌（v2 定版，见 docs/DESIGN-V2.md）
// 定版融合句沿礼记：「纸墨为体，玻璃为用。」内容层（分组、列表、
// 表单、消息）永远纸墨平面、零玻璃零阴影零描边；玻璃只活在功能
// 层（发送键），且染色只许走主题强调令牌（Palette.primary /
// primaryFill），禁止写死 hex。

// MARK: - 字阶（0.4.0 整表废止，审计 §3.1）
// TypeScale 与 Font.Weight.od（暗色降档）已删：视图直用
// Font.TextStyle 语义样式（.body/.callout/.footnote 等），
// 框架层不许 Font.system(size:) 写死文字、不许对正文
// .weight() 覆写。Markdown 内容标题与行内粗体属内容层
// 例外（MarkdownText 内直用语义样式）。字重账本
// TextRoleWeights 与 VisualWeight 随本表一并退役。

// MARK: - 玻璃令牌（0.3.8 已删）
// Mat 三档与 odGlassButton/odGlassSurface 曾是玻璃期的
// 令牌入口；发送舱 0.3.0 去玻璃后全仓零调用（0.3.8 删残
// 审计 grep 实证），本轮整段删除。浮件画法由白浮纸接管
// （Palette.floatFill＋odFloatPaper），玻璃不再回来。

// MARK: - Elevation（0.4.0 整表废止，审计 §1.1）
// ShadowSpec/Elevation/odElevation 已删：调用点 4 处全清
// （odFloatPaper/状态页头像/附件牌去影），仅抽屉右缘一
// 处保留系统近似档阴影、内联在 ChatView drawerPanel
// （例外 E5），参数不再独立成表。

// MARK: - 圆角同心机制（子圆角由容器推导，禁止手算）

public enum CornerRadius {
    /// 同心圆角：内层元素圆角 = 容器圆角 − 内边距，下限 2pt。
    public static func concentric(container: CGFloat, padding: CGFloat) -> CGFloat {
        max(container - padding, 2)
    }
}

// MARK: - Motion 令牌册（0.3.2 按礼记四档纪律收编，DESIGN-V4 §17）
// 礼记四档 ↔ OneDay 对应：press（点按反馈）/ liquidSpring
// （跟手位移与指示器滑移）/ pageCrossfade（内容切换默认过
// 渡）/ 偶发入场档（礼记为 sealIn 落印专用，OneDay 无落印
// 面，由 entrance 占此档：每屏至多一次）。OneDay 既有定版
// 弹簧（dragSpring/microSpring，§14 条 9）归档入册不改值。
// 另有两支专用档：swap（内容替换/状态变化）、streamIn
// （流式词元入场，§14 条 4 定版 120ms）。
// 纪律：全仓动画只许引用本册并经 resolved() 出口（Reduce
// Motion 开启即瞬时）；散落字面量曲线禁止。例外只有系统
// 行为（sheet/系统符号过渡）与 TimelineView 驱动的状态指
// 示（非 .animation 落点）。
// 退出快于进入（审查 M-4 成文）：弹簧面开合共用同一弹簧
// （归位语义）；定时面退出时长 ≤ 进入的 0.8——系统 sheet/
// popover 走系统行为不自改，本条只约束自有动画面。

public enum MotionTokens {
    /// press：一切点按反馈（150ms 内出）。OneDay 定版值
    /// （审查 E-5 确认为强项：按下即响应、只动 opacity/
    /// transform）；礼记同档为 snappy 0.22，本 App 不跟
    /// ——档位对齐、取值按自家实测口径，如实记于 §17
    public static let press = Animation.easeOut(duration: 0.15)
    /// swap：内容替换、错误出现、步骤状态变化、折叠展开
    public static let swap = Animation.easeInOut(duration: 0.2)
    /// liquidSpring：跟手位移、选择指示器滑移（礼记定版
    /// 值 interactiveSpring 0.34/0.72；0.3.2 起取代旧
    /// indicator 档，旧值 spring(0.35, 0.85) 退役）
    public static let liquidSpring = Animation.interactiveSpring(
        response: 0.34, dampingFraction: 0.72
    )
    /// entrance：偶发入场，每屏至多一次
    public static let entrance = Animation.easeOut(duration: 0.45)
    /// 页面交叉淡化（礼记定版值 0.25，0.3.2 对齐）
    public static let pageCrossfade = Animation.easeInOut(duration: 0.25)
    /// streamIn：流式词元渐显入场（§14 条 4 定版 120ms）
    public static let streamIn = Animation.easeOut(duration: 0.12)
    /// 条 9 定版弹簧·拖拽类（0.3.0，§14）：stiffness
    /// 1200 / damping 80——换算阻尼比 ζ≈1.15（过阻尼、
    /// 零回弹），抽屉拖动跟随与归位、一切拖拽类交互走它。
    /// 速度交接注（审查 E-2）：SwiftUI 无初速度参数，松手
    /// 瞬间以动量投影定去向＋本弹簧归位近似，为平台上限
    /// **0.7.1 注**：上句「平台上限」的自认已过时（iOS
    /// 17+ 弹簧重定向保速、interactiveSpring 专为手势交
    /// 接而设，chrome 裁决档 §2.4）；**抽屉用途自 0.7.1
    /// 起由 drawerSpring 取代**（裁决 §3.5 S7），本档其
    /// 余拖拽类用途暂不动、逐项另核
    public static let dragSpring = Animation.interpolatingSpring(
        stiffness: 1200, damping: 80
    )
    /// drawerSpring：抽屉归位专用（0.7.1，chrome 裁决
    /// 档 §3.5 S7）——interactiveSpring(response 0.34,
    /// dampingFraction 0.86)：response 沿 liquidSpring
    /// 的跟手位移档（0.34，抽屉本属跟手位移、0.7.1 前
    /// 错走 dragSpring），damping 取 interactiveSpring
    /// 默认档 0.86（无可见回弹）。归位中再抓由系统合并
    /// 速度（弹簧重定向保速），不许出现速度清零帧；
    /// 点按开合（零初速）同弹簧
    public static let drawerSpring = Animation.interactiveSpring(
        response: 0.34, dampingFraction: 0.86
    )
    /// 条 9 定版弹簧·小动作（0.3.0，§14）：stiffness
    /// 380 / damping 18——换算阻尼比 ζ≈0.46（欠阻尼、
    /// 微弹），点赞类点按反馈、徽标与浮钮的出现/跳动走它
    public static let microSpring = Animation.interpolatingSpring(
        stiffness: 380, damping: 18
    )

    /// selectionSpring：选择指示器滑移（0.36.2 新增，
    /// 动效宪法默认档——spring(response 0.35,
    /// dampingFraction 1.0)）：点按触发、无手势来源
    /// 的滑移零回弹（宪法条 3），与 liquidSpring 的
    /// 跟手档（0.72 有回弹）分工；首个消费面＝文件页
    /// 分段控件药丸 matchedGeometry 滑移
    public static let selectionSpring = Animation.spring(
        response: 0.35, dampingFraction: 1.0
    )

    /// Reduce Motion 降级口径：开启时返回 nil（调用方以
    /// withAnimation(resolved) 包裹，nil 即瞬时切换）；Reduce
    /// Transparency 的降级由系统玻璃自动回退实色，不在代码层处理。
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - 分段控件落值（文件页 [文件｜影音内容]）

/// 自制分段控件的尺寸真源（0.36.2，体验三件规格
/// §1.6；Muse 文件页实测口径）：总高 48、药丸高
/// 36、内缩 6、左右边距 16；轨道全胶囊（r＝总高/2
/// ＝24）、药丸同心收（r＝24−6＝18，与药丸高/2 同
/// 值、即胶囊）。旧口径「段高约 63 照图复刻」系目
/// 测高估 15pt（总高曾达 60、药丸 52），自本版退
/// 役；数值由 SegmentedControlSpecTests 钉死防回潮。
public enum SegmentedControlSpec {
    /// 控件总高
    public static let totalHeight: CGFloat = 48
    /// 选中药丸高（＝总高 − 2×内缩）
    public static let pillHeight: CGFloat = 36
    /// 药丸内缩（容器 padding，上下左右同值）
    public static let inset: CGFloat = 6
    /// 控件左右页边距（本控件局部口径，覆盖 pageGutter 20）
    public static let horizontalMargin: CGFloat = 16
    /// 轨道圆角（全胶囊＝总高/2）
    public static var trackCorner: CGFloat { totalHeight / 2 }
    /// 药丸圆角（同心＝轨道圆角 − 内缩；与药丸高/2 同值）
    public static var pillCorner: CGFloat { trackCorner - inset }
}
