import OneDayCore
import OneDayDesign
import SwiftUI

/// 连接自检面：客户端秒级只读探活（统一 iOS 26 Hero 摘要卡，不再嵌套二级子页）
struct ConnectionSelfCheckView: View {
    struct Target: Equatable {
        let config: ServerConfig
        let apiKey: String?
    }

    var target: Target? = nil

    @Environment(AppState.self) private var appState
    @State private var store = ConnectionSelfCheckStore()

    private var resolvedTarget: Target? {
        if let target { return target }
        guard let config = appState.config else { return nil }
        return Target(config: config, apiKey: appState.apiKey)
    }

    var body: some View {
        Group {
            if let resolvedTarget {
                checkList(target: resolvedTarget)
            } else {
                ContentUnavailableView(
                    "还没连上服务器",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text(
                        "连上服务器后，这里会逐项显示连接、服务状态与服务器能力的实测结论。"
                    )
                )
            }
        }
        .navigationTitle("连接自检")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkList(target: Target) -> some View {
        List {
            SettingsHeroCard(
                symbol: "antenna.radiowaves.left.and.right",
                tint: .green,
                title: "连接自检",
                subtitle: store.report.map {
                    "上次自检 \($0.checkedAt.formatted(date: .abbreviated, time: .shortened))"
                } ?? "客户端秒级只读探活：逐项验证网络连通、网关服务与接口能力。",
                statusText: store.isRunning ? "自检中…" : (store.report?.overallWord ?? "待检测"),
                statusTone: store.isRunning ? .neutral : ((store.report?.warnCount ?? 0) > 0 ? .warning : (store.report != nil ? .healthy : .neutral))
            )

            if self.target == nil {
                Section {
                    liveConnectionRow
                } header: {
                    SettingsSectionHeader("当前连接")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            if let report = store.report {
                ForEach(report.groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            rowView(row)
                        }
                    } header: {
                        SettingsSectionHeader(group.title)
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在自检…")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                Text("连接自检为客户端秒级只读探活；如需服务端深度审计与备份存档，请返回上一页进入「体检与存档」。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("重新自检") {
                    Task { await runNow(target: target) }
                }
                .disabled(store.isRunning)
            }
        }
        .task {
            if store.report == nil {
                await runNow(target: target)
            }
        }
        .refreshable {
            await runNow(target: target)
        }
    }

    private var liveConnectionRow: some View {
        let status = appState.connectionStatus
        return HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Circle()
                .fill(liveDotColor(for: status.phase))
                .frame(width: 9, height: 9)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(status.phaseWord)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let detail = status.detailText {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [status.phaseWord, status.detailText]
                .compactMap { $0 }
                .joined(separator: "，")
        )
    }

    private func liveDotColor(for phase: ConnectionPhase) -> Color {
        switch phase {
        case .online: return Palette.success
        case .retrying, .offline: return Palette.warning
        case .probing, .notConnected: return Palette.inkMuted
        }
    }

    private func runNow(target: Target) async {
        await store.run(
            client: appState.client, config: target.config,
            apiKey: target.apiKey
        )
    }

    private func rowView(_ row: SelfCheckRow) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Circle()
                .fill(dotColor(for: row.status))
                .frame(width: 9, height: 9)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    if let value = row.value {
                        Text(value)
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text(detailText(for: row))
                    .font(.footnote)
                    .foregroundStyle(detailColor(for: row.status))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: row))
    }

    private func detailText(for row: SelfCheckRow) -> String {
        guard let reason = row.reason else { return row.status.word }
        return "\(row.status.word) · \(reason)"
    }

    private func accessibilityText(for row: SelfCheckRow) -> String {
        var parts = [row.title, row.status.word]
        if let value = row.value { parts.append(value) }
        if let reason = row.reason { parts.append(reason) }
        return parts.joined(separator: "，")
    }

    private func dotColor(for status: SelfCheckRowStatus) -> Color {
        switch status {
        case .ok: return Palette.success
        case .warn: return Palette.warning
        case .off: return Palette.inkSecondary.opacity(0.55)
        case .unprobed: return Palette.inkSecondary.opacity(0.3)
        }
    }

    private func detailColor(for status: SelfCheckRowStatus) -> Color {
        switch status {
        case .ok: return Palette.successText
        case .warn: return Palette.warningText
        case .off, .unprobed: return Palette.inkSecondary
        }
    }
}
