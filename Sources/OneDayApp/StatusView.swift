import OneDayCore
import OneDayDesign
import SwiftUI

/// 「状态」屏（0.2.1 新增，仿 Muse 头像/状态屏）：入口在总览
/// 状态头。顶部智能体身份（名＋当前状态一句话），下分三段：
/// 活动（最近会话＋近期日志事件流）／定时（接下来运行列表，
/// 只读，与设置里的管理页同源）／系统（资源与版本，来自
/// /api/system/stats ＋ /api/status）。
/// 浏览器任务与审核记录两格：openapi 335 路径中无浏览器任务
/// 列表接口，「审核」只有 git 代码审查与安全审计触发端点、
/// 无记录列表接口——两格不做，不用假数据填充（施工前核查
/// 结论，见 0.2.1 汇报）。
struct StatusView: View {
    @Environment(AppState.self) private var appState
    var onOpenSession: (String) -> Void = { _ in }

    @State private var segment = 0
    @State private var status: ServerStatus?
    @State private var sessions: [ServerSession] = []
    @State private var logLines: [String] = []
    @State private var cronJobs: [CronJob] = []
    @State private var stats: SystemStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityHead
                Picker("状态分段", selection: $segment) {
                    Text("活动").tag(0)
                    Text("定时").tag(1)
                    Text("系统").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.top, OneDayMetrics.spacingL)
                switch segment {
                case 0: activitySection
                case 1: cronSection
                default: systemSection
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("状态")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 身份头

    private var identityHead: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text("Hermes")
                    .font(TypeScale.title)
                    .foregroundStyle(Palette.ink)
                StatusDot(color: status.map { Palette.stateColor($0.gatewayState) }
                    ?? Palette.inkMuted)
            }
            Text(statusLine)
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkSecondary)
            Text(appState.config?.host ?? "—")
                .font(TypeScale.monoFootnote)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private var statusLine: String {
        let word: String
        switch status?.gatewayState?.lowercased() {
        case "running": word = "运行中"
        case "stopped": word = "已停止"
        case "error", "failed": word = "异常"
        default: word = status == nil ? "状态读取中" : "未知状态"
        }
        let model = appState.modelID == "hermes-agent" ? "服务端默认模型" : appState.modelID
        return "\(word) · \(model)"
    }

    // MARK: - 活动

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("最近会话")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            if sessions.isEmpty {
                Text("暂无服务端会话")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        Button {
                            onOpenSession(session.id)
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                StatusDot(color: session.isActive
                                    ? Palette.success : Palette.inkMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(TypeScale.body)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text("\(AdminFormat.short(session.startedDate)) · \(session.messageCount ?? 0) 条")
                                        .font(TypeScale.footnote)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer(minLength: OneDayMetrics.spacingS)
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
                }
                .odGroup()
            }
            SectionLabel("近期事件")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            if logLines.isEmpty {
                Text("暂无日志")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(AdminFormat.cleanLogLine(line))
                            .font(TypeScale.monoCaption)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .odGroup()
            }
        }
    }

    // MARK: - 定时（只读）

    private var cronSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("接下来运行")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            if cronJobs.isEmpty {
                Text("暂无定时任务")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingJobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title)
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(job.scheduleText)
                                    .font(TypeScale.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            Text(jobNextText(job))
                                .font(TypeScale.monoCallout)
                                .foregroundStyle(job.enabled
                                    ? Palette.inkSecondary : Palette.inkMuted)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                    }
                }
                .odGroup()
            }
            Text("只读展示；新建、暂停与触发在「设置 · 智能体 · 定时任务」里。")
                .font(TypeScale.footnote)
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, OneDayMetrics.spacingM)
        }
    }

    /// 启用任务按 next_run 在前，暂停的垫底
    private var upcomingJobs: [CronJob] {
        cronJobs.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled }
            let l = AdminFormat.iso(lhs.nextRunAt) ?? .distantFuture
            let r = AdminFormat.iso(rhs.nextRunAt) ?? .distantFuture
            return l < r
        }
    }

    private func jobNextText(_ job: CronJob) -> String {
        guard job.enabled else { return "已暂停" }
        guard let next = AdminFormat.iso(job.nextRunAt) else { return "—" }
        return AdminFormat.short(next)
    }

    // MARK: - 系统

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("资源")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            if let stats {
                VStack(spacing: 0) {
                    percentRow("内存", percent: stats.memory?.percent,
                               detail: memoryDetail(stats))
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    percentRow("磁盘", percent: stats.disk?.percent,
                               detail: diskDetail(stats))
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("CPU", value: stats.cpuPercent.map {
                        "\(AdminFormat.count($0))% · \(stats.cpuCount ?? 0) 核"
                    } ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("负载", value: stats.loadAvg.map {
                        $0.map { AdminFormat.count($0) }.joined(separator: " / ")
                    } ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("运行时间", value: stats.uptimeSeconds.map(uptimeText) ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("进程内存", value: stats.process?.rss.map(byteText) ?? "—")
                }
                .odGroup()
                SectionLabel("版本与运行时")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    infoRow("Hermes", value: stats.hermesVersion.map { "v\($0)" } ?? "—", mono: true)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("主机", value: stats.hostname ?? "—", mono: true)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("系统", value: [stats.os, stats.arch]
                        .compactMap { $0 }.joined(separator: " · "), mono: true)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("Python", value: stats.pythonVersion ?? "—", mono: true)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("内核", value: stats.osRelease ?? "—", mono: true)
                }
                .odGroup()
            } else {
                Text("正在读取系统状态…")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func percentRow(_ label: String, percent: Double?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                Text(label)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(TypeScale.monoCallout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.fieldFill)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.primary)
                        .frame(width: geo.size.width * CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
    }

    private func infoRow(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
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

    // MARK: - 数据

    private func load() async {
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.status(config: config)
        }) {
            status = loaded
        }
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessions(config: config, limit: 8)
        }) {
            sessions = page.sessions
        }
        if let logs = try? await appState.performAdmin({ client, config in
            try await client.logs(config: config, level: nil, search: nil, lines: 30)
        }) {
            logLines = Array(logs.lines.suffix(12).reversed())
        }
        if let jobs = try? await appState.performAdmin({ client, config in
            try await client.cronJobs(config: config)
        }) {
            cronJobs = jobs
        }
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.systemStats(config: config)
        }) {
            stats = loaded
        }
    }
}
