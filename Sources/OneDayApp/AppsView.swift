import OneDayCore
import OneDayDesign
import SwiftUI

/// 应用格（0.6.0 五格 IA，蓝图 §4 一期）：版式对照
/// OpenMuse 应用页转译为原生 List——入口行＝图标牌＋
/// 标题＋一句事实副题＋披露箭头，分「工具」与「连接」
/// 两组。只挂真实存在、已有页面直达的入口：总览、
/// 文件、设置；浏览器于 0.9.0（P2 盒桥）转正入列，
/// 0.15.0（P9）升级为「电脑」行——电脑面（桌面/文件/
/// 终端三段），桌面段与枢纽浏览器段共用同一面、文件
/// 段与文件格电脑段共用同一组件，不出现第二套口径。
/// 内页面（总览/文件/设置/电脑）各自带「应用」返回
/// 钮回本页首页（各页既有 NavigationStack 不动，不套娃）。
struct AppsView: View {
    var onOpenChat: () -> Void = {}

    @Environment(AppState.self) private var appState
    @State private var page: AppsPage = .home

    var body: some View {
        Group {
            switch page {
            case .home:
                home
            case .overview:
                OverviewView(
                    onOpenAgent: { route in
                        appState.pendingAgentRoute = route
                        page = .settings
                    },
                    onOpenChatSession: { id in
                        appState.pendingChatSessionID = id
                    },
                    onOpenSettings: { route in
                        appState.pendingSettingsRoute = route
                        page = .settings
                    },
                    onOpenChat: onOpenChat,
                    onBackToApps: { page = .home }
                )
            case .files:
                FilesView(onBackToApps: { page = .home })
            case .computer:
                ComputerView(onBackToApps: { page = .home })
            case .settings:
                SettingsView(onBackToApps: { page = .home })
            }
        }
        .onAppear { consumePendingPage() }
        .onChange(of: appState.pendingAppsPage) { _, _ in
            consumePendingPage()
        }
    }

    private func consumePendingPage() {
        guard let pending = appState.pendingAppsPage else { return }
        appState.pendingAppsPage = nil
        page = pending
    }

    // MARK: - 首页（入口行列表）

    private var home: some View {
        NavigationStack {
            List {
                Section {
                    entryRow(
                        page: .overview, pair: TabBarSymbols.overview,
                        subtitle: "状态、用量与最近会话"
                    )
                    entryRow(
                        page: .files, pair: TabBarSymbols.files,
                        subtitle: "智能体生成的文件与影音"
                    )
                    computerEntryRow
                    entryRow(
                        page: .settings, pair: TabBarSymbols.settings,
                        subtitle: "服务器、模型与智能体"
                    )
                } header: {
                    SectionLabel("工具")
                }

                Section {
                    Button {
                        appState.pendingSettingsRoute = .serverDetail
                        page = .settings
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            entryIcon("server.rack")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前服务器")
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                Text(appState.config?.host ?? "未连接")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    SectionLabel("连接")
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.spacingL)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG)
            .navigationTitle("应用")
        }
    }

    private func entryRow(
        page target: AppsPage, pair: TabSymbolPair, subtitle: String
    ) -> some View {
        Button {
            page = target
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                entryIcon(pair.normal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pair.title)
    }

    /// 电脑入口行（0.9.0 为浏览器行、P9 升级为电脑行）：
    /// 符号表暂无电脑对位符号对，走与「当前服务器」行
    /// 同式的自组行
    private var computerEntryRow: some View {
        Button {
            page = .computer
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                entryIcon("desktopcomputer")
                VStack(alignment: .leading, spacing: 2) {
                    Text("电脑")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text("云电脑桌面、文件与终端")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("电脑")
    }

    /// 入口图标牌（OpenMuse 工具行形态的原生转译）：
    /// 中性浅面圆角牌 + 细线符号，不染色、不描边。
    private func entryIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Palette.ink)
            .frame(width: 38, height: 38)
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
