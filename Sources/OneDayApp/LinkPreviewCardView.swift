import LinkPresentation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 链接预览卡（按 Muse/iMessage 通行做法）：
/// 左侧站点图标、中间标题＋域名、右上角 ✕ 移除预览。
/// 用 LPLinkView 渲染富媒体卡片（iOS 原生 LinkPresentation）
struct LinkPreviewCardView: View {
    let metadata: LPLinkMetadata
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            LinkPreviewNativeView(metadata: metadata)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除链接预览")
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// LPLinkView 包装为 SwiftUI（UIViewRepresentable）：
/// iOS 原生链接预览渲染，自动适配明暗主题、布局
private struct LinkPreviewNativeView: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        let linkView = LPLinkView(metadata: metadata)
        // 移除默认的背景（我们在外层加卡片样式）
        linkView.backgroundColor = .clear
        return linkView
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {
        // LPLinkView 的 metadata 只在初始化时设置，
        // 变化时需要重建视图（SwiftUI 的 id 机制处理）
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: LPLinkView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: size.height)
    }
}
