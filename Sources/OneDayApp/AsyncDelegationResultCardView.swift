import SwiftUI
import OneDayCore
import OneDayDesign

// MARK: - Hermes 后台分身异步回调报文解析器（拦截误标为 user 的系统回报）

/// Hermes v0.23.0 在异步分身（`delegate_task`）完成后，会以 `role: "user"`
/// 向会话注入 `[ASYNC DELEGATION BATCH COMPLETE — deleg_xxx]` 等内部回调报文。
/// 本解析器在渲染层将其识别并结构化为中性「后台分身回报卡」，避免以绿色用户气泡
/// 暴露原始英文系统提示词。
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
    /// 去除 Hermes 英文系统样板后的分身正文汇报（可直接阅读）
    let cleanedBody: String
    /// 原始完整回调文本（供调试或复制）
    let rawContent: String
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

    /// 高性能 O(1) 前缀快速判定，避免列表滚动时做正则开销
    static func isSystemCallback(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return false }
        let upperHead = String(trimmed.prefix(48)).uppercased()
        return supportedPrefixes.contains { upperHead.hasPrefix($0.prefix) }
    }

    /// 供侧边栏摘要或引用预览使用的中文友好短文案
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

        // 1. 解析首行方括号内的 Batch ID（例如 [ASYNC DELEGATION BATCH COMPLETE — deleg_fe3ff772]）
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

        // 2. 提取子分身数量（例如 "1 subagent(s)"）
        var subagentCount: Int?
        if let match = trimmed.range(of: #"(\d+)\s+subagent"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = trimmed[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            subagentCount = Int(digits)
        }

        // 3. 逐行扫描结构化元数据，并剥离 Hermes 英文系统提示样板
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

        return AsyncDelegationCallbackData(
            kind: matched.kind,
            batchID: batchID,
            subagentCount: subagentCount,
            dispatchedAt: dispatchedAt,
            modelName: modelName,
            duration: duration,
            cleanedBody: cleanedBody,
            rawContent: trimmed
        )
    }
}

// MARK: - 对话内「后台分身异步回报卡」（中性系统卡片，对齐 SubagentDelegationCardView）

struct AsyncDelegationResultCardView: View {
    let data: AsyncDelegationCallbackData
    @State private var isExpanded = false
    @State private var copied = false

    private var previewText: String {
        if !data.cleanedBody.isEmpty {
            return data.cleanedBody
        }
        return "分身已完成后台执行并将结果同步至当前对话。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            // 顶部标题与完成态胶囊
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
                    if let dispatched = data.dispatchedAt, !dispatched.isEmpty {
                        Text("派出时间：\(dispatched)")
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

            // 结构化元数据胶囊行（分身数 / 模型 / 耗时 / Batch ID）
            if hasMetadataChips {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let count = data.subagentCount, count > 0 {
                            chip(text: "\(count) 个分身", fg: Palette.tintLavenderInk, bg: Palette.tintLavender)
                        }
                        if let model = data.modelName, !model.isEmpty {
                            chip(text: model, fg: Palette.tintSkyInk, bg: Palette.tintSky)
                        }
                        if let duration = data.duration, !duration.isEmpty {
                            chip(text: "耗时 \(duration)", fg: Palette.inkSecondary, bg: Palette.fillTertiary)
                        }
                        if let batchID = data.batchID, !batchID.isEmpty {
                            chip(text: batchID, fg: Palette.inkTertiary, bg: Palette.fillTertiary)
                        }
                    }
                }
            }

            // 折叠态简洁摘要（仅展示清洗后的有效正文）
            if !isExpanded {
                Text(previewText)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 展开/收起操作栏
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起完整回报" : "查看完整回报")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isExpanded {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = data.cleanedBody.isEmpty ? data.rawContent : data.cleanedBody
                        #endif
                        withAnimation(.snappy(duration: 0.15)) {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制正文", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(copied ? Palette.successText : Palette.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 展开后的完整汇报正文
            if isExpanded {
                Text(data.cleanedBody.isEmpty ? data.rawContent : data.cleanedBody)
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    }

    private var hasMetadataChips: Bool {
        data.subagentCount != nil || data.modelName != nil || data.duration != nil || data.batchID != nil
    }

    private func chip(text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(fg)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}
