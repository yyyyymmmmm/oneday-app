import OneDayDesign
import OneDayCore
import SwiftUI

/// 主线会话详情页：状态、智能体、可复制会话 ID、认领记录与直达续聊
struct MainSessionView: View {
    @Environment(AppState.self) private var appState
    var onRequestChat: (() -> Void)?
    var onClose: (() -> Void)?

    private var isLinked: Bool {
        if case .ready = appState.sessionLedger.mainSendGate() {
            return true
        }
        return false
    }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "link.circle.fill",
                tint: .teal,
                title: appState.agentDisplayName,
                subtitle: "与你的主线智能体保持长期连续上下文与跨端历史同步。",
                statusText: isLinked ? "已链接" : "未链接",
                statusTone: isLinked ? .healthy : .warning
            )

            Section {
                SettingsValueRow(
                    symbol: "person.crop.circle",
                    tint: .blue,
                    title: "智能体",
                    value: appState.agentDisplayName
                )
                if let sessionID = appState.sessionLedger.mainServerSessionID {
                    SettingsValueRow(
                        symbol: "number",
                        tint: .indigo,
                        title: "会话 ID",
                        value: sessionID,
                        monospaced: true,
                        copyable: true
                    )
                }
                if let sync = appState.sessionLedger.mainSyncStatus {
                    SettingsValueRow(
                        symbol: "arrow.triangle.2.circlepath",
                        tint: .teal,
                        title: "历史同步",
                        value: syncStatusText(sync)
                    )
                }
                if let note = appState.sessionLedger.localStateReadFailureNote {
                    SettingsValueRow(
                        symbol: "exclamationmark.triangle",
                        tint: .orange,
                        title: "本地状态",
                        value: note
                    )
                }
            } header: {
                SettingsSectionHeader("会话信息")
            } footer: {
                if !isLinked, let error = appState.sessionLedger.mainLinkLastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if let record = appState.sessionLedger.mainClaimRecord {
                Section {
                    SettingsValueRow(
                        symbol: "doc.text",
                        tint: .gray,
                        title: "认领会话",
                        value: record.sessionID,
                        monospaced: true,
                        copyable: true
                    )
                    SettingsValueRow(
                        symbol: "bubble.left.and.bubble.right",
                        tint: .blue,
                        title: "消息数",
                        value: record.messageCount.map { "\($0) 条" } ?? "未知"
                    )
                    if let activity = record.lastActivityAt {
                        SettingsValueRow(
                            symbol: "clock",
                            tint: .indigo,
                            title: "最近活动",
                            value: Self.activityText(activity)
                        )
                    }
                    if record.candidateCount > 1 {
                        SettingsValueRow(
                            symbol: "list.number",
                            tint: .orange,
                            title: "同名候选",
                            value: "\(record.candidateCount) 条（已自动选定）"
                        )
                    }
                    if record.isArchived {
                        SettingsValueRow(
                            symbol: "archivebox",
                            tint: .secondary,
                            title: "归档态",
                            value: "已归档（打开时自动解档）"
                        )
                    }
                    SettingsValueRow(
                        symbol: "checkmark.seal",
                        tint: .green,
                        title: "认领时间",
                        value: Self.activityText(record.claimedAt)
                    )
                } header: {
                    SettingsSectionHeader("认领记录")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            Section {
                Button {
                    Task {
                        await appState.sessionLedger.rediscoverMainline(appState: appState)
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        IconTile(symbol: "arrow.clockwise", color: Palette.primary, size: OneDayMetrics.iconSlot)
                        Text("重新发现主线")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Button {
                    onClose?()
                    onRequestChat?()
                } label: {
                    HStack {
                        Spacer()
                        Label("继续主线对话", systemImage: "bubble.left.and.text.bubble.right.fill")
                            .font(.rowTitleL.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.primary)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("主会话")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncStatusText(_ sync: MainSyncStatus) -> String {
        if sync.historyUnsynced {
            return "补齐中 · "
                + SessionHistorySync.progressText(
                    loaded: sync.historyLoaded,
                    serverTotal: sync.historyTotal
                )
        }
        switch sync.seedState {
        case .syncedTextOnly:
            return "已同步（本地仅文本）"
        case .localOnly:
            return "部分仅保存在本机"
        case .failed:
            return "同步失败，稍后重试"
        case .pending, .importing:
            return "正在同步…"
        case .notOwed, .serverHeld:
            return "已同步"
        }
    }

    private static func activityText(_ epoch: TimeInterval) -> String {
        Date(timeIntervalSince1970: epoch)
            .formatted(date: .abbreviated, time: .shortened)
    }
}
