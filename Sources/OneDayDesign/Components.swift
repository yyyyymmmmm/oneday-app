import OneDayCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - v2 组件层（定版 §3.5：每个组件全 App 只有一种实现）
// 内容层分离只靠留白、发丝线、一级表面差——零描边、零阴影、
// 零万能卡。玻璃与阴影各只有一个合法住所：发送键与浮空输入区。

public extension View {
    /// 分组容器：surface 底＋容器圆角，零描边零阴影（定版 §3.4）。
    /// 行与分隔线由内容自行排入（行走 ContentRow/FieldRow，
    /// 分隔走 GroupDivider），容器本身不加内边距。
    func odGroup() -> some View {
        self
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
            )
            .overlay(
                // 0.2.3（DESIGN-V4 §1）：页面底回归纯白后，分组面
                // 改靠 0.5pt 发丝线成面，不再靠底色对比
                RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner))
    }
}

/// 分组内发丝线：内缩至全页同一条对齐线（定版 §3.2）。
public struct GroupDivider: View {
    private let inset: CGFloat

    public init(inset: CGFloat = OneDayMetrics.dividerInset) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// 分区标题：0.23.0 起走字阶角色 sectionLabel（15
/// medium，审计 S4：与抽屉分区头/设置分区头三面统一
/// 同一角色；0.3.7 的 13 regular 旧档让位）、次色、
/// 句首大写、无字距。
/// 禁止大写 eyebrow（Hallmark Floor 9 / Impeccable 禁令）。
public struct SectionLabel: View {
    private let title: String
    @Environment(\.colorScheme) private var colorScheme

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
    }
}

/// 状态点：只许出现在状态位（总览状态头、平台行），永远与状态
/// 文字成对，本身不单独传意（定版 §3.5）。
public struct StatusDot: View {
    private let color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// 内容行：图标槽 28 等宽一列、标题＋副题、右侧安静的等宽元信息。
public struct ContentRow: View {
    private let icon: String?
    private let title: String
    private let subtitle: String?
    private let trailing: String?

    public init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        trailing: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            if let icon {
                Image(systemName: icon)
                    // 行图标走 rowIcon 角色（0.3.7 改版：
                    // regular 线条体，§22.5 图标变体令牌）
                    .font(.system(size: OneDayMetrics.rowIconGlyph))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    // 条 5（§14）：图标相对文字下移 0.125em
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    // 0.23.0：走字阶角色 rowTitle（17
                    // semibold）——0.3.3 注「行内唯一半
                    // 粗位」与本行旧 .body regular 的实
                    // 际落值自此对齐（审计 G2 角色表）
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        // 0.23.0：副题升角色 rowSubtitle
                        // （15；旧 footnote 13 升档，审计
                        // I1）＋inkSecondary（旧 inkMuted
                        // 2.75:1 退出文字位，审计 G1）
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if let trailing {
                Text(trailing)
                    // 0.23.0：元信息走角色 metaMonospaced
                    // （15 等宽；旧 footnote 13 升档）
                    .font(.metaMonospaced)
                    // 条 6（§14）：读数位等宽数字防抖
                    .tabularDigits()
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

/// 字段行（分组容器内）：标签在上、本体在下，行底无框，
/// 靠容器与发丝线成界（定版 §3.5）。
public struct FieldRow<Content: View>: View {
    private let label: String
    private let isActive: Bool
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    public init(
        label: String,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.isActive = isActive
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(isActive ? Palette.ink : Palette.inkSecondary)
            content
                .font(.body)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 主按钮：填充深档＋白字，每屏至多一个（定版 §3.5）。
/// 禁用态＝填充降至 35%，不整钮降透明。
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Palette.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.primaryButtonHeight)
                .background(
                    // 0.6.1：主钮改 OpenMuse 原貌——浅蓝填充
                    // primaryPale（#C8E7FF）＋深墨字（onPrimary），
                    // 取代旧「深蓝填充＋白字」；禁用 35% 为
                    // OneDay 既有口径（它无禁用原值）
                    isEnabled
                        ? Palette.primaryPale
                        : Palette.primaryPale.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.buttonCorner)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
                // 0.25.0（动效专包）：按压透明原为无动画
                // 硬切——补 press 令牌（按下即响应、触
                // 发在 touch-down 的 isPressed 上）＋走
                // resolved 出口（Reduce Motion 时瞬时）
                .animation(
                    MotionTokens.resolved(
                        MotionTokens.press, reduceMotion: reduceMotion
                    ),
                    value: configuration.isPressed
                )
        }
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var odPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// 次按钮：surface 面＋墨字，靠一级表面差成面（定版 §3.5）。
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }

    private struct SecondaryButtonBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.buttonCorner)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
                // 0.25.0（动效专包）：与主钮同改——按压
                // 透明补 press 令牌＋resolved 出口（原为
                // 无动画硬切）；为此由 makeBody 直出改
                // Body 视图承载（读 Reduce Motion 环境）
                .animation(
                    MotionTokens.resolved(
                        MotionTokens.press, reduceMotion: reduceMotion
                    ),
                    value: configuration.isPressed
                )
        }
    }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var odSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// 行/钮按压态（0.2.2 动效专项）：.plain 行默认无任何按压反馈，
/// 本样式补齐——按下时轻降透明＋微缩，松手弹簧回位。只服务
/// 状态感知（让用户看清点中了），参数登记于 DESIGN-V3-NOTES §7。
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressableButtonBody(configuration: configuration)
    }

    private struct PressableButtonBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.55 : 1)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                // 0.3.2：动画统一走 resolved 出口（Reduce
                // Motion 开启时按压反馈瞬时切换）
                .animation(
                    MotionTokens.resolved(
                        MotionTokens.press, reduceMotion: reduceMotion
                    ),
                    value: configuration.isPressed
                )
        }
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var odPressable: PressableButtonStyle { PressableButtonStyle() }
}

/// 空态：图标弱色 light、标题 semibold、说明次色，整页至多一个。
public struct EmptyState: View {
    private let icon: String
    private let title: String
    private let message: String

    public init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 行内错误：语义色图标＋墨色正文说清问题，恢复动作由调用方
/// 紧随其后放文字按钮（定版 §3.5）。
public struct InlineError: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
        }
    }
}

// MARK: - 数据条

/// 占用率数据条（0.3.7 卡 4/10 共用口径，中性）：填充
/// 恒墨系（ink），只有 ≥90% 才翻 danger 红示警；轨道
/// 用 fieldFill。占用类数据条是读数不是状态灯，状态
/// 色不进填充（卡 4「percentRow 填充去主色蓝」口径）。
public struct DataBar: View {
    public var fraction: Double
    public var height: CGFloat = 6

    public init(fraction: Double, height: CGFloat = 6) {
        self.fraction = fraction
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fieldFill)
                Capsule()
                    .fill(fraction >= 0.9 ? Palette.danger : Palette.ink)
                    .frame(
                        width: proxy.size.width
                            * min(max(fraction, 0.02), 1)
                    )
            }
        }
        .frame(height: height)
    }
}

// MARK: - 视觉纪律组件（0.3.0，DESIGN-V4 §14）

public extension View {
    /// （条 5 光学对齐 iconOpticalOffset 已于 0.4.0 删除，
    /// 审计 §1.2 #4：图标下移 0.125em 的 hack——SF Symbols
    /// 自带光学对齐基线，全部调用点一并删除）

    /// 条 6 等宽数字：数字一律 tabular，防宽度抖动。
    /// 含数字的 Text 统一施加（时间/计数/金额/读数）
    func tabularDigits() -> some View {
        monospacedDigit()
    }
}

/// 剪贴板写入口径（0.4.1 收敛）：全 App 的「复制到系统
/// 剪贴板」只许走这一处——CopyButton 与聊天页长按菜单
/// 的「复制」共用，不许两套写法
public enum Pasteboard {
    public static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

/// 条 10 复制反馈：点按复制 → 对勾确认态，2.5s 自动
/// 消失（重复点按重置计时）。全 App 复制点只许用它，
/// 不许各处自写一套反馈。0.3.2：命中区扩到 44×44（审
/// 查 I-2，视觉字形与 28pt 图标区不变、图标居中）；复制
/// 成功挂结果触感（.success，触感纪律见 Haptics 注）
public struct CopyButton: View {
    private let text: String
    private let iconSize: CGFloat
    @State private var copied = false
    @State private var copyCount = 0
    @State private var resetTask: Task<Void, Never>?

    public init(text: String, iconSize: CGFloat = 13) {
        self.text = text
        self.iconSize = iconSize
    }

    public var body: some View {
        Button {
            Pasteboard.copy(text)
            copied = true
            copyCount += 1
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                // 0.3.7 §22.5/§22.6：字形 regular，medium 退出
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(
                    copied ? Palette.success : Palette.inkSecondary
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                // 命中区 44×44（minTapTarget）：图标居中，
                // 视觉尺寸不变
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copyCount)
        .accessibilityLabel(copied ? "已复制" : "复制")
    }
}

// MARK: - 0.3.8 组件（白浮纸 / 身份锚点 / 统一行）
// （自绘底栏 FloatingTabBar 已于 0.4.0 删除：底栏回原生
// TabView，审计 §3.2）

public extension View {
    /// 白浮纸画法（fixlist 第 28 条立令牌）：浮件统一——
    /// floatFill 填充＋0.5pt 发丝描边。输入框/身份胶囊/
    /// 圆钮/抽屉底条全体浮件只许走这一处画法。0.4.0
    /// （审计 §1.1）：paper 柔影随 Elevation 整表废止退
    /// 役；浮件玻璃化与系统阴影归二期材质批（§6）
    func odFloatPaper(in shape: some Shape) -> some View {
        self
            .background(Palette.floatFill, in: shape)
            .overlay {
                shape.stroke(Palette.hairline, lineWidth: 0.5)
            }
    }
}

/// 身份锚点（基线补遗增量令 1＋fixlist 第 30 条）：智能
/// 体即界面——头像＋名字＋状态一枚胶囊，一级页（聊天/
/// 总览/文件/状态）顶部统一悬浮、切页锚点不动；页大标
/// 题退到锚点之下。
/// 0.4.0 A 案（审计 §3.3，用户 09:11 点选）：推翻第 30
/// 条「模型不许塞进来」——聊天页传 modelName 时胶囊尾
/// 部并入模型段（分隔线＋模型名＋chevron），一颗装身
/// 份＋状态＋模型；总览/文件页不传、维持身份三件
public struct IdentityAnchor: View {
    private let name: String
    private let statusWord: String
    private let statusColor: Color
    private let modelName: String?
    private let modelShortName: String?
    /// 真头像（0.22.0，视觉审计 F3）：消费面在 App 层
    /// 注入头像图（资产在 App bundle、本框架无资源目
    /// 录，注入是审计给的两条路之一）；未注入时回落
    /// sparkles 占位（旧形态）。此前文件页/总览页恒占
    /// 位、聊天页胶囊是真图——同一个人两个头像，切
    /// 换器并排即露馅，本版起三面同源
    private let avatarImage: Image?
    @Environment(\.colorScheme) private var colorScheme

    public init(
        name: String, statusWord: String, statusColor: Color,
        modelName: String? = nil, modelShortName: String? = nil,
        avatarImage: Image? = nil
    ) {
        self.name = name
        self.statusWord = statusWord
        self.statusColor = statusColor
        self.modelName = modelName
        self.modelShortName = modelShortName
        self.avatarImage = avatarImage
    }

    /// 宽度三档（0.4.1，用户 10:07 点名修）：旧实现把
    /// 胶囊塞进顶栏 HStack 后由布局压缩——名字无
    /// lineLimit 被挤成两行断字、模型名 lineLimit(1)
    /// 截断词中间（真机截图「Her/mes」「Dee…」）。改
    /// ViewThatFits 系统布局三档降级：全量（状态词＋
    /// 模型全名）→ 收状态词（只留状态点＋模型全名）→
    /// 模型短名（ChatModels 短名映射、整词缩短）；名
    /// 字在任何档位 lineLimit(1)＋fixedSize＋最高
    /// layoutPriority——永不断行、不截断，胶囊宽随
    /// 内容自适应（hug）。
    public var body: some View {
        ViewThatFits(in: .horizontal) {
            tier(statusWord: statusWord, model: modelName)
            tier(statusWord: nil, model: modelName)
            tier(statusWord: nil, model: modelShortName ?? modelName)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            modelName.map { "\(name)，\(statusWord)，当前模型 \($0)" }
                ?? "\(name)，\(statusWord)"
        )
    }

    private func tier(statusWord: String?, model: String?) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            if let avatarImage {
                avatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    Circle().fill(Palette.chatSurface)
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .accessibilityHidden(true)
                }
                .frame(width: 28, height: 28)
            }
            Text(name)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            HStack(spacing: 5) {
                StatusDot(color: statusColor)
                if let statusWord {
                    Text(statusWord)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            // A 案模型段（0.4.0，§3.3）：仅聊天页传入时出现
            if let model {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 0.5, height: 18)
                HStack(spacing: 3) {
                    Text(model)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        // 0.23.0（审计 G6）：9pt 字形升
                        // caption2 角色（默认 11 视觉当量、
                        // 随 Dynamic Type 缩放）
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
        .odFloatPaper(in: Capsule())
    }
}

/// 统一行（基线补遗增量令 2 的二级页行组件）：规格冻死
/// 在 OneDayCore.ListRowSpec——图标列 28、标题 17
/// regular、副题 13 灰、右侧元信息等宽 13；可选状态点
/// 与箭头（右侧至多两件、由调用方克制）。各页只换图标
/// 与文案，行型不许再自创
public struct UnifiedRow: View {
    private let icon: String?
    private let title: String
    private let subtitle: String?
    private let trailing: String?
    private let trailingColor: Color?
    private let statusColor: Color?
    private let showsChevron: Bool

    public init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        trailing: String? = nil,
        trailingColor: Color? = nil,
        statusColor: Color? = nil,
        showsChevron: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.trailingColor = trailingColor
        self.statusColor = statusColor
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: ListRowSpec.columnSpacing) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: OneDayMetrics.rowIconGlyph))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(
                        width: ListRowSpec.iconSlotWidth,
                        alignment: .leading
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    // 0.23.0：走字阶角色 rowTitle（与
                    // ContentRow 同步，审计 G2/I1）
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        // 0.23.0：副题升角色 rowSubtitle
                        // （15）＋inkSecondary（审计 G1/I1）
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if let trailing {
                Text(trailing)
                    // 0.23.0：元信息走角色 metaMonospaced（15）
                    .font(.metaMonospaced)
                    .tabularDigits()
                    .foregroundStyle(trailingColor ?? Palette.inkSecondary)
            }
            if let statusColor {
                StatusDot(color: statusColor)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: ListRowSpec.minHeight)
        .contentShape(Rectangle())
    }
}

/// 条 7 平滑高度展开（Grid 0fr→1fr 的 SwiftUI 等价）：
/// 内容实测高在后台量得，容器高度在 0 ↔ 实测高之间动
/// 画插值并裁剪——展开/收起全程平滑、禁跳变。折叠类交
/// 互只许用它
public struct SmoothExpand<Content: View>: View {
    private let isExpanded: Bool
    private let content: Content
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isExpanded: Bool, @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.content = content()
    }

    /// 重量护栏（0.3.2，审查 M-1）：内容实测高 >约 400pt
    /// 时高度动画掉帧风险高，降级为高度瞬时到位（内容仍
    /// 裁剪正确）；常规内容与 Reduce Motion 口径都走
    /// resolved(swap) 统一出口
    private var expandAnimation: Animation? {
        if contentHeight > 400 { return nil }
        return MotionTokens.resolved(
            MotionTokens.swap, reduceMotion: reduceMotion
        )
    }

    public var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, newValue in
                            contentHeight = newValue
                        }
                }
            }
            .frame(height: isExpanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .animation(expandAnimation, value: isExpanded)
    }
}
