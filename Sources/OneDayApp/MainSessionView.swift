import OneDayDesign
import OneDayCore
import SwiftUI

/// 主线会话详情页（prototype-2，DESIGN §164 升级监工纠正②）：
/// 真数据接线——状态派生自 mainSessionStatusText、智能体名走
/// displayName、会话 ID 可复制、继续对话复用现行关设置＋切聊天格
struct MainSessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 关闭设置并切聊天格（ContentView 注入）
    var onRequestChat: (() -> Void)?
    var onClose: (() -> Void)?
    @State private var showCopyToast = false

    var body: some View {
        List {
            Section {
                // 状态行
                LabeledContent {
                    Text(statusText)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                } label: {
                    Text("状态")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .listRowBackground(Palette.surface)

                // 智能体行
                LabeledContent {
                    Text(appState.agentDisplayName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                } label: {
                    Text("智能体")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .listRowBackground(Palette.surface)

                // 会话 ID 行（§331：id 已知即已链接类
                // 呈现——种子位退出显形条件）
                if let sessionID = appState.sessionLedger.mainServerSessionID {
                    LabeledContent {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Text(sessionID)
                                .font(.metaMonospaced)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Button {
                                UIPasteboard.general.string = sessionID
                                showCopyToast = true
                                Haptics.success()
                            } label: {
                                Text("复制")
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.primary)
                            }
                        }
                    } label: {
                        Text("会话 ID")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .listRowBackground(Palette.surface)
                }

                // 历史同步行（§331）：回补/种子的记账
                // 快照如实呈现——已齐/补齐中（带进度）/
                // 仅文本/仅本地/失败待重试；无快照（本
                // 进程还没跑过同步动作）不出现本行
                if let sync = appState.sessionLedger.mainSyncStatus {
                    LabeledContent {
                        Text(syncStatusText(sync))
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("历史同步")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .listRowBackground(Palette.surface)
                }

                // 本地状态读取失败提示（§332）：侧账解
                // 码失败的明示位——不复用链接错误行
                // （那是链接链的账）；自愈对账完成后
                // 本行自动消失，诊断痕留底可查
                if let note = appState.sessionLedger
                    .localStateReadFailureNote {
                    LabeledContent {
                        Text(note)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("本地状态")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .listRowBackground(Palette.surface)
                }
            } header: {
                Text("会话信息")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            }
            .listRowInsets(settingsRowInsets)

            // 认领记录（§330）：认领到哪条如实呈现——
            // 会话/消息数/最近活动/归档态/认领时间；未
            // 认领过不出现本节
            if let record = appState.sessionLedger.mainClaimRecord {
                Section {
                    LabeledContent {
                        Text(record.sessionID)
                            .font(.metaMonospaced)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } label: {
                        Text("认领会话")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .listRowBackground(Palette.surface)

                    LabeledContent {
                        Text(
                            record.messageCount
                                .map { "\($0) 条" } ?? "未知"
                        )
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    } label: {
                        Text("消息数")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .listRowBackground(Palette.surface)

                    if let activity = record.lastActivityAt {
                        LabeledContent {
                            Text(Self.activityText(activity))
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                        } label: {
                            Text("最近活动")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        .listRowBackground(Palette.surface)
                    }

                    if record.candidateCount > 1 {
                        LabeledContent {
                            Text("\(record.candidateCount) 条（已按规则选定）")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                        } label: {
                            Text("同名候选")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        .listRowBackground(Palette.surface)
                    }

                    if record.isArchived {
                        LabeledContent {
                            Text("已归档（打开主线时解档）")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                        } label: {
                            Text("归档态")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        .listRowBackground(Palette.surface)
                    }

                    LabeledContent {
                        Text(Self.activityText(record.claimedAt))
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    } label: {
                        Text("认领时间")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .listRowBackground(Palette.surface)
                } header: {
                    Text("认领记录")
                        .font(.sectionLabel)
                        .foregroundStyle(Palette.inkSecondary)
                        .textCase(nil)
                }
                .listRowInsets(settingsRowInsets)
            }

            // 重新发现（§330）：手动向服务端目录重新
            // 认领——绑定接错/服务端换代时的恢复入口，
            // 结果经状态行与认领记录呈现
            Section {
                Button {
                    Task {
                        await appState.sessionLedger
                            .rediscoverMainline(appState: appState)
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("重新发现主线")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(settingsRowInsets)
            }

            // 继续对话按钮
            Section {
                Button {
                    onClose?()
                    onRequestChat?()
                } label: {
                    HStack {
                        Spacer()
                        Text("继续主线对话")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.surface)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .listRowBackground(Palette.primary)
                .listRowInsets(settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("主线对话")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottom) {
            if showCopyToast {
                Text("会话 ID 已复制")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.surface)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .background(
                        Capsule()
                            .fill(Palette.ink.opacity(0.9))
                    )
                    .padding(.bottom, OneDayMetrics.spacingL)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation(
                                MotionTokens.resolved(
                                    MotionTokens.systemDefault, reduceMotion: reduceMotion
                                )
                            ) {
                                showCopyToast = false
                            }
                        }
                    }
            }
        }
    }

    /// 主线会话状态文案（§331 改判：链接态只认 id
    /// 已知——与发送闸 mainSendGate 同口径；种子/
    /// 回补的细分状态走「历史同步」行，不挤状态行）
    private var statusText: String {
        let store = appState.sessionLedger
        if case .ready = store.mainSendGate() {
            return "已链接"
        }
        if let error = store.mainLinkLastError {
            return "未链接 · \(error)"
        }
        return "未链接（打开聊天页或发送时自动链接）"
    }

    /// 历史同步快照 → 人话（§331）：未同步完优先报
    /// 进度；种子态其次（仅文本/仅本地/失败/同步
    /// 中）；全清＝已同步
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
            return "已同步（本地历史仅文本）"
        case .localOnly:
            return "部分本地历史仅保存在本机"
        case .failed:
            return "本地历史同步失败，稍后自动重试"
        case .pending, .importing:
            return "本地历史同步中…"
        case .notOwed, .serverHeld:
            return "已同步"
        }
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }

    /// epoch 秒 → 人话时刻（认领记录行用）
    private static func activityText(_ epoch: TimeInterval) -> String {
        Date(timeIntervalSince1970: epoch)
            .formatted(date: .abbreviated, time: .shortened)
    }
}
