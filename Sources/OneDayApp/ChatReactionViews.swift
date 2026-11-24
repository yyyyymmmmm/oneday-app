import OneDayCore
import OneDayDesign
import SwiftUI

/// 反应几何单源（台账 187）：pill 高 28、压气泡底
/// 角半身悬出（悬出净深 14）、行高为悬出再留 2pt
/// 呼吸共预留 16——呈现（本文件 pill 与 ChatView
/// 两支的 overlay 偏移）与行高合成器（ChatNative-
/// RowHeight.reactionReserve）同读本匣，不许两处
/// 各写一份数字（§329 行高单权威的 facet 纪律：
/// 预留与实际悬出必须逐值同源，差一像素即行高与
/// 渲染打架）
enum ChatReactionMetrics {
    static let pillHeight: CGFloat = 28
    static let hangDepth: CGFloat = 14
    static let rowReserve: CGFloat = 16
    /// pill 沿气泡底边向内让位（不贴死角）
    static let cornerInset: CGFloat = 8
    /// AI 角标高（§432）：比 pill 矮一档的小角标；
    /// 悬出仍走 hangDepth（挂载 offset 与 pill 同
    /// 值），rowReserve 预留口径不变、不另立数字
    static let badgeHeight: CGFloat = 24
}

/// 反应 pill（台账 187，照 OpenBot 气泡底角形态）：
/// 悬挂于气泡底角·朝中线侧（§334 正名：AI 行右
/// 下、用户行左下；挂载点在 ChatView 两支的
/// overlay）；面色走既有 surface 令
/// 牌、描边走页面底色（在气泡上切出悬挂感）、色
/// 调与 184 气泡档同源（自己的段以 primaryTint 轻
/// 染标示）。自己的段可点撤回（走 ChatView.apply-
/// Reaction 单写口）。§432 起本 pill 只承自己的
/// 段：助手段改走 AgentReactionBadgeView 角标
/// （分工见彼处），不再合并进本 pill
struct ReactionPillView: View {
    let reactions: [MessageReaction]
    /// 点自己的段（撤回自己的反应）
    let onClearOwn: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(
                Array(reactions.enumerated()),
                id: \.offset
            ) { _, reaction in
                segment(reaction)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: ChatReactionMetrics.pillHeight)
        .background(
            Palette.surface, in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                Palette.pageBG, lineWidth: 1.5
            )
        }
        .shadow(
            color: .black.opacity(0.10), radius: 4, y: 1
        )
    }

    @ViewBuilder
    private func segment(
        _ reaction: MessageReaction
    ) -> some View {
        if reaction.isOwn {
            Button(action: onClearOwn) {
                Text(reaction.emoji)
                    .font(.system(size: 14))
                    .padding(.horizontal, OneDayMetrics.spacingXS)
                    .background(
                        Palette.primaryTint, in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                L10n.format(
                    "你的反应：%@，点按撤回", reaction.emoji
                )
            )
        } else {
            Text(reaction.emoji)
                .font(.system(size: 14))
                .padding(.horizontal, OneDayMetrics.spacingXS)
                .accessibilityLabel(
                    L10n.format("助手反应：%@", reaction.emoji)
                )
        }
    }
}

/// AI 反应角标（DESIGN §432）：助手给用户消息贴
/// 的反应（author="agent"，服务端终态 attach 到
/// 本轮触发的用户消息行）——悬挂于用户气泡底角
/// 的小角标：单个 emoji、无计数、不可点（无任何
/// 手势，用户不能摘助手的反应，施工图 §4 口
/// 径）。与 ReactionPillView 分工：pill 只承用户
/// 自己的段（可点撤回），角标只承助手段，两面
/// 异位同角并排、永不合并计数。在场判定走 Core
/// AISelfReactionDecision.badgeEmoji（开关关＝不
/// 在场）；几何与 pill 同源（surface 面色、页面
/// 底色描边、同影），只高度矮一档
struct AgentReactionBadgeView: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.system(size: 13))
            .padding(.horizontal, 6)
            .frame(height: ChatReactionMetrics.badgeHeight)
            .background(
                Palette.surface, in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    Palette.pageBG, lineWidth: 1.5
                )
            }
            .shadow(
                color: .black.opacity(0.10), radius: 4, y: 1
            )
            .accessibilityLabel(
                L10n.format("助手反应：%@", emoji)
            )
    }
}
