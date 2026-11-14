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
    /// 「全部对话」行的跳出请求（管理收口包补件，用
    /// 户 2026-11-13 18:57 拍板入口自抽屉迁入）：全
    /// 部对话页是根级全屏页、不在本导航栈里——同
    /// onRequestChat 口径，本面只发请求，关面与呈现
    /// 由 ContentView 承接（走原抽屉入口同一呈现路）
    var onRequestAllConversations: (() -> Void)? = nil
    /// 「工作区」组三页的 sheet 呈现（总览/电脑自带导
    /// 航栈、服务器文件由本页包一层栈）：不进本页导航
    /// 栈——三页都是整面工作区、且各自带栈，套栈必乱；
    /// sheet 呈现与 Muse 设置里连接器/设备行打开整
    /// 面页的形态一致（原「管理」组，§164 改组名工作区）
    @State private var manageSheet: ManageSheet?
    // §164 合裁：§159 的身份卡 Menu 形态与呈现旗退役
    // ——身份卡改导航进 IdentityDetailView，编辑面本
    // 体在详情页内复用（AgentAvatarEditorView／
    // AgentNameEditorView 全仓一份不变）

    enum ManageSheet: String, Identifiable {
        case overview, computer, serverFiles
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var path: [SettingsRoute] = []
    /// 顶部搜索词（§164）：非空即搜索态——列表只剩
    /// 搜索结果一节，过滤走 Core SettingsCatalog.search
    @State private var searchText = ""
    /// 服务器状态：消费者——身份卡状态点、网关状态副
    /// 行、身份详情与关于页的注入值（0.22.0 值位撤除
    /// 后，各行摘要状态与其加载一并退役，见 loadSummaries）
    @State private var status: ServerStatus?
    @State private var showRestartConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var notice: String?

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
                    agentSection
                    serverAndWorkspaceSection
                    preferencesSection
                    labSection
                    supportSection
                    versionFooter
                }
                // notice 提示行在根页续存（§164 监工纠正⑥遗漏①）：浏览/搜索两态都显
                if let notice {
                    Section {
                        Text(notice)
                            // 0.22.0 小字清查：13→15 下限
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .listRowBackground(Palette.surface)
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
                        .accessibilityLabel("关闭设置")
                    }
                }
            }
            .sheet(item: $manageSheet) { item in
                manageSheetContent(item)
            }
            .task {
                await loadSummaries()
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
            .onChange(of: appState.pendingSettingsRoute) { _, _ in
                consumePendingRoutes()
            }
            .onChange(of: appState.pendingAgentRoute) { _, _ in
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
                case .sidebar:
                    DrawerSectionsView()
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
                    AboutView(
                        hermesVersionText: hermesVersionText,
                        companionLine: companionVersionLine,
                        companionNote: companionFooterNote
                    )
                case .privacy:
                    LegalDocumentView(kind: .privacy)
                case .terms:
                    LegalDocumentView(kind: .terms)
                case .agent(let agentRoute):
                    agentDestination(agentRoute)
                // prototype-2 新增枢纽页
                case .agentConfig:
                    AgentConfigView()
                case .serverManagement:
                    ServerManagementView(
                        status: status,
                        showDisconnectConfirm: $showDisconnectConfirm
                    )
                case .sessionManagement:
                    SessionManagementView()
                case .workspaceHub:
                    WorkspaceHubView(manageSheet: $manageSheet)
                case .mainSession:
                    MainSessionView(
                        onRequestChat: onRequestChat,
                        onClose: onClose
                    )
                case .restartGateway:
                    RestartGatewayView(
                        status: status,
                        showRestartConfirm: $showRestartConfirm
                    )
                }
            }
            .confirmationDialog(
                "重启网关？",
                isPresented: $showRestartConfirm,
                titleVisibility: .visible
            ) {
                Button("重启", role: .destructive) {
                    Task {
                        await restartGateway()
                        path.removeAll()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("重启期间对话会短暂中断，进行中的任务会被打断。")
            }
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
    }

    @ViewBuilder
    private func agentDestination(_ route: AgentRoute) -> some View {
        switch route {
        case .memory:
            MemoryView()
        case .skills:
            SkillsView()
        case .cron:
            CronJobsView()
        case .serverSessions:
            ServerSessionsView()
        case .serverSessionDetail(let id):
            ServerSessionDetailView(sessionID: id)
        case .mcp:
            // 0.29.0：目录本机服务详情的「总览」入口经
            // 本闭包回设置页开管理组总览 sheet（总览的
            // 承载在本页 manageSheet、不另立第二份）
            ConnectorsView(onOpenOverview: { manageSheet = .overview })
        case .devicePermissions:
            DevicePermissionsView()
        case .approvalRules:
            ApprovalRulesSettingsView()
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
    private var identityServerStatusText: String {
        if appState.config == nil { return L10n.string("未连接") }
        guard status != nil else { return "—" }
        return gatewayStateWord == "异常"
            ? L10n.string("异常")
            : L10n.string("已连接")
    }

    /// 网关状态词派生（与 ServerManagementView.gatewayStateWord 同口径）
    private var gatewayStateWord: String {
        switch status?.gatewayState?.lowercased() {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return status == nil ? "—" : "未知"
        }
    }

    // MARK: - 智能体组（prototype-2）

    /// 智能体组（prototype-2 收敛）：只剩模型与服务商／智能体配置／
    /// 定时任务三行——profiles/memory/skills 移入 agentConfig 枢纽页
    private var agentSection: some View {
        Section {
            ForEach(SettingsCatalog.browseEntries(in: .agent)) { entry in
                catalogNavRow(entry)
            }
        } header: {
            sectionHeader("智能体")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 服务与工作区组（prototype-2 新组）

    /// 服务与工作区组（prototype-2）：三个二级枢纽页——服务器管理／
    /// 会话管理／工作区
    private var serverAndWorkspaceSection: some View {
        Section {
            ForEach(SettingsCatalog.browseEntries(in: .serverAndWorkspace)) { entry in
                catalogNavRow(entry)
            }
        } header: {
            sectionHeader("服务与工作区")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 偏好与权限组（prototype-2 新组）

    /// 偏好与权限组（prototype-2）：外观／连接器／设备与权限
    private var preferencesSection: some View {
        Section {
            ForEach(SettingsCatalog.browseEntries(in: .preferences)) { entry in
                catalogNavRow(entry)
            }
        } header: {
            sectionHeader("偏好与权限")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 实验组（§257 换代包 3）

    /// 会话页新承载开关（Core ChatCarrierFeature，
    /// 与 ChatView 同键同源）：施工期机制、默认关；
    /// 开后消息列表与回底钮换新承载（几何/跟随口
    /// 径不变），关掉即回旧承载、无数据迁移。蓝图
    /// A/B/F 组真机验收后由换代包 6 处置去留
    @AppStorage(ChatCarrierFeature.defaultsKey)
    private var gen3CarrierEnabled = false

    private var labSection: some View {
        Section {
            Toggle(isOn: $gen3CarrierEnabled) {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(L10n.string("会话页新承载"))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(L10n.string("实验开关：开启后消息列表与回到底部按钮换用新承载，出问题关掉即回旧承载。"))
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            sectionHeader("实验")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 支持组（§164）

    /// 支持组：帮助与反馈／关于 OneDay（原关于组的版
    /// 本对齐两行与外链、原页脚隐私说明全迁关于页，
    /// 见 §164.2 对账）
    private var supportSection: some View {
        Section {
            ForEach(SettingsCatalog.browseEntries(in: .support)) { entry in
                catalogNavRow(entry)
            }
        } header: {
            sectionHeader("支持")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 工作区 sheet 呈现（prototype-2 保持）

    /// 工作区 sheet 内容：总览／电脑／服务器文件保持现行 sheet 机制
    @ViewBuilder
    private func manageSheetContent(_ item: ManageSheet) -> some View {
        switch item {
        case .overview:
            OverviewView(
                onOpenAgent: { route in
                    manageSheet = nil
                    path = [.agent(route)]
                },
                onOpenChatSession: { id in
                    manageSheet = nil
                    onClose?()
                    appState.pendingChatSessionID = id
                },
                onOpenSettings: { route in
                    manageSheet = nil
                    path = [route]
                },
                onOpenChat: {
                    manageSheet = nil
                    onRequestChat?()
                },
                onBackToApps: { manageSheet = nil }
            )
        case .computer:
            ComputerView(onBackToApps: { manageSheet = nil })
        case .serverFiles:
            NavigationStack {
                FilesBrowserView()
            }
        }
    }

    // MARK: - 搜索（§164）

    /// 搜索结果节：命中行＝题＋搜索副行＋chevron，点
    /// 按经 activate 点达（路由页压栈、管理三件开
    /// sheet、身份进详情页）；无命中给空态与清搜索
    /// 动作（原型同款）。搜索索引与浏览清单同源
    /// （SettingsCatalog），不另维护第二份
    private var searchSection: some View {
        let hits = SettingsCatalog.search(searchText)
        return Section {
            if hits.isEmpty {
                VStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .regular))
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
                ForEach(hits) { entry in
                    searchRow(entry)
                }
            }
        } header: {
            sectionHeader("搜索结果")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private func searchRow(_ entry: SettingsCatalogEntry) -> some View {
        Button {
            activate(entry)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(iconName(for: entry))
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(L10n.string(entry.title))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(L10n.string(entry.summary))
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .settingsSeparatorToIconEdge()
    }

    /// 搜索点达分发：管理三件开 sheet、全部对话发跳
    /// 出请求、余者压设置栈（与深链消费同一落点口径）
    private func activate(_ entry: SettingsCatalogEntry) {
        switch entry.destination {
        case .overview: manageSheet = .overview
        case .computer: manageSheet = .computer
        case .serverFiles: manageSheet = .serverFiles
        case .allConversations: onRequestAllConversations?()
        default:
            if let route = route(for: entry.destination) {
                path = [route]
            }
        }
    }

    /// 目录条目 id 取行（浏览组内特型行与目录行的混
    /// 排处用；id 是对账锚点、清单内必有）
    private func entry(id: String) -> SettingsCatalogEntry {
        SettingsCatalog.entries.first { $0.id == id }!
    }

    /// 目的地 → 设置路由（sheet 三件与无路由项返回
    /// nil，由 activate/特型行分流）
    private func route(
        for destination: SettingsDestination
    ) -> SettingsRoute? {
        switch destination {
        case .identity: return .identity
        case .profiles: return .profiles
        case .memory: return .agent(.memory)
        case .skills: return .agent(.skills)
        case .cron: return .agent(.cron)
        case .serverSessions: return .agent(.serverSessions)
        case .models: return .models
        case .envVars: return .envVars
        case .usage: return .usage
        case .serverDetail: return .serverDetail
        case .connectors: return .agent(.mcp)
        case .devicePermissions: return .agent(.devicePermissions)
        case .approvalRules: return .agent(.approvalRules)
        case .gateway: return .gateway
        case .logs: return .logs
        case .appearance: return .appearance
        case .sidebar: return .sidebar
        case .help: return .help
        case .about: return .about
        case .privacy: return .privacy
        case .terms: return .terms
        case .overview, .computer, .serverFiles,
             .allConversations: return nil
        // prototype-2 新增
        case .agentConfig: return .agentConfig
        case .serverManagement: return .serverManagement
        case .sessionManagement: return .sessionManagement
        case .workspaceHub: return .workspaceHub
        case .mainSession: return .mainSession
        case .restartGateway: return .restartGateway
        }
    }

    /// 条目行图标（SF 符号留 App 层；既有行图标沿旧
    /// 值不漂移，新行取同语义线性符号）
    private func iconName(for entry: SettingsCatalogEntry) -> String {
        switch entry.id {
        case "identity": return "person.crop.circle"
        case "profiles": return "archivebox"
        case "memory": return "memorychip"
        case "skills": return "puzzlepiece.extension"
        case "models": return "text.bubble"
        case "cron": return "clock.arrow.2.circlepath"
        case "serverSessions": return "bubble.left"
        case "server": return "server.rack"
        case "connectors": return "cable.connector"
        case "devicePermissions": return "iphone"
        case "approvalRules": return "checkmark.shield"
        case "gateway": return "network"
        case "logs": return "doc.text"
        case "envVars": return "key"
        case "usage": return "chart.bar"
        case "overview": return "chart.xyaxis.line"
        case "computer": return "display"
        case "serverFiles": return "folder"
        case "appearance": return "sun.max"
        case "sidebar": return "sidebar.left"
        // 全部对话行沿原抽屉管理行的字形（rectangle.
        // stack），入口换了、认页的记号不变
        case "allConversations": return "rectangle.stack"
        case "help": return "questionmark.circle"
        case "about": return "info.circle"
        case "privacy": return "lock.shield"
        case "terms": return "doc.text"
        // prototype-2 新增
        case "agentConfig": return "slider.horizontal.3"
        case "serverManagement": return "server.rack"
        case "sessionManagement": return "bubble.left.and.bubble.right"
        case "workspace": return "square.grid.2x2"
        case "mainSession": return "link"
        case "restartGateway": return "arrow.clockwise"
        default: return "gearshape"
        }
    }

    /// 目录驱动导航行：图标/题自条目、去向自 route
    /// 映射（条目必有路由——sheet 三件不走本行）
    /// 唯一例外＝全部对话行（管理收口包补件）：目的
    /// 地是根级全屏页、不在本栈内（route 恒 nil），
    /// 渲动作 Button 行——行貌与 navRow 同构（图标＋
    /// 标题、行高与分隔口径同），chevron 显式补（普
    /// 通 Button 在 List 里没有系统自带的揭示箭头，
    /// 与 searchRow 同式），点按发跳出请求
    @ViewBuilder
    private func catalogNavRow(_ entry: SettingsCatalogEntry) -> some View {
        if entry.destination == .allConversations {
            Button {
                onRequestAllConversations?()
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon(iconName(for: entry))
                    Text(L10n.string(entry.title))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
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
    /// 级墨，与全 App 详情页 SectionLabel 同字阶）
    private func sectionHeader(_ title: String) -> some View {
        Text(L10n.string(title))
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
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

    /// 本页统一行盒（0.3.8 第 5 条）：纵向 insets 钉 0，
    /// 行高只由行内容 minHeight 56 决定（旧形态系统行
    /// 实测约 83＝内容＋系统纵向 insets 叠加）；横向 20
    /// 与页 gutter 对齐线一致
    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }

    /// 身份节专用行盒（0.24.0）：首节顶距＋10——用户真
    /// 机图里身份卡紧贴导航栏区、Hermes 题上沿被横切；
    /// 给第一节留出栏下呼吸位，卡与题整行恒在栏区之
    /// 下完整呈现（其余节维持统一行盒不动）
    private var identityRowInsets: EdgeInsets {
        EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20)
    }

    // MARK: - 版本派生（关于页注入，§164）

    /// Hermes 版本位：status 读到才有版本，version
    /// 字段缺失或整份 status 没读到都如实显「未知」
    /// （原版本组口径：不许拿已知生产版本冒充现读）
    private var hermesVersionText: String {
        status?.version.map { "v\($0)" }
            ?? L10n.string("未知")
    }

    /// 伴生副行：探测态未立（还没探过）显「尚未检
    /// 测」；其余形态（现读/上次读到/未检测到/暂时
    /// 读不到）全由 Core 派生态出整行
    private var companionVersionLine: String {
        guard let status = appState.companionProbe.status
        else { return L10n.string("尚未检测") }
        return status.settingsLine()
    }

    private var companionFooterNote: String? {
        appState.companionProbe.status?.footerNote()
    }


    // MARK: - 共用行组件

    private func rowIcon(_ name: String, color: Color = Palette.ink) -> some View {
        Image(systemName: name)
            // 0.24.0（用户当日指令，口径变更）：字形
            // 28→21 regular（令牌 settingsGlyphSize 同
            // 改）落 HIG 符号带 20–22、与抽屉名单字形
            // 同值；槽宽 iconSlot 28→30 且字形改槽内居
            // 中——与抽屉同几何（槽 30＋间距 12＋居中），
            // 两面图→字视觉间距自此一致；符号一律线性
            // 非 fill 变体（换符号清单见 §51）
            .font(.system(
                size: FrameworkIcon.settingsGlyphSize,
                weight: .regular
            ))
            .foregroundStyle(color)
            .frame(width: OneDayMetrics.iconSlot, alignment: .center)
            .accessibilityHidden(true)
    }

    /// 导航行（共用行组件）：图标＋题（0.24.0 起
    /// Body 17 regular，角色 rowTitleL），披露箭头由
    /// NavigationLink 系统提供。0.22.0 起行尾值位整件
    /// 撤除——值一律进各自详情页；确属状态展示不可
    /// 撤的行走下方 statusNavRow 降为题下副行
    private func navRow(
        icon: String,
        title: String,
        route: SettingsRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon)
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

    /// 状态导航行（0.22.0）：题＋题下状态副行——只给
    /// 「状态本身就是这一行的内容」的行用（网关状态
    /// 的运行中/异常）：0.7.0 定案「桥连不上要一眼看
    /// 到」靠本形态保留，不回行尾小字
    private func statusNavRow(
        icon: String,
        title: String,
        status: String,
        route: SettingsRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon)
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

    /// 深链消费：设置内路由直接落位；智能体详情类路由垫一层
    /// 列表页，返回键才有落点（沿 0.2.0 智能体格口径）
    private func consumePendingRoutes() {
        if let route = appState.pendingSettingsRoute {
            appState.pendingSettingsRoute = nil
            path = [route]
            return
        }
        guard let route = appState.pendingAgentRoute else { return }
        appState.pendingAgentRoute = nil
        switch route {
        case .serverSessionDetail:
            path = [.agent(.serverSessions), .agent(route)]
        default:
            path = [.agent(route)]
        }
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

    private func restartGateway() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.gatewayRestart(config: config)
            }
            notice = "重启指令已发送，稍等片刻在总览确认状态。"
            // 结果触感（0.3.2 纪律）：指令成功 .success
            Haptics.success()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "重启失败，请稍后再试。"
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
        }
    }
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
