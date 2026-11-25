import OneDayCore
import OneDayDesign
import SwiftUI

/// 外观模式三档：跟随系统／浅色／深色。
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

/// 外观页（大厂原生标准版）：
/// 顶部钉住单数据源实时聊天预览，下方精简为两大聚焦分组：
/// - 主题与色彩：模式、整包聊天主题、强调色盘
/// - 背景与文字：精选聊天背景（可视化色块）与文字大小
/// 已移除冗余的「虚拟形象大小」与「气泡圆角」微调项。
struct AppearanceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppearanceStorageKeys.appearanceMode)
    private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage(AppearanceStorageKeys.chatTheme)
    private var chatThemeID = ChatThemes.defaultID
    @AppStorage(AppearanceStorageKeys.chatBackground)
    private var chatBackgroundRaw = ChatBackgroundStyle.standard.rawValue
    @AppStorage(AppearanceStorageKeys.chatTextSize)
    private var chatTextSizeRaw = ChatTextSizeTier.system.rawValue
    @AppStorage(AppearanceStorageKeys.chatAccentOverride)
    private var accentOverrideRaw = -1

    private enum AppearanceTab: String, CaseIterable, Identifiable {
        case theme = "主题与色彩"
        case surface = "背景与文字"
        var id: String { rawValue }
    }
    @State private var selectedTab: AppearanceTab = .theme

    /// 精选背景项（去除肉眼难辨的多余近灰，保留清晰有辨识度的 6 档）
    private static let curatedBackgrounds: [ChatBackgroundStyle] = [
        .theme, .standard, .mist, .dots, .grid, .diagonal,
    ]

    private var backgroundStyle: ChatBackgroundStyle {
        ChatBackgroundStyle(rawValue: chatBackgroundRaw) ?? .standard
    }

    private var textSizeTier: ChatTextSizeTier {
        ChatTextSizeTier(rawValue: chatTextSizeRaw) ?? .system
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

    private var accentOverrideHex: UInt32? {
        guard accentOverrideRaw >= 0,
              accentOverrideRaw <= 0xFFFFFF
        else { return nil }
        return UInt32(accentOverrideRaw)
    }

    private var effectiveAccentHex: UInt32 {
        accentOverrideHex ?? (previewIsDark ? theme.accentDark : theme.accentLight)
    }

    private var previewScheme: ColorScheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme
        }
    }

    private var previewIsDark: Bool { previewScheme == .dark }

    private var previewRenderKey: String {
        "\(chatThemeID)|\(accentOverrideRaw)|\(chatBackgroundRaw)|\(chatTextSizeRaw)|\(appearanceModeRaw)|\(previewIsDark)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: OneDayMetrics.spacingSM) {
                previewCard
                    .id(previewRenderKey)
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
                    modeSection
                    themeSection
                    accentSection
                case .surface:
                    backgroundSection
                    textSizeSection
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

    // MARK: - 实时预览（单数据源，紧凑大厂顶栏 + 真气泡/引用块）

    private var previewCard: some View {
        let accent = hexColor(effectiveAccentHex)
        return VStack(spacing: OneDayMetrics.spacingSM) {
            HStack(spacing: OneDayMetrics.spacingS) {
                appState.agentAvatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                Text(appState.agentDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .accessibilityHidden(true)

            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                Text(L10n.string("帮我看下明早去车站的高铁票"))
                    .font(.body)
                    .foregroundStyle(Palette.userBubbleText)
                    .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                    .padding(.vertical, OneDayMetrics.bubblePaddingV)
                    .background {
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.bubbleCorner,
                            style: .continuous
                        )
                        .fill(Palette.userBubbleFill)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent)
                        .frame(width: 3, height: 18)
                        .accessibilityHidden(true)
                    Text(L10n.string("明早去车站的高铁票"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                }
                Text(L10n.string("订好了，9:05 发车，提前 40 分钟到站就行。"))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.bubblePaddingH)
            .padding(.vertical, OneDayMetrics.bubblePaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.assistantBubbleCorner,
                    style: .continuous
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
            RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusPreview,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusPreview,
                style: .continuous
            )
            .strokeBorder(accent.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("外观预览")
    }

    // MARK: - 外观模式

    private var modeSection: some View {
        Section {
            Picker("外观模式", selection: $appearanceModeRaw) {
                ForEach(AppearanceMode.allCases) { item in
                    Text(item.displayName).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } header: {
            SettingsSectionHeader("外观模式")
        }
        .sensoryFeedback(.selection, trigger: appearanceModeRaw)
    }

    // MARK: - 聊天主题

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
            SettingsSectionHeader("聊天主题")
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: chatThemeID)
    }

    private func themeCard(_ item: ChatTheme) -> some View {
        let selected = item.id == theme.id
        let dark = previewIsDark
        return Button {
            Haptics.selection()
            withAnimation(
                MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion)
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
                                .fill(hexColor(item.bubbleFill(dark: dark)))
                                .frame(width: 26, height: 9)
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(hexColor(item.aiCardFill(dark: dark)))
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
                    .foregroundStyle(selected ? Palette.primary : Palette.ink)
            }
            .padding(OneDayMetrics.spacingS)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? Palette.primary : Palette.hairline,
                        lineWidth: selected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayName + (selected ? "，已选" : ""))
    }

    // MARK: - 强调色

    private static let accentPresetNames = [
        "蓝", "青", "绿", "粉", "橙", "紫", "红", "黄", "灰", "黑", "白",
    ]

    private var accentSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    accentDot(
                        hex: previewIsDark ? theme.accentDark : theme.accentLight,
                        name: "跟随主题",
                        selected: accentOverrideHex == nil
                    ) {
                        accentOverrideRaw = -1
                    }
                    ForEach(
                        Array(ChatAccentPresets.values.enumerated()),
                        id: \.offset
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
            SettingsSectionHeader("主题强调色")
        } footer: {
            Text("统一作用于主按钮、用户气泡、链接、选中态与输入光标；第一颗为当前主题默认色。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: accentOverrideRaw)
    }

    private func accentDot(
        hex: UInt32, name: String, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let luminance = (0.299 * Double((hex >> 16) & 0xFF)
            + 0.587 * Double((hex >> 8) & 0xFF)
            + 0.114 * Double(hex & 0xFF)) / 255.0
        return Button {
            Haptics.selection()
            withAnimation(
                MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion)
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
                            .foregroundStyle(luminance > 0.6 ? Color.black : Color.white)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name + (selected ? "，已选" : ""))
    }

    // MARK: - 聊天背景（可视化色块，一眼看清差异）

    private var backgroundSection: some View {
        Section {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(Self.curatedBackgrounds, id: \.self) { style in
                    backgroundSwatch(style)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingXS)
        } header: {
            SettingsSectionHeader("聊天背景")
        } footer: {
            Text("「跟随主题」自动匹配当前主题底色；纹理项会在纯净底面上叠加细腻质感。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: chatBackgroundRaw)
    }

    private func backgroundSwatch(_ style: ChatBackgroundStyle) -> some View {
        let selected = backgroundStyle == style
        let dark = previewIsDark
        let bgColor: Color = {
            switch style {
            case .theme: return hexColor(theme.chatBackground(dark: dark))
            case .standard, .dots, .grid, .diagonal:
                return dark ? Color(UIColor.systemBackground) : hexColor(0xFCFCFC)
            case .mist: return hexColor(dark ? 0x111113 : 0xF0F0F2)
            case .slate: return hexColor(dark ? 0x1A1A1E : 0xE6E6EA)
            case .wechatGray: return hexColor(dark ? 0x111113 : 0xEDEDED)
            case .gptGray: return hexColor(dark ? 0x1A1A1E : 0xF4F4F4)
            }
        }()
        let iconName: String? = {
            switch style {
            case .dots: return "circle.grid.3x3"
            case .grid: return "grid"
            case .diagonal: return "line.diagonal"
            default: return nil
            }
        }()
        return Button {
            Haptics.selection()
            chatBackgroundRaw = style.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bgColor)
                        .frame(height: 44)
                    if let iconName {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Palette.inkSecondary.opacity(0.65))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            selected ? Palette.primary : Palette.hairline,
                            lineWidth: selected ? 2 : 1
                        )
                }
                Text(style.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? Palette.primary : Palette.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 文字大小

    private var textSizeSection: some View {
        Section {
            Picker("文字大小", selection: textSizeBinding) {
                ForEach(ChatTextSizeTier.allCases, id: \.self) { tier in
                    Text(tier.displayName).tag(tier)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            SettingsSectionHeader("聊天文字大小")
        } footer: {
            Text("仅调整聊天消息文字大小；选择「跟随系统」与系统字体设置同步。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: chatTextSizeRaw)
    }

    // MARK: - 工具

    private func hexColor(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
