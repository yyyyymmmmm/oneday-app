import SwiftUI
import OneDayCore
import OneDayDesign

/// 消息行（棒 1 + mac-09 补全，对位 #13/#21/#22/#30）：
/// - 对标大厂桌面端排版：助手行浅灰圆角卡（圆角 16pt，最大读宽 740pt），
///   用户行右对齐主色气泡（圆角 16pt）；气泡旁悬停浮出快捷反应/复制条；
/// - 底部悬挂用户反应药丸（可点撤回）与 AI 自反应角标（§432 不可点，受开关门控）；
/// - 助手气泡下方挂接内嵌选项卡（MacOptionsCardView，Core OptionsCardState 单源）。
struct MacMessageRow: View {
    let message: SessionMessage
    let reactions: [MessageReaction]
    let optionsState: OptionsCardState
    let options: [MessageOption]
    let isFindCurrent: Bool
    let isFindMatch: Bool
    let onPickReaction: (String) -> Void
    let onClearOwnReaction: () -> Void
    let onSelectOption: (MessageOption) -> Void

    @AppStorage(ChatReactionsFloatingBarFeature.defaultsKey)
    private var floatingBarEnabled = true
    @AppStorage(ChatReactionsAISelfFeature.defaultsKey)
    private var aiSelfReactionsEnabled = true

    @State private var isHovering = false

    private var canReact: Bool {
        (message.role == "user" || message.role == "assistant")
            && (Int(exactly: message.id) ?? 0) > 0
    }

    private var ownReactions: [MessageReaction] {
        MessageReactions.ownReactions(in: reactions)
    }

    private var agentBadgeEmoji: String? {
        AISelfReactionDecision.badgeEmoji(
            reactions: reactions,
            featureEnabled: aiSelfReactionsEnabled
        )
    }

    private var hasReactionChrome: Bool {
        AISelfReactionDecision.hasVisibleChrome(
            reactions: reactions,
            featureEnabled: aiSelfReactionsEnabled
        )
    }

    var body: some View {
        Group {
            switch message.role {
            case "user":
                userRow
            case "tool":
                toolRow
            default:
                assistantRow
            }
        }
        .padding(.bottom, hasReactionChrome ? 12 : 0)
        .background {
            if isFindCurrent {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.findMatchFill.opacity(0.65))
            } else if isFindMatch {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.findMatchFill.opacity(0.30))
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - 用户行

    private var userRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 60)
            if isHovering && floatingBarEnabled {
                MacMessageHoverBar(
                    canReact: canReact,
                    currentOwnEmoji: MessageReactions.ownEmoji(in: reactions),
                    onPickReaction: onPickReaction,
                    onCopy: copyContent
                )
                .transition(.opacity)
            }
            Text(message.content)
                .font(.system(size: 14))
                .foregroundStyle(Palette.userBubbleText)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Palette.userBubbleFill,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(alignment: .bottomLeading) {
                    if hasReactionChrome {
                        reactionChromeBar
                            .offset(x: 8, y: 14)
                    }
                }
        }
    }

    // MARK: - 助手行（大厂桌面端浅灰卡片＋右侧悬停动作条＋下方选项卡）

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    if let reasoning = reasoningText {
                        DisclosureGroup("思考过程") {
                            Text(reasoning)
                                .font(.callout)
                                .foregroundStyle(Palette.inkSecondary)
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    if !message.toolCalls.isEmpty {
                        ForEach(
                            Array(message.toolCalls.enumerated()),
                            id: \.offset
                        ) { _, call in
                            Label(
                                call.name.isEmpty ? "工具调用" : call.name,
                                systemImage: "wrench.and.screwdriver"
                            )
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    if !message.content.isEmpty {
                        let split = VaultRequestMarker.split(
                            in: message.content
                        )
                        if !split.text.isEmpty {
                            MacMarkdownView(text: split.text)
                        }
                        ForEach(split.requestIDs, id: \.self) { requestID in
                            MacVaultRequestCard(requestID: requestID)
                        }
                    }
                    if !message.attachments.isEmpty {
                        ForEach(
                            Array(message.attachments.enumerated()),
                            id: \.offset
                        ) { _, attachment in
                            Label(
                                attachment.name.isEmpty
                                    ? "附件" : attachment.name,
                                systemImage: "paperclip"
                            )
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 740, alignment: .leading)
                .background(
                    Palette.bubbleFill,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(alignment: .bottomTrailing) {
                    if hasReactionChrome {
                        reactionChromeBar
                            .offset(x: -8, y: 14)
                    }
                }

                if isHovering && floatingBarEnabled {
                    MacMessageHoverBar(
                        canReact: canReact,
                        currentOwnEmoji: MessageReactions.ownEmoji(in: reactions),
                        onPickReaction: onPickReaction,
                        onCopy: copyContent
                    )
                    .transition(.opacity)
                }
                Spacer(minLength: 24)
            }

            if optionsState != .hidden {
                MacOptionsCardView(
                    state: optionsState,
                    options: options,
                    onSelect: onSelectOption
                )
                .padding(.top, hasReactionChrome ? 8 : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 工具行

    private var toolRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(Palette.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.toolName ?? "工具结果")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: 740, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
    }

    // MARK: - 反应铬件条（用户 pill＋AI 自反应角标并排不合并）

    private var reactionChromeBar: some View {
        HStack(spacing: 4) {
            if !ownReactions.isEmpty {
                MacReactionPillView(
                    reactions: ownReactions,
                    onClearOwn: onClearOwnReaction
                )
            }
            if let badge = agentBadgeEmoji {
                MacAgentReactionBadgeView(emoji: badge)
            }
        }
    }

    // MARK: - 右键上下文菜单（含回退反应子菜单）

    @ViewBuilder
    private var contextMenuItems: some View {
        if !message.content.isEmpty {
            Button("复制内容") { copyContent() }
        }
        if canReact {
            Menu("添加反应") {
                ForEach(MessageReactions.palette, id: \.self) { emoji in
                    Button(emoji) {
                        onPickReaction(emoji)
                    }
                }
            }
            if MessageReactions.ownEmoji(in: reactions) != nil {
                Button("撤回我的反应", role: .destructive) {
                    onClearOwnReaction()
                }
            }
        }
    }

    private func copyContent() {
        Pasteboard.copy(message.content)
    }

    private var reasoningText: String? {
        let raw = message.reasoningContent ?? message.reasoning
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines)
                  .isEmpty
        else { return nil }
        return raw
    }
}

/// 未读分隔线（棒 1，对位 #30）：锚点行上方一条
/// 「以下为未读」线，Core UnreadDivider 定锚
struct MacUnreadDividerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.red.opacity(0.6))
                .frame(height: 1)
            Text("以下为未读")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
            Rectangle()
                .fill(Color.red.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}
