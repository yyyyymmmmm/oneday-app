import OneDayDesign
import OneDayCore
import SwiftUI

/// 设置（0.2.1 用户改版，仿 Muse 设置形态；0.3.2 骨架
/// 礼记化，DESIGN-V4 §17）：原生 List(.insetGrouped)＋
/// Section＋共用行组件（学礼记 MeView 的结构纪律）——分组
/// 容器与披露箭头由系统唯一提供，不再自绘 ScrollView＋
/// odGroup＋手绘箭头；行一律走本页共用行组件（navRow/
/// infoRow/serverRow），行底走 Palette.surface 令牌。
/// 内容组织沿 0.2.1 定案不变：服务器与连接／智能体／模型
/// 与密钥／网关／外观／关于。IA v3 的「智能体」独立格已
/// 取消：运维四模块（记忆／技能／定时／服务端会话）收进
/// 本页「智能体」组，二级页沿用 0.2.0 实现。
/// 首页只到条目行＋当前值一层，摘要各自独立加载、单项
/// 失败只降级该行，不整页报错。
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [SettingsRoute] = []

    @State private var status: ServerStatus?
    @State private var activeProfile: String?
    @State private var todayTokens: Double?
    @State private var memorySummary: String?
    @State private var skillsSummary: String?
    @State private var cronSummary: String?
    @State private var sessionsSummary: String?
    @State private var showRestartConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var notice: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                serverSection
                agentSection
                modelSection
                gatewaySection
                appearanceSection
                aboutSection
                if let notice {
                    Section {
                        Text(notice)
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            // 0.3.3 组距放大（学礼记 MeView 的组间留白）：
            // 系统默认组距偏挤，按 spacingL 令牌拉开
            .listSectionSpacing(OneDayMetrics.spacingL)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG)
            .navigationTitle("设置")
            .task { await loadSummaries() }
            .onAppear { consumePendingRoutes() }
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
        }
    }

    // MARK: - 服务器与连接

    private var serverSection: some View {
        Section {
            serverRow
            navRow(
                icon: "rectangle.stack.person.crop", title: "档案 Profile",
                value: activeProfile ?? "—", route: .profiles
            )
            disconnectRow
        } header: {
            SectionLabel("服务器与连接")
        }
        .listRowBackground(Palette.surface)
    }

    /// 当前服务器行：两行式（标题＋主机名）——主机名是长标识，
    /// 单行值位在图标＋标题＋状态点＋箭头的竞争下必截断
    /// （0.2.0/0.2.1 两轮截图实证），改两行后完整可读。
    /// 0.3.2：改 NavigationLink，披露箭头由系统提供
    private var serverRow: some View {
        NavigationLink(value: SettingsRoute.serverDetail) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon("server.rack")
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前服务器")
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(Palette.ink)
                    Text(appState.config?.host ?? "—")
                        .font(TypeScale.monoFootnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if let status {
                    StatusDot(color: Palette.stateColor(status.gatewayState))
                }
            }
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
    }

    private var disconnectRow: some View {
        Button(role: .destructive) {
            showDisconnectConfirm = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon("rectangle.portrait.and.arrow.right", color: Palette.danger)
                Text("断开连接")
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(Palette.danger)
                Spacer()
            }
            .frame(minHeight: OneDayMetrics.rowHeight)
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
            navRow(
                icon: "brain", title: "记忆",
                value: memorySummary ?? "长期记忆与提供方",
                route: .agent(.memory)
            )
            navRow(
                icon: "puzzlepiece.extension", title: "技能",
                value: skillsSummary ?? "已装技能与开关",
                route: .agent(.skills)
            )
            navRow(
                icon: "clock.arrow.2.circlepath", title: "定时任务",
                value: cronSummary ?? "计划任务与运行记录",
                route: .agent(.cron)
            )
            navRow(
                icon: "bubble.left.and.text.bubble.right", title: "服务端会话",
                value: sessionsSummary ?? "服务端保存的全部会话",
                route: .agent(.serverSessions)
            )
        } header: {
            SectionLabel("智能体")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - 模型与密钥

    private var modelSection: some View {
        Section {
            navRow(
                icon: "text.bubble", title: "对话模型",
                value: appState.defaultModel ?? (appState.modelID == "hermes-agent" ? "服务端默认" : appState.modelID),
                route: .models, mono: true
            )
            navRow(icon: "key", title: "密钥", value: "环境变量", route: .envVars)
            navRow(
                icon: "chart.bar", title: "用量",
                value: todayTokens.map { "今日 \(AdminFormat.count($0)) Token" } ?? "—",
                route: .usage
            )
        } header: {
            SectionLabel("模型与密钥")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - 网关

    private var gatewaySection: some View {
        Section {
            navRow(
                icon: "network", title: "网关状态",
                value: gatewayStateWord, route: .gateway,
                dot: status.map { Palette.stateColor($0.gatewayState) }
            )
            Button {
                showRestartConfirm = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("arrow.clockwise")
                    Text("重启网关")
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            navRow(icon: "doc.text", title: "日志", value: "agent.log", route: .logs, mono: true)
        } header: {
            SectionLabel("网关")
        }
        .listRowBackground(Palette.surface)
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
            navRow(
                icon: "paintpalette", title: "主题",
                value: AccentStore.shared.theme.displayName,
                route: .appearance
            )
        } header: {
            SectionLabel("外观")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            infoRow(label: "OneDay 版本", value: "0.3.3", mono: true)
            infoRow(
                label: "服务端",
                value: status.map { "Hermes v\($0.version ?? "—")" } ?? "Hermes v0.23.0",
                mono: true
            )
            Link(destination: URL(string: "https://github.com/NousResearch/hermes-agent")!) {
                HStack {
                    Text("Hermes 开源项目")
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            // LORD Icon 署名（0.3.0，用户拍板免费层不买
            // PRO——免费层授权为 CC BY-ND 变体、必须署名，
            // 见 animated-icons 技能）：图标动效开始接入
            // 前署名先落位；上架时商店描述同步加同句
            Link(destination: URL(string: "https://lordicon.com")!) {
                HStack {
                    Text("Icons by Lordicon")
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            Text("OneDay 只与你自己的服务器通信；凭据存本机钥匙串，聊天记录存本机，服务端数据归你所有。")
                .font(TypeScale.footnote)
                .foregroundStyle(Palette.inkMuted)
                .padding(.vertical, OneDayMetrics.spacingXS)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            SectionLabel("关于")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - 共用行组件

    private func rowIcon(_ name: String, color: Color = Palette.inkSecondary) -> some View {
        Image(systemName: name)
            // 0.3.3：行图标走 rowIcon 角色（20 semibold
            // 粗实字形，学礼记行分量；此前 body 细线显单薄）
            .font(TypeScale.rowIcon)
            .foregroundStyle(color)
            .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
            // 条 5（§14）：同行图标走光学偏移（0.3.0 只落
            // ContentRow，本页行于 0.3.2 补齐）
            .iconOpticalOffset()
            .accessibilityHidden(true)
    }

    private enum ValueStyle {
        case callout, monoCallout, monoFootnote
    }

    /// 导航行（共用行组件）：图标＋标题＋当前值，披露箭头
    /// 由 NavigationLink 系统提供，本组件不自绘。值位读数
    /// 走等宽数字＋numericText 过渡（条 5/6 补落点，0.3.2）
    private func navRow(
        icon: String,
        title: String,
        value: String,
        route: SettingsRoute,
        mono: Bool = false,
        valueStyle: ValueStyle? = nil,
        dot: Color? = nil
    ) -> some View {
        let resolvedStyle = valueStyle ?? (mono ? .monoCallout : .callout)
        return NavigationLink(value: route) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon)
                Text(title)
                    // 0.3.3 行层级：标题唯一半粗（rowTitle
                    // 角色）；值 regular＋inkSecondary 退后
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                if let dot {
                    StatusDot(color: dot)
                }
                Text(value)
                    .font(
                        resolvedStyle == .monoFootnote
                            ? TypeScale.monoFootnote
                            : resolvedStyle == .monoCallout
                                ? TypeScale.monoCallout
                                : TypeScale.rowValue
                    )
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .tabularDigits()
                    .contentTransition(.numericText())
            }
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
    }

    private func infoRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.rowTitle)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.rowValue)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

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

    private func loadSummaries() async {
        if let config = appState.config,
           let loaded = try? await appState.client.status(config: config) {
            status = loaded
        }
        if let name = try? await appState.performAdmin({ client, config in
            try await client.activeProfileName(config: config)
        }) {
            activeProfile = name
        }
        if let usage = try? await appState.performAdmin({ client, config in
            try await client.usageAnalytics(config: config, days: 1)
        }) {
            todayTokens = usage.daily.last?.tokens ?? usage.totals.tokens
        }
        if let memory = try? await appState.performAdmin({ client, config in
            try await client.memoryStatus(config: config)
        }) {
            let active = memory.active?.isEmpty == false ? memory.active! : "内置记忆"
            memorySummary = "当前提供方 \(active)"
        }
        if let skills = try? await appState.performAdmin({ client, config in
            try await client.skills(config: config)
        }) {
            let enabled = skills.filter(\.isEnabled).count
            skillsSummary = "已装 \(skills.count) 个 · 启用 \(enabled) 个"
        }
        if let jobs = try? await appState.performAdmin({ client, config in
            try await client.cronJobs(config: config)
        }) {
            let enabled = jobs.filter(\.enabled)
            let next = enabled
                .compactMap { AdminFormat.iso($0.nextRunAt) }
                .min()
            if let next {
                cronSummary = "启用 \(enabled.count) 个 · 下次 \(AdminFormat.timeOnly(next))"
            } else {
                cronSummary = "启用 \(enabled.count) 个"
            }
        }
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessions(config: config, limit: 1)
        }) {
            sessionsSummary = "共 \(page.total ?? page.sessions.count) 条"
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
            Haptics.warning()
        }
    }
}
