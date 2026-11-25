import OneDayDesign
import OneDayCore
import SwiftUI

/// 设置（0.2.1 用户改版，仿 Muse 设置形态；0.3.2 骨架
/// 礼记化，DESIGN-V4 §17）：原生 List(.insetGrouped)＋
/// Section＋共用行组件（学礼记 MeView 的结构纪律）——分组
/// 容器与披露箭头由系统唯一提供，不再自绘 ScrollView＋
/// odGroup＋手绘箭头；行一律走本页共用行组件（navRow/
/// serverRow；键值行 0.4.0 起统一 LabeledContent），行
/// 底走 Palette.surface。
/// 0.22.0（设置图实测规格）：首页只剩条目行一层——行
/// 尾值位整件撤除（值进各自详情页；状态两行降题下副
/// 行），行题统一 20 regular 单字重、行图标 28、小字
/// 下限 15、分区头 15 灰；逐项改前/改后见 DESIGN-V4
/// §49。0.23.0：字阶全面落 Font 角色（rowTitleL/
/// rowSubtitle/meta/sectionLabel——默认字号与上述落
/// 值逐项等值、改随 Dynamic Type 缩放），行图标改引
/// 用 FrameworkIcon.settingsGlyphSize 单源，见 §50。
/// 0.24.0（用户 2026-11-10 指令，口径变更）：行题随
/// 角色改 Body 17 regular（HIG 落档，20 的 Muse 量测
/// 口径让位）、行图标 21 线性、身份节顶距＋顶边软效
/// 防横切，见 §51。
/// 设置页重塑（DESIGN §164，用户亲递原型 IA）：顶部
/// 搜索＋身份卡（点进「形象与名称」详情页）＋四组
/// （智能体／连接／应用／支持）＋工作区组（原管理组
/// 三件整面工作区）；分组与搜索共用 Core
/// SettingsCatalog 一份清单（搜得到的＝平时点得到
/// 的）。现行功能零丢失对账见 §164.2：原版本组迁关
/// 于页服务组、原关于组外链迁关于页开源组、网关/重
/// 启/日志/密钥/用量/定时/服务端会话按语义归入智能
/// 体与连接两组续存。组头小字随 IA 回归本页（0.36.3
/// 撤组头是无组名 IA 下的口径、四组命名 IA 需要组名
/// 领读，范围仅本页组头）
/// 结构归位（2026-11-20，纲要 D6/D7）：根页段序＝
/// 身份卡→智能体→服务与工作区→偏好与权限→支持→版
/// 本脚——上下文分组分根（智能体话题/服务器话题/本
/// 机偏好各成一组、叶子直达）；prototype-2 的四个转
/// 接枢纽页撤销（子项提回根组、断开连接落服务器组
/// 末行）；实验组沉入关于页末节，不再占根层位
/// 台账 198 收敛（2026-11-21）：服务与工作区按目录
/// segment 四段分段渲染（服务器/会话/工作区/维护，
/// 断开连接收维护段末）；重启网关根行与独立页退役
/// （重启归网关页控制组一条执行路径）；语音行归偏
/// 好组；聊天诊断根行退役（入口迁关于页内部实验
/// 节）；网关状态词改委托 Core ServerLabels 单源派
/// 生；行盒/组头改设计层共用件（OneDayMetrics
/// .settingsRowInsets／SettingsSectionHeader）
struct SettingsView: View {
    /// 0.20.0：呈现形态改根级 sheet（ContentView 呈现）
    /// ——关闭走本回调（页内大标题＋右上圆 X 头照 Muse
    /// 设置页图：navigationTitle 大标题＋toolbar 圆形
    /// 关闭钮，全系统件）；0.6.0 的应用格返回钮随应用
    /// 格退役
    var onClose: (() -> Void)? = nil
    /// 「去聊天」类动作（总览 sheet 内快捷动作）：关
    /// 设置并切聊天格（ContentView 注入）
    var onRequestChat: (() -> Void)? = nil
    // （工作区 sheet 呈现已于 §493 退役：电脑并入中
    // 枢电脑格、服务器文件正口归资源库，本页不再有
    // sheet 呈现的工作区面，ManageSheet 枚举一并删）
    // §164 合裁：§159 的身份卡 Menu 形态与呈现旗退役
    // ——身份卡改导航进 IdentityDetailView，编辑面本
    // 体在详情页内复用（AgentAvatarEditorView／
    // AgentNameEditorView 全仓一份不变）

    // （ManageSheet 枚举已于 §305 随 A-03/A-28 上移
    // AppRouter.swift 公共层——呈现槽枚举归呈现协调
    // 方，不再有枢纽页反向借用本页内部类型）

    @Environment(AppState.self) private var appState
    @State private var path: [SettingsRoute] = []
    /// 顶部搜索词（§164）：非空即搜索态——列表只剩
    /// 搜索结果一节，过滤走 Core SettingsCatalog.search
    @State private var searchText = ""
    /// 服务器状态：消费者——身份卡状态点、网关状态副
    /// 行、身份详情与关于页的注入值（0.22.0 值位撤除
    /// 后，各行摘要状态与其加载一并退役，见 loadSummaries）
    @State private var status: ServerStatus?
    @State private var showDisconnectConfirm = false
    /// 根页 notice 行（§493，D8）：伴生异常才显——
    /// 值＝伴生探测 footerNote（未检测到/需升级 App
    /// 时才有值、其余恒 nil 不占行）。旧 @State 自
    /// §164 续存起从未被赋值、该行实际恒不渲染，本
    /// 轮接真源
    private var notice: String? {
        appState.companionProbe.status?.footerNote()
    }
    /// 设置注册表（§437）：能力位亮且拉到才有值；nil
    /// ＝回落内置目录（与注册表上线前逐字一致）——注
    /// 册表是增益不是依赖，失败对用户零感知
    @State private var settingsRegistry: SettingsRegistryResponse?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if isSearching {
                    searchSection
                } else {
                    identitySection
                    generalPreferencesSection
                    modelAndConnectionSection
                    advancedAndSupportSection
                    versionFooter
                }
            }
            .listStyle(.insetGrouped)
            // 0.20.0（第六条照 Muse 设置图）：底换
            // Palette.settingsBG（浅灰托白卡）、组距按
            // 图中约 28 走 settingsSectionSpacing；卡圆
            // 角保留系统 insetGrouped 原生档（iOS 26 约
            // 20–24，与图中约 25 同量级——偏离登记见
            // §47：不为 1–3pt 自绘卡面、守全面原生令）
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            // §164：顶部搜索（系统 searchable、导航栏抽
            // 屉常显）——与原型页内搜索框同位同职，原生
            // 件优先
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索设置")
            )
            // 0.24.0（用户真机图：身份卡上沿被导航栏区
            // 横切成半截）：顶边改系统 soft 滚动边效——
            // 内容滑入栏下时渐隐而非被硬边切断（iOS 26
            // 官方解，沿本仓 chrome 定案的 scrollEdge-
            // Effect(.soft) 口径）；静止态无可见变化
            .scrollEdgeEffectStyle(.soft, for: .top)
            // 0.4.0（§3.2）：tabBarZone 手算底部留白删除——
            // 原生底栏回来后 List 底部避让由系统安全区自理
            // 0.36.3（用户 18:25 推翻 P8 例外）：撤
            // 「设置」大标题——不再设 navigationTitle，
            // 身份卡内容领头；右上圆形关闭钮保留（根
            // 级 sheet 的关闭动作、非标题栏）
            .toolbar {
                // 0.20.0：右上圆形关闭钮（sheet 形态，
                // 照图中圆 X；iOS 26 toolbar 玻璃圆钮由
                // 系统呈）；栈内二级页时本钮与返回钮同
                // 在亦无碍（关设置是根动作）
                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        // A6 根因修：关闭钮是结构钩子（冒烟门／回归
                        // 测试按「关闭设置」寻址），无障碍名必须逐字
                        // 稳定——字面量会走 LocalizedStringKey 查目录，
                        // 英文档下译成 "Close Settings"，钩子随之漂移、
                        // 测试找不到钮（sheet 本已呈现）。改 Text(verbatim:)
                        // 钉死逐字，与齿轮「设置」／底栏「聊天」等结构
                        // 名的既有口径一致；可见文案仍走目录本地化，不动。
                        .accessibilityLabel(Text(verbatim: "关闭设置"))
                    }
                }
            }
            .task {
                await loadSummaries()
                await loadSettingsRegistry()
                // 伴生探测（DESIGN §110）：打开设置时
                // 节流补探一次——RootView 的登录/前台触
                // 发是主路，本处保证用户直奔设置时版本
                // 组也是近鲜的（节流口径在 Store）
                await appState.companionProbe.probeIfNeeded(
                    appState: appState
                )
            }
            .onAppear {
                consumePendingRoutes()
            }
            .onChange(of: appState.router.pendingSettingsRoute) { _, _ in
                consumePendingRoutes()
            }
            .onChange(of: appState.router.pendingAgentRoute) { _, _ in
                consumePendingRoutes()
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .serverDetail:
                    ServerDetailView()
                case .profiles:
                    ProfilesView()
                case .models:
                    ModelSettingsView()
                case .envVars:
                    EnvVarsView()
                case .usage:
                    UsageDetailView()
                case .gateway:
                    GatewayView()
                case .logs:
                    LogsView()
                case .appearance:
                    AppearanceView()
                case .language:
                    LanguageSettingsView()
                case .interaction:
                    ReactionSettingsView()
                case .identity:
                    IdentityDetailView(
                        serverStatusText: identityServerStatusText,
                        onOpenChat: {
                            onClose?()
                            onRequestChat?()
                        }
                    )
                case .help:
                    HelpView()
                case .about:
                    AboutView()
                case .privacy:
                    LegalDocumentView(kind: .privacy)
                case .terms:
                    LegalDocumentView(kind: .terms)
                case .agent(let agentRoute):
                    agentDestination(agentRoute)
                // （prototype-2 四个枢纽页已于结构归位
                // 2026-11-20 撤销：子项提回根组直达、
                // 路由退役，见 SettingsCatalog 迁移口径）
                case .mainSession:
                    MainSessionView(
                        onRequestChat: onRequestChat,
                        onClose: onClose
                    )
                case .advancedDiagnostics:
                    advancedDiagnosticsView
                case .healthCheck:
                    HealthCheckView()
                case .connectionSelfCheck:
                    ConnectionSelfCheckView()
                case .voice:
                    VoiceSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .addDevice:
                    AddDeviceView()
                case .authSessions:
                    AuthSessionsView()
                case .pairingManagement:
                    PairingManagementView()
                case .chatDiagnostics:
                    ChatDiagnosticsView()
                case .crashReports:
                    CrashReportsView()
                }
            }
            // §496：断开行已迁当前服务器页，本确认框
            // 只余搜索 activate(.disconnect) 路径在用
            .confirmationDialog(
                "断开连接？",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("断开连接", role: .destructive) {
                    appState.disconnect()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除这台手机上保存的服务器凭据与登录会话。本地聊天记录保留。")
            }
        }
        .fullscreenPopBridge()
    }

    @ViewBuilder
    private func agentDestination(_ route: AgentRoute) -> some View {
        switch route {
        case .memory:
            MemoryView()
        case .skills:
            SkillsView()
        case .toolsets:
            ToolsetsSettingsView()
        case .delegation:
            DelegationRoutingView()
        case .cron:
            CronJobsView()
        case .serverSessionDetail(let id):
            ServerSessionDetailView(sessionID: id)
        case .mcp:
            // 本机服务详情原有的「总览」入口已随结构
            // 归位包撤除（纲要 D5-1 总览撤页）
            ConnectorsView()
        case .devicePermissions:
            DevicePermissionsView()
        }
    }

    // （自绘页标题行 pageTitleSection 已于 0.4.0 删除，
    // 审计 §3.1：标题回系统 navigationTitle；TypeScale
    // .settingsTitle 随之退役）

    // MARK: - 顶部身份卡（§164：点进形象与名称详情页）


    /// 身份卡：一行说清连的是谁——头像＋Hermes 名称
    /// ＋网关状态点，副行＝当前服务器 host；整卡是导
    /// 航行、点进「形象与名称」详情页（形象/名称的编
    /// 辑在详情页内，编辑面与枢纽共用本体）。服务器详
    /// 情入口在连接组「当前服务器」行——两行去向不同
    /// （一个管本机显示、一个管连接），不构成双箭头
    /// 指同一页（旧静态卡「避免双箭头」的顾虑随去向
    /// 分化销账）
    private var identitySection: some View {
        Section {
            NavigationLink(value: SettingsRoute.identity) {
                HStack(spacing: OneDayMetrics.spacingSM) {

                    appState.agentAvatarImage
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: OneDayMetrics.avatarListRow,
                            height: OneDayMetrics.avatarListRow
                        )
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(Palette.hairline, lineWidth: 0.5)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            // 0.36.22：身份头名收敛档案出口
                            Text(appState.agentDisplayName)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)

                                .lineLimit(1)
                            if let status {
                                StatusDot(
                                    color: Palette.stateColor(status.gatewayState)
                                )
                            }
                        }
                        // 0.20.0：副行给当前服务器 host（15
                        // 灰，照图中账户卡双行形态：题＋副）；
                        // 模型副行仍禁（0.4.0 A 案：模型露头
                        // 只许聊天页胶囊一处，不变）
                        Text(appState.config?.host ?? "未连接")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)

                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }

            .settingsSeparatorToIconEdge()
        }
        .listRowBackground(Palette.surface)
        // 0.24.0：身份节走专用行盒（顶距＋10 防栏区横
        // 切，见 identityRowInsets）
        .listRowInsets(identityRowInsets)
    }

    /// 身份详情页「服务器状态」值位：未配置显未连接、
    /// 状态未读到显 —、网关异常如实显异常、其余已连接
    /// （异常判定与状态词同源取词比较——委托 Core 后
    /// 状态词随语言走，比较也须走 L10n 同词，不再拿
    /// 中文字面量比本地化结果）
    private var identityServerStatusText: String {
        if appState.config == nil { return L10n.string("未连接") }
        guard status != nil else { return "—" }
        return gatewayStateWord == L10n.string("异常")
            ? L10n.string("异常")
            : L10n.string("已连接")
    }

    /// 网关状态词：委托 Core ServerLabels 单源派生
    /// （台账 198 收敛 S10——本页旧私有实现与已退役
    /// RestartGatewayView 的同名副本一并收口，词表
    /// 只此一处）
    private var gatewayStateWord: String {
        ServerLabels.gatewayStateWord(for: status)
    }

    // MARK: - 通用与偏好（大厂精简标准：高频偏好一屏直达）

    private var generalPreferencesSection: some View {
        Section {
            navRow(icon: "sun.max", title: L10n.string("外观"), route: .appearance)
            navRow(icon: "globe", title: L10n.string("语言"), route: .language)
            if let voiceAvailabilityWord {
                statusNavRow(
                    icon: "speaker.wave.2",
                    title: L10n.string("语音"),
                    status: voiceAvailabilityWord,
                    route: .voice
                )
            } else {
                navRow(icon: "speaker.wave.2", title: L10n.string("语音"), route: .voice)
            }
            navRow(icon: "bell", title: L10n.string("通知"), route: .notifications)
            navRow(icon: "face.smiling", title: L10n.string("互动"), route: .interaction)
            Toggle(isOn: Binding(
                get: { Haptics.isEnabled },
                set: { UserDefaults.standard.set($0, forKey: Haptics.enabledStorageKey) }
            )) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("iphone.radiowaves.left.and.right")
                    Text("触感反馈")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .settingsSeparatorToIconEdge()
        } header: {
            sectionHeader("通用与偏好")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 模型、用量与连接（核心账号与设备入口）

    private var modelAndConnectionSection: some View {
        Section {
            navRow(icon: "cpu", title: L10n.string("模型与服务商"), route: .models)
            navRow(icon: "chart.bar", title: L10n.string("用量统计"), route: .usage)
            navRow(icon: "server.rack", title: L10n.string("当前服务器"), route: .serverDetail)
            NavigationLink(value: SettingsRoute.authSessions) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("key.radiowaves.forward")
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("登录会话与票据")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text(appState.shortLivedTokenActive ? "短时票据已启用" : "点击启用或管理设备")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .settingsSeparatorToIconEdge()
            navRow(icon: "qrcode", title: L10n.string("添加设备"), route: .addDevice)
            if pendingPairingCount > 0 {
                statusNavRow(
                    icon: "person.badge.key",
                    title: L10n.string("设备配对"),
                    status: "\(pendingPairingCount) 条待批准",
                    route: .pairingManagement
                )
            }
        } header: {
            sectionHeader("模型与连接")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 高级与支持（运维诊断全部收进二级页，主列表零噪音）

    private var advancedAndSupportSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.advancedDiagnostics) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("wrench.and.screwdriver")
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("高级与诊断")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("网关 · 环境变量 · 日志 · 自检")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .settingsSeparatorToIconEdge()
            navRow(icon: "questionmark.circle", title: L10n.string("帮助与反馈"), route: .help)
            navRow(icon: "info.circle", title: L10n.string("关于 OneDay"), route: .about)
        } header: {
            sectionHeader("高级与支持")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    /// 二级收口页：运维、服务器诊断与极客项全部扁平收纳于此，不再套娃嵌套
    private var advancedDiagnosticsView: some View {
        List {
            SettingsHeroCard(
                symbol: "wrench.and.screwdriver",
                tint: .indigo,
                title: "高级与诊断",
                subtitle: "服务端运维配置与一键排障工具，全部同级直达。",
                statusText: gatewayStateWord,
                statusTone: gatewayStateWord == L10n.string("异常") ? .error : (status != nil ? .healthy : .neutral)
            )

            Section {
                statusNavRow(
                    icon: "network",
                    color: gatewayStateWord == L10n.string("异常") ? .red : nil,
                    title: L10n.string("网关状态"),
                    status: gatewayStateWord,
                    route: .gateway
                )
                navRow(icon: "key", title: L10n.string("环境变量"), route: .envVars)
                navRow(icon: "link", title: L10n.string("主会话"), route: .mainSession)
                navRow(icon: "person.badge.key", title: L10n.string("平台用户配对"), route: .pairingManagement)
            } header: {
                sectionHeader("服务端与运维")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                if let lastSelfCheckWord {
                    statusNavRow(
                        icon: "antenna.radiowaves.left.and.right",
                        color: lastSelfCheckWord == L10n.string("异常") ? .red : nil,
                        title: L10n.string("连接自检"),
                        status: lastSelfCheckWord,
                        route: .connectionSelfCheck
                    )
                } else {
                    navRow(icon: "antenna.radiowaves.left.and.right", title: L10n.string("连接自检"), route: .connectionSelfCheck)
                }
                if let lastHealthWord {
                    statusNavRow(
                        icon: "stethoscope",
                        color: lastHealthWord == L10n.string("异常") ? .red : nil,
                        title: L10n.string("体检与存档"),
                        status: lastHealthWord,
                        route: .healthCheck
                    )
                } else {
                    navRow(icon: "stethoscope", title: L10n.string("体检与存档"), route: .healthCheck)
                }
                navRow(icon: "doc.text", title: L10n.string("系统日志"), route: .logs)
                navRow(icon: "exclamationmark.triangle", color: .red, title: L10n.string("崩溃报告"), route: .crashReports)
                navRow(icon: "doc.text.magnifyingglass", title: L10n.string("聊天诊断"), route: .chatDiagnostics)
            } header: {
                sectionHeader("诊断与日志")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if let notice {
                Section {
                    Text(notice)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                } header: {
                    sectionHeader("伴生服务状态")
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("高级与诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    @State private var healthSummaryStore = HealthSummaryStore.shared
    @State private var pairingSummaryStore = PairingSummaryStore.shared
    @State private var selfCheckSummaryStore = SelfCheckSummaryStore.shared

    private var pendingPairingCount: Int {
        pairingSummaryStore.pendingCount(
            for: appState.config?.baseString
        ) ?? 0
    }

    private var lastHealthWord: String? {
        healthSummaryStore
            .summary(for: appState.config?.baseString)?
            .overall.word
    }

    private var lastSelfCheckWord: String? {
        selfCheckSummaryStore
            .summary(for: appState.config?.baseString)?
            .word
    }

    private var voiceAvailabilityWord: String? {
        let availability = SpeechPlayer.shared.availability
        return availability == .unknown ? nil : availability.word
    }

    // MARK: - 搜索（§164）

    /// 搜索结果节：命中行＝题＋搜索副行＋chevron，点
    /// 按经 activate 点达（路由页压栈、管理三件开
    /// sheet、身份进详情页）；无命中给空态与清搜索
    /// 动作（原型同款）。搜索索引与浏览清单同源
    /// （SettingsCatalog），不另维护第二份
    private var searchSection: some View {
        let hits = SettingsCatalog.effectiveSearch(
            searchText, registry: settingsRegistry
        )
        return Section {
            if hits.isEmpty {
                VStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: FrameworkIcon.tabGlyphSize))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityHidden(true)
                    Text("没有找到「\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))」")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("试试「服务器」「记忆」或「外观」。")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button("清除搜索") { searchText = "" }
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingM)
            } else {
                ForEach(hits) { row in
                    switch row {
                    case .destination(let entry):
                        searchRow(entry)
                    case .value(let record):
                        SettingsRegistryRowView(record: record)
                    }
                }
            }
        } header: {
            sectionHeader("搜索结果")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func searchRow(_ entry: SettingsCatalogEntry) -> some View {
        Button {
            activate(entry)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(iconName(for: entry))
                Text(L10n.string(entry.title))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                DisclosureChevron(font: .system(size: FrameworkIcon.composerGlyphSize))
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .settingsSeparatorToIconEdge()
    }

    /// 搜索点达分发：断开连接起确认框、余者压设置
    /// 栈（与深链消费同一落点口径）
    private func activate(_ entry: SettingsCatalogEntry) {
        switch entry.destination {
        case .disconnect: showDisconnectConfirm = true
        case .serverSessions:
            // 台账 199（2026-11-21 用户裁）：服务端会
            // 话名单正主＝全部对话（一级面），本行改
            // 深链——置根级呈现请求，ContentView 先
            // 收设置 sheet 再升全屏页（AfterSettings
            // 序）；设置内旧名单页已删
            appState.router.allConversationsRequested = true
        default:
            if let route = route(for: entry.destination) {
                path = [route]
            }
        }
    }

    /// 目的地 → 设置路由（映射本体已收口 AppRouter
    /// 侧 SettingsRoute.from(destination:)，设置页与
    /// 全局搜索共用一份，DESIGN §391）
    private func route(
        for destination: SettingsDestination
    ) -> SettingsRoute? {
        SettingsRoute.from(destination: destination)
    }

    /// 条目行图标（SF 符号留 App 层；既有行图标沿旧
    /// 值不漂移，新行取同语义线性符号）
    private func iconName(for entry: SettingsCatalogEntry) -> String {
        switch entry.id {
        case "identity": return "person.crop.circle"
        case "profiles": return "archivebox"
        case "memory": return "memorychip"
        case "skills": return "puzzlepiece.extension"
        case "toolsets": return "wrench.and.screwdriver"
        case "delegation": return "arrow.triangle.branch"
        case "models": return "text.bubble"
        case "cron": return "clock.arrow.2.circlepath"
        case "serverSessions": return "bubble.left"
        case "server": return "server.rack"
        case "connectors": return "cable.connector"
        case "devicePermissions": return "iphone"
        case "gateway": return "network"
        case "logs": return "doc.text"
        case "envVars": return "key"
        case "usage": return "chart.bar"
        case "appearance": return "sun.max"
        case "language": return "globe"
        case "interaction": return "face.smiling"
        case "help": return "questionmark.circle"
        case "about": return "info.circle"
        // 台账 198 收敛 S11：与体检行同为 stethoscope
        // 是根行图标唯一重名（搜索结果里两行同图易
        // 混）——诊断行换放大镜文档符号，体检保留听诊器
        case "chatDiagnostics": return "doc.text.magnifyingglass"
        case "crashReports": return "exclamationmark.triangle"
        case "privacy": return "lock.shield"
        case "terms": return "doc.text"
        // prototype-2 叶子（枢纽页四行图标随页退役）
        case "mainSession": return "link"
        case "healthCheck": return "stethoscope"
        case "connectionSelfCheck": return "antenna.radiowaves.left.and.right"
        case "voice": return "speaker.wave.2"
        case "notifications": return "bell"
        case "addDevice": return "qrcode"
        case "pairing": return "person.badge.key"
        case "disconnect": return "rectangle.portrait.and.arrow.right"
        default: return "gearshape"
        }
    }

    /// 目录驱动导航行：图标/题自条目、去向自 route
    /// 映射。有栈内路由的走 navRow；无路由的是动作行
    /// （全部对话＝根级全屏页、工作区三件＝sheet 呈
    /// 现，route 恒 nil）——渲动作 Button 行，点按走
    /// activate 与搜索点达同一分发。动作行行貌与
    /// navRow 同构（图标＋标题、行高与分隔口径同），
    /// chevron 显式补（普通 Button 在 List 里没有系
    /// 统自带的揭示箭头，与 searchRow 同式）
    @ViewBuilder
    private func catalogNavRow(_ entry: SettingsCatalogEntry) -> some View {
        if route(for: entry.destination) == nil {
            Button {
                activate(entry)
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon(iconName(for: entry))
                    Text(L10n.string(entry.title))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    DisclosureChevron(font: .system(size: FrameworkIcon.composerGlyphSize))
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .settingsSeparatorToIconEdge()
        } else if let route = route(for: entry.destination) {
            navRow(
                icon: iconName(for: entry), title: L10n.string(entry.title),
                route: route
            )
        }
    }

    /// 组头（§164 随 IA 回归：小字 sectionLabel＋次
    /// 级墨，与全 App 详情页 SectionLabel 同字阶；
    /// 台账 198 收敛 B7 起走设计层共用件
    /// SettingsSectionHeader，本页只供已本地化的题）
    private func sectionHeader(_ title: String) -> some View {
        SettingsSectionHeader(L10n.string(title))
    }

    /// 页脚签名行（§188 补回原型形态：App 图标小图
    /// 19pt/角 5＋「OneDay」＋版本小字，一行居中）：
    /// 无卡底；字面仍走 OneDayVersionLabel 单源——名
    /// 为字面、版本取 hero 面（full 整串保留为同文件
    /// 字面锚）；墨色沿 0.22.0 审计口径 inkSecondary
    private var versionFooter: some View {
        Section {
            HStack(spacing: OneDayMetrics.iconTextGap) {
                AppIconView(size: 19, cornerRadius: 5)
                (
                    Text("OneDay ")
                        .font(.meta)
                    + Text(OneDayVersionLabel.hero)
                        .font(.badgeOnly)
                )
                .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 行盒与辅助

    // （本页统一行盒已于台账 198 收敛 B7 上收设计层
    // OneDayMetrics.settingsRowInsets 单源——0.3.8 第
    // 5 条的口径不变：纵向 0、横向 20 与页 gutter 对齐）

    /// 身份节专用行盒（0.24.0）：首节顶距＋10——用户真
    /// 机图里身份卡紧贴导航栏区、Hermes 题上沿被横切；
    /// 给第一节留出栏下呼吸位，卡与题整行恒在栏区之
    /// 下完整呈现（其余节维持统一行盒不动）
    private var identityRowInsets: EdgeInsets {
        EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20)
    }

    // （版本派生三件已于 §493 退役：关于页服务组删
    // 除后 hermesVersionText/companionVersionLine 无
    // 消费方；companionFooterNote 的语义由根页 notice
    // 计算属性直读探测态承接）


    // MARK: - 共用行组件

    private func rowIcon(_ name: String, color: Color? = nil) -> some View {
        SettingsRowIcon(symbol: name, color: color)
    }

    /// 导航行（共用行组件）：图标＋题（0.24.0 起
    /// Body 17 regular，角色 rowTitleL），披露箭头由
    /// NavigationLink 系统提供。0.22.0 起行尾值位整件
    /// 撤除——值一律进各自详情页；确属状态展示不可
    /// 撤的行走下方 statusNavRow 降为题下副行
    private func navRow(
        icon: String,
        color: Color? = nil,
        title: String,
        route: SettingsRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon, color: color)
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .settingsSeparatorToIconEdge()
    }

    private func statusNavRow(
        icon: String,
        color: Color? = nil,
        title: String,
        status: String,
        route: SettingsRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon, color: color)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(title)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(status)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .settingsSeparatorToIconEdge()
    }

    // （infoRow 已于 0.4.0 删除，审计 §3.1：键值行统一 LabeledContent）

    // MARK: - 数据与动作

    /// 深链消费：设置内路由直接落位（会话详情旧垫层
    /// ——设置内名单页——已随台账 199 删除，详情路由
    /// 直达本体）
    private func consumePendingRoutes() {
        if let route = appState.router.pendingSettingsRoute {
            appState.router.pendingSettingsRoute = nil
            path = [route]
            return
        }
        guard let route = appState.router.pendingAgentRoute else { return }
        appState.router.pendingAgentRoute = nil
        path = [.agent(route)]
    }

    /// 0.22.0 瘦身：值位撤除后本页只剩 status 一个数
    /// 据依赖（身份卡状态点＋网关状态副行＋§164 身份
    /// 详情/关于页注入）；旧形态为各行摘要并行发 7 个
    /// 管理请求只为行尾小字——随值位一并退役，打开
    /// 设置页的请求面回到 1 个
    private func loadSummaries() async {
        if let config = appState.config,
           let loaded = try? await appState.client.status(config: config) {
            status = loaded
        }
    }

    /// 设置注册表拉取（§437）：能力位不亮／拉不到／
    /// 解不开一律保持 nil 回落内置目录——注册表是增
    /// 益不是依赖，失败零感知（判定走能力协商单源）
    private func loadSettingsRegistry() async {
        guard let config = appState.config,
              let apiKey = appState.apiKey,
              let capabilities = try? await appState.client
                .capabilities(config: config, apiKey: apiKey),
              CapabilityNegotiation.settingsRegistryAvailability(
                  capabilities
              ) == .available,
              let registry = try? await appState.client
                .settingsRegistry(config: config, apiKey: apiKey)
        else { return }
        settingsRegistry = registry
    }

    // （根页重启执行副本 restartGateway() 已于台账
    // 198 收敛 S4 删除：重启只走网关状态页控制组一
    // 条执行路径——确认＋执行＋状态回读，版本口径
    // 见 GatewayView）
}

private extension View {
    /// 分隔线贯通到图标左缘（0.36.3，用户 18:25 点名③）：
    /// 本页是原生 insetGrouped List，系统分隔线默认对齐
    /// 到文字列（图标下无线）——以 listRowSeparatorLeading
    /// 对齐引导把起始点钉到行内容左缘（＝图标左缘），与
    /// 0.36.0 自绘分组的贯通口径对齐。逐行施加于行根视图。
    func settingsSeparatorToIconEdge() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// 大厂级 iOS 26 设置页统一设计系统组件（治本收口）：
/// 所有设置二级页共用同一套视觉骨架——顶部 Hero 摘要卡、
/// 语义状态胶囊、图标导航行与操作按钮，消除各页风格割裂。
enum SettingsStatusTone {
    case healthy
    case warning
    case error
    case neutral

    var dotColor: Color {
        switch self {
        case .healthy: return Palette.success
        case .warning: return Palette.warning
        case .error: return Palette.danger
        case .neutral: return Palette.inkMuted
        }
    }

    var textColor: Color {
        switch self {
        case .healthy: return Palette.successText
        case .warning: return Palette.warningText
        case .error: return Palette.danger
        case .neutral: return Palette.inkSecondary
        }
    }

    var pillBackground: Color {
        switch self {
        case .healthy: return Palette.success.opacity(0.12)
        case .warning: return Palette.warning.opacity(0.14)
        case .error: return Palette.danger.opacity(0.12)
        case .neutral: return Palette.inkMuted.opacity(0.12)
        }
    }
}

/// 设置子页顶部 Hero 摘要卡（对标 iOS 设置 / Telegram / ChatGPT）：
/// 顶部居中或左对齐大图标块 + 标题 + 一句话说明 + 可选状态胶囊
struct SettingsHeroCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var statusText: String? = nil
    var statusTone: SettingsStatusTone = .neutral

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                HStack(alignment: .center, spacing: OneDayMetrics.spacingM) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint.gradient)
                            .frame(width: 48, height: 48)
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if let statusText {
                                SettingsStatusPill(text: statusText, tone: statusTone)
                            }
                        }
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }
}

/// 语义状态胶囊（带状态点，不单靠颜色传意）
struct SettingsStatusPill: View {
    let text: String
    let tone: SettingsStatusTone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(tone.textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tone.pillBackground, in: Capsule())
    }
}

/// 统一设置行图标：20pt 单色线性 SF Symbols，默认次级色，
/// 仅在异常、危险或明确状态指示时传入语义色
struct SettingsRowIcon: View {
    let symbol: String
    var color: Color? = nil

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color ?? Palette.inkSecondary)
            .frame(width: OneDayMetrics.iconSlot, height: OneDayMetrics.iconSlot)
            .accessibilityHidden(true)
    }
}

/// 带图标的键值信息行（支持点按复制）
struct SettingsValueRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    var monospaced: Bool = false
    var copyable: Bool = false

    @State private var copied = false

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            SettingsRowIcon(symbol: symbol)
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    Haptics.success()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(copied ? "已复制" : value)
                            .font(monospaced ? .metaMonospaced : .rowSubtitle)
                            .foregroundStyle(copied ? Palette.successText : Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(copied ? Palette.successText : Palette.primary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(monospaced ? .metaMonospaced : .rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }
}
