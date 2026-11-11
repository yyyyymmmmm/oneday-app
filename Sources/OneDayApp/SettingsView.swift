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
/// 内容组织沿 0.2.1 定案不变：服务器与连接／智能体／模型
/// 与密钥／网关／外观／关于。IA v3 的「智能体」独立格已
/// 取消：运维四模块（记忆／技能／定时／服务端会话）收进
/// 本页「智能体」组，二级页沿用 0.2.0 实现。
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
    /// 「管理」组三页的 sheet 呈现（总览/电脑自带导航
    /// 栈、服务器文件由本页包一层栈）：不进本页导航栈
    /// ——三页都是整面工作区、且各自带栈，套栈必乱；
    /// sheet 呈现与 Muse 设置里连接器/设备行打开整
    /// 面页的形态一致
    @State private var manageSheet: ManageSheet?

    private enum ManageSheet: String, Identifiable {
        case overview, computer, serverFiles
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var path: [SettingsRoute] = []
    /// 服务器状态：只剩两处消费者——身份卡状态点与
    /// 网关状态副行（0.22.0 值位撤除后，各行摘要状态
    /// 与其加载一并退役，见 loadSummaries）
    @State private var status: ServerStatus?
    @State private var showRestartConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var notice: String?
    var body: some View {
        NavigationStack(path: $path) {
            List {
                identitySection
                manageSection
                agentSection
                modelSection
                gatewaySection
                appearanceSection
                serverSection
                versionSection
                aboutSection
                disconnectSection
                versionFooter
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

    // MARK: - 顶部身份头（0.3.4，借 aheze/Setting 的
    // profile header 模式、只借模式不引库）：一行说清
    // 连的是谁——Hermes 名称＋网关状态点，副行＝当前
    // 服务器 host · 当前模型。静态信息行（不挂导航，
    // 详情入口在下方服务器组，避免两个箭头指同一页）

    private var identitySection: some View {
        Section {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        // 0.36.22：身份头名收敛档案出口
                        Text(appState.agentDisplayName)
                            // 0.22.0（设置图实测规格）：行题
                            // 统一 20 regular 单一字重——参考
                            // 图账户卡题即 regular，强调只靠
                            // 位置不靠加粗；0.20.0 的 semibold
                            // 让位。0.24.0：随角色改 Body 17
                            // regular（HIG 落档，见 §51）；身
                            // 份名 bold 配额只给抽屉名字头，
                            // 本卡是列表行、从行题口径
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
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
            .settingsSeparatorToIconEdge()
        }
        .listRowBackground(Palette.surface)
        // 0.24.0：身份节走专用行盒（顶距＋10 防栏区横
        // 切，见 identityRowInsets）
        .listRowInsets(identityRowInsets)
    }

    // MARK: - 管理（0.20.0 新增：原应用格入口的新家）

    /// 管理组：原底栏「应用」格的三件整面工作区（总
    /// 览/电脑/服务器文件）迁入本组（迁移表见 §47）；
    /// 行形态与本页导航行同规格（0.24.0：21 图标＋
    /// 17 题＋chevron），点按走 sheet 呈现（各页自带
    /// 导航栈，不套本页栈）
    private var manageSection: some View {
        Section {
            manageRow(icon: "chart.xyaxis.line", title: "总览") {
                manageSheet = .overview
            }
            // 0.24.0：电脑图标 desktopcomputer（屏幕实
            // 心字形）→display（空屏线性同义符号）
            manageRow(icon: "display", title: "电脑") {
                manageSheet = .computer
            }
            manageRow(icon: "folder", title: "服务器文件") {
                manageSheet = .serverFiles
            }
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

    /// 版本居中小灰字行（0.20.0，照 Muse 设置图页脚
    /// 「Muse vX.Y.Z」形态）：无卡底、居中、15 灰；
    /// 本行字面即版本源第五处（与 Project.swift 四处
    /// 同改同验）
    private var versionFooter: some View {
        Section {
            Text("OneDay v0.49.3")
                .font(.meta)
                // 0.22.0：版本行是要读的字——inkMuted
                // （2.75:1）换 inkSecondary（审计 G1）
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - 服务器与连接

    private var serverSection: some View {
        Section {
            serverRow
            // 0.22.0：档案行值位（档案名）撤除——档案页
            // 本身即其详情（0.3.8 的 ServerLabels 翻译在
            // 档案页内仍用）
            // 0.24.0：档案图标 rectangle.stack.person.
            // crop（人像剪影填充）→archivebox（线性档
            // 案盒，同义且疏）
            navRow(
                icon: "archivebox", title: "档案",
                route: .profiles
            )
            // 0.33.1：「桥钥匙」行整行退役（用户 16:08
            // 定版：只持一把 Hermes 登录密钥、桥分权纯
            // 服务器内部）——桥鉴权与登录同钥，桥连不
            // 上即登录面问题、不再单设钥匙行与状态文案
            // 0.27.0：主线会话链接状态如实展示——已链
            // 接显会话 id、未链接显最近一次链接失败的
            // 错误原文（链接失败不许再静默，见串话热
            // 修）；非导航行（无详情页可去），形态与
            // statusNavRow 同（题＋状态副行）
            statusInfoRow(
                icon: "link", title: "主线会话",
                status: mainSessionStatusText
            )
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    /// 断开连接独立成组（0.3.8 第 8 条）：破坏性操作不
    /// 混连接卡——从服务器组拆出、单独一节（红字红图标
    /// 只在本组内，不与正常连接行同卡相邻）
    private var disconnectSection: some View {
        Section {
            disconnectRow
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
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
                        // 0.22.0：题随全页统一 20 regular
                        // （0.20.0 的半粗让位）；副 15 沿旧
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

    private var disconnectRow: some View {
        Button(role: .destructive) {
            showDisconnectConfirm = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                // 0.20.0（照 Muse 设置图「Log out」行）：
                // 红字行不带图标——独立卡内只有一行红字
                // （20pt）；0.3.8 的红图标同行形态让位
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

    // MARK: - 智能体（运维四模块，原「智能体」格并入）

    private var agentSection: some View {
        Section {
            // 0.22.0：五行值位（计数摘要）全撤——计数在
            // 各自详情页（记忆文件数/技能总数/启用数/会
            // 话总数/MCP 总数），本页只留题＋chevron
            // 0.24.0：记忆图标 brain（密实填充）→
            // memorychip（线性芯片，同义且疏，取舍
            // 登记 §51）
            navRow(
                icon: "memorychip", title: "记忆",
                route: .agent(.memory)
            )
            navRow(
                icon: "puzzlepiece.extension", title: "技能",
                route: .agent(.skills)
            )
            navRow(
                icon: "clock.arrow.2.circlepath", title: "定时任务",
                route: .agent(.cron)
            )
            // 0.24.0：服务端会话图标 bubble.left.and.
            // text.bubble.right 是双泡宽字形——28pt 时
            // 自然宽溢出 28 槽、压住行题（0.23.0 真机
            // 图实证）；换单泡窄符号 bubble.left，槽
            // 内宽恒小于槽宽、构造上不重叠
            navRow(
                icon: "bubble.left", title: "服务端会话",
                route: .agent(.serverSessions)
            )
            // 0.28.0：原「MCP 连接」升级为连接器目录
            // 页（已连接实查＋可连接目录），行题随改
            navRow(
                icon: "cable.connector", title: "连接器",
                route: .agent(.mcp)
            )
            // 0.34.0：本机连接器批一——五件数据源的授
            // 权与调用开关总览（与连接器同组、紧随其后）
            navRow(
                icon: "iphone", title: "设备与权限",
                route: .agent(.devicePermissions)
            )
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 模型与密钥

    private var modelSection: some View {
        Section {
            // 0.4.0（审计 §3.3 #3）：「服务端默认模型」
            // 命名沿用——本行管理的是服务端默认，与聊天
            // 页胶囊的本机逐请求模型是两回事
            // 0.22.0：三行值位全撤（默认模型名在模型页、
            // 用量读数在用量页、「环境变量」本就只是描
            // 述词不是值）
            navRow(
                icon: "text.bubble", title: "服务端默认模型",
                route: .models
            )
            navRow(icon: "key", title: "密钥", route: .envVars)
            navRow(
                icon: "chart.bar", title: "用量",
                route: .usage
            )
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 网关

    private var gatewaySection: some View {
        Section {
            // 网关状态行的内容就是状态本身（运行中/异
            // 常）——0.22.0 改状态副行形态（0.3.8 的撤点
            // 口径不变：状态点仍只留身份卡一处）
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
                        // 0.22.0：题随全页统一 20 regular
                        // （旧 .body 17 让位）
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .settingsSeparatorToIconEdge()
            // 0.22.0：日志行值位（agent.log）撤除，进日
            // 志页即其详情
            navRow(icon: "doc.text", title: "日志", route: .logs)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private var gatewayStateWord: String {
        switch status?.gatewayState?.lowercased() {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return status == nil ? "—" : "未知"
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            // 0.4.0（§1.1）：主题体系废止，本行是「外
            // 观」（三档系统外观）；0.22.0 值位（当前档
            // 名）撤除——外观页内的勾选即其详情
            // 0.24.0：外观图标 circle.lefthalf.filled
            // （半实心）→sun.max（线性，与同列细线一
            // 致；明暗双态语义弱化为亮度语义，取舍登
            // 记 §51）
            navRow(
                icon: "sun.max", title: "外观",
                route: .appearance
            )
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 版本（本包，DESIGN §110）

    /// 版本组（服务端收口形态定版的「版本对齐两行」
    /// 落点）：Hermes 本体版本一行（真源＝/api/status
    /// 的 version，loadSummaries 既有读数；读不到如
    /// 实显「未知」——本组立项时一并废除关于组旧行
    /// 在 status 缺失时写死 "Hermes v0.23.0" 的兜底，
    /// 那是拿已知生产版本冒充现读）＋伴生一行（版
    /// 本＋状态副行，派生全在 Core CompanionStatus）。
    /// 伴生缺失/需升级 App 时组脚注给一句可行动的
    /// 人话；不弹警告、不阻断任何功能
    private var versionSection: some View {
        Section {
            LabeledContent("Hermes") {
                Text(hermesVersionText)
                    .font(.system(.callout, design: .monospaced))
            }
            .settingsSeparatorToIconEdge()
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("伴生服务")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(companionVersionLine)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
            .settingsSeparatorToIconEdge()
        } footer: {
            if let note = companionFooterNote {
                Text(note)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    /// Hermes 版本位：status 读到才有版本，version
    /// 字段缺失或整份 status 没读到都如实显「未知」
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

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            // （OneDay 版本行 0.20.0 移出本组：版本号改
            // 页脚居中小灰字行 versionFooter，照 Muse
            // 设置图页脚形态；版本源第五处随之移位）
            // （服务端版本行本包移出本组：升入上方版本
            // 组与伴生行成对，见 versionSection）
            Link(destination: URL(string: "https://github.com/NousResearch/hermes-agent")!) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Color.clear
                        .frame(width: OneDayMetrics.iconSlot)
                        .accessibilityHidden(true)
                    Text("Hermes 开源项目")
                        // 0.22.0：题随全页统一 20 regular、
                        // 外链字形 13→15（小字清查下限）
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .settingsSeparatorToIconEdge()
            // LORD Icon 署名（0.3.0，用户拍板免费层不买
            // PRO——免费层授权为 CC BY-ND 变体、必须署名，
            // 见 animated-icons 技能）：图标动效开始接入
            // 前署名先落位；上架时商店描述同步加同句
            Link(destination: URL(string: "https://lordicon.com")!) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Color.clear
                        .frame(width: OneDayMetrics.iconSlot)
                        .accessibilityHidden(true)
                    Text("Icons by Lordicon")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .settingsSeparatorToIconEdge()
        } footer: {
            // 0.3.4：隐私说明移组脚注（不再占行）
            // 0.22.0：脚注是阅读文字——13 footnote＋
            // inkMuted（2.75:1）升 15＋inkSecondary（小
            // 字清查＋审计 G1）
            Text("OneDay 只与你自己的服务器通信；凭据存本机钥匙串，聊天记录存本机，服务端数据归你所有。")
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    // MARK: - 共用行组件

    private func rowIcon(_ name: String, color: Color = Palette.ink) -> some View {
        Image(systemName: name)
            // 0.22.0 规格（用户 00:30 设置图实测量）：行
            // 图标约 28–30 细线字形——24→28 regular＋主
            // 墨色（槽宽 iconSlot 28 不变、对齐线不漂；
            // 字形密度由 RenderMeasureTests 在 28pt 复
            // 量把守）；0.20.0 的 24 让位
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
            // 条 5（§14）：同行图标走光学偏移（0.3.0 只落
            // ContentRow，本页行于 0.3.2 补齐）
            .accessibilityHidden(true)
    }

    // （settingsHeader 已于 0.36.3 退役：分组小标题
    // 随用户 18:25 点名整批撤除，分组靠卡片与间距）

    /// 导航行（共用行组件）：图标＋题（0.24.0 起
    /// Body 17 regular，角色 rowTitleL），披露箭头由
    /// NavigationLink 系统提供。
    /// 0.22.0（设置图实测规格）：**行尾值位整件撤除**
    /// ——参考图所有导航行只有题＋chevron，值一律进各
    /// 自详情页（档案名/计数摘要/模型名/用量读数同
    /// 此）；确属状态展示不可撤的行（网关状态；桥钥匙
    /// 行已于 0.33.1 随整节退役）走下方 statusNavRow
    /// 降为题下副行。
    /// 旧值位组件（ValueStyle/等宽读数/numericText 过
    /// 渡）随撤除退役
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

    /// 状态导航行（0.22.0）：题＋题下状态副行（15
    /// inkSecondary，对参考图账户卡副行档）——只给
    /// 「状态本身就是这一行的内容」的行用（审批桥钥
    /// 匙的已设置/桥未连接、网关状态的运行中/异常）：
    /// 0.7.0 定案「桥连不上要一眼看到」靠本形态保
    /// 留，不回行尾小字
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
    /// 航行（题＋题下状态副行），只去掉 Navigation-
    /// Link 与 chevron
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
    /// 据依赖（身份卡状态点＋网关状态副行）；旧形态为
    /// 各行摘要并行发 7 个管理请求（档案/用量/记忆/
    /// 技能/定时/会话/MCP）只为行尾小字——随值位一
    /// 并退役，打开设置页的请求面回到 1 个
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
