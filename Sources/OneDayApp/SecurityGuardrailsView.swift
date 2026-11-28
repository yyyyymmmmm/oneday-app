import OneDayCore
import OneDayDesign
import SwiftUI

/// 安全护栏与风控策略中心（Hermes v0.23.0 P1 #46）：
/// - Smart 风险审批模式（strict 手动确认 / smart 智能风险分级 / off 自动放行）
/// - 命令黑名单 Glob 规则（如 `rm -rf *`、`curl * | sh`）
/// - 网站访问策略（全部允许 / 白名单 / 黑名单）
/// - OSV 供应链安全扫描开关（安装技能/依赖前校验漏洞）
struct SecurityGuardrailsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var approvalMode = "smart"
    @State private var denyPatterns: [String] = []
    @State private var newDenyPattern = ""
    @State private var websitePolicy = "allow_all"
    @State private var websiteDomainsText = ""
    @State private var osvScanEnabled = true
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var isError = false

    private static let presetDenyPatterns: [String] = [
        "rm -rf *",
        "curl * | sh",
        "git push --force*",
        "sudo *",
        "chmod 777 *",
    ]

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "shield.checkered",
                tint: Palette.tintGreenInk,
                title: "安全护栏与风控",
                subtitle: "集中管控 Hermes 的智能风险审批档位、高危命令黑名单、网站访问边界与 OSV 供应链漏洞扫描。",
                statusText: modeLabel(for: approvalMode),
                statusTone: approvalMode == "off" ? .warning : .healthy
            )

            Section {
                Picker("审批模式", selection: $approvalMode) {
                    Text("严格手动").tag("manual")
                    Text("智能分级").tag("smart")
                    Text("自动放行").tag("off")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                Text(modeDescription)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                SettingsSectionHeader("Smart 风险审批模式")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    TextField("添加命令黑名单 glob（如 rm -rf *）", text: $newDenyPattern)
                        .font(.metaMonospaced)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { addDenyPattern() }

                    Button("添加") { addDenyPattern() }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Palette.primary)
                        .disabled(newDenyPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.presetDenyPatterns, id: \.self) { preset in
                            let exists = denyPatterns.contains(preset)
                            Button {
                                if !exists {
                                    withAnimation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion)) {
                                        denyPatterns.append(preset)
                                    }
                                    Haptics.selection()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: exists ? "checkmark" : "plus")
                                        .font(.caption2)
                                    Text(preset)
                                        .font(.metaMonospaced)
                                }
                                .foregroundStyle(exists ? Palette.inkMuted : Palette.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(exists ? Palette.fillPrimary : Palette.primaryTint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(exists)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if denyPatterns.isEmpty {
                    Text("暂无自定义命令黑名单，高危操作将按审批模式弹窗确认。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    ForEach(denyPatterns, id: \.self) { pattern in
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(Palette.danger)
                            Text(pattern)
                                .font(.metaMonospaced)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Button {
                                withAnimation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion)) {
                                    denyPatterns.removeAll { $0 == pattern }
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                }
            } header: {
                SettingsSectionHeader("命令黑名单（Deny Glob）")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                Picker(selection: $websitePolicy) {
                    Text("全部允许（默认）").tag("allow_all")
                    Text("仅允许白名单域名").tag("allowlist")
                    Text("拦截黑名单域名").tag("blocklist")
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "globe.badge.chevron.backward", color: Palette.tintSkyInk)
                        Text("网站访问策略")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)

                if websitePolicy != "allow_all" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(websitePolicy == "allowlist" ? "允许访问的域名（逗号分隔）" : "禁止访问的域名（逗号分隔）")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        TextField("例如：github.com,docs.python.org", text: $websiteDomainsText)
                            .font(.metaMonospaced)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }

                Toggle(isOn: $osvScanEnabled) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "shippingbox.and.arrow.backward.fill", color: Palette.tintOrangeInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OSV 供应链安全扫描")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text("安装技能包、MCP 服务或依赖前自动比对已知 CVE 漏洞")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .tint(Palette.primary)
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                SettingsSectionHeader("网络边界与供应链防护")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                Button {
                    Task { await saveGuardrails() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSaving ? "正在同步安全策略…" : "保存安全护栏配置")
                            .font(.rowTitleL.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .disabled(isSaving || isLoading)
            } footer: {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? Palette.danger : Palette.successText)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .animation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion), value: websitePolicy)
        .navigationTitle("安全护栏与风控")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadGuardrails() }
    }

    private func modeLabel(for mode: String) -> String {
        switch mode {
        case "manual": return "严格手动"
        case "smart": return "智能分级"
        case "off": return "自动放行"
        default: return "智能分级"
        }
    }

    private var modeDescription: String {
        switch approvalMode {
        case "manual":
            return "所有写入、终端命令和外部调用都需要人工确认，适合高敏感生产环境。"
        case "smart":
            return "只读检索与低风险动作自动放行，删除、外发、提权与命中黑名单的操作触发确认。"
        default:
            return "除明确写入下方命令黑名单的规则外全部自动放行（YOLO 模式），请谨慎开启。"
        }
    }

    private func addDenyPattern() {
        let trimmed = newDenyPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !denyPatterns.contains(trimmed) else { return }
        withAnimation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion)) {
            denyPatterns.append(trimmed)
        }
        newDenyPattern = ""
        Haptics.selection()
    }

    private func loadGuardrails() async {
        guard appState.config != nil else { return }
        isLoading = true
        defer { isLoading = false }
        guard let raw = try? await appState.readDashboardConfig(),
              let sec = raw["security"]?.objectValue
        else { return }
        if let mode = sec["approval_mode"]?.stringValue, !mode.isEmpty {
            approvalMode = mode
        }
        if let patterns = sec["deny_patterns"]?.arrayValue?.compactMap(\.stringValue) {
            denyPatterns = patterns
        }
        if let policy = sec["website_policy"]?.stringValue, !policy.isEmpty {
            websitePolicy = policy
        }
        if let domains = sec["website_domains"]?.arrayValue?.compactMap(\.stringValue) {
            websiteDomainsText = domains.joined(separator: ",")
        }
        if let osv = sec["osv_scan_enabled"]?.boolValue {
            osvScanEnabled = osv
        }
    }

    private func saveGuardrails() async {
        guard appState.config != nil else { return }
        isSaving = true
        statusMessage = nil
        isError = false
        defer { isSaving = false }

        let domains = websiteDomainsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let securityPatch: [String: JSONValue] = [
            "approval_mode": .string(approvalMode),
            "deny_patterns": .array(denyPatterns.map(JSONValue.string)),
            "website_policy": .string(websitePolicy),
            "website_domains": .array(domains.map(JSONValue.string)),
            "osv_scan_enabled": .bool(osvScanEnabled),
        ]
        do {
            try await appState.applyDashboardConfig(["security": .object(securityPatch)]
            )
            statusMessage = "安全护栏与风控策略已同步至 Hermes 服务端。"
            isError = false
            Haptics.success()
        } catch {
            statusMessage = (error as? HermesError)?.userMessage ?? "保存失败：\(error.localizedDescription)"
            isError = true
            Haptics.error()
        }
    }
}
