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

    private enum ManageSheet: String, Identifiable {
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
                    connectionSection
                    workspaceSection
                    appSection
                    supportSection
                    disconnectSection
                    versionFooter
                }
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
                }
            }
            .confirmationDialog(
                "重启网关？",
                isPresented: $showRestartConfirm,
                titleVisibility: .visible
            ) {
                Button("重启", role: .destructive) {
                    Task { await restartGateway() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("重启期间对话会短暂中断，进行中的任务会被打断。")
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
                        .frame(width: 44, height: 44)
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

    // MARK: - 智能体组（§164）

    /// 智能体组：配置档案（原服务器组「档案」行迁入改
    /// 名——档案决定人设与系统提示、属智能体侧，原型
    /// 与三层命名口径一致）／记忆／技能／模型与服务商
    /// （原「服务端默认模型」行改名随模型页现名）／定
    /// 时任务／服务端会话——六行全由目录清单驱动
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

    // MARK: - 连接组（§164）

    /// 连接组：当前服务器（特型两行行）＋主线会话状态
    /// （原服务器组状态行随迁）／连接器／设备与权限／
    /// 网关状态（特型状态行）＋重启网关（原网关组动作
    /// 行随迁）／日志／密钥／用量（原模型组两行按服务
    /// 器侧语义归入本组）
    private var connectionSection: some View {
        Section {
            serverRow
            // 0.27.0：主线会话链接状态如实展示——已链
            // 接显会话 id、未链接显最近一次链接失败的
            // 错误原文（链接失败不许再静默，见串话热
            // 修）；非导航行（无详情页可去），形态与
            // statusNavRow 同（题＋状态副行）
            statusInfoRow(
                icon: "link", title: "主线会话",
                status: mainSessionStatusText
            )
            catalogNavRow(entry(id: "connectors"))
            catalogNavRow(entry(id: "devicePermissions"))
            // 网关状态行的内容就是状态本身（运行中/异
            // 常）——状态副行形态（0.3.8 的撤点口径不
            // 变：状态点仍只留身份卡一处）
            statusNavRow(
                icon: "network", title: "网关状态",
                status: gatewayStateWord, route: .gateway
            )
            Button {
                showRestartConfirm = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("arrow.clockwise")
                    Text("重启网关")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .settingsSeparatorToIconEdge()
            catalogNavRow(entry(id: "logs"))
            catalogNavRow(entry(id: "envVars"))
            catalogNavRow(entry(id: "usage"))
        } header: {
            sectionHeader("连接")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 工作区组（原管理组，§164 改名）

    /// 工作区组：原底栏「应用」格的三件整面工作区
    /// （总览/电脑/服务器文件，迁移表见 §47）；行形态
    /// 与本页导航行同规格（21 图标＋17 题＋chevron），
    /// 点按走 sheet 呈现（各页自带导航栈，不套本页栈）
    private var workspaceSection: some View {
        Section {
            manageRow(icon: "chart.xyaxis.line", title: "总览") {
                manageSheet = .overview
            }
            // 电脑图标 display（空屏线性同义符号，
            // 0.24.0 定）
            manageRow(icon: "display", title: "电脑") {
                manageSheet = .computer
            }
            manageRow(icon: "folder", title: "服务器文件") {
                manageSheet = .serverFiles
            }
        } header: {
            sectionHeader("工作区")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private func manageRow(
        icon: String, title: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon)
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    // 0.22.0 小字清查：本页字形下限随文
                    // 字档对齐 15（chevron 是字形非文字，
                    // 同步升档保同页一致）
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
                // 0.36.0（宪法 §5／审计 C9 同族）：撤
                // 居中标题与手写关闭——文件列表内容领
                // 头、关闭走系统下拉手势
            }
        }
    }

    // MARK: - 应用组与支持组（§164）

    /// 应用组：外观一行（页内含聊天主题/形象大小/模
    /// 式/语言四件，原型外观页四项现行全有）；原型
    /// 「通知」开关行不建——全仓无被控对象（伴生通知
    /// 是 App 内记录、无总开关、推送未通），不许假开
    /// 关，降级登记见 §164.4
    private var appSection: some View {
        Section {
            ForEach(SettingsCatalog.browseEntries(in: .app)) { entry in
                catalogNavRow(entry)
            }
        } header: {
            sectionHeader("应用")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

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

    /// 搜索点达分发：管理三件开 sheet、余者压设置栈
    /// （与深链消费同一落点口径）
    private func activate(_ entry: SettingsCatalogEntry) {
        switch entry.destination {
        case .overview: manageSheet = .overview
        case .computer: manageSheet = .computer
        case .serverFiles: manageSheet = .serverFiles
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
        case .gateway: return .gateway
        case .logs: return .logs
        case .appearance: return .appearance
        case .help: return .help
        case .about: return .about
        case .privacy: return .privacy
        case .terms: return .terms
        case .overview, .computer, .serverFiles: return nil
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
        case "gateway": return "network"
        case "logs": return "doc.text"
        case "envVars": return "key"
        case "usage": return "chart.bar"
        case "overview": return "chart.xyaxis.line"
        case "computer": return "display"
        case "serverFiles": return "folder"
        case "appearance": return "sun.max"
        case "help": return "questionmark.circle"
        case "about": return "info.circle"
        case "privacy": return "lock.shield"
        case "terms": return "doc.text"
        default: return "gearshape"
        }
    }

    /// 目录驱动导航行：图标/题自条目、去向自 route
    /// 映射（条目必有路由——sheet 三件不走本行）
    @ViewBuilder
    private func catalogNavRow(_ entry: SettingsCatalogEntry) -> some View {
        if let route = route(for: entry.destination) {
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

    /// 版本居中小灰字行（0.20.0，照 Muse 设置图页脚
    /// 「Muse vX.Y.Z」形态）：无卡底、居中、15 灰；
    /// 字面走 OneDayVersionLabel 单源（与关于页 hero
    /// 同值，版本源第五处收敛于该常量）
    private var versionFooter: some View {
        Section {
            Text(OneDayVersionLabel.full)

                .font(.meta)
                // 0.22.0：版本行是要读的字——inkMuted
                // （2.75:1）换 inkSecondary（审计 G1）
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - 服务器行与断开连接

    /// 当前服务器行：两行式（标题＋主机名）——主机名是长标识，
    /// 单行值位在图标＋标题＋状态点＋箭头的竞争下必截断
    /// （0.2.0/0.2.1 两轮截图实证），改两行后完整可读。
    /// 0.3.2：改 NavigationLink，披露箭头由系统提供
    private var serverRow: some View {
        NavigationLink(value: SettingsRoute.serverDetail) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon("server.rack")
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("当前服务器")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(appState.config?.host ?? "—")
                        .font(.metaMonospaced)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                // 0.3.8 第 9/12 条：状态点撤下——右侧只留系
                // 统披露箭头一件（旧形态绿点＋箭头双元素、
                // 且绿点与身份卡那颗同屏重复）；连接状态
                // 只在身份卡留一处（点＋Hermes 名同行）
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .settingsSeparatorToIconEdge()
    }

    /// 断开连接独立成组（0.3.8 第 8 条）：破坏性操作不
    /// 混连接卡——单独一节（红字只在本组内，不与正常
    /// 连接行同卡相邻）；§164 保留原位（页脚之前）
    private var disconnectSection: some View {
        Section {
            disconnectRow
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private var disconnectRow: some View {
        Button(role: .destructive) {
            showDisconnectConfirm = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                // 0.20.0（照 Muse 设置图「Log out」行）：
                // 红字行不带图标——独立卡内只有一行红字
                Text("断开连接")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.danger)
                Spacer()
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
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

    private var gatewayStateWord: String {
        switch status?.gatewayState?.lowercased() {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return status == nil ? "—" : "未知"
        }
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

    /// 状态信息行（0.27.0）：statusNavRow 的非导航
    /// 版——状态本身就是全部内容、没有详情页可去的
    /// 行用（主线会话链接状态）；形态逐字同状态导
    /// 航行，只去掉 NavigationLink 与 chevron
    private func statusInfoRow(
        icon: String,
        title: String,
        status: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            rowIcon(icon)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(status)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
        .settingsSeparatorToIconEdge()
    }

    /// 主线会话状态文案（0.27.0）：已链接（确认＋
    /// 种子双位）显 id；有失败留痕显「未链接＋错误
    /// 原文」；其余显未链接与自动链接的去向
    private var mainSessionStatusText: String {
        let store = appState.sideChats
        if store.mainServerConfirmed, store.mainServerSeeded,
           let id = store.mainServerSessionID {
            return "已链接 · \(id)"
        }
        if let error = store.mainLinkLastError {
            return "未链接 · \(error)"
        }
        return "未链接（打开聊天页或发送时自动链接）"
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
