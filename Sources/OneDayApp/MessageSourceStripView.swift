import OneDayCore
import OneDayDesign
import SwiftUI

/// 来源条（D4，§349）：定稿气泡下方的轮级来源清
/// 单——同轮 web_search/web_extract 工具卡的来源
/// 经 Core WebSourceExtractor 提取、TurnSource-
/// Aggregation 按轮聚合（呈现层派生、不落盘：数
/// 据源恒是工具行原文单源，旧会话回放天然有条）。
/// 形态学活动线同族（ToolCardView 活动线）：头行
/// 一线小字、左界与气泡正文对齐、点开成列、点行
/// 开链接。与工具卡分工：工具卡是单次调用的排障
/// 原始面（参数/结果全文），来源条是整轮的聚合
/// 清单（标题/域名/链接），数据同源、面向不同。
/// 行高由合成器 sourceStripHeight 同口径定价
/// （头行 minTapTarget、展开逐行 footnote 一行
/// ＋spacingXS 间隔），拟合测试钉住两态
struct MessageSourceStripView: View {
    let sources: [MessageSource]
    /// §329 行状态账本：展开态存账本——行高合成
    /// 器须看得见（展开即重测高）；无账本环境回
    /// 落本地 @State、行为不变
    var expansionKey: String? = nil
    var ledger: ChatRowStateLedger? = nil
    @State private var localExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private var expanded: Bool {
        if let ledger, let expansionKey {
            return ledger.expansionOverride(
                for: expansionKey
            ) ?? false
        }
        return localExpanded
    }

    private func setExpanded(_ value: Bool) {
        if let ledger, let expansionKey {
            ledger.setExpansion(value, for: expansionKey)
        } else {
            localExpanded = value
        }
    }

    private var headerText: String {
        L10n.format("来源 · %lld", sources.count)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: OneDayMetrics.spacingXS
        ) {
            header
            if expanded {
                ForEach(sources) { source in
                    sourceRow(source)
                }
            }
        }
        .padding(.leading, OneDayMetrics.bubblePaddingH)
    }

    /// 头行一线：字形＋计数标题＋首个域名＋展开向
    /// 箭头；命中域纵向补到 minTapTarget（与活动
    /// 线头行同式：视觉一行、命中 44）
    private var header: some View {
        Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap,
                    reduceMotion: reduceMotion
                )
            ) {
                setExpanded(!expanded)
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "globe")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text(headerText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let first = sources.first {
                    Text(first.host)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(
                    systemName: expanded
                        ? "chevron.down" : "chevron.right"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(headerText)
        .accessibilityHint(expanded ? "收起详情" : "展开详情")
    }

    /// 来源行：标题一行截断＋域名小字；点行经系
    /// 统 openURL 开链接（浏览器/通用链接由系统
    /// 路由，本面不自建网页承载）
    private func sourceRow(_ source: MessageSource) -> some View {
        Button {
            if let url = URL(string: source.url) {
                openURL(url)
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "globe")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                Text(source.title)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(source.host)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(source.title)
    }
}
