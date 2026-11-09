import OneDayCore
import OneDayDesign
import SwiftUI

/// 思考（reasoning）折叠单元（0.5.1，DESIGN-V4 §32；
/// B 案拆解清单 4.5 照改，对照 Fullmoon／Enchanted 两
/// 家成型单元的共同形态）：
/// - 流式期：恒展开——标题「思考中 · Ns」实时计时，
///   思考原文以次级色＋左竖线呈现（草稿文本走纯 Text，
///   半截 Markdown 语法不进解析器）；
/// - 落盘后：默认折叠，标题「已思考 · 约 Ns」，点按
///   展开/收起（系统 Button＋系统动画，无自绘控件）。
/// 标题与展开口径走 OneDayCore.ReasoningPresentation
/// 纯函数（单测把守）；色走 Palette 次级口径字面钉死，
/// 不新开颜色；左界与气泡正文对齐（bubblePaddingH）。
struct ReasoningBlock: View {
    /// 思考原文（已发布快照或落盘全文）
    let text: String
    /// 落盘实测思考耗时（秒）；流式期传 nil
    let seconds: Double?
    /// 是否正在流式生成（流式期恒展开、标题走计时）
    let isStreaming: Bool
    /// 流式开始时刻（计时现算用）；落盘态不用
    var startedAt: Date? = nil

    @State private var expanded = false

    private var showsText: Bool {
        ReasoningPresentation.showsText(
            isStreaming: isStreaming, expanded: expanded
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            header
            if showsText, !text.isEmpty {
                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 2)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .textSelection(.disabled)
                }
            }
        }
        .padding(.leading, OneDayMetrics.bubblePaddingH)
    }

    @ViewBuilder
    private var header: some View {
        if isStreaming {
            TimelineView(.periodic(from: startedAt ?? Date(), by: 0.5)) { context in
                headerLabel(
                    title: ReasoningPresentation.header(
                        isStreaming: true,
                        seconds: nil,
                        elapsed: startedAt.map {
                            context.date.timeIntervalSince($0)
                        }
                    ),
                    chevron: nil
                )
            }
        } else {
            Button {
                withAnimation(.default) { expanded.toggle() }
            } label: {
                headerLabel(
                    title: ReasoningPresentation.header(
                        isStreaming: false,
                        seconds: seconds,
                        elapsed: nil
                    ),
                    chevron: expanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                expanded ? "收起思考过程" : "展开思考过程"
            )
        }
    }

    private func headerLabel(title: String, chevron: String?) -> some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            Image(systemName: "brain")
                .font(.footnote)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            if let chevron {
                Image(systemName: chevron)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
