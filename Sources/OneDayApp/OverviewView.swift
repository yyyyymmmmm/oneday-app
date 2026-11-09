import OneDayDesign
import OneDayCore
import SwiftData
import SwiftUI

/// 总览（IA v3 §5.4 五段，0.3.7 卡 2 改版）：顶部状态大卡
/// 置顶（收编状态头＋指标：状态行＝状态点＋人话状态词、
/// 大数字＝今日 Token、进度＝内存占用 %，取数口径见卡 2
/// 已裁注），五段其余保留卡下。0.3.6 真机纠正四条同轮
/// 落地：状态字号回正常行（不再 36pt 大字压页标题）、
/// 「待处理」改人话结论列表（无则明写，没有日志原文、
/// INFO 不挂红）、平台名/状态词全走 ServerLabels 翻译
/// （api_server/connected 原文退出本页）、底部留白补到
/// 悬浮底栏带（tabBarZone）。总览只看不动，唯一的写动
/// 作是快捷动作里的重启网关（二次确认）。每段独立加
/// 载：一段失败只降级该段，不整页报错。
struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var localThreads: [ChatThread]

    var onOpenAgent: (AgentRoute) -> Void = { _ in }
    /// 服务端会话点按（0.4.0，§3.4）：改道聊天页续聊
    /// （状态页最近会话与本页服务端会话行共用此口）
    var onOpenChatSession: (String) -> Void = { _ in }
    var onOpenSettings: (SettingsRoute) -> Void = { _ in }
    var onOpenChat: () -> Void = {}

    @State private var status: ServerStatus?
    @State private var stats: SystemStats?
    @State private var serverSessions: [ServerSession] = []
    @State private var sessionsLoaded = false
    @State private var cronJobs: [CronJob] = []
    @State private var todayTokens: Double?
    @State private var errorLogCount = 0
    @State private var egressAbnormal = false
    @State private var statusError: String?
    @State private var isLoading = false
    @State private var showRestartConfirm = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 身份锚点（0.3.8 基线补遗增量令 1）：一级
                    // 页顶部统一悬浮身份胶囊、切页锚点不动，
                    // 页大标题（导航栏「总览」）退其下
                    HStack {
                        Spacer()
                        IdentityAnchor(
                            name: "Hermes",
                            statusWord: status.map(stateWord) ?? "读取中",
                            statusColor: status.map {
                                Palette.stateColor($0.gatewayState)
                            } ?? Palette.inkMuted
                        )
                        Spacer()
                    }
                    .padding(.bottom, OneDayMetrics.spacingM)
                    if let status {
                        statusCard(status)
                        platformsGroup(status)
                    } else if let statusError {
                        errorSection(statusError)
                    }
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
                // 0.4.0（§3.2）：tabBarZone 手算留白删除——
                // 原生底栏回来后滚动底部避让由系统安全区自理
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

    // MARK: - 状态大卡（卡 2 置顶收编：状态行＋大数字＋进度＋次级指标）

    private func statusCard(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                StatusView(
                    onOpenSession: { onOpenChatSession($0) }
                )
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    StatusDot(color: Palette.stateColor(status.gatewayState))
                    Text(stateWord(status))
                        .font(TypeScale.body)
                        .foregroundStyle(isAbnormal(status) ? Palette.danger : Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        // 卡 17：字形 regular 线条体
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("状态详情")
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingM)

            // 大数字＝今日 Token（已裁 2）；等宽＋numericText
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(todayTokens.map { AdminFormat.count($0) } ?? "—")
                    .font(TypeScale.metricNumber)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .tabularDigits()
                    .contentTransition(.numericText())
                Text("今日 Token")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingL)

            // 进度＝内存占用 %（已裁 2：唯一有真分母的候选）
            if let percent = stats?.memory?.percent {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    HStack {
                        Text("内存占用")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer()
                        Text("\(Int(percent.rounded()))%")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .tabularDigits()
                    }
                    DataBar(fraction: percent / 100)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.top, OneDayMetrics.spacingM)
            }

            GroupDivider(inset: OneDayMetrics.spacingM)
                .padding(.top, OneDayMetrics.spacingM)

            // 卡内次级指标（原指标行收编，深链保留）
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
            }
        }
        .odGroup()
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
                    // 卡 17：24 semibold → title 位 bold 口径
                    .font(TypeScale.title(for: colorScheme))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .tabularDigits()
                    .contentTransition(.numericText())
                Text(label)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func stateWord(_ status: ServerStatus) -> String {
        ServerLabels.gatewayState(status.gatewayState, running: status.gatewayRunning)
    }

    private func isAbnormal(_ status: ServerStatus) -> Bool {
        switch status.gatewayState?.lowercased() {
        case "error", "failed", "disconnected", "stopped":
            return true
        default:
            return false
        }
    }

    // MARK: - 平台连接（明细正主在网关页，本段保留段位；名/词走翻译）

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
                // 卡 2 纠正 3：平台名与状态词走 ServerLabels，
                // 原始 key/state 不上屏
                Text(ServerLabels.platformName(name))
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(ServerLabels.platformState(platform.state))
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

    // MARK: - 待处理（人话结论列表，无则明写；日志原文只进日志页）

    private var abnormalPlatforms: [(name: String, state: String)] {
        guard let status else { return [] }
        return status.platforms
            .filter { ($0.value.state ?? "").lowercased() != "connected" }
            .map { (name: $0.key, state: $0.value.state ?? "") }
            .sorted { $0.name < $1.name }
    }

    private var hasTodo: Bool {
        !abnormalPlatforms.isEmpty || errorLogCount > 0 || egressAbnormal
    }

    @ViewBuilder
    private var todoGroup: some View {
        if status != nil {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("待处理")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    if !hasTodo {
                        // 卡 2 纠正 2：无待处理明写，不留空组
                        Text("没有待处理")
                            .font(TypeScale.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .frame(minHeight: OneDayMetrics.rowHeight)
                    }
                    ForEach(Array(abnormalPlatforms.enumerated()), id: \.element.name) { index, item in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        todoRow(
                            icon: "exclamationmark.triangle",
                            text: "平台 \(ServerLabels.platformName(item.name)) 状态为 \(ServerLabels.platformState(item.state))，可能影响消息收发。",
                            color: isErrorState(item.state) ? Palette.danger : Palette.warning
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
                    if errorLogCount > 0 {
                        if !abnormalPlatforms.isEmpty || egressAbnormal {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        // 卡 2 纠正 2：日志原文不上总览，只留
                        // 一条人话摘要，点去日志页看原文
                        Button {
                            onOpenSettings(.logs)
                        } label: {
                            todoRow(
                                icon: "exclamationmark.circle",
                                text: "服务日志有新的错误记录，去日志页查看。",
                                color: Palette.danger
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .odGroup()
            }
        }
    }

    private func isErrorState(_ state: String) -> Bool {
        ["error", "failed"].contains(state.lowercased())
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
        .contentShape(Rectangle())
    }

    // MARK: - 最近会话（标题/副题走 SessionDisplay，与抽屉同源）

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
            onOpenChatSession(session.id)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                if session.isActive {
                    StatusDot(color: Palette.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    // 卡 16/18 同源：标题 humanTitle、副题
                    // humanSubtitle，原始 title/source 不上屏
                    Text(session.humanTitle)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(session.humanSubtitle(now: Date()))
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
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
                    .font(.system(size: 13, weight: .regular))
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

    // MARK: - 快捷动作（IA v3 定版三项，裁定保留）

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
        if let sysStats = try? await appState.performAdmin({ client, config in
            try await client.systemStats(config: config)
        }) {
            stats = sysStats
        }
        if let logs = try? await appState.performAdmin({ client, config in
            try await client.logs(config: config, level: "error", search: nil, lines: 50)
        }) {
            // 只数条数（待处理人话摘要用），原文不上本页
            errorLogCount = logs.lines.count
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
