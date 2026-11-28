import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 单个付费 MCP 服务的预算门配置（对齐 Hermes v0.23.0 `spend_limit` 契约：
/// 即使处于 YOLO 全自动模式，超额付费调用也强制拦截确认）。
struct MCPServerBudget: Codable, Equatable, Sendable {
    /// 是否标记为付费 MCP（如计费 API / 商业搜索 / 云端算力）
    var isPaidService: Bool = false
    /// 估算单次调用标价（USD）
    var estimatedPricePerCallUSD: Double = 0.0
    /// 单次调用硬上限（USD），超出强制拦截
    var perCallSpendLimitUSD: Double = 1.0
    /// 月度累计预算上限（USD）
    var monthlySpendLimitUSD: Double = 20.0
    /// 当月已估算消费（USD）
    var spentThisMonthUSD: Double = 0.0
    /// 豁免 YOLO 模式：付费调用超过单次门槛时始终要求人工确认
    var immuneToYoloMode: Bool = true
}

/// 付费 MCP 标价与 `spend_limit` 预算门持久化仓。
@MainActor
@Observable
final class MCPBudgetStore {
    static let shared = MCPBudgetStore()

    private static let storageKey = "oneday.mcp.budget.policies.v1"

    var budgets: [String: MCPServerBudget] = [:]
    var lastSyncMessage: String?

    private init() {
        load()
    }

    func budget(for serverName: String) -> MCPServerBudget {
        budgets[serverName] ?? MCPServerBudget()
    }

    func update(_ budget: MCPServerBudget, for serverName: String) {
        budgets[serverName] = budget
        save()
    }

    func recordSpend(_ amountUSD: Double, for serverName: String) {
        var current = budget(for: serverName)
        current.spentThisMonthUSD = max(0, current.spentThisMonthUSD + amountUSD)
        budgets[serverName] = current
        save()
    }

    func resetMonthlySpend(for serverName: String) {
        var current = budget(for: serverName)
        current.spentThisMonthUSD = 0
        budgets[serverName] = current
        save()
    }

    func totalMonthlySpendUSD() -> Double {
        budgets.values.filter(\.isPaidService).reduce(0) { $0 + $1.spentThisMonthUSD }
    }

    func totalMonthlyLimitUSD() -> Double {
        budgets.values.filter(\.isPaidService).reduce(0) { $0 + $1.monthlySpendLimitUSD }
    }

    func paidServerCount() -> Int {
        budgets.values.filter(\.isPaidService).count
    }

    /// 同步 `spend_limit` 配置至 Hermes 服务端 `config.yaml`
    func syncToServer(serverName: String, appState: AppState) async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        let b = budget(for: serverName)
        let patch: [String: Any] = [
            "mcp": [
                "spend_limits": [
                    serverName: [
                        "enabled": b.isPaidService,
                        "per_call_usd": b.perCallSpendLimitUSD,
                        "monthly_usd": b.monthlySpendLimitUSD,
                        "estimated_call_usd": b.estimatedPricePerCallUSD,
                        "require_approval": b.immuneToYoloMode,
                    ]
                ]
            ]
        ]
        do {
            try await appState.client.updateConfig(config: config, apiKey: apiKey, values: patch)
            lastSyncMessage = "已同步「\(serverName)」的预算门配置至服务端。"
            Haptics.success()
        } catch {
            lastSyncMessage = "已保存在本机，服务端同步失败：\(error.localizedDescription)"
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: MCPServerBudget].self, from: data)
        else { return }
        budgets = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(budgets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// 嵌入 `MCPServerDetailView` 的付费 MCP 标价与 `spend_limit` 预算门配置分组。
struct MCPBudgetPolicySection: View {
    @Environment(AppState.self) private var appState
    let serverName: String

    @State private var store = MCPBudgetStore.shared
    @State private var isSyncing = false

    private var current: MCPServerBudget {
        store.budget(for: serverName)
    }

    private var progressRatio: Double {
        guard current.monthlySpendLimitUSD > 0 else { return 0 }
        return min(1.0, current.spentThisMonthUSD / current.monthlySpendLimitUSD)
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { current.isPaidService },
                set: { enabled in
                    var updated = current
                    updated.isPaidService = enabled
                    store.update(updated, for: serverName)
                    Haptics.selection()
                }
            )) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(symbol: "dollarsign.circle.fill", color: Palette.tintOrangeInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("付费 MCP 预算门")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("启用单次标价提示与月度 spend_limit 硬上限")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .tint(Palette.tintOrangeInk)

            if current.isPaidService {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("本月估算消耗")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer()
                        Text(String(format: "$%.2f / $%.2f", current.spentThisMonthUSD, current.monthlySpendLimitUSD))
                            .font(.footnote.monospaced().weight(.semibold))
                            .foregroundStyle(progressRatio >= 0.85 ? Palette.danger : Palette.ink)
                    }
                    ProgressView(value: progressRatio)
                        .tint(progressRatio >= 0.85 ? Palette.danger : Palette.tintOrangeInk)
                }
                .padding(.vertical, 4)

                Stepper(
                    value: Binding(
                        get: { current.estimatedPricePerCallUSD },
                        set: { val in
                            var updated = current
                            updated.estimatedPricePerCallUSD = max(0, (val * 100).rounded() / 100)
                            store.update(updated, for: serverName)
                        }
                    ),
                    in: 0...50,
                    step: 0.05
                ) {
                    LabeledContent("单次调用标价") {
                        Text(String(format: "$%.2f / 次", current.estimatedPricePerCallUSD))
                            .font(.rowSubtitle.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                Stepper(
                    value: Binding(
                        get: { current.perCallSpendLimitUSD },
                        set: { val in
                            var updated = current
                            updated.perCallSpendLimitUSD = max(0.05, (val * 100).rounded() / 100)
                            store.update(updated, for: serverName)
                        }
                    ),
                    in: 0.05...100,
                    step: 0.25
                ) {
                    LabeledContent("单次上限 (spend_limit)") {
                        Text(String(format: "$%.2f", current.perCallSpendLimitUSD))
                            .font(.rowSubtitle.monospaced())
                            .foregroundStyle(Palette.tintOrangeInk)
                    }
                }

                Stepper(
                    value: Binding(
                        get: { current.monthlySpendLimitUSD },
                        set: { val in
                            var updated = current
                            updated.monthlySpendLimitUSD = max(1, val.rounded())
                            store.update(updated, for: serverName)
                        }
                    ),
                    in: 1...500,
                    step: 5
                ) {
                    LabeledContent("月度预算上限") {
                        Text(String(format: "$%.0f / 月", current.monthlySpendLimitUSD))
                            .font(.rowSubtitle.monospaced())
                            .foregroundStyle(Palette.ink)
                    }
                }

                Toggle(isOn: Binding(
                    get: { current.immuneToYoloMode },
                    set: { val in
                        var updated = current
                        updated.immuneToYoloMode = val
                        store.update(updated, for: serverName)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("豁免 YOLO 自动放行")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("即使开启全自动模式，超额付费调用仍强制弹窗确认")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .tint(Palette.primary)

                HStack(spacing: OneDayMetrics.spacingM) {
                    Button {
                        Task {
                            isSyncing = true
                            await store.syncToServer(serverName: serverName, appState: appState)
                            isSyncing = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSyncing { ProgressView().controlSize(.small) }
                            Text("同步预算门至服务端")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSyncing)

                    Spacer()

                    Button("归零本月统计", role: .destructive) {
                        store.resetMonthlySpend(for: serverName)
                        Haptics.selection()
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
            }
        } header: {
            SettingsSectionHeader("付费标价与预算门")
        } footer: {
            if let msg = store.lastSyncMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }
}
