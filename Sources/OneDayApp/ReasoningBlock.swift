import OneDayCore
import OneDayDesign
import SwiftUI

/// 思考（reasoning）折叠单元（0.5.1 立，DESIGN-V4 §32；
/// 0.20.0 按用户 2026-11-09 23:36 硬规格重做呈现层）：
///
/// - **有界容器**：正文区限高 ReasoningPresentation
///   .maxBodyHeight（240pt，约视高三分之一），区内独
///   立滚动；思考再长也不许把答案与输入舱顶出屏外、
///   不许整屏霸占（旧形态纯 Text 无界平铺、长思考整
///   屏铺开且透到输入舱之下，用户斥为低级错误）。
/// - **相位默认态**（Core ReasoningPresentation
///   .defaultExpanded 把守）：纯思考期默认展开（流式
///   跟随最新一行：bottom 锚＋顶部渐隐）；正文起流
///   后自动收起；本轮结束/落盘/历史载入恒默认收起
///   为一行「已思考 · 约 Ns」＋chevron。
/// - **两态可点**：标题恒为按钮，用户点按随时展开/
///   收起，覆盖态优先于相位默认、本视图生命周期内
///   保持（旧形态流式期标题非按钮、点不动）。
/// - 排版：footnote 小一号＋次级色（Palette
///   .inkSecondary），与工具卡的折叠同为「头行＋点按
///   展开」一族（同构口径：头行 Button＋.default 系
///   统动画，不自绘曲线）；左界与气泡正文对齐
///   （bubblePaddingH），左竖线沿容器高。
/// - 流式打字 blur 渐显纪律（§14 条 4）在正文泡侧、
///   不在本单元：思考原文是草稿文本、走纯 Text 不进
///   Markdown 解析（0.5.1 口径沿用）。
struct ReasoningBlock: View {
    /// 思考原文（已发布快照或落盘全文）
    let text: String
    /// 落盘实测思考耗时（秒）；流式期传 nil
    let seconds: Double?
    /// 是否正在流式生成
    let isStreaming: Bool
    /// 流式开始时刻（计时现算用）；落盘态不用
    var startedAt: Date? = nil
    /// 正文（或工具卡）是否已开始产出（0.20.0 相位入
    /// 参）：流式行由 ChatView 按已发布正文/工具卡现
    /// 算；落盘条目恒 false（相位由 isStreaming 决定）
    var contentStarted: Bool = false

    /// 用户点按覆盖（nil＝跟相位默认）：一旦点按，本
    /// 轮内不再被相位自动收/展覆盖
    @State private var userOverride: Bool?

    private var phase: ReasoningPhase {
        guard isStreaming else { return .finished }
        return contentStarted ? .contentStarted : .streaming
    }

    private var expanded: Bool {
        userOverride
            ?? ReasoningPresentation.defaultExpanded(phase: phase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            header
            if expanded, !text.isEmpty {
                bodyRegion
            }
        }
        .padding(.leading, OneDayMetrics.bubblePaddingH)
    }

    /// 有界正文区：限高＋区内滚动（系统 ScrollView）；
    /// 流式期 bottom 锚跟随最新一行＋顶部渐隐罩（内容
    /// 在罩下化开、不硬切），落盘展开 top 锚从头读
    private var bodyRegion: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 2)
            ScrollView {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxHeight: CGFloat(
                    ReasoningPresentation.maxBodyHeight
                )
            )
            .defaultScrollAnchor(isStreaming ? .bottom : .top)
            .overlay(alignment: .top) {
                if isStreaming {
                    LinearGradient(
                        colors: [
                            Palette.chatSurface,
                            Palette.chatSurface.opacity(0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    /// 标题行（0.20.0 起两态恒为按钮）：流式期实时计
    /// 时（TimelineView 现算）；点按翻转覆盖态，动画
    /// 走系统 .default（与工具卡折叠同口径、不自绘）
    private var header: some View {
        Button {
            withAnimation(.default) {
                userOverride = !expanded
            }
        } label: {
            if isStreaming {
                TimelineView(
                    .periodic(from: startedAt ?? Date(), by: 0.5)
                ) { context in
                    headerLabel(
                        title: ReasoningPresentation.header(
                            isStreaming: true,
                            seconds: nil,
                            elapsed: startedAt.map {
                                context.date.timeIntervalSince($0)
                            }
                        ),
                        chevron: expanded ? "chevron.up" : "chevron.down"
                    )
                }
            } else {
                headerLabel(
                    title: ReasoningPresentation.header(
                        isStreaming: false,
                        seconds: seconds,
                        elapsed: nil
                    ),
                    chevron: expanded ? "chevron.up" : "chevron.down"
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            expanded ? "收起思考过程" : "展开思考过程"
        )
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
