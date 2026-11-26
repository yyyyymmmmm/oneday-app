import SwiftUI
import OneDayCore
import OneDayDesign

/// 外观设置页（棒 5 / mac-07，对位 #67）：
/// 与 iOS AppearanceView 逐键同源（Core AppearanceStorageKeys），
/// 顶部单数据源实时聊天预览＋外观模式/聊天主题/强调色/背景/文字大小。
struct MacSettingsAppearancePane: View {
    @Environment(\.colorScheme) private var systemScheme

    @AppStorage(AppearanceStorageKeys.appearanceMode)
    private var appearanceModeRaw = "system"
    @AppStorage(AppearanceStorageKeys.chatTheme)
    private var chatThemeID = ChatThemes.defaultID
    @AppStorage(AppearanceStorageKeys.chatBackground)
    private var chatBackgroundRaw = ChatBackgroundStyle.standard.rawValue
    @AppStorage(AppearanceStorageKeys.chatTextSize)
    private var chatTextSizeRaw = ChatTextSizeTier.system.rawValue
    @AppStorage(AppearanceStorageKeys.chatAccentOverride)
    private var accentOverrideRaw = -1

    private static let curatedBackgrounds: [ChatBackgroundStyle] = [
        .theme, .standard, .mist, .dots, .grid, .diagonal,
    ]

    private var theme: ChatTheme {
        ChatThemes.theme(forID: chatThemeID)
    }

    private var previewScheme: ColorScheme {
        switch appearanceModeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return systemScheme
        }
    }

    private var previewIsDark: Bool { previewScheme == .dark }

    private var accentOverrideHex: UInt32? {
        guard accentOverrideRaw >= 0, accentOverrideRaw <= 0xFFFFFF else { return nil }
        return UInt32(accentOverrideRaw)
    }

    private var effectiveAccentHex: UInt32 {
        accentOverrideHex ?? (previewIsDark ? theme.accentDark : theme.accentLight)
    }

    var body: some View {
        Form {
            Section("实时预览") {
                previewCard
                    .id("\(chatThemeID)|\(accentOverrideRaw)|\(chatBackgroundRaw)|\(chatTextSizeRaw)|\(appearanceModeRaw)|\(previewIsDark)")
            }

            Section("外观模式") {
                Picker("模式", selection: $appearanceModeRaw) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("聊天主题") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ChatThemes.all) { item in
                            themeCard(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        accentDot(
                            hex: previewIsDark ? theme.accentDark : theme.accentLight,
                            selected: accentOverrideHex == nil
                        ) { accentOverrideRaw = -1 }
                        ForEach(
                            Array(ChatAccentPresets.values.enumerated()),
                            id: \.offset
                        ) { _, hex in
                            accentDot(
                                hex: hex,
                                selected: accentOverrideHex == hex
                            ) { accentOverrideRaw = Int(hex) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("主题强调色")
            } footer: {
                Text("第一颗为当前主题默认色；选定后同步作用于主按钮、用户气泡与强调元素。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            Section("聊天背景") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(Self.curatedBackgrounds, id: \.self) { style in
                        backgroundSwatch(style)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("聊天文字大小") {
                Picker("文字大小", selection: $chatTextSizeRaw) {
                    ForEach(ChatTextSizeTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private var previewCard: some View {
        let accent = hexColor(effectiveAccentHex)
        return VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 80)
                Text("帮我看下明早去车站的高铁票")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.userBubbleText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Palette.userBubbleFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            HStack {
                Text("订好了，9:05 发车，提前 40 分钟到站就行。")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                Spacer(minLength: 40)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background { ChatBackgroundSurface() }
        .environment(\.colorScheme, previewScheme)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.45), lineWidth: 1)
        }
    }

    private func themeCard(_ item: ChatTheme) -> some View {
        let selected = item.id == theme.id
        let dark = previewIsDark
        return Button {
            chatThemeID = item.id
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hexColor(item.chatBackground(dark: dark)))
                    VStack(spacing: 3) {
                        HStack {
                            Spacer()
                            Capsule()
                                .fill(hexColor(item.bubbleFill(dark: dark)))
                                .frame(width: 24, height: 8)
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(hexColor(item.aiCardFill(dark: dark)))
                                .frame(width: 36, height: 8)
                            Spacer()
                        }
                    }
                    .padding(5)
                }
                .frame(width: 56, height: 38)
                Text(item.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? Palette.primary : Palette.ink)
            }
            .padding(6)
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Palette.primary : Palette.hairline,
                        lineWidth: selected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func accentDot(
        hex: UInt32, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        let luminance = (0.299 * Double((hex >> 16) & 0xFF)
            + 0.587 * Double((hex >> 8) & 0xFF)
            + 0.114 * Double(hex & 0xFF)) / 255.0
        return Button(action: action) {
            Circle()
                .fill(hexColor(hex))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle().stroke(
                        selected ? Palette.primary : Palette.hairline,
                        lineWidth: selected ? 2 : 1
                    )
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(luminance > 0.6 ? Color.black : Color.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func backgroundSwatch(_ style: ChatBackgroundStyle) -> some View {
        let selected = chatBackgroundRaw == style.rawValue
        let dark = previewIsDark
        let bgColor: Color = {
            switch style {
            case .theme: return hexColor(theme.chatBackground(dark: dark))
            case .standard, .dots, .grid, .diagonal:
                return dark ? Color(nsColor: .windowBackgroundColor) : hexColor(0xFCFCFC)
            case .mist: return hexColor(dark ? 0x111113 : 0xF0F0F2)
            case .slate: return hexColor(dark ? 0x1A1A1E : 0xE6E6EA)
            case .wechatGray: return hexColor(dark ? 0x111113 : 0xEDEDED)
            case .gptGray: return hexColor(dark ? 0x1A1A1E : 0xF4F4F4)
            }
        }()
        return Button {
            chatBackgroundRaw = style.rawValue
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bgColor)
                    .frame(height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                selected ? Palette.primary : Palette.hairline,
                                lineWidth: selected ? 2 : 1
                            )
                    }
                Text(style.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? Palette.primary : Palette.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private func hexColor(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
