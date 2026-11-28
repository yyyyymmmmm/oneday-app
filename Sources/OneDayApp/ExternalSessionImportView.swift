import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - #21 外部会话导入（Claude / Codex / ChatGPT / JSONL）

enum ExternalImportSource: String, CaseIterable, Identifiable {
    case auto = "自动识别"
    case claude = "Claude.ai (conversations.json)"
    case codex = "Codex / ChatGPT 导出包"
    case markdown = "Markdown 对话记录"
    var id: String { rawValue }
}

struct ParsedExternalThread: Identifiable, Equatable {
    struct Message: Equatable {
        let role: String
        let content: String
    }

    let id: String
    let title: String
    let sourceLabel: String
    let messages: [Message]
}

enum ExternalSessionParser {
    static func parse(data: Data, hint: ExternalImportSource) -> [ParsedExternalThread] {
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) {
            if let arr = jsonObj as? [[String: Any]] {
                let threads = arr.enumerated().compactMap { idx, dict in
                    parseConversationObject(dict, index: idx)
                }
                if !threads.isEmpty { return threads }
            } else if let dict = jsonObj as? [String: Any] {
                if let list = dict["conversations"] as? [[String: Any]] {
                    return list.enumerated().compactMap { parseConversationObject($0.element, index: $0.offset) }
                }
                if let single = parseConversationObject(dict, index: 0) {
                    return [single]
                }
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            // Try JSONL
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            var jsonlMessages: [ParsedExternalThread.Message] = []
            for line in lines {
                if let lineData = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let role = obj["role"] as? String,
                   let content = obj["content"] as? String {
                    jsonlMessages.append(.init(role: normalizeRole(role), content: content))
                }
            }
            if !jsonlMessages.isEmpty {
                return [
                    ParsedExternalThread(
                        id: UUID().uuidString,
                        title: "导入的 JSONL 会话",
                        sourceLabel: "Codex / JSONL",
                        messages: jsonlMessages
                    )
                ]
            }

            // Markdown fallback
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return [
                    ParsedExternalThread(
                        id: UUID().uuidString,
                        title: "导入的文本记录",
                        sourceLabel: hint == .markdown ? "Markdown" : "纯文本",
                        messages: [.init(role: "user", content: trimmed)]
                    )
                ]
            }
        }
        return []
    }

    private static func parseConversationObject(_ dict: [String: Any], index: Int) -> ParsedExternalThread? {
        let title = (dict["name"] as? String)
            ?? (dict["title"] as? String)
            ?? "外部会话 #\(index + 1)"

        // Claude.ai format: chat_messages[{sender, text}]
        if let chatMessages = dict["chat_messages"] as? [[String: Any]] {
            let msgs: [ParsedExternalThread.Message] = chatMessages.compactMap { item in
                let sender = (item["sender"] as? String) ?? "human"
                let text = (item["text"] as? String) ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return .init(role: normalizeRole(sender), content: text)
            }
            if !msgs.isEmpty {
                return ParsedExternalThread(
                    id: (dict["uuid"] as? String) ?? UUID().uuidString,
                    title: title,
                    sourceLabel: "Claude.ai",
                    messages: msgs
                )
            }
        }

        // OpenAI / Codex generic messages[{role, content}]
        if let rawMessages = dict["messages"] as? [[String: Any]] {
            let msgs: [ParsedExternalThread.Message] = rawMessages.compactMap { item in
                let role = (item["role"] as? String) ?? "user"
                let content = (item["content"] as? String) ?? ""
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return .init(role: normalizeRole(role), content: content)
            }
            if !msgs.isEmpty {
                return ParsedExternalThread(
                    id: (dict["id"] as? String) ?? UUID().uuidString,
                    title: title,
                    sourceLabel: "Codex / OpenAI",
                    messages: msgs
                )
            }
        }

        // ChatGPT mapping tree format
        if let mapping = dict["mapping"] as? [String: [String: Any]] {
            var collected: [(Double, ParsedExternalThread.Message)] = []
            for node in mapping.values {
                guard let message = node["message"] as? [String: Any],
                      let author = message["author"] as? [String: Any],
                      let role = author["role"] as? String,
                      role == "user" || role == "assistant",
                      let content = message["content"] as? [String: Any],
                      let parts = content["parts"] as? [Any]
                else { continue }
                let joined = parts.compactMap { $0 as? String }.joined(separator: "\n")
                guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let ts = (message["create_time"] as? Double) ?? 0
                collected.append((ts, .init(role: normalizeRole(role), content: joined)))
            }
            collected.sort { $0.0 < $1.0 }
            if !collected.isEmpty {
                return ParsedExternalThread(
                    id: (dict["id"] as? String) ?? UUID().uuidString,
                    title: title,
                    sourceLabel: "ChatGPT / Codex",
                    messages: collected.map(\.1)
                )
            }
        }

        return nil
    }

    private static func normalizeRole(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower == "human" || lower == "user" { return "user" }
        return "assistant"
    }
}

struct ExternalSessionImportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var source: ExternalImportSource = .auto
    @State private var showFileImporter = false
    @State private var pastedText = ""
    @State private var parsedThreads: [ParsedExternalThread] = []
    @State private var selectedIDs: Set<String> = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "square.and.arrow.down.on.square.fill",
                tint: Palette.tintLavenderInk,
                title: "外部会话导入",
                subtitle: "将 Claude.ai、Codex / ChatGPT 或 Markdown 历史对话无缝导入 OneDay，继续在 Hermes 中协作与检索。",
                statusText: parsedThreads.isEmpty ? "支持 JSON / JSONL / MD" : "已解析 \(parsedThreads.count) 条",
                statusTone: parsedThreads.isEmpty ? .neutral : .healthy
            )

            Section {
                Picker("来源格式", selection: $source) {
                    ForEach(ExternalImportSource.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "doc.badge.plus", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("从「文件」选择导出包")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text("选择 conversations.json、.jsonl 或 .md 文件")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .buttonStyle(.odPressable)
            } header: {
                SettingsSectionHeader("文件导入")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                TextEditor(text: $pastedText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                Button("解析粘贴的内容") {
                    parseRawData(Data(pastedText.utf8))
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                SettingsSectionHeader("或直接粘贴 JSON / Markdown")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if !parsedThreads.isEmpty {
                Section {
                    ForEach(parsedThreads) { thread in
                        let isSelected = selectedIDs.contains(thread.id)
                        Button {
                            Haptics.selection()
                            if isSelected {
                                selectedIDs.remove(thread.id)
                            } else {
                                selectedIDs.insert(thread.id)
                            }
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Palette.primary : Palette.inkMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(thread.title)
                                        .font(.rowTitleL)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text("\(thread.sourceLabel) · \(thread.messages.count) 条消息")
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        commitImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("导入选中的 \(selectedIDs.count) 条会话到 OneDay")
                                .font(.rowTitleL.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    }
                    .disabled(selectedIDs.isEmpty)
                    .listRowBackground(Palette.primary)
                } header: {
                    SettingsSectionHeader("待导入会话预览（\(parsedThreads.count)）")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            if let errorMessage {
                Section {
                    InlineError(errorMessage)
                }
                .listRowBackground(Palette.surface)
            }

            if let statusMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.success)
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("外部会话导入")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    parseRawData(data)
                } catch {
                    errorMessage = "读取文件失败：\(error.localizedDescription)"
                }
            case .failure(let error):
                errorMessage = "文件选择取消或失败：\(error.localizedDescription)"
            }
        }
    }

    private func parseRawData(_ data: Data) {
        errorMessage = nil
        statusMessage = nil
        let threads = ExternalSessionParser.parse(data: data, hint: source)
        if threads.isEmpty {
            errorMessage = "未能识别出有效的对话消息，请确认文件为 Claude / Codex JSON、JSONL 或 Markdown。"
        } else {
            parsedThreads = threads
            selectedIDs = Set(threads.map(\.id))
            Haptics.success()
        }
    }

    private func commitImport() {
        let targets = parsedThreads.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        var totalMessages = 0
        for item in targets {
            let thread = ChatThread(title: item.title)
            thread.titleIsManual = true
            modelContext.insert(thread)
            for msg in item.messages {
                let entry = ChatEntry(role: msg.role, content: msg.content, thread: thread)
                modelContext.insert(entry)
                totalMessages += 1
            }
        }
        try? modelContext.save()
        Haptics.success()
        statusMessage = "已成功导入 \(targets.count) 条会话（共 \(totalMessages) 条消息），可在侧边抽屉的旁聊列表中打开续聊。"
        parsedThreads = []
        selectedIDs = []
        pastedText = ""
    }
}
