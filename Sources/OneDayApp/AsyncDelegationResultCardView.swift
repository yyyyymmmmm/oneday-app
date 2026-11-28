import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - 单个分身的独立结构化汇报

struct SubagentIndividualReport: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let summary: String
    let markdownBody: String
}

// MARK: - Hermes 后台分身异步回调报文解析器（拦截误标为 user 的系统回报 + 拆分单分身独立汇报）

struct AsyncDelegationCallbackData: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case asyncDelegation
        case subagentResult
        case backgroundTask
        case scheduledJob

        var title: String {
            switch self {
            case .asyncDelegation: return "后台分身已完成汇报"
            case .subagentResult: return "子分身执行回报"
            case .backgroundTask: return "后台任务已完成"
            case .scheduledJob: return "定时任务执行回报"
            }
        }

        var iconName: String {
            switch self {
            case .asyncDelegation: return "person.2.wave.2.fill"
            case .subagentResult: return "person.crop.circle.badge.checkmark"
            case .backgroundTask: return "checkmark.circle.badge.clock"
            case .scheduledJob: return "clock.badge.checkmark"
            }
        }

        var badgeText: String {
            switch self {
            case .asyncDelegation, .subagentResult: return "已回传"
            case .backgroundTask, .scheduledJob: return "已完成"
            }
        }
    }

    let kind: Kind
    let batchID: String?
    let subagentCount: Int?
    let dispatchedAt: String?
    let modelName: String?
    let duration: String?
    let cleanedBody: String
    let rawContent: String
    /// 按单个分身拆分后的独立汇报列表，支持逐个点击展开完整 Markdown 渲染
    let individualReports: [SubagentIndividualReport]
}

enum AsyncDelegationCallbackParser {
    private static let supportedPrefixes: [(prefix: String, kind: AsyncDelegationCallbackData.Kind)] = [
        ("[ASYNC DELEGATION BATCH COMPLETE", .asyncDelegation),
        ("[ASYNC DELEGATION", .asyncDelegation),
        ("[DELEGATION RESULT", .subagentResult),
        ("[SUBAGENT RESULT", .subagentResult),
        ("[BACKGROUND TASK COMPLETE", .backgroundTask),
        ("[CRON JOB RESULT", .scheduledJob),
        ("[SCHEDULED TASK RESULT", .scheduledJob)
    ]

    static func isSystemCallback(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return false }
        let upperHead = String(trimmed.prefix(48)).uppercased()
        return supportedPrefixes.contains { upperHead.hasPrefix($0.prefix) }
    }

    static func friendlyPreview(for content: String) -> String? {
        guard let data = parse(from: content) else { return nil }
        var parts = [data.kind.title]
        if let count = data.subagentCount, count > 0 {
            parts.append("\(count) 个分身")
        }
        if let duration = data.duration, !duration.isEmpty {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }

    static func parse(from content: String) -> AsyncDelegationCallbackData? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return nil }
        let upperHead = String(trimmed.prefix(48)).uppercased()
        guard let matched = supportedPrefixes.first(where: { upperHead.hasPrefix($0.prefix) }) else {
            return nil
        }

        var batchID: String?
        if let closeBracket = trimmed.firstIndex(of: "]") {
            let header = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
            for sep in ["—", "–", "-", ":"] {
                if let range = header.range(of: sep) {
                    let candidate = header[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        batchID = candidate
                        break
                    }
                }
            }
        }

        var subagentCount: Int?
        if let match = trimmed.range(of: #"(\d+)\s+subagent"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = trimmed[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            subagentCount = Int(digits)
        }

        let lines = trimmed.components(separatedBy: .newlines)
        var dispatchedAt: String?
        var modelName: String?
        var duration: String?
        var bodyLines: [String] = []

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if index == 0, line.hasPrefix("[") {
                continue
            }
            if line.hasPrefix("A background fan-out unit you dispatched earlier")
                || line.hasPrefix("Any other units from the same delegate_task")
                || line.hasPrefix("If you are still waiting on siblings") {
                continue
            }
            if line.lowercased().hasPrefix("dispatched:") {
                let value = String(line.dropFirst("dispatched:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { dispatchedAt = value }
                continue
            }
            if line.lowercased().hasPrefix("model:") {
                let value = String(line.dropFirst("model:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { modelName = value }
                continue
            }
            if line.lowercased().hasPrefix("total duration:") {
                let value = String(line.dropFirst("total duration:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { duration = value }
                continue
            }
            if line.lowercased().hasPrefix("duration:"), duration == nil {
                let value = String(line.dropFirst("duration:".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { duration = value }
                continue
            }
            bodyLines.append(rawLine)
        }

        let cleanedBody = bodyLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let reports = splitIndividualReports(
            from: cleanedBody.isEmpty ? trimmed : cleanedBody,
            fallbackCount: subagentCount ?? 1,
            modelName: modelName
        )

        return AsyncDelegationCallbackData(
            kind: matched.kind,
            batchID: batchID,
            subagentCount: subagentCount,
            dispatchedAt: dispatchedAt,
            modelName: modelName,
            duration: duration,
            cleanedBody: cleanedBody,
            rawContent: trimmed,
            individualReports: reports
        )
    }

    /// 识别 Hermes 批次回报里的多子分身分段（如 `--- Subagent 1: ... ---`、`### Subagent 1`、`### @分身名`、`Task 1:`）
    /// 将每个分身拆成独立汇报条目，让用户可以逐个点击查看完整渲染好的 Markdown。
    private static func splitIndividualReports(
        from body: String,
        fallbackCount: Int,
        modelName: String?
    ) -> [SubagentIndividualReport] {
        let lines = body.components(separatedBy: .newlines)
        var sections: [(title: String, lines: [String])] = []
        var currentTitle: String?
        var currentLines: [String] = []

        let headerPattern = #"^(?:#{1,3}\s*|---\s*|===\s*)(?:Subagent|Task|分身|@\S+)\s*[#0-9：:\-—]*.*$"#

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: headerPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                if let title = currentTitle {
                    sections.append((title, currentLines))
                } else if !currentLines.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(("分身 1 汇报", currentLines))
                }
                let cleanTitle = trimmed
                    .replacingOccurrences(of: #"^[#\-=\s]+|[\-=\s]+$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentTitle = cleanTitle.isEmpty ? "分身 \(sections.count + 1)" : cleanTitle
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        if let title = currentTitle {
            sections.append((title, currentLines))
        }

        if sections.isEmpty {
            let summaryLine = firstMeaningfulLine(in: body)
            return [
                SubagentIndividualReport(
                    id: "subagent-0",
                    title: fallbackCount > 1 ? "分身汇总汇报" : "专属分身汇报",
                    subtitle: modelName,
                    summary: summaryLine,
                    markdownBody: body
                )
            ]
        }

        return sections.enumerated().map { idx, sec in
            let md = sec.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let finalMD = md.isEmpty ? body : md
            return SubagentIndividualReport(
                id: "subagent-\(idx)",
                title: sec.title,
                subtitle: modelName,
                summary: firstMeaningfulLine(in: finalMD),
                markdownBody: finalMD
            )
        }
    }

    private static func firstMeaningfulLine(in markdown: String) -> String {
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw
                .replacingOccurrences(of: #"[#*`>_]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.count >= 4 {
                return line
            }
        }
        return "点按查看完整渲染汇报"
    }
}

// MARK: - 独立分身完整 Markdown 渲染详情弹窗（消除列表行高跳动与大段空白，渲染标题/列表/代码块）

struct SubagentReportReaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String?
    let markdownContent: String
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    MarkdownText(markdownContent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, 14)
            }
            .background(Palette.chatSurface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = markdownContent
                        #endif
                        Haptics.selection()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 对话内「后台分身异步回报卡」（单分身独立行 + 点击弹出完整 Markdown 渲染 Sheet，零空白零重叠）

struct AsyncDelegationResultCardView: View {
    let data: AsyncDelegationCallbackData
    var onPinAsResident: (() -> Void)? = nil
    @State private var activeReport: SubagentIndividualReport?
    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: data.kind.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.tintLavenderInk)
                    .frame(width: 28, height: 28)
                    .background(Palette.tintLavender, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(data.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if let meta = compactMetaLine {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(data.kind.badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.successText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.tintGreen, in: Capsule())
            }

            // 每个分身独立成行，点按直接弹出完整渲染好的 Markdown 汇报 Sheet
            VStack(spacing: 6) {
                ForEach(data.individualReports) { report in
                    Button {
                        Haptics.selection()
                        activeReport = report
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(Palette.tintLavenderInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(report.summary)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            HStack(spacing: 2) {
                                Text("查看")
                                    .font(.caption2.weight(.medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Palette.primary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let onPinAsResident {
                HStack {
                    Button {
                        onPinAsResident()
                        withAnimation(.snappy(duration: 0.15)) {
                            pinned = true
                        }
                    } label: {
                        Label(
                            pinned ? "已常驻本对话" : "设为常驻分身",
                            systemImage: pinned ? "checkmark.circle.fill" : "pin.fill"
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(pinned ? Palette.successText : Palette.tintLavenderInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(pinned)
                    Spacer()
                }
            }
        }
        .padding(OneDayMetrics.spacingSM)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        }
        .sheet(item: $activeReport) { report in
            SubagentReportReaderSheet(
                title: report.title,
                subtitle: compactMetaLine,
                markdownContent: report.markdownBody
            )
        }
    }

    private var compactMetaLine: String? {
        var parts: [String] = []
        if let count = data.subagentCount, count > 0 { parts.append("\(count) 个分身") }
        if let model = data.modelName, !model.isEmpty { parts.append(model) }
        if let duration = data.duration, !duration.isEmpty { parts.append("耗时 \(duration)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
