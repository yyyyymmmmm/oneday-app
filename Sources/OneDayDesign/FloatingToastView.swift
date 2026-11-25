import SwiftUI

/// iOS 26 顶部悬浮液态玻璃胶囊 Toast（大厂成熟形态，取代笨重全宽横幅）：
/// 悬浮于内容上方、不参与底部输入栏布局流（杜绝输入框跳动）；
/// 支持信息/错误两种语义色、可选动作按钮与上滑即消。
public struct FloatingToastView: View {
    public enum Tone: Equatable {
        case info
        case error
    }

    private let message: String
    private let tone: Tone
    private let actionTitle: String?
    private let onAction: (() -> Void)?
    private let onDismiss: () -> Void

    @State private var dragOffsetY: CGFloat = 0

    public init(
        message: String,
        tone: Tone = .info,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: tone == .error
                  ? "exclamationmark.circle.fill"
                  : "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone == .error ? Palette.danger : Palette.primary)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let actionTitle, let onAction {
                Button(actionTitle) {
                    onAction()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.primary)
                .buttonStyle(.plain)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .padding(.leading, OneDayMetrics.spacingM)
        .padding(.trailing, OneDayMetrics.spacingS)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .offset(y: min(0, dragOffsetY))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffsetY = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -24 {
                        onDismiss()
                    } else {
                        withAnimation(.snappy(duration: 0.2)) {
                            dragOffsetY = 0
                        }
                    }
                }
        )
        .accessibilityElement(children: .combine)
    }
}
