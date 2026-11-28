import OneDayCore
import OneDayDesign
import SwiftUI

/// 对话内 `@分身 / @全员` 实时解析器（纯函数，无副作用）：
/// - 仅在 `@` 位于行首或空白字符之后时触发，避免输入邮箱地址（如 `name@domain.com`）误弹浮层；
/// - 一旦 `@关键词` 后出现空格或换行即自动收起；
/// - 支持从正文中提取 `@全员` 与已命中的真实常驻分身名单，供主助手编排协同。
enum ChatMentionQuery {
    static let allMembersToken = "全员"

    struct Match: Equatable {
        let range: Range<String.Index>
        let keyword: String
    }

    static func activeQuery(in rawInput: String) -> Match? {
        guard !rawInput.isEmpty else { return nil }
        // 若当前已触发 `/` 命令浮层，不与 `@` 抢槽位
        if rawInput.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
            return nil
        }

        var cursor = rawInput.endIndex
        while cursor > rawInput.startIndex {
            let prev = rawInput.index(before: cursor)
            let ch = rawInput[prev]
            if ch.isWhitespace || ch.isNewline {
                return nil
            }
            if ch == "@" {
                // 仅当 `@` 在开头或前面紧邻空白/换行时视为有效召唤触发
                if prev == rawInput.startIndex {
                    let keywordStart = rawInput.index(after: prev)
                    let keyword = String(rawInput[keywordStart..<rawInput.endIndex])
                    return Match(range: prev..<rawInput.endIndex, keyword: keyword)
                }
                let beforeAt = rawInput[rawInput.index(before: prev)]
                if beforeAt.isWhitespace || beforeAt.isNewline {
                    let keywordStart = rawInput.index(after: prev)
                    let keyword = String(rawInput[keywordStart..<rawInput.endIndex])
                    return Match(range: prev..<rawInput.endIndex, keyword: keyword)
                }
                return nil
            }
            cursor = prev
        }
        return nil
    }

    static func applyingMention(_ token: String, to rawInput: String) -> String {
        guard let match = activeQuery(in: rawInput) else {
            let suffix = rawInput.isEmpty || rawInput.hasSuffix(" ") ? "" : " "
            return rawInput + suffix + "@\(token) "
        }
        var updated = rawInput
        updated.replaceSubrange(match.range, with: "@\(token) ")
        return updated
    }

    struct ResolvedTargets: Equatable {
        let mentionsAll: Bool
        let matchedProfiles: [ProfileSummary]

        var isActive: Bool {
            mentionsAll || !matchedProfiles.isEmpty
        }
    }

    static func resolveTargets(
        in text: String,
        knownProfiles: [ProfileSummary]
    ) -> ResolvedTargets {
        let mentionsAll = text.contains("@\(allMembersToken)")
            || text.localizedCaseInsensitiveContains("@all")
            || text.localizedCaseInsensitiveContains("@everyone")
        let matched = knownProfiles.filter { profile in
            text.contains("@\(profile.name)")
        }
        return ResolvedTargets(mentionsAll: mentionsAll, matchedProfiles: matched)
    }

    /// 将对话内的 `@全员` / `@分身名` 转换为透明的 Hermes 多体协同路由前缀（仅发往模型上下文，
    /// 不污染用户本地聊天记录气泡），让主助手按真实分身画像并行委派并统一汇总。
    static func enrichedOutgoingPrompt(
        for rawText: String,
        knownProfiles: [ProfileSummary]
    ) -> String {
        let resolved = resolveTargets(in: rawText, knownProfiles: knownProfiles)
        guard resolved.isActive else { return rawText }

        if resolved.mentionsAll {
            let rosterDesc: String
            if knownProfiles.isEmpty {
                rosterDesc = "当前尚未创建自定义常驻分身，请按任务拆分为 2-3 个专家子代理并行协作"
            } else {
                let names = knownProfiles.map { profile in
                    if let model = profile.model, !model.isEmpty {
                        return "\(profile.name)(\(model))"
                    }
                    return profile.name
                }.joined(separator: "、")
                rosterDesc = "已召集全部常驻专家分身（\(names)）并行分工"
            }
            return """
            [多体协同指令：@全员｜\(rosterDesc)。请使用 delegate_task 并行拆解，每个分身各抒己见并标注角色署名，最后由你汇总为一份可执行结论。]
            \(rawText)
            """
        }

        let targetDesc = resolved.matchedProfiles.map { profile in
            if let model = profile.model, !model.isEmpty {
                return "@\(profile.name)（模型：\(model)）"
            }
            return "@\(profile.name)"
        }.joined(separator: "、")
        return """
        [分身定向指令：用户点名召唤 \(targetDesc)。请优先按该分身专长（必要时通过 delegate_task）处理并明确署名汇报。]
        \(rawText)
        """
    }
}

/// 对话输入舱上方的原生 `@分身 / @全员` 召唤浮层：
/// 复用 `ChatSlashCommandPaletteView` 同一套 Liquid Glass / Surface 浮层骨架与尺寸契约，
/// 平时零界面堆砌，敲 `@` 即刻弹出真实常驻分身花名册与置顶「@全员」协作入口。
struct ChatMentionPaletteView: View {
    let query: String
    let profiles: [ProfileSummary]
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onManageProfiles: () -> Void

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var showsAllMembersRow: Bool {
        if normalizedQuery.isEmpty { return true }
        return ChatMentionQuery.allMembersToken.contains(normalizedQuery)
            || "all".contains(normalizedQuery)
            || "everyone".contains(normalizedQuery)
            || "全".contains(normalizedQuery)
    }

    private var filteredProfiles: [ProfileSummary] {
        guard !normalizedQuery.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.name.lowercased().contains(normalizedQuery)
                || (profile.model ?? "").lowercased().contains(normalizedQuery)
                || (profile.provider ?? "").lowercased().contains(normalizedQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().foregroundStyle(Palette.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if showsAllMembersRow {
                        allMembersRow
                        if !filteredProfiles.isEmpty || isLoading {
                            Divider()
                                .foregroundStyle(Palette.hairline)
                                .padding(.leading, 56)
                        }
                    }

                    if isLoading && profiles.isEmpty {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在同步常驻专家分身…")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, 12)
                    } else if filteredProfiles.isEmpty && !showsAllMembersRow {
                        emptyMatchRow
                    } else {
                        ForEach(Array(filteredProfiles.enumerated()), id: \.element.name) { idx, profile in
                            profileRow(profile)
                            if idx < filteredProfiles.count - 1 {
                                Divider()
                                    .foregroundStyle(Palette.hairline)
                                    .padding(.leading, 56)
                            }
                        }
                        if profiles.isEmpty && !isLoading {
                            createFirstProfileHintRow
                        }
                    }
                }
            }
            .frame(maxHeight: 224)
        }
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    private var headerBar: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Text("召唤专家分身")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)

            if !profiles.isEmpty {
                Text("\(profiles.count) 位常驻")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkMuted)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.selection()
                onManageProfiles()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                    Text("管理分身")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Palette.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, 8)
    }

    private var allMembersRow: some View {
        Button {
            Haptics.selection()
            onSelect(ChatMentionQuery.allMembersToken)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "person.3.fill")
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Palette.primary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("@\(ChatMentionQuery.allMembersToken)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text("群策协同")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Palette.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.primary.opacity(0.12), in: Capsule())
                    }
                    Text(
                        profiles.isEmpty
                            ? "召集多领域专家分身并行拆解任务，主助手统一汇总"
                            : "召集全部 \(profiles.count) 位常驻分身并行协同，汇总交付"
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func profileRow(_ profile: ProfileSummary) -> some View {
        let visual = Self.visual(for: profile.name)
        return Button {
            Haptics.selection()
            onSelect(profile.name)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: visual.symbol)
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(visual.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        visual.tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("@\(profile.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if profile.isActive {
                            Text("当前默认")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Palette.successText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.tintGreenBG, in: Capsule())
                        }
                    }

                    HStack(spacing: 4) {
                        if let model = profile.model, !model.isEmpty {
                            Text(model)
                                .font(.metaMonospaced)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        } else {
                            Text("跟随默认模型")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        if let provider = profile.provider, !provider.isEmpty {
                            Text("· \(provider)")
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyMatchRow: some View {
        Button {
            Haptics.selection()
            onManageProfiles()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "plus.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Palette.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("未找到「@\(query)」分身")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text("点按前往创建专属专家分身")
                        .font(.caption)
                        .foregroundStyle(Palette.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createFirstProfileHintRow: some View {
        Button {
            Haptics.selection()
            onManageProfiles()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "person.badge.plus")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Palette.fill,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("创建你的第一位专家分身")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text("如代码架构师、深度研究员、日程助理，创建后即可在此随时 @ 召唤")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func visual(for name: String) -> (symbol: String, tint: Color) {
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
        if lower.contains("write") || lower.contains("写作") || lower.contains("内容") {
            return ("pencil.and.outline", Palette.tintGreenInk)
        }
        return ("sparkles", Palette.tintLavenderInk)
    }
}
