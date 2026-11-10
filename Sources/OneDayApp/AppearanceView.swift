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

/// 外观页（0.26.0 重做，用户 10:28 对标 Muse 外观页
/// 令）：0.4.0 的「只剩模式三档」占位结构退役，重做为
/// 四件套——①顶部实时预览（迷你聊天框：头像＋名签、
/// 用户泡×2、助手泡、灰卡块；气泡色跟主题、头像跟
/// 形象档、明暗跟模式，框内局部强制 colorScheme 演
/// 示、不动全 App 当前呈现）②聊天主题（横滑圆形色
/// 板，机制＝Palette 级主题变体、Core ChatThemes 单
/// 一真源，切换即时生效于真实聊天页）③虚拟形象大小
/// （原生 Menu 行，大/中/小，作用面＝聊天胶囊头像＋
/// 空态形象）④模式（三行勾选行，复用既有
/// preferredColorScheme 链）。全页遵 0.24.0 定版：
/// List(.insetGrouped)＋settingsBG、行题 Body 17
/// regular（rowTitleL）、分区头 Footnote 13
/// （sectionLabel）＋inkSecondary、行高 settingsRow-
/// Height、图标槽 iconSlot 30/图字距 12——与设置首
/// 页同规格（settingsHeader 形态在本页复刻同口径助
/// 手）。参考图的分区头约 15pt 灰不直搬（守 0.24.0
/// 角色表），差异登记 §53。三组持久化键见 Core
/// AppearanceStorageKeys（appearanceMode 为 0.4.0
/// 既有键、不改名不迁移，老用户已选值原样保留）。
struct AppearanceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppearanceStorageKeys.appearanceMode)
    private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage(AppearanceStorageKeys.chatTheme)
    private var chatThemeID = ChatThemes.defaultID
    @AppStorage(AppearanceStorageKeys.avatarSize)
    private var avatarSizeRaw = AvatarSizeTier.medium.rawValue

    private var mode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var theme: ChatTheme {
        ChatThemes.theme(forID: chatThemeID)
    }

    private var tier: AvatarSizeTier {
        AvatarSizeTier(rawValue: avatarSizeRaw) ?? .medium
    }

    /// 预览演示明暗：模式显式选浅/暗按所选演示、跟随
    /// 系统按当前系统——只喂预览框与色板的局部呈现
    private var previewScheme: ColorScheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme
        }
    }

    private var previewIsDark: Bool { previewScheme == .dark }

    /// 行盒与设置首页同值（其 settingsRowInsets 为该
    /// 文件私有，本页复刻同口径：横向 20 与页 gutter
    /// 对齐、纵向 0 靠行内容 minHeight 定高）
    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }

    var body: some View {
        List {
            previewSection
            themeSection
            avatarSection
            modeSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 分区头（与设置首页 settingsHeader 同口径复刻）

    private func appearanceHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    // MARK: - ① 实时预览

    private var previewSection: some View {
        Section {
            previewCard
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(
            EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        )
    }

    /// 迷你聊天框：全为演示形状（空白泡/卡块，无假文
    /// 字）；用户泡与描边走当前主题在预览明暗下的实
    /// 色、助手泡与卡块走 Palette 泡色（经框内
    /// colorScheme 演示档解析）、头像边长走当前形象
    /// 档——三组选择任一改动在此立即可见
    private var previewCard: some View {
        let bubble = hexColor(
            previewIsDark ? theme.bubbleDark : theme.bubbleLight
        )
        let accent = hexColor(
            previewIsDark ? theme.accentDark : theme.accentLight
        )
        return VStack(spacing: OneDayMetrics.spacingSM) {
            VStack(spacing: -5) {
                // 0.36.22：预览卡的头像与名读档案（预览
                // 的就是用户真实所见，不许演旧名旧头像）
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.surface, in: Capsule())
                    .overlay {
                        Capsule().stroke(Palette.hairline, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            HStack {
                Spacer(minLength: 56)
                previewBubble(width: 148, height: 44, fill: bubble)
            }
            HStack {
                previewBubble(
                    width: 188, height: 30, fill: Palette.bubbleFill
                )
                Spacer(minLength: 56)
            }
            HStack {
                Spacer(minLength: 104)
                previewBubble(width: 108, height: 30, fill: bubble)
            }
            HStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Palette.bubbleFill)
                    .frame(width: 205, height: 58)
                    .accessibilityHidden(true)
                Spacer(minLength: 40)
            }
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity)
        .background(Palette.pageBG)
        .environment(\.colorScheme, previewScheme)
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

    private func previewBubble(
        width: CGFloat, height: CGFloat, fill: Color
    ) -> some View {
        RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
            .fill(fill)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    // MARK: - ② 聊天主题

    private var themeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ChatThemes.all) { item in
                        themeSwatch(item)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 20)
            }
            .listRowInsets(
                EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0)
            )
        } header: {
            appearanceHeader("聊天主题")
        }
        .listRowBackground(Palette.surface)
    }

    /// 色板一格（44pt 圆）：默认款以三狗头像图为样、
    /// 余款以其气泡色（预览明暗档）填充；选中＝强调
    /// 色描边环＋泡字色对勾（参考图形态）；点按写键
    /// 即全 App 生效，动效走 MotionTokens.swap 出口
    private func themeSwatch(_ item: ChatTheme) -> some View {
        let selected = item.id == theme.id
        let checkColor = hexColor(
            previewIsDark ? item.bubbleTextDark : item.bubbleTextLight
        )
        return Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) {
                chatThemeID = item.id
            }
        } label: {
            Group {
                if item.id == ChatThemes.defaultID {
                    Image("SangouPartner")
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(
                        hexColor(
                            previewIsDark
                                ? item.bubbleDark : item.bubbleLight
                        )
                    )
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(
                    selected ? Palette.primary : Palette.hairline,
                    lineWidth: selected ? 2.5 : 1
                )
            }
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(checkColor)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            item.displayName + (selected ? "，已选" : "")
        )
    }

    // MARK: - ③ 虚拟形象大小

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
                    // 0.36.22：形象大小选择器标签头像读档案
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
        } header: {
            appearanceHeader("虚拟形象大小")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(rowInsets)
    }

    // MARK: - ④ 模式

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
        .listRowInsets(rowInsets)
    }

    // MARK: - 工具

    /// 主题十六进制值 → SwiftUI 色（预览/色板需按预览
    /// 明暗显式取档，不能走 Palette 的 traits 解析）
    private func hexColor(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
