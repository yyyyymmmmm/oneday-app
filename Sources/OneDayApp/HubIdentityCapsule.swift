import OneDayCore
import OneDayDesign
import SwiftUI

/// 身份胶囊（紧凑大厂 44–52pt 单行顶栏版）：
/// 支持可选内嵌 28pt 头像与状态圆点，聊天页与内容页共用同一胶囊，
/// 让全 App 四主屏保持统一高度与 iOS 26 原生顶部朦胧位置。
struct HubIdentityCapsule: View {
    var displayName: String
    var statusWord: String?
    var needsApproval: Bool = false
    var avatar: Image? = nil
    var statusColor: Color? = nil
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
                            .frame(width: 34, height: 34)
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
                    .frame(
                        width: HeaderButtonSpec.diameter,
                        height: HeaderButtonSpec.diameter
                    )
                    .glassEffect(.regular, in: Circle())
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
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
