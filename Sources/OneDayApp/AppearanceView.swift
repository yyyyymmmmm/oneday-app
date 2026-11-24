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
/// preferredColorScheme 链）。§145 续加 ⑤语言四档
/// （勾选行与 ④ 同构、区脚注明系统托管面仍随系统
/// 语言，见 languageSection）；第 104 条在模式与
/// 语言之间续加 ⑤回复呈现（打字动画开关，见
/// replyPresentationSection，语言顺延 ⑥）；台账
/// 198 收敛 S6 起同组并入「流式增量呈现」开关（键
/// chat.streaming.gen4 与关于页旧实验开关同键同
/// 源、旧写口已删）。全页
/// 遵 0.24.0 定版：
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
    // 气泡浓淡（台账 184）已随 188 定版整套退役：
    // 用户泡单档定死（饱和实填＋白字），本页不再
    // 有浓淡写口、chatBubbleFillStyle 键无消费方
    @AppStorage(AppearanceStorageKeys.avatarSize)
    private var avatarSizeRaw = AvatarSizeTier.medium.rawValue
    /// 语言四档（§145）：与模式同形态——AppStorage
    /// 单一事实源（LanguageStorageKeys.appLanguage），
    /// 本页写、根层 OneDayApp 消费（.environment＋
    /// .id 整树重建，即时生效不重启）
    @AppStorage(LanguageStorageKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreference.system.rawValue
    /// 打字动画（第 104 条）：键 chat.streaming.-
    /// typewriter（Core StreamingTypewriterFeature
    /// 单一事实源），本页写、聊天页 StreamingText
    /// 读；缺省开
    @AppStorage(StreamingTypewriterFeature.defaultsKey)
    private var typewriterEnabled = true
    /// 流式增量呈现（台账 198 收敛 S6 归位）：键
    /// chat.streaming.gen4（Core ChatStreamingFeature
    /// 单一事实源），本页写、聊天页读；缺省开。与关
    /// 于页旧「内部实验」开关是同一键的第二个写口
    /// ——旧写口已删、键不变无迁移，老用户已选值原
    /// 样保留；两键语义不同不合并（增量方式 vs 渐显
    /// 口味，见 replyPresentationSection 区脚互指）
    @AppStorage(ChatStreamingFeature.defaultsKey)
    private var streamingEnabled = true
    /// 反应浮排（DESIGN §343）：键 chat.reactions.
    /// floatingBar（Core ChatReactionsFloatingBar-
    /// Feature 单一事实源），本页写、聊天页读；缺
    /// 省开，关＝长按回系统菜单「添加反应」子菜单
    @AppStorage(ChatReactionsFloatingBarFeature.defaultsKey)
    private var floatingBarEnabled = true
    /// AI 反应（DESIGN §432）：键 chat.reactions.
    /// aiSelf（Core ChatReactionsAISelfFeature 单一
    /// 事实源），本页写、聊天页角标判定读；缺省
    /// 开，关＝只隐藏本机呈现（数据不删、重开全量
    /// 回来）。行显隐由服务端能力位门控（见
    /// aiSelfRowVisible），无能力位整行不出
    @AppStorage(ChatReactionsAISelfFeature.defaultsKey)
    private var aiSelfReactionsEnabled = true

    /// AI 反应行显隐（§432）：单读 AppState 的能力
    /// 协商结论（Core SelfReactionsSettingsRow-
    /// Policy 判定），未探得/未广告恒不出
    private var aiSelfRowVisible: Bool {
        SelfReactionsSettingsRowPolicy.isRowVisible(
            availability: appState.selfReactionsAvailability
        )
    }
    /// 气泡样式（台账 179，OB-I1）：键 chatBubbleStyle
    /// （Core AppearanceStorageKeys 单源），本页写、
    /// Palette 圆角读口现读；缺省定版 standard
    @AppStorage(AppearanceStorageKeys.chatBubbleStyle)
    private var bubbleStyleRaw = ChatBubbleStyle.standard.rawValue
    /// 聊天背景（台账 179）：键 chatBackground，本页
    /// 写、Palette.chatBackground 现读；缺省定版
    /// standard（与 chatSurface 同值）
    @AppStorage(AppearanceStorageKeys.chatBackground)
    private var chatBackgroundRaw =
        ChatBackgroundStyle.standard.rawValue

    /// §431 触感落点计数（形象大小 Menu 点开）：标签
    /// 点按一次 +1、经声明式 impact .light 施加；本页
    /// 其余四点（主题／模式／语言／形象大小选择）走
    /// selection＋值变化触发，见 Haptics.swift 头部
    /// §431 修宪与各分区尾修饰
    @State private var avatarMenuTapCount = 0

    private var bubbleStyle: ChatBubbleStyle {
        ChatBubbleStyle(rawValue: bubbleStyleRaw) ?? .standard
    }

    private var backgroundStyle: ChatBackgroundStyle {
        ChatBackgroundStyle(rawValue: chatBackgroundRaw)
            ?? .standard
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

    private var languagePreference: AppLanguagePreference {
        AppLanguagePreference(rawValue: appLanguageRaw) ?? .system
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

    // （行盒已于台账 198 收敛 B7 上收设计层
    // OneDayMetrics.settingsRowInsets 单源，本页不再
    // 复刻；口径不变：横向 20 与页 gutter 对齐、纵
    // 向 0 靠行内容 minHeight 定高）

    var body: some View {
        List {
            previewSection
            themeSection
            personalizationSection
            avatarSection
            modeSection
            replyPresentationSection
            languageSection
        }
        .task {
            await appState.refreshSelfReactionsAvailability()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 分区头（台账 198 收敛 B7：走设计层共
    // 用件 SettingsSectionHeader，本页只留转发壳保
    // 既有调用点不动）

    private func appearanceHeader(_ title: String) -> some View {
        SettingsSectionHeader(title)
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
            theme.bubbleFill(dark: previewIsDark)
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
                    .padding(.horizontal, OneDayMetrics.rowInnerGap)
                    .padding(.vertical, OneDayMetrics.spacingMicro)
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
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
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
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ForEach(ChatThemes.all) { item in
                        themeSwatch(item)
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
                .padding(.trailing, OneDayMetrics.pageGutter)
            }
            .listRowInsets(
                EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0)
            )
            // 气泡浓淡分段（台账 184）已随 188 定版
            // 删除：用户泡单档定死、本区只剩主题选择
        } header: {
            appearanceHeader("聊天主题")
        }
        .listRowBackground(Palette.surface)
        .sensoryFeedback(.selection, trigger: chatThemeID)
    }

    /// 色板一格（44pt 圆）：默认款以三狗头像图为样、
    /// 余款以其气泡色（预览明暗档）填充；选中＝强调
    /// 色描边环＋泡字色对勾（参考图形态）；点按写键
    /// 即全 App 生效，动效走 MotionTokens.swap 出口
    private func themeSwatch(_ item: ChatTheme) -> some View {
        let selected = item.id == theme.id
        let checkColor = hexColor(
            item.bubbleText(dark: previewIsDark)
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
                            item.bubbleFill(dark: previewIsDark)
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
                        .font(.system(size: FrameworkIcon.smallGlyphSize, weight: .bold))
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

    // MARK: - 聊天个性化（台账 179，OB-I1；§391）

    /// 可选开关、默认定版：气泡样式与聊天背景两项，
    /// 不动任何默认值——没改过的用户呈现与定版逐值
    /// 相同；智能体专属 backdrop 未在本区（缺口见 §391）
    private var personalizationSection: some View {
        Section {
            Picker("气泡样式", selection: bubbleStyleBinding) {
                ForEach(
                    ChatBubbleStyle.allCases, id: \.self
                ) { style in
                    Text(style.displayName).tag(style)
                }
            }
            Picker("聊天背景", selection: backgroundStyleBinding) {
                ForEach(
                    ChatBackgroundStyle.allCases, id: \.self
                ) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } header: {
            appearanceHeader("聊天个性化")
        }
        .listRowBackground(Palette.surface)
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
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: appearanceModeRaw)
    }

    // MARK: - ⑤ 回复呈现（第 104 条）

    /// 回复呈现组（第 104 条＋台账 198 收敛 S6）：
    /// 两件相邻成组、文案互指——「流式增量呈现」管
    /// 回复怎么长出来（按块增量／逐词出现），「打字
    /// 动画」只管新文字带不带单次轻渐显（首批恒直
    /// 显）；两键语义不同、不合并。流式开关原在关于
    /// 页「内部实验」节（与本键同键的第二写口），已
    /// 随 S6 删除、只留本页一位。Reduce Motion 的优
    /// 先关系不在开关行表达——它在入场计划层（Core
    /// StreamingEntrance）恒压过打字动画，区脚只如
    /// 实注明结果
    private var replyPresentationSection: some View {
        Section {
            Toggle(isOn: $streamingEnabled) {
                Text(L10n.string("流式增量呈现"))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            Toggle(isOn: $typewriterEnabled) {
                Text(L10n.string("打字动画"))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            Toggle(isOn: $floatingBarEnabled) {
                Text(L10n.string("反应浮排"))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            // §432：AI 反应行——服务端未广告 self_
            // reactions 能力位时整行不出（僵尸禁令）
            if aiSelfRowVisible {
                Toggle(isOn: $aiSelfReactionsEnabled) {
                    Text(L10n.string("AI 反应"))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        } header: {
            appearanceHeader(L10n.string("回复呈现"))
        } footer: {
            Text(replyPresentationFooter)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    /// 回复呈现区脚（§432 增补）：AI 反应一句只在
    /// 开关行在场时拼入——行不在场不提不存在的开
    /// 关；句内写清关开关的语义（只关本机呈现、
    /// 数据不删、重开全量回来，施工图 §4 口径）
    private var replyPresentationFooter: String {
        var text = L10n.string("流式增量呈现管回复怎么长出来：开着按块增量刷新，关掉回到逐词出现。打字动画只管新文字带不带渐显，与增量方式是两件事。系统开启减弱动态效果时，始终直接显示。反应浮排管长按消息时的反应入口：开着先浮出表情排，关掉回到菜单里的「添加反应」。")
        if aiSelfRowVisible {
            text += L10n.string("AI 反应管助手贴在你消息上的表情：关了只是本机不显示，记录还在，重新打开会全量回来。")
        }
        return text
    }

    // MARK: - ⑥ 语言（§145）

    /// 语言四档勾选行（形态与 ④ 模式同构）：档名
    /// 经 L10n 按当前界面语言取词（切档瞬间整树重
    /// 建、新语言下重渲本页，档名随之换语）；区脚
    /// 小字如实注明系统托管面（权限弹窗/分享单等）
    /// 仍随系统语言——平台常态、不在本档承诺内
    private var languageSection: some View {
        Section {
            ForEach(AppLanguagePreference.allCases) { item in
                Button {
                    appLanguageRaw = item.rawValue
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Color.clear
                            .frame(width: OneDayMetrics.iconSlot)
                            .accessibilityHidden(true)
                        Text(L10n.string(item.displayKey))
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if item == languagePreference {
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
                    L10n.string(item.displayKey)
                        + (item == languagePreference ? "，已选" : "")
                )
            }
        } header: {
            appearanceHeader(L10n.string("语言"))
        } footer: {
            Text(L10n.string("系统弹窗与分享界面等由系统显示的部分，仍跟随系统语言。"))
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .sensoryFeedback(.selection, trigger: appLanguageRaw)
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
