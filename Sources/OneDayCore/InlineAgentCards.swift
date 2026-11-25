import Foundation

/// Hermes v0.23.0 原生工具结构化卡片解析器：
/// 1) `todo` 工具 → 对话内实时/落定任务进度清单（TodoChecklistCard）
/// 2) `clarify` 工具 → 对话内结构化澄清提问卡（ClarifyPromptCard，点击选项直接回复）

public struct TodoChecklistItem: Equatable, Sendable, Identifiable {
    public enum Status: String, Equatable, Sendable {
        case completed
        case inProgress
        case pending
        case cancelled
    }

    public let id: String
    public let content: String
    public let status: Status

    public init(id: String, content: String, status: Status) {
        self.id = id
        self.content = content
        self.status = status
    }
}

public enum TodoChecklistParser {
    /// 判断是否为 Hermes `todo` 工具调用并解析任务条目列表
    public static func parse(from card: ToolCard) -> [TodoChecklistItem]? {
        let short = ToolCardClassifier.shortName(forToolName: card.toolName).lowercased()
        guard short == "todo" || short == "todo_write" || short == "todowrite" else {
            return nil
        }
        // 优先解析 arguments JSON（包含最新提交的 todos 列表），次选 result JSON
        for raw in [card.arguments, card.result].compactMap({ $0 }) {
            if let items = extractItems(fromJSONString: raw), !items.isEmpty {
                return items
            }
        }
        return nil
    }

    private static func extractItems(fromJSONString raw: String) -> [TodoChecklistItem]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        let rawList: [[String: Any]]?
        if let dict = obj as? [String: Any] {
            rawList = (dict["todos"] as? [[String: Any]])
                ?? (dict["items"] as? [[String: Any]])
                ?? (dict["tasks"] as? [[String: Any]])
        } else if let arr = obj as? [[String: Any]] {
            rawList = arr
        } else {
            rawList = nil
        }
        guard let list = rawList else { return nil }
        var result: [TodoChecklistItem] = []
        for (idx, item) in list.enumerated() {
            let text = (item["content"] as? String)
                ?? (item["title"] as? String)
                ?? (item["text"] as? String)
                ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let id = (item["id"] as? String) ?? "todo-\(idx)"
            let rawStatus = ((item["status"] as? String) ?? "pending").lowercased()
            let status: TodoChecklistItem.Status
            switch rawStatus {
            case "completed", "done", "finished":
                status = .completed
            case "in_progress", "inprogress", "running", "active":
                status = .inProgress
            case "cancelled", "canceled", "skipped":
                status = .cancelled
            default:
                status = .pending
            }
            result.append(TodoChecklistItem(id: id, content: trimmed, status: status))
        }
        return result
    }
}

public struct ClarifyPromptCard: Equatable, Sendable {
    public let question: String
    public let choices: [String]
    public let allowFreeform: Bool

    public init(question: String, choices: [String], allowFreeform: Bool = true) {
        self.question = question
        self.choices = choices
        self.allowFreeform = allowFreeform
    }
}

public enum ClarifyPromptParser {
    /// 判断是否为 Hermes `clarify` 工具调用并解析问题与选项
    public static func parse(from card: ToolCard) -> ClarifyPromptCard? {
        let short = ToolCardClassifier.shortName(forToolName: card.toolName).lowercased()
        guard short == "clarify" || short == "ask_user" else {
            return nil
        }
        for raw in [card.arguments, card.result].compactMap({ $0 }) {
            guard let data = raw.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let question = ((dict["question"] as? String)
                ?? (dict["prompt"] as? String)
                ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else { continue }
            var choices: [String] = []
            if let strChoices = dict["choices"] as? [String] {
                choices = strChoices
            } else if let strOptions = dict["options"] as? [String] {
                choices = strOptions
            } else if let objChoices = dict["choices"] as? [[String: Any]] {
                choices = objChoices.compactMap { ($0["label"] as? String) ?? ($0["text"] as? String) }
            }
            let cleanedChoices = choices
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let allowFreeform = (dict["allow_freeform"] as? Bool) ?? true
            return ClarifyPromptCard(
                question: question,
                choices: cleanedChoices,
                allowFreeform: allowFreeform
            )
        }
        return nil
    }
}
