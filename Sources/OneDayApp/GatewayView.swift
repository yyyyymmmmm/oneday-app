import OneDayDesign
import OneDayCore
import SwiftUI

/// 网关状态页（统一原生 iOS 26 List(.insetGrouped) + Hero 摘要卡，
/// 彻底替换旧版手绘 ScrollView + .odGroup() 拼接风格）
struct GatewayView: View {
    @Environment(AppState.self) private var appState

    @State private var status: ServerStatus?
    @State private var systemStats: SystemStats?
    @State private var systemStatsAttempted = false
    @State private var errorMessage: String?
    @State private var pendingAction: String?
    @State private var notice: String?
    @State private var isActing = false

    var body: some View {
        List {
            if let status {
                let running = status.gatewayRunning == true
                    || status.gatewayState?.lowercased() == "running"
                SettingsHeroCard(
                    symbol: "network",
                    tint: running ? .blue : .orange,
                    title: "Hermes 网关",
                    subtitle: status.version.map { "服务端 v\($0)" } ?? "实时监控网关通道、资源占用与启停控制。",
                    statusText: stateWord(status),
                    statusTone: running ? .healthy : .warning
                )

                Section {
                    SettingsValueRow(
                        symbol: "tag",
                        tint: .blue,
                        title: "服务端版本",
                        value: status.version.map { "v\($0)" } ?? "—",
                        monospaced: true
                    )
                    if let date = status.releaseDate {
                        SettingsValueRow(
                            symbol: "calendar",
                            tint: .indigo,
                            title: "发布日期",
                            value: date
                        )
                    }
                    NavigationLink(value: SettingsRoute.usage) {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            IconTile(symbol: "chart.bar", color: .teal, size: OneDayMetrics.iconSlot)
                            Text("用量统计")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                } header: {
                    SettingsSectionHeader("运行概览")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Section {
                    if status.platforms.isEmpty {
                        Text("暂无平台状态")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    } else {
                        ForEach(status.platforms.keys.sorted(), id: \.self) { name in
                            if let platform = status.platforms[name] {
                                HStack(spacing: OneDayMetrics.spacingSM) {
                                    StatusDot(color: Palette.stateColor(platform.state))
                                    Text(ServerLabels.platformName(name))
                                        .font(.rowTitleL)
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text(ServerLabels.platformState(platform.state))
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Palette.stateTextColor(platform.state))
                                }
                                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader("平台连接")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Section {
                    Button {
                        pendingAction = "restart"
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            IconTile(symbol: "arrow.clockwise", color: .blue, size: OneDayMetrics.iconSlot)
                            Text("重启网关")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if isActing { ProgressView() }
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .disabled(isActing)

                    Button(role: running ? .destructive : nil) {
                        pendingAction = running ? "stop" : "start"
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            IconTile(
                                symbol: running ? "stop.fill" : "play.fill",
                                color: running ? .red : .green,
                                size: OneDayMetrics.iconSlot
                            )
                            Text(running ? "停止网关" : "启动网关")
                                .font(.rowTitleL)
                                .foregroundStyle(running ? Palette.danger : Palette.ink)
                            Spacer()
                            if isActing { ProgressView() }
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .disabled(isActing)
                } header: {
                    SettingsSectionHeader("控制")
                } footer: {
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                systemSection
            } else if let errorMessage {
                Section {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                }
                .listRowBackground(Palette.surface)
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取网关状态…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("网关状态")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(dialogButton, role: pendingAction == "stop" ? .destructive : nil) {
                if let action = pendingAction {
                    Task { await perform(action) }
                }
                pendingAction = nil
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(dialogMessage)
        }
    }

    @ViewBuilder
    private var systemSection: some View {
        Section {
            if let systemStats {
                percentRow("内存", percent: systemStats.memory?.percent, detail: memoryDetail(systemStats))
                percentRow("磁盘", percent: systemStats.disk?.percent, detail: diskDetail(systemStats))
                SettingsValueRow(
                    symbol: "cpu",
                    tint: .teal,
                    title: "CPU",
                    value: systemStats.cpuPercent.map {
                        "\(AdminFormat.count($0))% · \(systemStats.cpuCount ?? 0) 核"
                    } ?? "—"
                )
                SettingsValueRow(
                    symbol: "gauge.medium",
                    tint: .orange,
                    title: "负载",
                    value: systemStats.loadAvg.map {
                        $0.map { AdminFormat.count($0) }.joined(separator: " / ")
                    } ?? "—",
                    monospaced: true
                )
                SettingsValueRow(
                    symbol: "clock",
                    tint: .blue,
                    title: "运行时间",
                    value: systemStats.uptimeSeconds.map(uptimeText) ?? "—"
                )
                SettingsValueRow(
                    symbol: "memorychip",
                    tint: .purple,
                    title: "进程内存",
                    value: systemStats.process?.rss.map(byteText) ?? "—"
                )
                SettingsValueRow(
                    symbol: "desktopcomputer",
                    tint: .gray,
                    title: "主机",
                    value: systemStats.hostname ?? "—"
                )
                SettingsValueRow(
                    symbol: "gearshape.2",
                    tint: .secondary,
                    title: "系统",
                    value: [systemStats.os, systemStats.arch].compactMap { $0 }.joined(separator: " · ")
                )
            } else {
                Text(systemStatsAttempted ? "系统状态没读到，下拉刷新再试。" : "正在读取系统状态…")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } header: {
            SettingsSectionHeader("系统资源")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)

        Section {
            SessionStatsBlock()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func percentRow(_ label: String, percent: Double?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                Text(label)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
            }
            DataBar(fraction: (percent ?? 0) / 100, height: 6)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    private var dialogTitle: String {
        switch pendingAction {
        case "restart": return "重启网关？"
        case "stop": return "停止网关？"
        default: return "启动网关？"
        }
    }

    private var dialogButton: String {
        switch pendingAction {
        case "restart": return "重启"
        case "stop": return "停止"
        default: return "启动"
        }
    }

    private var dialogMessage: String {
        switch pendingAction {
        case "stop":
            return "停止后 Agent 将无法收发消息，直到重新启动。"
        case "restart":
            return "重启期间对话会短暂中断，进行中的任务会被打断。"
        default:
            return "启动后 Agent 恢复收发消息。"
        }
    }

    private func memoryDetail(_ stats: SystemStats) -> String {
        guard let memory = stats.memory,
              let used = memory.used, let total = memory.total else {
            return stats.memory?.percent.map { "\(AdminFormat.count($0))%" } ?? "—"
        }
        return "\(byteText(used)) / \(byteText(total))"
    }

    private func diskDetail(_ stats: SystemStats) -> String {
        guard let disk = stats.disk,
              let used = disk.used, let total = disk.total else {
            return stats.disk?.percent.map { "\(AdminFormat.count($0))%" } ?? "—"
        }
        return "\(byteText(used)) / \(byteText(total))"
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func uptimeText(_ seconds: Double) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours) 小时 \(minutes) 分"
    }

    private func stateWord(_ status: ServerStatus) -> String {
        ServerLabels.gatewayState(status.gatewayState, running: status.gatewayRunning)
    }

    private func load() async {
        guard let config = appState.config else { return }
        do {
            status = try await appState.client.status(config: config)
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "网关状态没读出来，可能是网络或服务暂时没响应"
        }
        let loadedStats = try? await appState.performAdmin({ client, config in
            try await client.systemStats(config: config)
        })
        if let loadedStats {
            systemStats = loadedStats
        }
        systemStatsAttempted = true
    }

    private func perform(_ action: String) async {
        isActing = true
        defer { isActing = false }
        do {
            switch action {
            case "restart":
                try await appState.performAdmin { client, config in
                    try await client.gatewayRestart(config: config)
                }
                notice = "重启指令已发送。"
            case "stop":
                try await appState.performAdmin { client, config in
                    try await client.gatewayStop(config: config)
                }
                notice = "停止指令已发送。"
            default:
                try await appState.performAdmin { client, config in
                    try await client.gatewayStart(config: config)
                }
                notice = "启动指令已发送。"
            }
            Haptics.success()
            try? await Task.sleep(for: .seconds(3))
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "操作失败，请稍后再试。"
            Haptics.error()
        }
    }
}
