import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 逐模型推理强度档位（对齐 Hermes v0.23.0 `apps/shared/src/reasoning-effort.ts`
/// 与 `agent.reasoning_overrides` 配置契约）。
enum ReasoningEffortLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "关闭"
        case .minimal: return "极简"
        case .low: return "轻度"
        case .medium: return "均衡"
        case .high: return "深度"
        case .max: return "极限"
        }
    }

    var shortBadge: String {
        switch self {
        case .none: return "Off"
        case .minimal: return "Min"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "直接作答，不消耗额外思考 Token"
        case .minimal: return "最短链路校验，适合简单问答"
        case .low: return "快速推理，兼顾响应速度与准确度"
        case .medium: return "默认推荐，平衡深度与延迟"
        case .high: return "适合复杂代码、架构与多步分析"
        case .max: return "最大推理预算，用于疑难攻关"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "bolt.slash"
        case .minimal: return "hare"
        case .low: return "gauge.with.dots.needle.33percent"
        case .medium: return "gauge.with.dots.needle.50percent"
        case .high: return "gauge.with.dots.needle.67percent"
        case .max: return "flame.fill"
        }
    }

    var tint: Color {
        switch self {
        case .none: return Palette.inkSecondary
        case .minimal: return Palette.tintGreenInk
        case .low: return Palette.tintSkyInk
        case .medium: return Palette.primary
        case .high: return Palette.tintOrangeInk
        case .max: return Palette.tintLavenderInk
        }
    }
}

/// 逐模型推理强度与 Fast 模式状态仓（本地持久化 + 同步 Hermes `PUT /api/config`）。
@MainActor
@Observable
final class ReasoningEffortStore {
    static let shared = ReasoningEffortStore()

    private static let overridesKey = "oneday.reasoning.effort.overrides.v1"
    private static let fastModelsKey = "oneday.reasoning.fast.models.v1"

    /// modelName -> ReasoningEffortLevel
    var overrides: [String: ReasoningEffortLevel] = [:]
    /// 开启 Fast 低延迟通道的模型集合
    var fastModels: Set<String> = []
    var isSyncing = false
    var lastSyncMessage: String?

    private init() {
        load()
    }

    func effort(for model: String) -> ReasoningEffortLevel {
        overrides[model] ?? .medium
    }

    func isFastEnabled(for model: String) -> Bool {
        fastModels.contains(model)
    }

    func summaryBadge(for model: String) -> String {
        let level = effort(for: model).title
        return isFastEnabled(for: model) ? "\(level) · Fast" : level
    }

    func setEffort(_ level: ReasoningEffortLevel, for model: String) {
        overrides[model] = level
        save()
    }

    func setFast(_ enabled: Bool, for model: String) {
        if enabled {
            fastModels.insert(model)
        } else {
            fastModels.remove(model)
        }
        save()
    }

    func syncToServer(model: String, appState: AppState) async {
        guard appState.config != nil else { return }
        isSyncing = true
        defer { isSyncing = false }

        let patch: [String: JSONValue] = [
            "agent": .object([
                "reasoning_overrides": .object(overrides.mapValues { .string($0.rawValue) }),
                "fast_mode": .bool(isFastEnabled(for: model)),
            ]),
        ]

        do {
            try await appState.applyDashboardConfig(patch
            )
            lastSyncMessage = "已同步至 Hermes 服务端（\(effort(for: model).title)\(isFastEnabled(for: model) ? " + Fast" : "")）"
            Haptics.success()
        } catch {
            lastSyncMessage = "已保存在本机，服务端同步失败：\(error.localizedDescription)"
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.overridesKey),
           let decoded = try? JSONDecoder().decode([String: ReasoningEffortLevel].self, from: data) {
            overrides = decoded
        }
        if let list = UserDefaults.standard.stringArray(forKey: Self.fastModelsKey) {
            fastModels = Set(list)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.overridesKey)
        }
        UserDefaults.standard.set(Array(fastModels), forKey: Self.fastModelsKey)
    }
}

/// 逐模型推理强度与 Fast 档位选择器（可作为设置二级页或对话内 Sheet 复用）。
struct ReasoningEffortSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let modelName: String
    /// 若在对话内调用，点击「同步并应用到当前对话」可顺带触发 `/reasoning` 通知
    var onApplySlashCommand: ((String) -> Void)? = nil

    @State private var store = ReasoningEffortStore.shared

    private var currentEffort: ReasoningEffortLevel {
        store.effort(for: modelName)
    }

    private var isFast: Bool {
        store.isFastEnabled(for: modelName)
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "brain.head.profile",
                tint: currentEffort.tint,
                title: "推理强度与 Fast 档位",
                subtitle: "为当前模型 \(modelName) 单独配置思考深度与快速通道，自动同步至 Hermes `agent.reasoning_overrides`。",
                statusText: store.summaryBadge(for: modelName),
                statusTone: isFast ? .warning : .healthy
            )

            Section {
                Toggle(isOn: Binding(
                    get: { isFast },
                    set: { newValue in
                        Haptics.selection()
                        store.setFast(newValue, for: modelName)
                        Task { await store.syncToServer(model: modelName, appState: appState) }
                    }
                )) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "bolt.fill", color: Palette.tintOrangeInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fast 快速通道")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text("优先使用低延迟推理路由，适合高频交互")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .tint(Palette.tintOrangeInk)
            } header: {
                SettingsSectionHeader("响应速度")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                ForEach(ReasoningEffortLevel.allCases) { level in
                    Button {
                        Haptics.selection()
                        store.setEffort(level, for: modelName)
                        Task { await store.syncToServer(model: modelName, appState: appState) }
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: level.symbol, color: level.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(level.title)
                                        .font(.rowTitleL)
                                        .foregroundStyle(Palette.ink)
                                    Text(level.shortBadge)
                                        .font(.caption2.monospaced().weight(.semibold))
                                        .foregroundStyle(level.tint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(level.tint.opacity(0.12), in: Capsule())
                                }
                                Text(level.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            if currentEffort == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.primary)
                            }
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SettingsSectionHeader("逐模型推理深度")
            } footer: {
                if let msg = store.lastSyncMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    Text("不同模型可分别记住自己的推理档位，切换模型时自动生效。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if let onApplySlashCommand {
                Section {
                    Button {
                        Haptics.success()
                        onApplySlashCommand("/reasoning \(currentEffort.rawValue)")
                        dismiss()
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "paperplane.fill", color: Palette.primary)
                            Text("立即发送 /reasoning \(currentEffort.rawValue) 生效")
                                .font(.rowTitleL.weight(.medium))
                                .foregroundStyle(Palette.primary)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("推理强度与 Fast")
        .navigationBarTitleDisplayMode(.inline)
    }
}
