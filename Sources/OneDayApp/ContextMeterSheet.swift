import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 上下文 Token 占用仪表盘（`/context` 实时透视 + 一键 `/compress` 压缩）：
/// 按 Hermes v0.23.0 七维上下文结构估算当前对话窗口占用，帮助用户提前发现超窗风险并一键压缩。
struct ContextMeterSheet: View {
    let modelName: String
    let entries: [ChatEntry]
    let onCompress: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var focusTopic = ""

    private struct Slice: Identifiable {
        let id: String
        let title: String
        let tokens: Int
        let color: Color
    }

    private var contextWindow: Int {
        let lower = modelName.lowercased()
        if lower.contains("gemini") { return 1_000_000 }
        if lower.contains("claude") { return 200_000 }
        if lower.contains("gpt-5") || lower.contains("gpt-4.1") { return 128_000 }
        return 128_000
    }

    private var conversationTokens: Int {
        let chars = entries.reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) }
        // 中英文混排近似 1.8 字符 ≈ 1 token
        return max(0, Int(Double(chars) / 1.8))
    }

    private var toolCallTokens: Int {
        entries.filter { $0.toolCard != nil }.count * 380
    }

    private var slices: [Slice] {
        [
            Slice(id: "system", title: "System Prompt 与人设", tokens: 2_200, color: Palette.tintSkyInk),
            Slice(id: "tools", title: "内置工具与 MCP Schema", tokens: 3_600 + toolCallTokens, color: Palette.tintLavenderInk),
            Slice(id: "skills", title: "Skills 元数据索引", tokens: 950, color: Palette.tintGreenInk),
            Slice(id: "memory", title: "长期记忆与画像", tokens: 1_200, color: Palette.tintOrangeInk),
            Slice(id: "history", title: "当前对话历史（\(entries.count) 条）", tokens: conversationTokens, color: Palette.primary),
        ]
    }

    private var totalUsed: Int {
        slices.reduce(0) { $0 + $1.tokens }
    }

    private var usageRatio: Double {
        min(1.0, Double(totalUsed) / Double(max(contextWindow, 1)))
    }

    private var usagePercentText: String {
        String(format: "%.1f%%", usageRatio * 100)
    }

    private var healthTone: SettingsStatusTone {
        if usageRatio >= 0.8 { return .error }
        if usageRatio >= 0.55 { return .warning }
        return .healthy
    }

    private var healthLabel: String {
        if usageRatio >= 0.8 { return "建议立即压缩" }
        if usageRatio >= 0.55 { return "占用偏高" }
        return "窗口充裕"
    }

    var body: some View {
        NavigationStack {
            List {
                SettingsHeroCard(
                    symbol: "gauge.with.dots.needle.67percent",
                    tint: usageRatio >= 0.8 ? Palette.danger : Palette.tintSkyInk,
                    title: "上下文占用 · \(usagePercentText)",
                    subtitle: "当前模型 \(modelName) · 估算已用 \(formatTokens(totalUsed)) / \(formatTokens(contextWindow)) tokens。",
                    statusText: healthLabel,
                    statusTone: healthTone
                )

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(slices) { slice in
                                    let frac = Double(slice.tokens) / Double(max(totalUsed, 1))
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(slice.color)
                                        .frame(width: max(4, geo.size.width * usageRatio * frac))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.fillTertiary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .frame(height: 12)

                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 8, height: 8)
                                Text(slice.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text(formatTokens(slice.tokens))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    SettingsSectionHeader("上下文构成透视（实时估算）")
                }
                .listRowBackground(Palette.surface)

                Section {
                    Button {
                        Haptics.selection()
                        dismiss()
                        onCompress(nil)
                    } label: {
                        Label("一键无损压缩上下文 (/compress)", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 8) {
                        TextField("可选：定向保留主题（如：保留接口契约）", text: $focusTopic)
                            .font(.subheadline)
                        Button("定向压缩") {
                            let topic = focusTopic.trimmingCharacters(in: .whitespacesAndNewlines)
                            Haptics.selection()
                            dismiss()
                            onCompress(topic.isEmpty ? nil : topic)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .disabled(focusTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    SettingsSectionHeader("上下文压缩")
                } footer: {
                    Text("将向当前会话发送 /compress 指令，由 Hermes 服务端保留关键决策与记忆并释放冗长历史 Token。")
                        .font(.caption)
                }
                .listRowBackground(Palette.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("上下文仪表盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
