import SwiftUI
import OneDayCore
import OneDayDesign

/// 消息行（棒 1，对位 #13/#30）：用户行右对齐气泡
/// （Design 层用户泡令牌），助手行全宽 Markdown，
/// 工具行紧凑卡（名＋正文摘要），思考行折叠呈现。
/// 查找当前命中行与未读分隔锚由聊天面叠加背景/线。
struct MacMessageRow: View {
    let message: SessionMessage
    let isFindCurrent: Bool
    let isFindMatch: Bool

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
        .background {
            if isFindCurrent {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.25))
            } else if isFindMatch {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.yellow.opacity(0.15))
            }
        }
    }

    private var userRow: some View {
        HStack {
            Spacer(minLength: 80)
            Text(message.content)
                .font(.body)
                .foregroundStyle(Palette.userBubbleText)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Palette.userBubbleFill,
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reasoning = reasoningText {
                DisclosureGroup("思考过程") {
                    Text(reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                }
            }
            if !message.content.isEmpty {
                MacMarkdownView(text: message.content)
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
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.toolName ?? "工具结果")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(8)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 8)
        )
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
