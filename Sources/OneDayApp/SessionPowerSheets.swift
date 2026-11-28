import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - #29 持久 Python 代码内核执行卡（execute_code / python RPC）

struct CodeExecutionCardData: Equatable {
    let id: String
    let language: String
    let code: String
    let stdout: String
    let stderr: String
    let artifacts: [String]
    let isRunning: Bool
    let isFailed: Bool
}

enum CodeExecutionParser {
    private static let codeToolNames: Set<String> = [
        "execute_code", "python", "run_python", "python_repl", "code_interpreter", "jupyter_exec"
    ]

    static func parse(from card: ToolCard) -> CodeExecutionCardData? {
        let lower = card.name.lowercased()
        let isCodeTool = codeToolNames.contains(lower)
            || lower.contains("execute_code")
            || lower.contains("python")
        guard isCodeTool else { return nil }

        let code = extractField(["code", "script", "source", "command"], from: card.args)
            ?? card.args.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawResult = card.result ?? ""
        let stdout = extractField(["stdout", "output", "result"], from: rawResult) ?? rawResult
        let stderr = extractField(["stderr", "error", "traceback"], from: rawResult) ?? ""
        let artifacts = extractArtifactPaths(from: rawResult)

        return CodeExecutionCardData(
            id: card.id,
            language: lower.contains("js") || lower.contains("node") ? "JavaScript" : "Python 3",
            code: code,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            artifacts: artifacts,
            isRunning: card.status == .running,
            isFailed: card.status == .failed || !stderr.isEmpty
        )
    }

    private static func extractField(_ keys: [String], from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in keys {
            if let value = obj[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func extractArtifactPaths(from text: String) -> [String] {
        let pattern = #"(/[A-Za-z0-9._/\-]+\.(?:png|jpg|jpeg|svg|pdf|csv|xlsx|json|html|md|txt|zip))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var results: [String] = []
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text) {
                let path = String(text[r])
                if seen.insert(path).inserted {
                    results.append(path)
                }
            }
        }
        return results
    }
}

struct CodeExecutionCardView: View {
    let card: CodeExecutionCardData
    var onOpenArtifact: (String) -> Void = { _ in }

    @State private var showCode = false
    @State private var showOutput = true
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tintLavenderInk)
                    .frame(width: 26, height: 26)
                    .background(Palette.tintLavender, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("\(card.language) 内核执行")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text("持久 RPC")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Palette.tintLavenderInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.tintLavender, in: Capsule())
                    }
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(card.isFailed ? Palette.danger : Palette.inkSecondary)
                }

                Spacer(minLength: 4)

                if card.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: card.isFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(card.isFailed ? Palette.danger : Palette.success)
                }
            }

            if !card.code.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showCode.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showCode ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.semibold))
                            Text(showCode ? "收起代码" : "查看执行代码（\(card.code.components(separatedBy: .newlines).count) 行）")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Button {
                                UIPasteboard.general.string = card.code
                                Haptics.selection()
                                copied = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    copied = false
                                }
                            } label: {
                                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2.weight(.medium))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.plain)

                    if showCode {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(card.code)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Palette.ink)
                                .textSelection(.enabled)
                                .padding(10)
                        }
                        .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if !card.stdout.isEmpty || !card.stderr.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showOutput.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showOutput ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.semibold))
                            Text(card.stderr.isEmpty ? "标准输出 (stdout)" : "执行输出与错误")
                                .font(.caption.weight(.medium))
                            Spacer()
                        }
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.plain)

                    if showOutput {
                        VStack(alignment: .leading, spacing: 4) {
                            if !card.stdout.isEmpty {
                                Text(String(card.stdout.prefix(1200)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Palette.ink)
                                    .textSelection(.enabled)
                            }
                            if !card.stderr.isEmpty {
                                Text(String(card.stderr.prefix(800)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Palette.danger)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if !card.artifacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(card.artifacts, id: \.self) { path in
                            Button {
                                Haptics.selection()
                                onOpenArtifact(path)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.richtext")
                                        .font(.caption)
                                    Text((path as NSString).lastPathComponent)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Palette.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.primaryTint, in: Capsule())
                            }
                            .buttonStyle(.odPressable)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private var statusSubtitle: String {
        if card.isRunning { return "正在持久内核中运行代码…" }
        if card.isFailed { return "执行遇到异常，可展开查看 stderr" }
        if !card.artifacts.isEmpty { return "已完成 · 生成 \(card.artifacts.count) 个产物文件" }
        return "执行完成"
    }
}

// MARK: - #19 文件检查点与 /rollback 回滚工作表

struct FileCheckpointSnapshot: Identifiable {
    let id: String
    let toolName: String
    let filePath: String
    let timestamp: Date
    let diffLines: [String]
}

struct CheckpointHistorySheet: View {
    let entries: [ChatEntry]
    let onRollback: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSnapshotID: String?

    private var snapshots: [FileCheckpointSnapshot] {
        var result: [FileCheckpointSnapshot] = []
        let fileTools = ["write_file", "patch", "edit_file", "replace_file_content", "multi_replace_file_content", "delete_file"]
        for entry in entries.reversed() {
            guard let card = entry.toolCard else { continue }
            let lower = card.name.lowercased()
            guard fileTools.contains(where: { lower.contains($0) }) else { continue }
            let path = extractPath(from: card.args) ?? card.name
            let diffLines = buildDiffLines(from: card.args, result: card.result ?? "")
            result.append(
                FileCheckpointSnapshot(
                    id: card.id,
                    toolName: card.name,
                    filePath: path,
                    timestamp: entry.createdAt,
                    diffLines: diffLines
                )
            )
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                SettingsHeroCard(
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    tint: .orange,
                    title: "文件检查点与回滚",
                    subtitle: "查看本会话中 AI 修改过的文件检查点与彩色 Diff，随时一键执行 /rollback 恢复。",
                    statusText: snapshots.isEmpty ? "随时可回滚" : "\(snapshots.count) 个检查点",
                    statusTone: snapshots.isEmpty ? .neutral : .healthy
                )

                Section {
                    Button {
                        Haptics.selection()
                        dismiss()
                        onRollback("/rollback")
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "arrow.uturn.backward.circle.fill", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("回滚至最近一次文件检查点")
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                Text("发送 /rollback 指令撤销最近一轮文件改动")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .buttonStyle(.odPressable)
                } header: {
                    SettingsSectionHeader("快捷回滚")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                if !snapshots.isEmpty {
                    Section {
                        ForEach(snapshots) { snap in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.badge.gearshape")
                                        .foregroundStyle(Palette.tintOrangeInk)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text((snap.filePath as NSString).lastPathComponent)
                                            .font(.rowTitleL)
                                            .foregroundStyle(Palette.ink)
                                        Text("\(snap.toolName) · \(snap.timestamp.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(Palette.inkSecondary)
                                    }
                                    Spacer()
                                    Button("回滚") {
                                        Haptics.selection()
                                        dismiss()
                                        onRollback("/rollback \(snap.id)")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.tintOrangeInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Palette.tintOrange, in: Capsule())
                                    .buttonStyle(.odPressable)
                                }

                                if !snap.diffLines.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(Array(snap.diffLines.prefix(12).enumerated()), id: \.offset) { _, line in
                                            Text(line)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(diffColor(for: line))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(diffBackground(for: line))
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    } header: {
                        SettingsSectionHeader("本会话文件变更时间轴")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                } else {
                    Section {
                        ContentUnavailableView(
                            "暂无本地变更记录",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("你仍可通过上方快捷按钮向服务端发送 /rollback 查看并回滚云端文件检查点。")
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("检查点历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func diffColor(for line: String) -> Color {
        if line.hasPrefix("+") { return Palette.successText }
        if line.hasPrefix("-") { return Palette.danger }
        return Palette.inkSecondary
    }

    private func diffBackground(for line: String) -> Color {
        if line.hasPrefix("+") { return Palette.success.opacity(0.10) }
        if line.hasPrefix("-") { return Palette.danger.opacity(0.10) }
        return Color.clear
    }

    private func extractPath(from rawArgs: String) -> String? {
        guard let data = rawArgs.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in ["path", "file_path", "TargetFile", "filename"] {
            if let v = obj[key] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    private func buildDiffLines(from rawArgs: String, result: String) -> [String] {
        var lines: [String] = []
        if let data = rawArgs.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let oldText = obj["old_string"] as? String ?? obj["TargetContent"] as? String {
                for l in oldText.components(separatedBy: .newlines).prefix(5) {
                    lines.append("- \(l)")
                }
            }
            if let newText = obj["new_string"] as? String ?? obj["ReplacementContent"] as? String ?? obj["content"] as? String {
                for l in newText.components(separatedBy: .newlines).prefix(5) {
                    lines.append("+ \(l)")
                }
            }
        }
        if lines.isEmpty, !result.isEmpty {
            lines = result.components(separatedBy: .newlines).prefix(6).map { "  \($0)" }
        }
        return lines
    }
}

// MARK: - #20 多格式脱敏导出与跨端 /handoff 工作表

enum SessionExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case html = "HTML"
    case json = "JSON"
    var id: String { rawValue }
}

enum SessionRedactor {
    static func redact(_ text: String) -> (output: String, count: Int) {
        let patterns: [(String, String)] = [
            (#"sk-[A-Za-z0-9_\-]{16,}"#, "[REDACTED_API_KEY]"),
            (#"gh[pousr]_[A-Za-z0-9]{20,}"#, "[REDACTED_GITHUB_TOKEN]"),
            (#"xox[baprs]-[A-Za-z0-9\-]{16,}"#, "[REDACTED_SLACK_TOKEN]"),
            (#"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#, "Bearer [REDACTED_TOKEN]"),
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[REDACTED_EMAIL]"),
        ]
        var result = text
        var totalHits = 0
        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, range: range)
            if matches > 0 {
                totalHits += matches
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        return (result, totalHits)
    }
}

struct SessionExportHandoffSheet: View {
    let threadTitle: String
    let entries: [ChatEntry]
    let onHandoff: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case export = "脱敏导出"
        case handoff = "跨端转交"
        var id: String { rawValue }
    }

    @State private var activeTab: Tab = .export
    @State private var format: SessionExportFormat = .markdown
    @State private var redactSecrets = true
    @State private var copiedFeedback = false
    @State private var handoffChannel = "telegram"
    @State private var handoffNote = ""

    private let handoffChannels: [(id: String, name: String, symbol: String)] = [
        ("telegram", "Telegram 机器人", "paperplane.fill"),
        ("slack", "Slack 频道", "number.square.fill"),
        ("discord", "Discord 频道", "bubble.left.and.bubble.right.fill"),
        ("web", "Web 控制台", "globe"),
        ("cli", "本地 CLI 终端", "terminal.fill"),
    ]

    private var exportResult: (payload: String, redactedCount: Int) {
        let conversational = entries.filter { $0.toolCard == nil && !$0.content.isEmpty }
        var raw = ""
        switch format {
        case .markdown:
            raw = "# \(threadTitle)\n\n" + conversational.map { entry in
                let speaker = entry.role == "user" ? "用户" : "Hermes"
                return "### \(speaker)（\(entry.createdAt.formatted(date: .abbreviated, time: .shortened))）\n\n\(entry.content)"
            }.joined(separator: "\n\n")
        case .html:
            let rows = conversational.map { entry in
                let speaker = entry.role == "user" ? "用户" : "Hermes"
                let escaped = entry.content
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br/>")
                return "<article><h3>\(speaker)</h3><p>\(escaped)</p></article>"
            }.joined(separator: "\n")
            raw = "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(threadTitle)</title></head><body><h1>\(threadTitle)</h1>\n\(rows)\n</body></html>"
        case .json:
            let items: [[String: String]] = conversational.map { entry in
                [
                    "role": entry.role,
                    "created_at": ISO8601DateFormatter().string(from: entry.createdAt),
                    "content": entry.content,
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: ["title": threadTitle, "messages": items], options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                raw = str
            }
        }
        if redactSecrets {
            let res = SessionRedactor.redact(raw)
            return (res.output, res.count)
        }
        return (raw, 0)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("功能", selection: $activeTab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if activeTab == .export {
                    exportSections
                } else {
                    handoffSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("导出与跨端转交")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var exportSections: some View {
        let res = exportResult
        Section {
            Picker("导出格式", selection: $format) {
                ForEach(SessionExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            Toggle(isOn: $redactSecrets) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动脱敏密钥与邮箱")
                        .font(.rowTitleL)
                    Text(res.redactedCount > 0 ? "已拦截并替换 \(res.redactedCount) 处敏感凭据" : "自动识别 API Key、Bearer Token 与邮箱")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            SettingsSectionHeader("导出设置")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)

        Section {
            Text(String(res.payload.prefix(600)))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(10)
                .padding(.vertical, 4)
        } header: {
            SettingsSectionHeader("预览（共 \(res.payload.count) 字符）")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)

        Section {
            ShareLink(item: res.payload, subject: Text(threadTitle)) {
                HStack {
                    Spacer()
                    Label("系统分享 / 存储文件", systemImage: "square.and.arrow.up")
                        .font(.rowTitleL.weight(.semibold))
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            Button {
                UIPasteboard.general.string = res.payload
                Haptics.success()
                copiedFeedback = true
            } label: {
                HStack {
                    Spacer()
                    Label(copiedFeedback ? "已复制到剪贴板" : "复制完整内容", systemImage: copiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.rowTitleL)
                        .foregroundStyle(copiedFeedback ? Palette.successText : Palette.primary)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    @ViewBuilder
    private var handoffSections: some View {
        Section {
            ForEach(handoffChannels, id: \.id) { ch in
                Button {
                    Haptics.selection()
                    handoffChannel = ch.id
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: ch.symbol, color: handoffChannel == ch.id ? .blue : nil)
                        Text(ch.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if handoffChannel == ch.id {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.primary)
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            SettingsSectionHeader("选择目标渠道（/handoff）")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)

        Section {
            TextField("可选：附带交接重点（如：继续排查测试失败）", text: $handoffNote, axis: .vertical)
                .lineLimit(2...4)
            Button {
                let trimmed = handoffNote.trimmingCharacters(in: .whitespacesAndNewlines)
                let cmd = trimmed.isEmpty ? "/handoff \(handoffChannel)" : "/handoff \(handoffChannel) \(trimmed)"
                Haptics.success()
                dismiss()
                onHandoff(cmd)
            } label: {
                HStack {
                    Spacer()
                    Text("立即转交到目标渠道")
                        .font(.rowTitleL.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .listRowBackground(Palette.primary)
        } header: {
            SettingsSectionHeader("交接说明")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }
}

// MARK: - #39 Skill Bundles 与 /learn 自学习技能面板

struct SkillBundlePreset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let skills: [String]
}

struct SkillBundlesSheet: View {
    let onSendCommand: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var learnSkillName = ""

    private let bundles: [SkillBundlePreset] = [
        SkillBundlePreset(
            id: "fullstack-dev",
            title: "全栈开发与代码审计套件",
            subtitle: "Git 工作流、单元测试、代码审查与重构技能包",
            symbol: "hammer.fill",
            skills: ["git-workflow", "code-review", "test-runner", "refactor"]
        ),
        SkillBundlePreset(
            id: "deep-research",
            title: "深度调研与行业研报套件",
            subtitle: "多源检索、竞品对比、引用核验与结构化报告",
            symbol: "doc.text.magnifyingglass",
            skills: ["web-research", "fact-check", "report-writer"]
        ),
        SkillBundlePreset(
            id: "cloud-ops",
            title: "云电脑与自动化运维套件",
            subtitle: "终端巡检、日志分析、容器排障与定时告警",
            symbol: "server.rack",
            skills: ["terminal-ops", "log-triage", "cron-builder"]
        ),
        SkillBundlePreset(
            id: "creator-studio",
            title: "内容创作与社媒运营套件",
            subtitle: "多平台文案改写、视觉提示词与数据复盘",
            symbol: "sparkles.rectangle.stack.fill",
            skills: ["copywriting", "social-adapt", "analytics-brief"]
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                SettingsHeroCard(
                    symbol: "sparkles",
                    tint: .indigo,
                    title: "Skill Bundles 与 /learn",
                    subtitle: "一键装载场景技能组合，或将当前对话的高价值步骤沉淀为永久复用的自定义 Skill。",
                    statusText: "\(bundles.count) 套精选组合",
                    statusTone: .healthy
                )

                Section {
                    TextField("可选：新技能名称（如 weekly-report）", text: $learnSkillName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        let trimmed = learnSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cmd = trimmed.isEmpty ? "/learn" : "/learn \(trimmed)"
                        Haptics.success()
                        dismiss()
                        onSendCommand(cmd)
                    } label: {
                        HStack {
                            Spacer()
                            Label("从当前对话提炼为技能（/learn）", systemImage: "wand.and.stars")
                                .font(.rowTitleL.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .listRowBackground(Palette.primary)
                } header: {
                    SettingsSectionHeader("自学习技能沉淀")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Section {
                    ForEach(bundles) { bundle in
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: bundle.symbol, color: .indigo)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bundle.title)
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                Text(bundle.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(2)
                                Text(bundle.skills.joined(separator: " · "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Palette.inkMuted)
                            }
                            Spacer(minLength: 6)
                            Button("启用") {
                                Haptics.selection()
                                dismiss()
                                onSendCommand("/bundle \(bundle.id)")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.primaryTint, in: Capsule())
                            .buttonStyle(.odPressable)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    SettingsSectionHeader("官方 Skill Bundles")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("技能组合与沉淀")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
