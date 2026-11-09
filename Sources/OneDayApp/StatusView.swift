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
    @Environment(\.colorScheme) private var colorScheme
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
            // 0.4.0（§3.2）：tabBarZone 手算留白删除，底部
            // 避让回系统安全区；留常规尾距
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
        // 0.3.7 卡 4：身份头居中＋头像位（圆面＋字形），
        // host 地址行撤下（归服务器详情）
        VStack(spacing: OneDayMetrics.spacingS) {
            ZStack {
                // 0.3.8：枢纽页头像改白浮纸画法（近白面＋
                // 发丝边＋柔影，与全局浮件令牌同族）
                Circle()
                    .fill(Palette.floatFill)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Palette.hairline, lineWidth: 0.5)
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            // 0.4.0（§1.1）：头像圆的手搓阴影随 Elevation
            // 整表废止退役
            HStack(spacing: OneDayMetrics.spacingS) {
                Text("Hermes")
                    .font(.title2)
                    .foregroundStyle(Palette.ink)
                StatusDot(color: status.map { Palette.stateColor($0.gatewayState) }
                    ?? Palette.inkMuted)
            }
            Text(statusLine)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLine: String {
        // 0.4.0（审计 §3.3 #4）：模型后缀撤除——模型露头
        // 只许聊天页胶囊一处（A 案），本行只留状态词
        status == nil
            ? "状态读取中"
            : ServerLabels.gatewayState(status?.gatewayState, running: status?.gatewayRunning)
    }

    // MARK: - 活动

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("最近会话")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            if sessions.isEmpty {
                Text("暂无服务端会话")
                    .font(.callout)
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
                                    // 卡 16/18 同源：SessionDisplay
                                    // 人话标题＋副题，原始名不上屏
                                    Text(session.humanTitle)
                                        .font(.body)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(session.humanSubtitle(now: Date()))
                                        .font(.footnote)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer(minLength: OneDayMetrics.spacingS)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .regular))
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
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                // 0.3.8 基线补遗（审计三行结构）：近期事件
                // 改人话三行——动作标题＋说明＋级别·时间脚
                // 注，原始日志行退到脚注（LogDisplay 解析）
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        let entry = LogDisplay.parse(line)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.headline)
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(entry.meta)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .padding(OneDayMetrics.spacingM)
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
                    .font(.callout)
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
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(job.scheduleText)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            Text(jobNextText(job))
                                .font(.system(.callout, design: .monospaced))
                                // 0.23.0（审计 G1）：停用态的下次
                                // 时间也是要读的字，inkMuted 退出
                                // 文字位，两态同归 inkSecondary
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                    }
                }
                .odGroup()
            }
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
                    LabeledContent("CPU", value: stats.cpuPercent.map {
                        "\(AdminFormat.count($0))% · \(stats.cpuCount ?? 0) 核"
                    } ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("负载", value: stats.loadAvg.map {
                        $0.map { AdminFormat.count($0) }.joined(separator: " / ")
                    } ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("运行时间", value: stats.uptimeSeconds.map(uptimeText) ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("进程内存", value: stats.process?.rss.map(byteText) ?? "—")
                }
                .odGroup()
                SectionLabel("版本与运行时")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    LabeledContent("Hermes") {
                        Text(stats.hermesVersion.map { "v\($0)" } ?? "—")
                            .font(.system(.callout, design: .monospaced))
                    }
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("主机") {
                        Text(stats.hostname ?? "—")
                            .font(.system(.callout, design: .monospaced))
                    }
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("系统") {
                        Text([stats.os, stats.arch]
                        .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(.callout, design: .monospaced))
                    }
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("Python") {
                        Text(stats.pythonVersion ?? "—")
                            .font(.system(.callout, design: .monospaced))
                    }
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("内核") {
                        Text(stats.osRelease ?? "—")
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                .odGroup()
            } else {
                Text("正在读取系统状态…")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func percentRow(_ label: String, percent: Double?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                Text(label)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
            }
            // 0.3.7 卡 4：数据条走共享 DataBar 中性口径
            // （原主色蓝填充退出——蓝只许功能位）
            DataBar(fraction: (percent ?? 0) / 100, height: 6)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
    }

    // （infoRow 已于 0.4.0 删除，审计 §3.1：键值行统一 LabeledContent）

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
