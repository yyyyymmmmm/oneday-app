import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 单条 AI / 用户设置变更审计记录（对应服务端 `settings_admin.py` 的 `GET /v1/settings/events`）。
private struct SettingsAuditEventItem: Identifiable, Equatable {
    let id: String
    let ts: Double
    let actor: String
    let runID: String?
    let action: String
    let key: String
    let beforeSummary: String
    let afterSummary: String
    let revokes: String?

    var isAgentActor: Bool { actor == "agent" }
    var isRevokeEvent: Bool { action == "revoke" }

    var actionLabel: String {
        switch action {
        case "set": return "修改配置"
        case "register": return "注册设置项"
        case "delete": return "删除覆盖"
        case "revoke": return "撤销回滚"
        default: return action
        }
    }
}

/// AI 设置变更审计与一键撤销页（对接服务端已在役的 `/v1/settings/events` 与 `/v1/settings/revoke`）：
/// 兑现「AI 自治必须白名单 + 可审计 + 主人随时一键撤销」的大厂治理闭环。
struct AISettingsAuditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case agentOnly = "仅 AI 变更"
        case revoked = "撤销记录"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var events: [SettingsAuditEventItem] = []
    @State private var isLoading = false
    @State private var revokingID: String?
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    private var revokedTargetIDs: Set<String> {
        Set(events.compactMap(\.revokes))
    }

    private var filteredEvents: [SettingsAuditEventItem] {
        switch filter {
        case .all:
            return events
        case .agentOnly:
            return events.filter { $0.isAgentActor && !$0.isRevokeEvent }
        case .revoked:
            return events.filter { $0.isRevokeEvent }
        }
    }

    private var agentMutationCount: Int {
        events.filter { $0.isAgentActor && !$0.isRevokeEvent }.count
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "checkmark.shield.fill",
                tint: Palette.tintGreenInk,
                title: "AI 变更审计与撤销",
                subtitle: "只追加记录 AI 与主人对设置注册表的每一次写入；支持随时一键追加补偿事件无损回滚，绝不修改历史。",
                statusText: events.isEmpty ? "暂无变更" : "AI 变更 \(agentMutationCount) 次",
                statusTone: agentMutationCount > 0 ? .warning : .healthy
            )

            Section {
                Picker("筛选范围", selection: $filter) {
                    ForEach(Filter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            if let errorMessage {
                Section {
                    InlineError(errorMessage)
                }
            }

            if let noticeMessage {
                Section {
                    Text(noticeMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                if isLoading && events.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        ProgressView()
                        Text("正在读取服务端设置审计日志…")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                } else if filteredEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("暂无匹配的审计记录")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("当 AI 经白名单通道（settings_admin）调整可逆配置时，每条变更都会实时落盘在此处。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(filteredEvents) { item in
                        eventRow(item)
                    }
                }
            } header: {
                SettingsSectionHeader("变更时间线（最新在前）")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .animation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion), value: filter)
        .navigationTitle("AI 变更审计")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadEvents() }
        .task { await loadEvents() }
    }

    private func eventRow(_ item: SettingsAuditEventItem) -> some View {
        let alreadyRevoked = revokedTargetIDs.contains(item.id)
        let canRevoke = !item.isRevokeEvent && !alreadyRevoked

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SettingsStatusPill(
                    text: item.isAgentActor ? "AI 变更" : "主人操作",
                    tone: item.isAgentActor ? .warning : .neutral
                )
                Text(item.actionLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Text(Date(timeIntervalSince1970: item.ts), style: .relative)
                    .font(.caption)
                    .foregroundStyle(Palette.inkMuted)
            }

            Text(item.key)
                .font(.metaMonospaced)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Text("\(item.beforeSummary) → \(item.afterSummary)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(item.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Palette.inkMuted)
                if let revokes = item.revokes {
                    Text("· 回滚了 \(revokes)")
                        .font(.caption2)
                        .foregroundStyle(Palette.successText)
                }
                Spacer()
                if alreadyRevoked {
                    Text("已撤销")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.inkMuted)
                } else if canRevoke {
                    Button {
                        Task { await revoke(eventID: item.id) }
                    } label: {
                        if revokingID == item.id {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("一键撤销")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.danger)
                    .controlSize(.mini)
                    .disabled(revokingID != nil)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadEvents() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: config.endpoint("/v1/settings/events?limit=100"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await OneDayNetworkTransport.shared.standardSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "服务端暂未开启设置审计接口（需 hermes-deploy ≥ 2.5.0）。"
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawList = json["data"] as? [[String: Any]] else {
                events = []
                return
            }
            let parsed = rawList.compactMap { dict -> SettingsAuditEventItem? in
                guard let id = dict["id"] as? String,
                      let key = dict["key"] as? String,
                      let action = dict["action"] as? String else { return nil }
                return SettingsAuditEventItem(
                    id: id,
                    ts: (dict["ts"] as? Double) ?? 0,
                    actor: (dict["actor"] as? String) ?? "unknown",
                    runID: dict["run_id"] as? String,
                    action: action,
                    key: key,
                    beforeSummary: Self.summarize(dict["before"]),
                    afterSummary: Self.summarize(dict["after"]),
                    revokes: dict["revokes"] as? String
                )
            }
            events = parsed.reversed()
        } catch {
            errorMessage = "读取审计日志失败：\(error.localizedDescription)"
        }
    }

    private func revoke(eventID: String) async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        revokingID = eventID
        errorMessage = nil
        noticeMessage = nil
        defer { revokingID = nil }

        var request = URLRequest(url: config.endpoint("/v1/settings/revoke"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["event_id": eventID])

        do {
            let (data, response) = try await OneDayNetworkTransport.shared.standardSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                errorMessage = msg ?? "撤销失败，请稍后重试。"
                Haptics.error()
                return
            }
            noticeMessage = "已成功追加补偿事件，回滚变更 \(eventID)。"
            Haptics.success()
            await loadEvents()
        } catch {
            errorMessage = "撤销请求异常：\(error.localizedDescription)"
            Haptics.error()
        }
    }

    private static func summarize(_ raw: Any?) -> String {
        guard let raw, !(raw is NSNull) else { return "空" }
        if let b = raw as? Bool { return b ? "true" : "false" }
        if let s = raw as? String { return s.isEmpty ? "\"\"" : s }
        if let n = raw as? NSNumber { return n.stringValue }
        if let data = try? JSONSerialization.data(withJSONObject: raw),
           let str = String(data: data, encoding: .utf8) {
            return str.count > 48 ? String(str.prefix(48)) + "…" : str
        }
        return String(describing: raw)
    }
}
