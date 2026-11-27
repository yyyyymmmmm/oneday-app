import OneDayCore
import OneDayDesign
import SwiftUI

/// 身份胶囊（紧凑大厂 44–52pt 单行顶栏版）：
/// 支持可选内嵌 28pt 头像与状态圆点，聊天页与内容页共用同一胶囊，
/// 让全 App 四主屏保持统一高度与 iOS 26 原生顶部朦胧位置。
/// §名下状态行改造（2026-11-27）：名胶囊下增「当前活动」
/// 一行——优先显示 liveActivityPhrase（工具短语），无时
/// 回落 connectionStatusWord（连接状态词），nil 不占位
struct HubIdentityCapsule: View {
    var displayName: String
    var statusWord: String?
    var needsApproval: Bool = false
    var avatar: Image? = nil
    var statusColor: Color? = nil
    /// §名下状态行改造：当前活动短语（工具执行中优先）
    var liveActivityPhrase: String? = nil
    /// §名下状态行改造：连接状态词（活动短语无时兜底）
    var connectionStatusWord: String? = nil
    var onOpenHub: () -> Void
    var onFindInConversation: (() -> Void)? = nil
    var onForkSession: (() -> Void)? = nil

    private var effectiveStatusWord: String? {
        if needsApproval {
            return L10n.string("需要批准")
        }
        guard let statusWord, !statusWord.isEmpty else {
            return nil
        }
        return statusWord
    }

    /// §名下状态行改造：当前活动有效值（活动短语优先、
    /// 无时回落连接状态词）
    private var effectiveActivityText: String? {
        if let liveActivityPhrase, !liveActivityPhrase.isEmpty {
            return liveActivityPhrase
        }
        if let connectionStatusWord, !connectionStatusWord.isEmpty {
            return connectionStatusWord
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
        // 2026-11-27：用户亲令改上下排列（头像在上、名字胶囊在下）
        VStack(spacing: 6) {
            if let avatar {
                Button {
                    onOpenHub()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        avatar
                            .resizable()
                            .scaledToFill()
                            .frame(width: Palette.avatarChatHero, height: Palette.avatarChatHero)
                            .clipShape(Circle())
                        if let statusColor {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 9, height: 9)
                                .overlay {
                                    Circle()
                                        .stroke(Palette.surface, lineWidth: 1.5)
                                }
                                .offset(x: 1, y: 1)
                        }
                    }
                    .glassEffect(.regular, in: Circle())
                    )
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
                    if let text = effectiveStatusWord {
                        Text(text)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(
                                needsApproval
                                    ? Palette.primary
                                    : Palette.inkSecondary
                            )
                            .lineLimit(1)
                    }
                    // §名下状态行改造：当前活动行（活动
                    // 短语或连接状态兜底，nil 不占位）
                    if let activityText = effectiveActivityText {
                        Text(activityText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(height: HeaderButtonSpec.diameter)
                .glassEffect(.regular, in: Capsule())
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel(
                effectiveStatusWord.map { "\(displayName)，\($0)，打开枢纽" }
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
