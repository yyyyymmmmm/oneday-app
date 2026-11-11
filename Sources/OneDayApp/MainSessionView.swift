import OneDayDesign
import OneDayCore
import SwiftUI

/// 主线会话详情页（prototype-2，DESIGN §164 升级监工纠正②）：
/// 真数据接线——状态派生自 mainSessionStatusText、智能体名走
/// displayName、会话 ID 可复制、继续对话复用现行关设置＋切聊天格
struct MainSessionView: View {
    @Environment(AppState.self) private var appState
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

                // 会话 ID 行（已链接时显示）
                if let sessionID = appState.sideChats.mainServerSessionID,
                   appState.sideChats.mainServerConfirmed,
                   appState.sideChats.mainServerSeeded {
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
            } header: {
                Text("会话信息")
                    .font(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .textCase(nil)
            }
            .listRowInsets(settingsRowInsets)

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
        .navigationTitle("主线会话")
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
                            withAnimation {
                                showCopyToast = false
                            }
                        }
                    }
            }
        }
    }

    /// 主线会话状态文案（监工纠正②：复用现行 mainSessionStatusText 逻辑）
    private var statusText: String {
        let store = appState.sideChats
        if store.mainServerConfirmed, store.mainServerSeeded,
           let id = store.mainServerSessionID {
            return "已链接"
        }
        if let error = store.mainLinkLastError {
            return "未链接 · \(error)"
        }
        return "未链接（打开聊天页或发送时自动链接）"
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
