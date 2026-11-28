import OneDayCore
import OneDayDesign
import SwiftUI

/// 单条专家分身观点段落（用于 `@全员` 群策协作折叠卡组）
struct ChatSpecialistSection: Identifiable, Equatable {
    let id: String
    let name: String
    let body: String
}

/// 助手消息的分身署名与多专家协作解析结果
enum ChatSpecialistReplyLayout: Equatable {
    /// 普通单聊回复（默认主助手，零额外装饰）
    case plain
    /// 点名单个专家分身回复（顶部轻量署名眉 + 正文）
    case singleSpecialist(name: String, model: String?, body: String)
    /// `@全员` 多专家分身协同回复（可折叠专家观点卡组 + 主助手综合结论）
    case multiSpecialist(specialists: [ChatSpecialistSection], synthesis: String)
}

/// 纯函数解析器：从助手 Markdown 正文及上文 `@分身` 上下文识别分身署名与多专家分项观点
enum ChatSpecialistReplyParser {
    private static let synthesisHeadings: Set<String> = [
        "综合结论", "最终结论", "总结", "汇总", "汇总结论", "综合建议", "执行建议", "结论"
    ]

    static func parse(
        markdown: String,
        inferredSingleProfile: ProfileItem? = nil
    ) -> ChatSpecialistReplyLayout {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }

        // 1. 解析 `### @分身名` / `## @分身名` / `### 综合结论` 结构化分段
        let lines = trimmed.components(separatedBy: .newlines)
        var sections: [(heading: String, isMentionHeading: Bool, isSynthesis: Bool, lines: [String])] = []
        var preambleLines: [String] = []

        for line in lines {
            if let heading = extractHeading(from: line) {
                let clean = heading.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSynth = synthesisHeadings.contains(where: { clean.contains($0) })
                let isMention = clean.hasPrefix("@")
                let normalizedTitle = isMention ? String(clean.dropFirst()).trimmingCharacters(in: .whitespaces) : clean
                sections.append((
                    heading: normalizedTitle,
                    isMentionHeading: isMention,
                    isSynthesis: isSynth,
                    lines: []
                ))
            } else if sections.isEmpty {
                preambleLines.append(line)
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }

        let mentionSections = sections.filter { $0.isMentionHeading && !$0.isSynthesis }
        if mentionSections.count >= 2 {
            let specialistItems = mentionSections.enumerated().map { idx, sec in
                ChatSpecialistSection(
                    id: "\(idx)-\(sec.heading)",
                    name: sec.heading,
                    body: sec.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            let synthesisBlocks = sections.filter(\.isSynthesis).map { sec in
                let body = sec.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty ? "" : "### \(sec.heading)\n\(body)"
            }.filter { !$0.isEmpty }

            let preamble = preambleLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let synthesisText: String
            if !synthesisBlocks.isEmpty {
                synthesisText = synthesisBlocks.joined(separator: "\n\n")
            } else if !preamble.isEmpty {
                synthesisText = preamble
            } else {
                synthesisText = "以上 \(specialistItems.count) 位专家分身已完成并行分析，点开上方卡片可查看各位分身的详细论证。"
            }
            return .multiSpecialist(specialists: specialistItems, synthesis: synthesisText)
        }

        // 2. 单分身署名标题（例如正文首段为 `### @架构师` 或 `[@架构师]`）
        if mentionSections.count == 1, sections.count == 1, preambleLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let sec = mentionSections[0]
            let body = sec.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                return .singleSpecialist(
                    name: sec.heading,
                    model: inferredSingleProfile?.model,
                    body: body
                )
            }
        }

        // 3. 若上一条用户消息明确点名了某一位常驻分身，则自动挂轻量署名眉
        if let profile = inferredSingleProfile {
            return .singleSpecialist(
                name: profile.name,
                model: profile.model,
                body: trimmed
            )
        }

        return .plain
    }

    private static func extractHeading(from line: String) -> String? {
        let s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("### ") {
            return String(s.dropFirst(4))
        }
        if s.hasPrefix("## ") {
            return String(s.dropFirst(3))
        }
        if s.hasPrefix("**@"), s.hasSuffix("**"), s.count > 5 {
            return String(s.dropFirst(2).dropLast(2))
        }
        if s.hasPrefix("[@"), s.hasSuffix("]"), s.count > 3 {
            return String(s.dropFirst(1).dropLast(1))
        }
        return nil
    }
}

/// 单分身回复的轻量署名眉（位于助手气泡左上角，克制不喧宾夺主）
struct ChatSpecialistEyebrowView: View {
    let name: String
    let model: String?

    var body: some View {
        let visual = Self.visual(for: name)
        HStack(spacing: 6) {
            Image(systemName: visual.symbol)
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(visual.tint)
                .frame(width: 20, height: 20)
                .background(visual.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("@\(name)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

            if let model, !model.isEmpty {
                Text(model)
                    .font(.metaMonospaced)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 2)
    }

    static func visual(for name: String) -> (symbol: String, tint: Color) {
        let lower = name.lowercased()
        if lower.contains("code") || lower.contains("dev") || lower.contains("代码") || lower.contains("架构") {
            return ("chevron.left.forwardslash.chevron.right", Palette.tintSkyInk)
        }
        if lower.contains("research") || lower.contains("研究") || lower.contains("分析") {
            return ("magnifyingglass.circle.fill", Palette.tintLavenderInk)
        }
        if lower.contains("ops") || lower.contains("运维") || lower.contains("安全") {
            return ("shield.lefthalf.filled", Palette.tintOrangeInk)
        }
        if lower.contains("write") || lower.contains("写作") || lower.contains("内容") || lower.contains("设计") {
            return ("pencil.and.outline", Palette.tintGreenInk)
        }
        return ("sparkles", Palette.tintLavenderInk)
    }
}

/// `@全员` 多分身协作可折叠观点卡组：
/// 默认折叠为一行安静摘要（展示参与分身与人数），点按平滑展开查看每位专家的独立论证，
/// 紧跟下方呈现主助手最终综合结论，避免多 Bot 同时刷屏。
struct ChatSpecialistPerspectivesDeckView: View {
    let specialists: [ChatSpecialistSection]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var summaryNames: String {
        specialists.map(\.name).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    // 叠层专家小图标
                    HStack(spacing: -6) {
                        ForEach(Array(specialists.prefix(3).enumerated()), id: \.element.id) { _, item in
                            let visual = ChatSpecialistEyebrowView.visual(for: item.name)
                            Image(systemName: visual.symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(visual.tint)
                                .frame(width: 22, height: 22)
                                .background(Palette.surface, in: Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(visual.tint.opacity(0.35), lineWidth: 1)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(specialists.count) 位专家分身已协作")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text(summaryNames)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: OneDayMetrics.spacingS)

                    HStack(spacing: 3) {
                        Text(isExpanded ? "收起观点" : "展开观点")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().foregroundStyle(Palette.hairline)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    ForEach(specialists) { specialist in
                        specialistCard(specialist)
                    }
                }
                .padding(OneDayMetrics.spacingSM)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private func specialistCard(_ specialist: ChatSpecialistSection) -> some View {
        let visual = ChatSpecialistEyebrowView.visual(for: specialist.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: visual.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(visual.tint)
                    .frame(width: 22, height: 22)
                    .background(visual.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("@\(specialist.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            Text(specialist.body)
                .font(.footnote)
                .foregroundStyle(Palette.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.pageBG,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
