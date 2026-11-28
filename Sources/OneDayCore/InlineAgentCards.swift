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

// MARK: - 分身委派任务卡（Hermes `delegate_task` → 让用户亲眼看到 AI 开分身干活）

public struct SubagentTaskSummary: Equatable, Sendable, Identifiable {
    public let id: String
    public let goal: String
    public let toolsets: [String]
    public let profile: String?

    public init(id: String, goal: String, toolsets: [String] = [], profile: String? = nil) {
        self.id = id
        self.goal = goal
        self.toolsets = toolsets
        self.profile = profile
    }
}

public struct SubagentDelegationCard: Equatable, Sendable {
    public let tasks: [SubagentTaskSummary]
    public let state: ToolCardPresentation.State
    public let output: String?

    public init(
        tasks: [SubagentTaskSummary],
        state: ToolCardPresentation.State,
        output: String?
    ) {
        self.tasks = tasks
        self.state = state
        self.output = output
    }
}

public enum SubagentDelegationParser {
    public static func parse(from card: ToolCard) -> SubagentDelegationCard? {
        let short = ToolCardClassifier.shortName(forToolName: card.toolName).lowercased()
        guard short == "delegate_task" || short == "delegate" || short == "subagent" else {
            return nil
        }
        var tasks: [SubagentTaskSummary] = []
        if let rawArgs = card.arguments,
           let data = rawArgs.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let batch = dict["tasks"] as? [[String: Any]], !batch.isEmpty {
                for (idx, item) in batch.enumerated() {
                    let goal = ((item["goal"] as? String)
                        ?? (item["task"] as? String)
                        ?? (item["prompt"] as? String)
                        ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !goal.isEmpty else { continue }
                    let toolsets = (item["toolsets"] as? [String]) ?? []
                    let profile = item["profile"] as? String
                    tasks.append(SubagentTaskSummary(
                        id: "sub-\(idx)",
                        goal: goal,
                        toolsets: toolsets,
                        profile: profile
                    ))
                }
            } else if let goal = ((dict["goal"] as? String)
                ?? (dict["task"] as? String)
                ?? (dict["prompt"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !goal.isEmpty {
                let toolsets = (dict["toolsets"] as? [String]) ?? []
                let profile = dict["profile"] as? String
                tasks.append(SubagentTaskSummary(
                    id: "sub-0",
                    goal: goal,
                    toolsets: toolsets,
                    profile: profile
                ))
            }
        }
        if tasks.isEmpty {
            let fallbackGoal = card.summary.isEmpty ? "并行执行子分身任务" : card.summary
            tasks.append(SubagentTaskSummary(id: "sub-0", goal: fallbackGoal))
        }
        let cleanedOutput: String? = {
            guard let res = card.result, !ToolResultUnwrap.isMeaningless(res) else { return nil }
            return res
        }()
        return SubagentDelegationCard(
            tasks: tasks,
            state: ToolCardPresentation.state(of: card),
            output: cleanedOutput
        )
    }
}

// MARK: - CLI 终端执行实时卡（Hermes `terminal` / `execute_code` / `process` / `shell`）

public struct TerminalExecutionCard: Equatable, Sendable {
    public let command: String
    public let kindLabel: String
    public let state: ToolCardPresentation.State
    public let output: String?

    public init(
        command: String,
        kindLabel: String,
        state: ToolCardPresentation.State,
        output: String?
    ) {
        self.command = command
        self.kindLabel = kindLabel
        self.state = state
        self.output = output
    }
}

public enum TerminalExecutionParser {
    public static func parse(from card: ToolCard) -> TerminalExecutionCard? {
        let short = ToolCardClassifier.shortName(forToolName: card.toolName).lowercased()
        guard short == "terminal"
            || short == "execute_code"
            || short == "process"
            || short == "shell"
        else { return nil }

        var commandText = ""
        if let rawArgs = card.arguments,
           let data = rawArgs.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let cmd = dict["command"] as? String, !cmd.isEmpty {
                commandText = cmd
            } else if let code = dict["code"] as? String, !code.isEmpty {
                commandText = code
            } else if let action = dict["action"] as? String, !action.isEmpty {
                let sid = (dict["session_id"] as? String) ?? ""
                commandText = sid.isEmpty ? "process \(action)" : "process \(action) \(sid)"
            }
        }
        if commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commandText = card.summary.isEmpty ? short : card.summary
        }

        let kindLabel: String = {
            switch short {
            case "execute_code": return "代码执行"
            case "process": return "后台进程"
            case "shell": return "云电脑终端"
            default: return "CLI 终端"
            }
        }()

        let cleanedOutput: String? = {
            guard let res = card.result, !ToolResultUnwrap.isMeaningless(res) else { return nil }
            return res
        }()

        return TerminalExecutionCard(
            command: commandText.trimmingCharacters(in: .whitespacesAndNewlines),
            kindLabel: kindLabel,
            state: ToolCardPresentation.state(of: card),
            output: cleanedOutput
        )
    }
}

// MARK: - 云电脑操作实时卡（Hermes `computer_act` / `browser_navigate` / `screenshot`）

public struct CloudComputerActionCard: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let state: ToolCardPresentation.State

    public init(title: String, detail: String, state: ToolCardPresentation.State) {
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public enum CloudComputerActionParser {
    public static func parse(from card: ToolCard) -> CloudComputerActionCard? {
        let short = ToolCardClassifier.shortName(forToolName: card.toolName).lowercased()
        guard short == "computer_act"
            || short == "browser_navigate"
            || short == "screenshot"
            || short == "box_view"
        else { return nil }
        let detail: String = {
            if !card.summary.isEmpty { return card.summary }
            if let first = ToolCardPresentation.firstMeaningfulLine(of: card.result) {
                return first
            }
            return "正在云电脑上执行操作"
        }()
        return CloudComputerActionCard(
            title: card.title,
            detail: detail,
            state: ToolCardPresentation.state(of: card)
        )
    }
}
