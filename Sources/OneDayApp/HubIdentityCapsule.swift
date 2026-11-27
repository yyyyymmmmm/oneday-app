import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 中间身份标识：头像上置，姓名胶囊紧贴头像下缘，可选活动单行。
struct HubIdentityCapsule: View {
    var displayName: String
    var avatar: Image? = nil
    /// §名下状态行改造：当前活动短语（工具执行中优先）
    var liveActivityPhrase: String? = nil
    var onOpenHub: () -> Void
    var onFindInConversation: (() -> Void)? = nil
    var onForkSession: (() -> Void)? = nil

    private var effectiveActivityText: String? {
        if let liveActivityPhrase, !liveActivityPhrase.isEmpty {
            return liveActivityPhrase
        }
        return nil
    }

    var body: some View {
        if let onFindInConversation {
            capsuleButton
                .accessibilityAction(named: "在对话中查找") {
                    onFindInConversation()
                }
        } else {
            capsuleButton
        }
    }

    private var capsuleButton: some View {
        VStack(spacing: -OneDayMetrics.spacingXS) {
            if let avatar {
                Button {
                    onOpenHub()
                } label: {
                    avatar
                        .resizable()
                        .scaledToFill()
                        .frame(width: OneDayMetrics.avatarChatHero, height: OneDayMetrics.avatarChatHero)
                        .clipShape(Circle())
                        .glassEffect(.regular, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.odPressable)
                .accessibilityHidden(true)
            }

            Button {
                onOpenHub()
            } label: {
                VStack(alignment: .center, spacing: 1) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let activityText = effectiveActivityText {
                        Text(activityText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.spacingXS)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(.regular, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel(
                effectiveActivityText.map { "\(displayName)，\($0)，打开枢纽" }
                    ?? "\(displayName)，打开枢纽"
            )
            .accessibilityIdentifier("topbar.identityCapsule")
        }
        .contextMenu {
            Button {
                onOpenHub()
            } label: {
                Label("打开枢纽", systemImage: "person.crop.circle")
            }
            if let onFindInConversation {
                Button {
                    onFindInConversation()
                } label: {
                    Label("在对话中查找", systemImage: "magnifyingglass")
                }
            }
            if let onForkSession {
                Button {
                    onForkSession()
                } label: {
                    Label("克隆分支会话", systemImage: "arrow.triangle.branch")
                }
            }
        }
    }
}
