import OneDayCore
import OneDayDesign
import SwiftUI

/// 连接自检面（H13，台账 33，DESIGN §357）：设置·连
/// 接（服务器段）的驻留诊断面——客户端只读探活的逐
/// 项实测结论（连接／服务状态／服务器能力／扩展能
/// 力四组），每行状态点＋文字结论＋实测值/人话原
/// 因，结论只来自真回读（拉不到显未探/异常，不假
/// 绿）。与体检（H1）分工写死：自检＝客户端探活
/// （秒级、全只读 GET）；体检＝服务端深检（跑
/// action、分钟级）——页脚互链一行。
///
/// 入参 target 非 nil 时按给定连接探（连接引导失败
/// 面深链用：候选地址＋已填密钥）；nil 时读 AppState
/// 当前连接，未连接显诚实空态
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
            if target == nil {
                Section("当前连接") {
                    liveConnectionRow
                }
            }

            if let report = store.report {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(report.overallWord)
                                .font(.headline)
                                .foregroundStyle(
                                    report.warnCount > 0
                                        ? Palette.warningText
                                        : Palette.successText
                                )
                            Text("上次自检 \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        if store.isRunning {
                            ProgressView()
                        }
                    }
                }
                ForEach(report.groups) { group in
                    Section(group.title) {
                        ForEach(group.rows) { row in
                            rowView(row)
                        }
                    }
                }
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在自检…")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    HealthCheckView()
                } label: {
                    Label("深度问题？运行体检", systemImage: "stethoscope")
                }
                Text("自检是客户端的秒级探活；体检在服务器上跑深度自检与安全审计，要几分钟。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
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

    /// 当前连接实时行（总表 156，DESIGN §394）：读
    /// AppState 上的连接状态快照（OverviewBridgeStore
    /// 探活链喂入）——阶段＋第几次尝试＋人话原因，与自
    /// 检报告分工：报告是按需全量实测、本行是常驻探活
    /// 的现况。深链探候选连接（target 非 nil）时整节
    /// 不显，免与候选结论混淆
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

    /// 自检行：状态点（小圆点、语义色）＋标题＋实测
    /// 值（右置、AX 大字号下随行换行不截断）；结论一
    /// 词与原因在副行——不只靠颜色传达（准入四问④）
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
