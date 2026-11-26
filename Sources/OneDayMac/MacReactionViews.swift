import SwiftUI
import OneDayCore
import OneDayDesign

/// 消息反应视图族（mac-09，对位 #22 / 台账 187 / §432）：
/// 复用 Core MessageReactions / ReactionEmojiCatalog /
/// AISelfReactionDecision 单源——
/// - 用户自己的反应走 MacReactionPillView（点按撤回）
/// - 助手自反应走 MacAgentReactionBadgeView（不可点）
/// - 桌面端悬停浮条 MacMessageHoverBar（照成熟桌面聊
///   天形态：气泡旁浮出 ☺ 表情选择器＋复制钮）
struct MacReactionPillView: View {
    let reactions: [MessageReaction]
    let onClearOwn: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(
                Array(reactions.enumerated()), id: \.offset
            ) { _, reaction in
                if reaction.isOwn {
                    Button(action: onClearOwn) {
                        Text(reaction.emoji)
                            .font(.system(size: 13))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Palette.primaryTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("点击撤回你的反应")
                } else {
                    Text(reaction.emoji)
                        .font(.system(size: 13))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(Palette.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Palette.pageBG, lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

/// AI 自反应角标（§432）：只承 author="agent"，单个
/// emoji、无计数、不可点（用户不能摘助手的反应）
struct MacAgentReactionBadgeView: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(Palette.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Palette.pageBG, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            .help("助手反应")
    }
}

/// 气泡旁桌面悬停动作条（照大厂桌面聊天形态：☺ 表情
/// 反应＋复制正文）：悬停显现，点 ☺ 弹出原生 Popover
/// （8 个常用反应＋「＋」展开完整目录）
struct MacMessageHoverBar: View {
    let canReact: Bool
    let currentOwnEmoji: String?
    let onPickReaction: (String) -> Void
    let onCopy: () -> Void

    @State private var showPicker = false
    @State private var showMore = false

    var body: some View {
        HStack(spacing: 2) {
            if canReact {
                Button {
                    showMore = false
                    showPicker.toggle()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("添加反应")
                .popover(isPresented: $showPicker, arrowEdge: .top) {
                    reactionPopover
                }
            }
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("复制内容")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Palette.surface.opacity(0.95),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                Palette.separator.opacity(0.45), lineWidth: 0.5
            )
        }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var reactionPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(MessageReactions.palette, id: \.self) { emoji in
                    let selected = emoji == currentOwnEmoji
                    Button {
                        showPicker = false
                        onPickReaction(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 18))
                            .frame(width: 30, height: 30)
                            .background(
                                selected ? Palette.primaryTint : Color.clear,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showMore.toggle()
                } label: {
                    Image(systemName: showMore ? "chevron.up" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 28, height: 28)
                        .background(Palette.fillQuaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help(showMore ? "收起更多表情" : "更多表情")
            }

            if showMore {
                Divider()
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(32), spacing: 4),
                            count: 8
                        ),
                        spacing: 4
                    ) {
                        ForEach(
                            ReactionEmojiCatalog.morePalette, id: \.self
                        ) { emoji in
                            Button {
                                showPicker = false
                                onPickReaction(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 18))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        emoji == currentOwnEmoji
                                            ? Palette.primaryTint : Color.clear,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(10)
    }
}
