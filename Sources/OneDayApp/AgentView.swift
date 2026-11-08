import OneDayDesign
import OneDayCore
import SwiftUI

/// 智能体格（IA v3 §5.2）：运维四模块的目录页。首页只到
/// 「条目行＋当前值摘要」一层（深度纪律沿 v2/v3），点入二级
/// 页操作。摘要各自独立加载：单项失败只让该行回到占位，
/// 不整页报错——目录页的职责是导航，不是状态面。
struct AgentView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [AgentRoute] = []

    @State private var memorySummary: String?
    @State private var skillsSummary: String?
    @State private var cronSummary: String?
    @State private var sessionsSummary: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("运维模块")
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        moduleRow(
                            icon: "brain",
                            title: "记忆",
                            summary: memorySummary ?? "长期记忆与提供方",
                            route: .memory
                        )
                        GroupDivider(inset: 56)
                        moduleRow(
                            icon: "puzzlepiece.extension",
                            title: "技能",
                            summary: skillsSummary ?? "已装技能与开关",
                            route: .skills
                        )
                        GroupDivider(inset: 56)
                        moduleRow(
                            icon: "clock.arrow.2.circlepath",
                            title: "定时任务",
                            summary: cronSummary ?? "计划任务与运行记录",
                            route: .cron
                        )
                        GroupDivider(inset: 56)
                        moduleRow(
                            icon: "bubble.left.and.text.bubble.right",
                            title: "服务端会话",
                            summary: sessionsSummary ?? "服务端保存的全部会话",
                            route: .serverSessions
                        )
                    }
                    .odGroup()
                    Text("本机聊天记录在聊天页的会话抽屉里；这里是服务端侧的工作面。")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("智能体")
            .task { await loadSummaries() }
            .onAppear { consumePendingRoute() }
            .onChange(of: appState.pendingAgentRoute) { _, _ in
                consumePendingRoute()
            }
            .navigationDestination(for: AgentRoute.self) { route in
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
        }
    }

    private func moduleRow(
        icon: String, title: String, summary: String, route: AgentRoute
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                    Text(summary)
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
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 深链消费：详情类路由要垫一层列表页，返回键才有落点
    private func consumePendingRoute() {
        guard let route = appState.pendingAgentRoute else { return }
        appState.pendingAgentRoute = nil
        switch route {
        case .serverSessionDetail:
            path = [.serverSessions, route]
        default:
            path = [route]
        }
    }

    private func loadSummaries() async {
        if let status = try? await appState.performAdmin({ client, config in
            try await client.memoryStatus(config: config)
        }) {
            let active = status.active?.isEmpty == false ? status.active! : "内置记忆"
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
                cronSummary = "启用 \(enabled.count) 个 · 下次 \(AdminFormat.short(next))"
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
}
