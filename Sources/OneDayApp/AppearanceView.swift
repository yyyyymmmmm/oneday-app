import OneDayCore
import OneDayDesign
import SwiftUI

/// 外观模式三档（0.4.0）：跟随系统／浅色／深色。AppStorage
/// 键 appearanceMode 为单一事实源——本页 Picker 写、根层
/// RootView 读后施加 .preferredColorScheme。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension ChatTextSizeTier {
    /// §503 映射单源（App 层）：固定档→DynamicType-
    /// Size；跟随系统＝nil（消费方回落环境值）。
    /// DynamicTypeSize.large 即系统默认正文档、故
    /// 「标准」档落 .large。聊天页与本页预览同读
    var fixedDynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: return nil
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .xlarge: return .xxLarge
        }
    }
}

/// 外观页（0.26.0 重做；§503 按 TG 骨架再重构，
/// 2026-11-24 用户三层框架＋18:36 终裁）：骨架自
/// 上而下——①实时预览（**单数据源**：预览直接渲
/// 染与真实聊天同一组 Palette/主题读口——真背景
/// 面打底、用户泡带字、AI 全宽卡带字＋引用块；改
/// 任一设置，预览与真实聊天同刻同变；旧预览的空
/// 形状＋写死 pageBG 底已整卡废弃）②聊天主题
/// （整包主题卡片列、带名——一款主题同辖 AI 卡/
/// 用户泡/背景/强调，见 Core ChatTheme §503 整包
/// 化；旧纯色圆无名形态与默认款头像图混格退役）
/// ③聊天背景（Menu 行：跟随主题＋纯色盘＋图案
/// 三款，相册图列二期缺件见 §503）④强调色（TG
/// 预设 11 色点列＋「跟随主题」复位，覆盖键辖）
/// ⑤文字大小（五档，聊天面字阶覆盖层）⑥气泡圆
/// 角（原「气泡样式」假名行归位——实只辖圆角）
/// ⑦虚拟形象大小（沿旧）⑧模式（沿旧）。
/// §503 退役：「回复呈现」整节删除（流式/打字渐
/// 显定死常开、仍服从 Reduce Motion；反应浮排＋
/// AI 反应两开关迁「互动」页 ReactionSettings-
/// View）；语言整节迁「语言」页 LanguageSettings-
/// View。全页规格沿 0.24.0 定版（List insetGrouped
/// ＋settingsBG、行题 rowTitleL、分区头 Settings-
/// SectionHeader、行高 settingsRowHeight）。持久
/// 化键见 Core AppearanceStorageKeys（既有键不改
/// 名不迁移、老用户已选值原样保留）。
struct AppearanceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppearanceStorageKeys.appearanceMode)
    private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage(AppearanceStorageKeys.chatTheme)
    private var chatThemeID = ChatThemes.defaultID
    // 气泡浓淡（台账 184）已随 188 定版整套退役：
    // 用户泡单档定死，本页不再有浓淡写口
    @AppStorage(AppearanceStorageKeys.avatarSize)
    private var avatarSizeRaw = AvatarSizeTier.medium.rawValue
    /// 气泡圆角（台账 179，§503 改行名）：键 chat-
    /// BubbleStyle（Core 单源），本页写、Palette 圆
    /// 角读口现读；缺省定版 standard
    @AppStorage(AppearanceStorageKeys.chatBubbleStyle)
    private var bubbleStyleRaw = ChatBubbleStyle.standard.rawValue
    /// 聊天背景（台账 179，§503 扩容）：键 chat-
    /// Background，本页写、Palette.chatBackground
    /// 现读；缺省定版 standard（与 chatSurface 同值）
    @AppStorage(AppearanceStorageKeys.chatBackground)
    private var chatBackgroundRaw =
        ChatBackgroundStyle.standard.rawValue
    /// 聊天文字大小（§503）：键 chatTextSize，本页
    /// 写、聊天页生效字阶读口读；缺省跟随系统
    @AppStorage(AppearanceStorageKeys.chatTextSize)
    private var chatTextSizeRaw = ChatTextSizeTier.system.rawValue
    /// 强调色覆盖（§503）：键 chatAccentOverride 存
    /// hex 整数；「跟随主题」以 -1 哨兵落盘（App-
    /// Storage 无删键口）——Core 读口 Appearance-
    /// Preferences.accentOverride 按范围过滤、-1
    /// 与删键等效回 nil，Palette 覆盖判定只认读口
    @AppStorage(AppearanceStorageKeys.chatAccentOverride)
    private var accentOverrideRaw = -1

    /// §431 触感落点计数（形象大小 Menu 点开）：标
    /// 签点按一次 +1、经声明式 impact .light 施加
    @State private var avatarMenuTapCount = 0

    private enum AppearanceTab: String, CaseIterable, Identifiable {
        case theme = "主题"
        case background = "背景"
        case details = "文字与样式"
        var id: String { rawValue }
    }
    @State private var selectedTab: AppearanceTab = .theme

    private var bubbleStyle: ChatBubbleStyle {
        ChatBubbleStyle(rawValue: bubbleStyleRaw) ?? .standard
    }

    private var backgroundStyle: ChatBackgroundStyle {
        ChatBackgroundStyle(rawValue: chatBackgroundRaw)
            ?? .standard
    }

    private var textSizeTier: ChatTextSizeTier {
        ChatTextSizeTier(rawValue: chatTextSizeRaw) ?? .system
    }

    private var bubbleStyleBinding: Binding<ChatBubbleStyle> {
        Binding(
            get: { bubbleStyle },
            set: { bubbleStyleRaw = $0.rawValue }
        )
    }

    private var backgroundStyleBinding:
        Binding<ChatBackgroundStyle> {
        Binding(
            get: { backgroundStyle },
            set: { chatBackgroundRaw = $0.rawValue }
        )
    }

    private var textSizeBinding: Binding<ChatTextSizeTier> {
        Binding(
            get: { textSizeTier },
            set: { chatTextSizeRaw = $0.rawValue }
        )
    }

    private var mode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var theme: ChatTheme {
        ChatThemes.theme(forID: chatThemeID)
    }

    private var tier: AvatarSizeTier {
        AvatarSizeTier(rawValue: avatarSizeRaw) ?? .medium
    }

    /// 当前强调覆盖（nil＝跟随主题）：与 Core 读
    /// 口同口径——键值 <0 或 >0xFFFFFF 均视未设
    /// （本页哨兵 -1 即在此过滤）
    private var accentOverrideHex: UInt32? {
        guard accentOverrideRaw >= 0,
              accentOverrideRaw <= 0xFFFFFF
        else { return nil }
        return UInt32(accentOverrideRaw)
    }

    /// 预览演示明暗：模式显式选浅/暗按所选演示、跟
    /// 随系统按当前系统——只喂预览框的局部呈现
    private var previewScheme: ColorScheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme
        }
    }

    private var previewIsDark: Bool { previewScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            // 大厂标准（OpenBot / Telegram / WhatsApp）：
            // 真实聊天预览卡钉顶固定，下面切换主题/背景/文字时同帧实时可见、永不滚出屏幕
            VStack(spacing: OneDayMetrics.spacingSM) {
                previewCard
                Picker("外观分组", selection: $selectedTab) {
                    ForEach(AppearanceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
            .padding(.bottom, OneDayMetrics.spacingSM)
            .background(Palette.settingsBG)
            Divider()
            List {
                switch selectedTab {
                case .theme:
                    themeSection
                    accentSection
                    modeSection
                case .background:
                    backgroundSection
                case .details:
                    textSizeSection
                    bubbleCornerSection
                    avatarSection
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
        }
        .background(Palette.settingsBG)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 分区头（走设计层共用件 SettingsSect-
    // ionHeader，本页只留转发壳保既有调用点不动）

    private func appearanceHeader(_ title: String) -> some View {
        SettingsSectionHeader(title)
    }

    // MARK: - ① 实时预览（§503 单数据源重做）

    private var previewSection: some View {
        Section {
            previewCard
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(
            EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        )
    }

    /// 迷你聊天框（§503）：与真实聊天同一组读口现
    /// 渲——背景＝ChatBackgroundSurface（底色＋图
    /// 案、与聊天页背景层同一消费面）、用户泡＝
    /// Palette.userBubbleFill/userBubbleText 带真
    /// 字、AI 卡＝Palette.bubbleFill 全宽卡（内含
    /// 引用块：强调竖线＋次级字），头像＋名签读档
    /// 案、字阶读文字大小档。任一设置改动在此与真
    /// 实聊天同刻同变（预览无副本、无第二数据源）
    private var previewCard: some View {
        let accent = hexColor(
            previewIsDark ? theme.accentDark : theme.accentLight
        )
        return VStack(spacing: OneDayMetrics.spacingSM) {
            VStack(spacing: -5) {
                // 预览头像与名读档案（用户真实所见）
                appState.agentAvatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: tier.capsulePointSize,
                        height: tier.capsulePointSize
                    )
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text(appState.agentDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, OneDayMetrics.rowInnerGap)
                    .padding(.vertical, OneDayMetrics.spacingMicro)
                    .background(Palette.surface, in: Capsule())
                    .overlay {
                        Capsule().stroke(Palette.hairline, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            // 用户泡（带字、主题色现读）
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                Text("帮我看下明早去车站的高铁票")
                    .font(.body)
                    .foregroundStyle(Palette.userBubbleText)
                    .padding(
                        .horizontal, OneDayMetrics.bubblePaddingH
                    )
                    .padding(
                        .vertical, OneDayMetrics.bubblePaddingV
                    )
                    .background {
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.bubbleCorner
                        )
                        .fill(Palette.userBubbleFill)
                    }
                    .accessibilityHidden(true)
            }
            // AI 全宽卡（带字＋引用块、卡面现读）
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingS
            ) {
                HStack(
                    alignment: .top,
                    spacing: OneDayMetrics.spacingS
                ) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.primary)
                        .frame(width: 3, height: 18)
                        .accessibilityHidden(true)
                    Text("明早去车站的高铁票")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                }
                Text("订好了，9:05 发车，提前 40 分钟到站就行。")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.bubblePaddingH)
            .padding(.vertical, OneDayMetrics.bubblePaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius:
                        OneDayMetrics.assistantBubbleCorner
                )
                .fill(Palette.bubbleFill)
            }
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity)
        .background {
            ChatBackgroundSurface()
        }
        .environment(\.colorScheme, previewScheme)
        .environment(
            \.dynamicTypeSize,
            textSizeTier.fixedDynamicTypeSize ?? systemTypeSize
        )
        .clipShape(
            RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
            .strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("外观预览")
    }

    // MARK: - ② 聊天主题（§503 卡片列）

    private var themeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ForEach(ChatThemes.all) { item in
                        themeCard(item)
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
                .padding(.trailing, OneDayMetrics.pageGutter)
            }
            .listRowInsets(
                EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0)
            )
        } header: {
            appearanceHeader("聊天主题")
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: chatThemeID)
    }

    /// 主题卡片一格（§503）：缩略场景（该款背景打
    /// 底＋用户泡小条＋AI 卡小条、三值皆该款整包在
    /// 预览明暗下的实值）＋款名；选中＝强调描边环。
    /// 旧形态（纯色圆无名、默认款头像图混格）退役
    /// ——卡片自带名字与整包预告，与 TG 主题列同构
    private func themeCard(_ item: ChatTheme) -> some View {
        let selected = item.id == theme.id
        let dark = previewIsDark
        return Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) {
                chatThemeID = item.id
            }
        } label: {
            VStack(spacing: OneDayMetrics.spacingXS) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hexColor(item.chatBackground(dark: dark)))
                    VStack(spacing: 3) {
                        HStack {
                            Spacer()
                            Capsule()
                                .fill(
                                    hexColor(item.bubbleFill(dark: dark))
                                )
                                .frame(width: 26, height: 9)
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    hexColor(item.aiCardFill(dark: dark))
                                )
                                .frame(width: 40, height: 9)
                            Spacer()
                        }
                    }
                    .padding(5)
                }
                .frame(width: 58, height: 42)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.primary)
                            .background(Palette.surface, in: Circle())
                            .offset(x: 4, y: -4)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .topTrailing
                            )
                    }
                }
                Text(item.displayName)
                    .font(.caption)
                    .foregroundStyle(
                        selected ? Palette.primary : Palette.ink
                    )
            }
            .padding(OneDayMetrics.spacingS)
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? Palette.primary : Palette.hairline,
                        lineWidth: selected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            item.displayName + (selected ? "，已选" : "")
        )
    }

    // MARK: - Menu 行共用件（背景/文字/圆角三行同式）

    /// Menu 行标签（与形象大小行同式）：题＋当前值
    /// ＋上下 chevron；点开走原生 Menu（内嵌 Picker）
    private func menuRowLabel(
        title: String, value: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Color.clear
                .frame(width: OneDayMetrics.iconSlot)
                .accessibilityHidden(true)
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value)
                .font(.rowTitleL)
                .foregroundStyle(Palette.inkSecondary)
            DisclosureChevron(
                .upDown,
                font: .system(
                    size: FrameworkIcon.smallGlyphSize,
                    weight: .semibold
                )
            )
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
    }

    // MARK: - ③ 聊天背景

    private var backgroundSection: some View {
        Section {
            Menu {
                Picker("聊天背景", selection: backgroundStyleBinding) {
                    ForEach(
                        ChatBackgroundStyle.allCases, id: \.self
                    ) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } label: {
                menuRowLabel(
                    title: "聊天背景",
                    value: backgroundStyle.displayName
                )
            }
        } header: {
            appearanceHeader("聊天背景")
        } footer: {
            Text("「跟随主题」随所选主题整包的背景；图案只改底面质感，不影响阅读。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: chatBackgroundRaw)
    }

    // MARK: - ④ 强调色（§503，TG 预设盘）

    /// 预设色名（与 ChatAccentPresets.values 同序，
    /// 只供无障碍标签与区脚说明、不参与解析）
    private static let accentPresetNames = [
        "蓝", "青", "绿", "粉", "橙", "紫", "红", "黄", "灰", "黑", "白",
    ]

    private var accentSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    accentDot(
                        hex: previewIsDark
                            ? theme.accentDark : theme.accentLight,
                        name: "跟随主题",
                        selected: accentOverrideHex == nil
                    ) {
                        accentOverrideRaw = -1
                    }
                    ForEach(
                        Array(
                            ChatAccentPresets.values.enumerated()
                        ), id: \.offset
                    ) { index, hex in
                        accentDot(
                            hex: hex,
                            name: Self.accentPresetNames[index],
                            selected: accentOverrideHex == hex
                        ) {
                            accentOverrideRaw = Int(hex)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 20)
            }
            .listRowInsets(
                EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0)
            )
        } header: {
            appearanceHeader("强调色")
        } footer: {
            Text("用于链接、引用标记与选中状态；第一颗是跟随当前主题的强调色。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: accentOverrideRaw)
    }

    /// 强调色点一颗：30pt 实色圆；选中＝同色描边
    /// 环＋对勾（勾色按该色明暗取黑/白、保证可辨）
    private func accentDot(
        hex: UInt32, name: String, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let luminance = (0.299 * Double((hex >> 16) & 0xFF)
            + 0.587 * Double((hex >> 8) & 0xFF)
            + 0.114 * Double(hex & 0xFF)) / 255.0
        return Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) {
                action()
            }
        } label: {
            Circle()
                .fill(hexColor(hex))
                .frame(width: 30, height: 30)
                .overlay {
                    Circle().stroke(
                        selected ? Palette.primary : Palette.hairline,
                        lineWidth: selected ? 2.5 : 1
                    )
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                luminance > 0.6
                                    ? Color.black : Color.white
                            )
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(name + (selected ? "，已选" : ""))
    }

    // MARK: - ⑤ 文字大小（§503）

    private var textSizeSection: some View {
        Section {
            Menu {
                Picker("文字大小", selection: textSizeBinding) {
                    ForEach(
                        ChatTextSizeTier.allCases, id: \.self
                    ) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
            } label: {
                menuRowLabel(
                    title: "文字大小",
                    value: textSizeTier.displayName
                )
            }
        } header: {
            appearanceHeader("文字大小")
        } footer: {
            Text("只影响聊天页的文字大小；「跟随系统」与系统「显示与文字大小」一致。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: chatTextSizeRaw)
    }

    // MARK: - ⑥ 气泡圆角（§503 归位，原「气泡样式」）

    private var bubbleCornerSection: some View {
        Section {
            Menu {
                Picker("气泡圆角", selection: bubbleStyleBinding) {
                    ForEach(
                        ChatBubbleStyle.allCases, id: \.self
                    ) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } label: {
                menuRowLabel(
                    title: "气泡圆角",
                    value: bubbleStyle.displayName
                )
            }
        } header: {
            appearanceHeader("气泡圆角")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: bubbleStyleRaw)
    }

    // MARK: - ⑦ 虚拟形象大小（沿旧）

    private var avatarTierBinding: Binding<AvatarSizeTier> {
        Binding(
            get: { tier },
            set: { avatarSizeRaw = $0.rawValue }
        )
    }

    private var avatarSection: some View {
        Section {
            Menu {
                Picker("虚拟形象大小", selection: avatarTierBinding) {
                    ForEach(AvatarSizeTier.allCases) { sizeTier in
                        Text(sizeTier.displayName).tag(sizeTier)
                    }
                }
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    // 形象大小选择器标签头像读档案
                    appState.agentAvatarImage
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: OneDayMetrics.iconSlot,
                            height: OneDayMetrics.iconSlot
                        )
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    Text("虚拟形象大小")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(tier.displayName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.inkSecondary)
                    DisclosureChevron(.upDown, font: .system(size: FrameworkIcon.smallGlyphSize, weight: .semibold))
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { avatarMenuTapCount += 1 }
                )
            }
        } header: {
            appearanceHeader("虚拟形象大小")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: avatarSizeRaw)
        .sensoryFeedback(.impact(weight: .light), trigger: avatarMenuTapCount)
    }

    // MARK: - ⑧ 模式（沿旧）

    private var modeSection: some View {
        Section {
            ForEach(AppearanceMode.allCases) { item in
                Button {
                    withAnimation(
                        MotionTokens.resolved(
                            MotionTokens.swap,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        appearanceModeRaw = item.rawValue
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Color.clear
                            .frame(width: OneDayMetrics.iconSlot)
                            .accessibilityHidden(true)
                        Text(item.displayName)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if item == mode {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel(
                    item.displayName + (item == mode ? "，已选" : "")
                )
            }
        } header: {
            appearanceHeader("模式")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: appearanceModeRaw)
    }

    // MARK: - 工具

    /// 主题十六进制值 → SwiftUI 色（预览/卡片/色点
    /// 需按预览明暗显式取档，不能走 Palette 的
    /// traits 解析）
    private func hexColor(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
