import OneDayDesign
import OneDayCore
import SwiftUI

/// 设置（IA v3 §5.3，四组）：配置类中枢——服务器／模型与
/// 密钥／网关／关于。首页只到「组＋条目行＋当前值」一层，
/// 改动进二级页（深度纪律沿 v2/v3）。运维四模块不在这里，
/// 在「智能体」格（分界线见 docs/IA-V3.md §5.2）。
/// 视觉沿 v2：ScrollView＋SectionLabel＋GroupBox 一套语言。
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [SettingsRoute] = []

    @State private var status: ServerStatus?
    @State private var activeProfile: String?
    @State private var todayTokens: Double?
    @State private var showRestartConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var notice: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    serverGroup
                    modelGroup
                    gatewayGroup
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
            .onAppear { consumePendingRoute() }
            .onChange(of: appState.pendingSettingsRoute) { _, _ in
                consumePendingRoute()
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

    // MARK: - 服务器

    private var serverGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务器")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                navRow(
                    title: "当前服务器",
                    value: appState.config?.host ?? "—",
                    route: .serverDetail,
                    mono: true
                ) {
                    if let status {
                        StatusDot(color: Palette.stateColor(status.gatewayState))
                    }
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                navRow(
                    title: "档案 Profile",
                    value: activeProfile ?? "—",
                    route: .profiles
                )
                GroupDivider(inset: OneDayMetrics.spacingM)
                disconnectRow
            }
            .odGroup()
        }
    }

    private var disconnectRow: some View {
        Button(role: .destructive) {
            showDisconnectConfirm = true
        } label: {
            HStack {
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

    // MARK: - 模型与密钥

    private var modelGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("模型与密钥")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                navRow(
                    title: "对话模型",
                    value: appState.modelID == "hermes-agent" ? "服务端默认" : appState.modelID,
                    route: .models,
                    mono: true
                )
                GroupDivider(inset: OneDayMetrics.spacingM)
                navRow(title: "密钥", value: "环境变量", route: .envVars)
                GroupDivider(inset: OneDayMetrics.spacingM)
                navRow(
                    title: "用量",
                    value: todayTokens.map { "今日 \(AdminFormat.count($0)) Token" } ?? "—",
                    route: .usage
                )
            }
            .odGroup()
        }
    }

    // MARK: - 网关

    private var gatewayGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("网关")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                navRow(
                    title: "网关状态",
                    value: gatewayStateWord,
                    route: .gateway
                ) {
                    if let status {
                        StatusDot(color: Palette.stateColor(status.gatewayState))
                    }
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                Button {
                    showRestartConfirm = true
                } label: {
                    HStack {
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
                GroupDivider(inset: OneDayMetrics.spacingM)
                navRow(title: "日志", value: "agent.log", route: .logs, mono: true)
            }
            .odGroup()
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

    // MARK: - 关于

    private var aboutGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("关于")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                infoRow(label: "OneDay 版本", value: "0.2.0", mono: true)
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
            .odGroup()
        }
    }

    // MARK: - 行

    private func navRow(
        title: String,
        value: String,
        route: SettingsRoute,
        mono: Bool = false,
        @ViewBuilder leading: () -> some View = { EmptyView() }
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                leading()
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                Text(value)
                    .font(mono ? TypeScale.monoCallout : TypeScale.callout)
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
        .buttonStyle(.plain)
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

    private func consumePendingRoute() {
        guard let route = appState.pendingSettingsRoute else { return }
        appState.pendingSettingsRoute = nil
        path = [route]
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
