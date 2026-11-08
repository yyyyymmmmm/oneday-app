import OneDayDesign
import OneDayCore
import SwiftUI

/// 设置（0.2.1 用户改版，仿 Muse 设置形态）：带图标的分组行
/// 目录——图标＋名称＋当前值＋右箭头、大圆角分组容器、组间
/// 留白。IA v3 的「智能体」独立格取消：运维四模块（记忆／
/// 技能／定时／服务端会话）收进本页「智能体」组，二级页沿用
/// 0.2.0 实现，功能不变、只改归属。分组：服务器与连接／
/// 智能体／模型与密钥／网关／外观／关于。
/// 首页只到条目行＋当前值一层，摘要各自独立加载、单项失败
/// 只降级该行，不整页报错。
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    serverGroup
                    agentGroup
                    modelGroup
                    gatewayGroup
                    appearanceGroup
                    aboutGroup
                    if let notice {
                        Text(notice)
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
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

    private var serverGroup: some View {
        groupBlock("服务器与连接", isFirst: true) {
            serverRow
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(
                icon: "rectangle.stack.person.crop", title: "档案 Profile",
                value: activeProfile ?? "—", route: .profiles
            )
            GroupDivider(inset: OneDayMetrics.dividerInset)
            disconnectRow
        }
    }

    /// 当前服务器行：两行式（标题＋主机名）——主机名是长标识，
    /// 单行值位在图标＋标题＋状态点＋箭头的竞争下必截断
    /// （0.2.0/0.2.1 两轮截图实证），改两行后完整可读
    private var serverRow: some View {
        Button {
            path.append(.serverDetail)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon("server.rack")
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前服务器")
                        .font(TypeScale.body)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var disconnectRow: some View {
        Button(role: .destructive) {
            showDisconnectConfirm = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon("rectangle.portrait.and.arrow.right", color: Palette.danger)
                Text("断开连接")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.danger)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var agentGroup: some View {
        groupBlock("智能体") {
            navRow(
                icon: "brain", title: "记忆",
                value: memorySummary ?? "长期记忆与提供方",
                route: .agent(.memory)
            )
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(
                icon: "puzzlepiece.extension", title: "技能",
                value: skillsSummary ?? "已装技能与开关",
                route: .agent(.skills)
            )
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(
                icon: "clock.arrow.2.circlepath", title: "定时任务",
                value: cronSummary ?? "计划任务与运行记录",
                route: .agent(.cron)
            )
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(
                icon: "bubble.left.and.text.bubble.right", title: "服务端会话",
                value: sessionsSummary ?? "服务端保存的全部会话",
                route: .agent(.serverSessions)
            )
        }
    }

    // MARK: - 模型与密钥

    private var modelGroup: some View {
        groupBlock("模型与密钥") {
            navRow(
                icon: "text.bubble", title: "对话模型",
                value: appState.defaultModel ?? (appState.modelID == "hermes-agent" ? "服务端默认" : appState.modelID),
                route: .models, mono: true
            )
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(icon: "key", title: "密钥", value: "环境变量", route: .envVars)
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(
                icon: "chart.bar", title: "用量",
                value: todayTokens.map { "今日 \(AdminFormat.count($0)) Token" } ?? "—",
                route: .usage
            )
        }
    }

    // MARK: - 网关

    private var gatewayGroup: some View {
        groupBlock("网关") {
            navRow(
                icon: "network", title: "网关状态",
                value: gatewayStateWord, route: .gateway,
                dot: status.map { Palette.stateColor($0.gatewayState) }
            )
            GroupDivider(inset: OneDayMetrics.dividerInset)
            Button {
                showRestartConfirm = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowIcon("arrow.clockwise")
                    Text("重启网关")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GroupDivider(inset: OneDayMetrics.dividerInset)
            navRow(icon: "doc.text", title: "日志", value: "agent.log", route: .logs, mono: true)
        }
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

    private var appearanceGroup: some View {
        groupBlock("外观") {
            navRow(
                icon: "paintpalette", title: "主题",
                value: AccentStore.shared.theme.displayName,
                route: .appearance
            )
        }
    }

    // MARK: - 关于

    private var aboutGroup: some View {
        groupBlock("关于") {
            infoRow(label: "OneDay 版本", value: "0.2.4", mono: true)
            GroupDivider(inset: OneDayMetrics.spacingM)
            infoRow(
                label: "服务端",
                value: status.map { "Hermes v\($0.version ?? "—")" } ?? "Hermes v0.23.0",
                mono: true
            )
            GroupDivider(inset: OneDayMetrics.spacingM)
            Link(destination: URL(string: "https://github.com/NousResearch/hermes-agent")!) {
                HStack {
                    Text("Hermes 开源项目")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            GroupDivider(inset: OneDayMetrics.spacingM)
            Text("OneDay 只与你自己的服务器通信；凭据存本机钥匙串，聊天记录存本机，服务端数据归你所有。")
                .font(TypeScale.footnote)
                .foregroundStyle(Palette.inkMuted)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingSM)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 行与分组骨架

    private func groupBlock<Content: View>(
        _ title: String, isFirst: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.top, isFirst ? 0 : 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                content()
            }
            .odGroup()
        }
    }

    private func rowIcon(_ name: String, color: Color = Palette.inkSecondary) -> some View {
        Image(systemName: name)
            .font(TypeScale.body)
            .foregroundStyle(color)
            .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
            .accessibilityHidden(true)
    }

    private enum ValueStyle {
        case callout, monoCallout, monoFootnote
    }

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
        return Button {
            path.append(route)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                rowIcon(icon)
                Text(title)
                    .font(TypeScale.body)
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
                                : TypeScale.callout
                    )
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func infoRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
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
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "重启失败，请稍后再试。"
        }
    }
}
