import OneDayDesign
import OneDayCore
import SwiftData
import SwiftUI

/// 总览（IA v3 §5.4 五段）：状态头／指标行／待办面／最近
/// 会话／快捷动作。配方依据同类样本 OpenClaw 安卓 Overview
/// （状态头＋计数指标深链＋最近会话）与 Muse 状态屏的监督
/// 职能（待办面）。配置回声（模型/提供商/工具集）已退出本页
/// ——它们在设置里。总览只看不动，唯一的写动作是快捷动作里
/// 的重启网关（二次确认）。每段独立加载：一段失败只降级
/// 该段，不整页报错。
struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var localThreads: [ChatThread]

    var onOpenAgent: (AgentRoute) -> Void = { _ in }
    var onOpenSettings: (SettingsRoute) -> Void = { _ in }
    var onOpenChat: () -> Void = {}

    @State private var status: ServerStatus?
    @State private var serverSessions: [ServerSession] = []
    @State private var sessionsLoaded = false
    @State private var cronJobs: [CronJob] = []
    @State private var todayTokens: Double?
    @State private var errorLines: [String] = []
    @State private var egressAbnormal = false
    @State private var statusError: String?
    @State private var isLoading = false
    @State private var showRestartConfirm = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let status {
                        NavigationLink {
                            StatusView(
                                onOpenSession: { onOpenAgent(.serverSessionDetail($0)) }
                            )
                        } label: {
                            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                                statusHead(status)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.inkMuted)
                                    .padding(.top, OneDayMetrics.spacingSM)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("状态详情")
                        platformsGroup(status)
                    } else if let statusError {
                        errorSection(statusError)
                    }
                    metricsGroup
                    todoGroup
                    recentGroup
                    actionsGroup
                    if let notice {
                        Text(notice)
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                    if status == nil && statusError == nil {
                        VStack(spacing: OneDayMetrics.spacingS) {
                            ProgressView()
                            Text("正在读取服务器状态…")
                                .font(TypeScale.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, OneDayMetrics.spacingXXL)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("总览")
            .refreshable { await load() }
            .task { await load() }
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

    // MARK: - 1 状态头（签名排版沿用：状态即排版，数字即读数）

    private func statusHead(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务器")
            HStack(spacing: OneDayMetrics.spacingSM) {
                StatusDot(color: Palette.stateColor(status.gatewayState))
                Text(stateWord(status))
                    .font(TypeScale.display)
                    .foregroundStyle(isAbnormal(status) ? Palette.danger : Palette.ink)
            }
            .padding(.top, OneDayMetrics.spacingS)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(appState.config?.host ?? "—")
                    .font(TypeScale.monoFootnote)
                    .foregroundStyle(Palette.inkSecondary)
                Text(versionLine(status))
                    .font(TypeScale.monoFootnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.top, OneDayMetrics.spacingSM)
        }
    }

    private func platformsGroup(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("平台连接")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if status.platforms.isEmpty {
                    Text("暂无平台状态")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                }
                ForEach(
                    Array(status.platforms.keys.sorted().enumerated()),
                    id: \.element
                ) { index, name in
                    if index > 0 {
                        GroupDivider(inset: 36)
                    }
                    if let platform = status.platforms[name] {
                        platformRow(name: name, platform: platform)
                    }
                }
            }
            .odGroup()
        }
    }

    private func platformRow(name: String, platform: ServerStatus.PlatformState) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                StatusDot(color: Palette.stateColor(platform.state))
                Text(name)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(platform.state ?? "未知")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.stateColor(platform.state))
            }
            if let message = platform.errorMessage, !message.isEmpty {
                Text(message)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.leading, OneDayMetrics.spacingM + OneDayMetrics.spacingSM)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func stateWord(_ status: ServerStatus) -> String {
        switch status.gatewayState?.lowercased() {
        case "running":
            return "运行中"
        case "stopped":
            return "已停止"
        case "error", "failed":
            return "异常"
        default:
            return status.gatewayRunning == true ? "运行中" : "未运行"
        }
    }

    private func isAbnormal(_ status: ServerStatus) -> Bool {
        switch status.gatewayState?.lowercased() {
        case "error", "failed", "disconnected", "stopped":
            return true
        default:
            return false
        }
    }

    private func versionLine(_ status: ServerStatus) -> String {
        let version = status.version.map { "v\($0)" } ?? "版本未知"
        guard let date = status.releaseDate else { return version }
        return "\(version) · 发布于 \(date)"
    }

    // MARK: - 2 指标行（单容器三列，逐项深链）

    private var activeSessionCount: Int {
        serverSessions.filter(\.isActive).count
    }

    private var enabledCronCount: Int {
        cronJobs.filter(\.enabled).count
    }

    private var nextCronRun: Date? {
        cronJobs
            .filter(\.enabled)
            .compactMap { AdminFormat.iso($0.nextRunAt) }
            .min()
    }

    private var metricsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("指标")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            HStack(spacing: 0) {
                metricCell(
                    value: sessionsLoaded ? "\(activeSessionCount)" : "—",
                    label: "活跃会话"
                ) {
                    onOpenAgent(.serverSessions)
                }
                metricDivider
                metricCell(
                    value: "\(enabledCronCount)",
                    label: nextCronRun.map { "定时 · 下次 \(AdminFormat.timeOnly($0))" } ?? "定时任务"
                ) {
                    onOpenAgent(.cron)
                }
                metricDivider
                metricCell(
                    value: todayTokens.map { AdminFormat.count($0) } ?? "—",
                    label: "今日 Token"
                ) {
                    onOpenSettings(.usage)
                }
            }
            .odGroup()
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1)
            .padding(.vertical, OneDayMetrics.spacingSM)
    }

    private func metricCell(
        value: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3 待办面（无异常不渲染，绝不占位造假）

    private var abnormalPlatforms: [(name: String, state: String)] {
        guard let status else { return [] }
        return status.platforms
            .filter { ($0.value.state ?? "").lowercased() != "connected" }
            .map { (name: $0.key, state: $0.value.state ?? "未知") }
            .sorted { $0.name < $1.name }
    }

    private var hasTodo: Bool {
        !abnormalPlatforms.isEmpty || !errorLines.isEmpty || egressAbnormal
    }

    @ViewBuilder
    private var todoGroup: some View {
        if hasTodo {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("待处理")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(Array(abnormalPlatforms.enumerated()), id: \.element.name) { index, item in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        todoRow(
                            icon: "exclamationmark.triangle",
                            text: "平台 \(item.name) 状态为 \(item.state)，可能影响消息收发。",
                            color: Palette.danger
                        )
                    }
                    if egressAbnormal {
                        if !abnormalPlatforms.isEmpty {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        todoRow(
                            icon: "exclamationmark.triangle",
                            text: "出口代理已启用但未在监听，出网流量可能受阻。",
                            color: Palette.warning
                        )
                    }
                    ForEach(Array(errorLines.enumerated()), id: \.offset) { index, line in
                        if index > 0 || !abnormalPlatforms.isEmpty || egressAbnormal {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        todoRow(
                            icon: "exclamationmark.circle",
                            text: AdminFormat.cleanLogLine(line),
                            color: Palette.danger
                        )
                    }
                }
                .odGroup()
            }
        }
    }

    private func todoRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(TypeScale.subhead)
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4 最近会话（服务端优先，无则回退本机）

    private var recentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("最近会话")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if sessionsLoaded && !serverSessions.isEmpty {
                    let recent = Array(
                        serverSessions
                            .sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
                            .prefix(5)
                    )
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        serverSessionRow(session)
                    }
                } else if !localThreads.isEmpty {
                    ForEach(Array(localThreads.prefix(3).enumerated()), id: \.element.id) { index, thread in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        localThreadRow(thread)
                    }
                } else {
                    Text("暂无会话")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }

    private func serverSessionRow(_ session: ServerSession) -> some View {
        Button {
            onOpenAgent(.serverSessionDetail(session.id))
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                if session.isActive {
                    StatusDot(color: Palette.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(recentSubtitle(session))
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recentSubtitle(_ session: ServerSession) -> String {
        var parts = [AdminFormat.short(session.startedDate)]
        if let profile = session.profile, !profile.isEmpty {
            parts.append(profile)
        }
        if let count = session.messageCount {
            parts.append("\(count) 条")
        }
        return parts.joined(separator: " · ")
    }

    private func localThreadRow(_ thread: ChatThread) -> some View {
        Button {
            onOpenChat()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("本机 · \(AdminFormat.short(thread.updatedAt))")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5 快捷动作（IA v3 定版三项）

    private var actionsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("快捷动作")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                actionRow(title: "重启网关", icon: "arrow.clockwise.circle") {
                    showRestartConfirm = true
                }
                GroupDivider(inset: 56)
                actionRow(title: "新建定时任务", icon: "plus.circle") {
                    appState.cronCreateRequested = true
                    onOpenAgent(.cron)
                }
                GroupDivider(inset: 56)
                actionRow(title: "看日志", icon: "doc.text.magnifyingglass") {
                    onOpenSettings(.logs)
                }
            }
            .odGroup()
        }
    }

    private func actionRow(
        title: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
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

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            InlineError(message)
            Button("重试") {
                Task { await load() }
            }
            .buttonStyle(.odSecondary)
        }
    }

    // MARK: - 加载（各段独立降级）

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let config = appState.config else { return }
        do {
            status = try await appState.client.status(config: config)
            statusError = nil
        } catch {
            statusError = (error as? HermesError)?.userMessage ?? "状态读取失败。"
        }
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessions(config: config, limit: 100)
        }) {
            serverSessions = page.sessions
            sessionsLoaded = true
        }
        if let jobs = try? await appState.performAdmin({ client, config in
            try await client.cronJobs(config: config)
        }) {
            cronJobs = jobs
        }
        if let usage = try? await appState.performAdmin({ client, config in
            try await client.usageAnalytics(config: config, days: 1)
        }) {
            todayTokens = usage.daily.last?.tokens ?? usage.totals.tokens
        }
        if let logs = try? await appState.performAdmin({ client, config in
            try await client.logs(config: config, level: "error", search: nil, lines: 50)
        }) {
            // 文件正序：取最后 3 条、最新在前
            errorLines = Array(logs.lines.suffix(3).reversed())
        }
        if let egress = try? await appState.performAdmin({ client, config in
            try await client.egressStatus(config: config)
        }) {
            egressAbnormal = egress.isAbnormal
        }
    }

    private func restartGateway() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.gatewayRestart(config: config)
            }
            notice = "重启指令已发送，稍等片刻下拉刷新确认状态。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "重启失败，请稍后再试。"
        }
    }
}
