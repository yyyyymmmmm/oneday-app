import Foundation

/// 聊天富内容纯逻辑（0.8.0，P1 包）：工具调用卡片的分类、
/// 人话标题与参数摘要、结果剥包裹、assistant/tool 行配对
/// 拼装、图片附件标记解析、文件路径探测、流式工具调用
/// 分片累积。全部对生产实查冻结的 fixture 写单测
/// （RichContentTests；样本来源见该文件头注）。
///
/// 载荷地基（2026-11-09 全功能施工图 §2＋本版收割复核）：
/// content 恒字符串；assistant 工具调用在 tool_calls
/// （function.name＋function.arguments JSON 字符串）；
/// tool 行以 tool_call_id 回联、tool_name 带真实工具名
/// （经 tool_call 间接层也一样）；MCP 结果带
/// <untrusted_tool_result source="…"> 包裹（内含一段英文
/// 免责声明＋{"result": …} JSON）；原生工具结果是 JSON
/// 字符串（terminal 的 {"output","exit_code"}、
/// vision_analyze 的 {"analysis"} 等）。

// MARK: - 卡片模型

public enum ToolCardCategory: String, Codable, Sendable, CaseIterable {
    case browser
    case desktop
    case search
    case file
    case terminal
    case memory
    case skill
    case vision
    case task
    case connection
    case device
    case other

    /// 中文类名（0.36.10，诊断 D3-3）：未知工具的标
    /// 题回落只许用它——英文短名只进详情，不上卡面
    /// （宪法 §8 零外文漏出）
    public var fallbackTitle: String {
        switch self {
        case .browser: return "浏览器操作"
        case .desktop: return "电脑操作"
        case .search: return "搜索查找"
        case .file: return "文件操作"
        case .terminal: return "运行命令"
        case .memory: return "记忆操作"
        case .skill: return "技能操作"
        case .vision: return "看图分析"
        case .task: return "任务操作"
        case .connection: return "连接管理"
        case .device: return "手机设备"
        case .other: return "工具调用"
        }
    }
}

/// 一张工具调用卡（可落盘：ChatEntry 以 JSON 编码保存）。
/// result 为 nil＝结果未回（如流式进行中）；resultFailed
/// 只认结果自带信号（exit_code 非 0／success 为 false）。
public struct ToolCard: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// 真实工具名（已穿透 tool_call 间接层）
    public let toolName: String
    public let category: ToolCardCategory
    /// 人话标题（中文映射优先，服务端 label 兜底）
    public let title: String
    /// 关键参数摘要（可为空串）
    public let summary: String
    public let result: String?
    public let resultFailed: Bool
    /// 原始参数全文（0.36.10，诊断 D3-1：参数原文撤
    /// 出卡面、只进点开详情）。旧落盘卡无此键——
    /// Optional 合成解码缺键回 nil，兼容既有数据；
    /// 直播卡由 events 构造、无参数通道，恒 nil，
    /// 落定以 transcript 重建补齐
    public let arguments: String?

    public init(
        id: String, toolName: String, category: ToolCardCategory,
        title: String, summary: String, result: String?,
        resultFailed: Bool, arguments: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.category = category
        self.title = title
        self.summary = summary
        self.result = result
        self.resultFailed = resultFailed
        self.arguments = arguments
    }
}

// MARK: - 参数 JSON 小工具

enum ToolArguments {
    /// arguments 是 JSON 字符串：解成字典，失败回 nil
    static func dictionary(from arguments: String) -> [String: Any]? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { return nil }
        return dict
    }

    static func string(_ dict: [String: Any]?, _ key: String) -> String? {
        guard let value = dict?[key] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    /// 首个 operations 元素（memory/skill_manage 的参数形态）
    static func firstOperation(
        _ dict: [String: Any]?
    ) -> [String: Any]? {
        guard let ops = dict?["operations"] as? [[String: Any]] else {
            return nil
        }
        return ops.first
    }

    /// 摘要截断：整词不切半，超限加省略号
    static func truncate(_ text: String, limit: Int = 90) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard oneLine.count > limit else { return oneLine }
        return String(oneLine.prefix(limit)) + "…"
    }
}

// MARK: - 分类与标题

public enum ToolCardClassifier {
    /// 去掉 MCP 前缀的短名（mcp__box__browser_navigate
    /// → browser_navigate；terminal → terminal）
    public static func shortName(forToolName name: String) -> String {
        guard name.hasPrefix("mcp__") else { return name }
        let parts = name.split(separator: "__", omittingEmptySubsequences: false)
        return parts.last.map(String.init) ?? name
    }

    public static func category(forToolName name: String) -> ToolCardCategory {
        let lower = name.lowercased()
        let short = shortName(forToolName: name).lowercased()
        if short.hasPrefix("browser") || short.contains("browser") {
            return .browser
        }
        // Box 桌面系（截图/接管/状态/桌面内 shell）归电脑卡
        if lower.hasPrefix("mcp__box__") { return .desktop }
        // 手机设备系（0.36.10）：须排在 search 之前——
        // contacts_search 含 search 字样、归设备不归搜索
        if short.hasPrefix("calendar_") || short.hasPrefix("reminders_")
            || short.hasPrefix("contacts_") || short.hasPrefix("health_")
            || short.hasPrefix("home_") || short.hasPrefix("device_") {
            return .device
        }
        // 连接管理系（0.36.10，诊断 D3-3 盲区补齐）
        if short == "manage_connections" || short.contains("connection") {
            return .connection
        }
        if short.contains("vision") || short == "image" {
            return .vision
        }
        if short.contains("search") { return .search }
        if short == "terminal" || short == "execute_code"
            || short.hasSuffix("_shell") || short.contains("terminal") {
            return .terminal
        }
        if short.contains("memory") { return .memory }
        if short.contains("skill") { return .skill }
        if short.contains("file") { return .file }
        if short.contains("kanban") || short.contains("task") {
            return .task
        }
        return .other
    }

    /// 中文人话标题：已知工具逐个映射；memory/skill 的
    /// 动作从参数 operations 里取；未知回 nil，调用方
    /// 以 fallbackTitle（中文类名）兜底（0.36.10）
    public static func title(
        forToolName name: String, arguments: String
    ) -> String? {
        let short = shortName(forToolName: name)
        let dict = ToolArguments.dictionary(from: arguments)
        switch short {
        case "browser_navigate": return "打开网页"
        case "browser_back", "browser_forward", "browser_reload":
            return "浏览器导航"
        case "browser_click": return "点击页面"
        case "browser_type": return "在页面输入"
        case "browser_snapshot", "browser_get_content",
             "browser_read", "browser_tabs":
            return "读取页面"
        case "box_status": return "查看云电脑状态"
        case "box_list": return "查看云电脑"
        case "screenshot", "computer_state": return "查看电脑画面"
        case "computer_act": return "操作电脑"
        case "box_view": return "打开电脑画面"
        case "shell": return "在云电脑运行命令"
        case "terminal": return "运行命令"
        case "execute_code": return "运行代码"
        case "vision_analyze": return "看图分析"
        case "tool_search": return "查找工具"
        case "manage_connections": return "管理连接"
        case "device_status": return "查看设备状态"
        case "calendar_list_events": return "查询日历日程"
        case "calendar_create_event": return "新建日程"
        case "calendar_update_event": return "修改日程"
        case "reminders_list": return "查看提醒事项"
        case "reminders_create": return "新建提醒"
        case "reminders_complete": return "完成提醒"
        case "contacts_search": return "查通讯录"
        case "health_daily_summary": return "查看健康摘要"
        case "home_status": return "查看家庭状态"
        case "web_search": return "联网搜索"
        case "tool_describe": return "查阅工具说明"
        case "tool_call": return "调用工具"
        case "read_file": return "读取文件"
        case "write_file": return "写入文件"
        case "kanban_complete": return "完成任务"
        case "memory":
            switch ToolArguments.string(
                ToolArguments.firstOperation(dict), "action"
            ) {
            case "add": return "写入记忆"
            case "replace", "update": return "更新记忆"
            case "remove", "delete": return "删除记忆"
            case "search": return "查找记忆"
            default: return "记忆操作"
            }
        case "skill_manage":
            switch ToolArguments.string(
                ToolArguments.firstOperation(dict), "action"
            ) {
            case "create": return "新建技能"
            case "update", "patch": return "更新技能"
            case "delete", "remove": return "删除技能"
            default: return "技能操作"
            }
        default:
            if short.hasPrefix("browser") { return "浏览器操作" }
            if short.hasPrefix("kanban") { return "任务操作" }
            return nil
        }
    }

    /// 标题回落（0.36.10，诊断 D3-3）：映射表与服务
    /// 端 label 都没有时，用分类的中文类名——英文短
    /// 名从此不上卡面（只进详情的「工具名」行）
    public static func fallbackTitle(forToolName name: String) -> String {
        category(forToolName: name).fallbackTitle
    }

    /// 直播期摘要净化（0.36.10）：events 的 preview 原
    /// 文单行化＋90 字截断，与落定摘要同口径
    public static func sanitizedSummary(_ text: String) -> String {
        ToolArguments.truncate(text)
    }

    /// 命令摘要（0.36.10，诊断 D3-5）：先取首行；首
    /// 行内以 ; ／ && ／ || 拼接多条命令时呈「N 条
    /// 命令 · 首条 …」，不整段直出（实拍事故：整串
    /// 复合命令上卡两行截断）。多行脚本仍只取首行
    public static func commandSummary(_ command: String) -> String {
        let firstLine = command
            .split(separator: "\n")
            .first.map(String.init) ?? ""
        let segments = firstLine
            .replacingOccurrences(of: "&&", with: ";")
            .replacingOccurrences(of: "||", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard segments.count > 1, let first = segments.first
        else {
            return ToolArguments.truncate(firstLine)
        }
        return ToolArguments.truncate(
            "\(segments.count) 条命令 · \(first)"
        )
    }

    /// 关键参数摘要：按工具取最能说明「在干什么」的一个
    /// 字段；取不到给空串（卡面只剩标题，不编造）
    public static func summary(
        forToolName name: String, arguments: String
    ) -> String {
        let short = shortName(forToolName: name)
        let dict = ToolArguments.dictionary(from: arguments)
        let raw: String?
        switch short {
        case "terminal":
            // 复合命令走命令摘要（N 条命令 · 首条），
            // 不整段直出（0.36.10，诊断 D3-5）
            if let command = ToolArguments.string(dict, "command") {
                return commandSummary(command)
            }
            raw = nil
        case "execute_code":
            raw = ToolArguments.string(dict, "code")?
                .split(separator: "\n")
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(String.init)
        case "browser_navigate":
            raw = ToolArguments.string(dict, "url")
        case "vision_analyze":
            raw = ToolArguments.string(dict, "question")
                ?? ToolArguments.string(dict, "image_url")
                .map { ($0 as NSString).lastPathComponent }
        case "tool_search":
            raw = (dict?["queries"] as? [String])?.first
        case "tool_describe":
            raw = (dict?["names"] as? [String])
                .map { $0.map { shortName(forToolName: $0) } }
                .map { $0.joined(separator: "、") }
        case "memory":
            let op = ToolArguments.firstOperation(dict)
            raw = ToolArguments.string(op, "content")
                ?? ToolArguments.string(op, "name")
        case "skill_manage":
            let op = ToolArguments.firstOperation(dict)
            raw = ToolArguments.string(op, "name")
                ?? ToolArguments.string(op, "content")?
                .split(separator: "\n").first.map(String.init)
        case "kanban_complete":
            raw = ToolArguments.string(dict, "summary")
        default:
            // 默认字段序命中即取；命中 command 字段同
            // 走命令摘要净化（0.36.10，诊断 D3-5）
            var picked: String?
            for key in ["url", "path", "file_path", "file",
                        "query", "name", "command"] {
                if let value = ToolArguments.string(dict, key) {
                    picked = key == "command"
                        ? commandSummary(value) : value
                    break
                }
            }
            raw = picked
        }
        return raw.map { ToolArguments.truncate($0) } ?? ""
    }
}

// MARK: - 结果剥包裹

public enum ToolResultUnwrap {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let failed: Bool
    }

    /// 无意义输出判定（0.36.10，诊断 D3-7）：空、或
    /// 通篇只有分隔符/空白（如 terminal 回的 "---"）
    /// ——呈现层据此显「（无输出）」，不把符号当内容
    /// 画（实拍事故：虚线般的 "---" 被当结果正文）
    public static func isMeaningless(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty { return true }
        let separators = CharacterSet(
            charactersIn: "-=*_~#·•—–―|/\\<> "
        )
        return trimmed.unicodeScalars.allSatisfy {
            separators.contains($0)
        }
    }

    /// tool 行 content → 可展示文本＋失败标记。处理链：
    /// untrusted 包裹（剥标签＋免责声明）→ JSON 分型
    /// （result/output/analysis/tools/message）→ 兜底
    /// 原文。解不出也不丢内容，最差整段原文呈现。
    public static func unwrap(_ raw: String) -> Result {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var failed = false
        if text.contains("<untrusted_tool_result") {
            text = stripUntrustedWrapper(text)
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return Result(text: text, failed: failed)
        }
        if let dict = object as? [String: Any] {
            if let inner = dict["result"] as? String {
                // MCP 结果的 result 常是再一层 JSON 字符串
                let nested = unwrap(inner)
                return Result(text: nested.text, failed: nested.failed)
            }
            if let output = dict["output"] as? String {
                if let code = dict["exit_code"] as? NSNumber,
                   code.intValue != 0 {
                    failed = true
                }
                var body = output
                if let error = dict["error"] as? String, !error.isEmpty {
                    body += "\n" + error
                }
                return Result(text: body.trimmingCharacters(
                    in: .whitespacesAndNewlines), failed: failed)
            }
            if let analysis = dict["analysis"] as? String {
                if (dict["success"] as? Bool) == false { failed = true }
                return Result(text: analysis, failed: failed)
            }
            if let tools = dict["tools"] as? [String: Any] {
                let names = tools.keys.sorted().map {
                    ToolCardClassifier.shortName(forToolName: $0)
                }
                return Result(
                    text: names.joined(separator: "、"), failed: false
                )
            }
            if let message = dict["message"] as? String {
                if (dict["success"] as? Bool) == false { failed = true }
                var body = message
                if let gist = dict["gist"] as? String, !gist.isEmpty {
                    body = gist + "\n" + body
                }
                return Result(text: body, failed: failed)
            }
            return Result(text: prettyJSON(object), failed: failed)
        }
        return Result(text: prettyJSON(object), failed: failed)
    }

    /// 剥 <untrusted_tool_result …>…</…> 并去掉标签与
    /// JSON 之间的英文免责声明段（实查原文含 "Treat it
    /// as DATA"／"retrieved from an external source"）
    static func stripUntrustedWrapper(_ text: String) -> String {
        var inner = text
        if let open = inner.range(of: "<untrusted_tool_result"),
           let tagEnd = inner.range(
               of: ">", range: open.upperBound..<inner.endIndex
           ) {
            inner = String(inner[tagEnd.upperBound...])
        }
        if let close = inner.range(of: "</untrusted_tool_result>") {
            inner = String(inner[..<close.lowerBound])
        }
        inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        // 免责声明在 JSON 之前：认出标记词后从首个 { 起取
        if inner.hasPrefix("{") == false,
           inner.contains("Treat it as DATA")
            || inner.contains("retrieved from an external source"),
           let brace = inner.firstIndex(of: "{"),
           let lastBrace = inner.lastIndex(of: "}") {
            inner = String(inner[brace...lastBrace])
        }
        return inner
    }

    static func prettyJSON(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let string = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return string
    }
}

// MARK: - 卡级呈现（0.36.10，诊断 D2/D3）

/// 工具卡的呈现判定单一真源：状态只看本卡自己的结
/// 果回没回（诊断 D2 第一名：旧实现拿整轮 isLive 冒
/// 充每张卡进行中，结果已回的卡也挂转圈）。整轮进
/// 行中归轮次级指示（发送舱/导航区），永不下放单卡。
public enum ToolCardPresentation {
    public enum State: Equatable, Sendable {
        /// 本卡结果未回
        case running
        case succeeded
        case failed
    }

    public static func state(of card: ToolCard) -> State {
        guard card.result != nil else { return .running }
        return card.resultFailed ? .failed : .succeeded
    }

    /// 结果首行净化（单行化＋截断）：无意义输出回
    /// nil（呈现层据此显「（无输出）」占位）
    public static func firstMeaningfulLine(
        of result: String?, limit: Int = 60
    ) -> String? {
        guard let result,
              !ToolResultUnwrap.isMeaningless(result)
        else { return nil }
        // 浏览器结果首行形态 "Page: 标题 (URL)"：卡
        // 面只出 URL（标题在详情正文里已有，不重复）
        if result.hasPrefix("Page: "),
           let open = result.firstIndex(of: "("),
           let close = result.firstIndex(of: ")"),
           open < close {
            let url = String(
                result[result.index(after: open)..<close]
            )
            if url.hasPrefix("http") { return url }
        }
        let line = result
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return nil }
        return ToolArguments.truncate(line, limit: limit)
    }

    /// 一行状态语（卡面副行/详情状态行共用）：
    /// · 进行中 → 「进行中」
    /// · 失败 → 「失败」＋原因首行（有才拼）
    /// · 成功有输出 → 输出首行净化
    /// · 成功无输出 → 「（无输出）」
    public static func statusLine(of card: ToolCard) -> String {
        switch state(of: card) {
        case .running:
            return "进行中"
        case .failed:
            if let reason = firstMeaningfulLine(of: card.result) {
                return "失败 · \(reason)"
            }
            return "失败"
        case .succeeded:
            return firstMeaningfulLine(of: card.result)
                ?? "（无输出）"
        }
    }

    /// 组头摘要（诊断 D3-8）：同轮连续 ≥2 张卡收成
    /// 一组，组头一行说清总数与命运分布；失败不隐藏
    /// （D3-9），进行中如实计数
    public static func groupHeader(cards: [ToolCard]) -> String {
        let total = cards.count
        let running = cards.filter { $0.result == nil }.count
        let failed = cards.filter {
            $0.result != nil && $0.resultFailed
        }.count
        var parts = ["调用了 \(total) 个工具"]
        if running > 0 {
            parts.append("\(running) 个进行中")
            if failed > 0 { parts.append("\(failed) 个失败") }
        } else if failed > 0 {
            parts.append("\(failed) 个失败")
        } else {
            parts.append("全部完成")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 配对拼装

/// 历史消息 → 呈现项：普通消息与工具卡按服务端原序。
/// tool 行不单独成项（被配对进卡）；session_meta/system
/// 不成项（与既有导入口径一致）。卡带源消息时间，导入
/// 落盘排序用。
public enum RichHistoryItem: Sendable {
    case message(SessionMessage)
    case toolCard(ToolCard, date: Date?)
}

public enum ToolCardBuilder {
    public static func build(
        from messages: [SessionMessage]
    ) -> [RichHistoryItem] {
        var rowsByCallID: [String: SessionMessage] = [:]
        for message in messages where message.role == "tool" {
            if let callID = message.toolCallID {
                rowsByCallID[callID] = message
            }
        }
        var items: [RichHistoryItem] = []
        for message in messages {
            guard message.role == "user" || message.role == "assistant"
            else { continue }
            items.append(.message(message))
            for (index, call) in message.toolCalls.enumerated() {
                items.append(.toolCard(
                    card(for: call, index: index, in: message,
                         row: rowsByCallID[call.id]),
                    date: message.date
                ))
            }
        }
        return items
    }

    static func card(
        for call: SessionToolCall, index: Int,
        in message: SessionMessage, row: SessionMessage?
    ) -> ToolCard {
        var realName = call.name
        var effectiveArguments = call.arguments
        // tool_call 间接层先解内层：真实名与参数都在里面
        if call.name == "tool_call",
           let inner = innerCall(of: call.arguments) {
            realName = inner.name
            effectiveArguments = inner.arguments
        }
        // 真实名最终优先信 tool 行（实查：间接层行也带
        // 真实名，与内层解包互为印证）
        if let rowName = row?.toolName, !rowName.isEmpty {
            realName = rowName
        }
        // 0.36.10（诊断 D3-3）：标题回落改中文类名——
        // 服务端 label 与英文短名退出卡面回落链（label
        // 可能是外文、短名必为外文，宪法 §8）；英文
        // 原名保留在 toolName、只进详情
        let title = ToolCardClassifier.title(
            forToolName: realName, arguments: effectiveArguments
        ) ?? ToolCardClassifier.fallbackTitle(forToolName: realName)
        let unwrapped = row.map { ToolResultUnwrap.unwrap($0.content) }
        return ToolCard(
            id: call.id.isEmpty
                ? "msg-\(Int(message.id))-\(index)" : call.id,
            toolName: realName,
            category: ToolCardClassifier.category(forToolName: realName),
            title: title,
            summary: ToolCardClassifier.summary(
                forToolName: realName, arguments: effectiveArguments
            ),
            result: unwrapped?.text,
            resultFailed: unwrapped?.failed ?? false,
            arguments: effectiveArguments.isEmpty
                ? nil : effectiveArguments
        )
    }

    /// tool_call 间接层参数：{"calls": [{"name": …,
    /// "arguments": {…}}]}，取首个内层调用
    static func innerCall(
        of arguments: String
    ) -> (name: String, arguments: String)? {
        guard let dict = ToolArguments.dictionary(from: arguments),
              let calls = dict["calls"] as? [[String: Any]],
              let first = calls.first,
              let name = first["name"] as? String else { return nil }
        var argumentsString = ""
        if let innerArgs = first["arguments"],
           let data = try? JSONSerialization.data(
               withJSONObject: innerArgs, options: [.sortedKeys]
           ) {
            argumentsString = String(data: data, encoding: .utf8) ?? ""
        }
        return (name, argumentsString)
    }
}

// MARK: - 图片附件标记

/// 服务端落盘的图片消息形态（生产实查，combo-smoke 会话）：
/// user 正文里嵌 "[Image attached at: /opt/data/…/x.png]"
/// 标记，图片本体在服务器该路径（可经 /api/files/download
/// 取回，本版实测 200＋PNG 魔数通过）。
public enum AttachedImageRef {
    public static func parse(
        _ content: String
    ) -> (text: String, paths: [String]) {
        guard content.contains("[Image attached at:") else {
            return (content, [])
        }
        let pattern = #"\[Image attached at: ([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return (content, []) }
        let range = NSRange(content.startIndex..., in: content)
        var paths: [String] = []
        let cleaned = regex.stringByReplacingMatches(
            in: content, range: range, withTemplate: ""
        )
        for match in regex.matches(in: content, range: range) {
            if let pathRange = Range(match.range(at: 1), in: content) {
                paths.append(String(content[pathRange])
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        // 标记抽走后收拾空行：三连换行压成两连、去首尾空白
        var text = cleaned
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return (
            text.trimmingCharacters(in: .whitespacesAndNewlines), paths
        )
    }
}

// MARK: - 文件引用探测

/// 从消息文本里探测可预览的服务端文件路径（绝对路径＋
/// 已知扩展名）。文件消息在现有历史里无样本（2026-11-09
/// 全扫零命中），本探测按实查路径形态（/opt/data/cache/
/// documents、/opt/data/… 的 agent 产出）施工：命中即
/// 文件牌，点击走既有 /api/files/download 取回预览。
public enum FileRefDetector {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic",
    ]

    private static let pattern =
        #"/[A-Za-z0-9_\-./]+?\.(?:pdf|docx?|xlsx?|pptx?|md|txt|csv|json|zip|png|jpe?g|gif|webp|heic|mp3|wav|m4a|mp4|mov)\b"#

    public static func detect(
        in text: String, excluding excluded: [String] = []
    ) -> [String] {
        guard text.contains("/") else { return [] }
        guard let regex = try? NSRegularExpression(
            pattern: Self.pattern, options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen: Set<String> = Set(excluded)
        var found: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text)
            else { continue }
            // URL 的路径段不是服务端文件：前一字符是冒号
            // （:// 的一部分）时跳过
            if matchRange.lowerBound > text.startIndex {
                let before = text[text.index(
                    before: matchRange.lowerBound
                )]
                if before == ":" { continue }
            }
            let path = String(text[matchRange])
            // "//…" 是 URL 的残段不是路径；至少含一层目录
            // （裸 "/x.pdf" 不是服务端产出形态）
            guard !path.hasPrefix("//"),
                  path.dropFirst().contains("/") else { continue }
            if seen.insert(path).inserted {
                found.append(path)
            }
        }
        return found
    }

    public static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}

// MARK: - 流式工具调用累积

/// 流式 delta.tool_calls 分片累积（OpenAI 流式形态：
/// 同一 index 的 name/arguments 分多片到达）。一片跨
/// index＝前一片调用完成。服务端是否真下发此分片未经
/// 生产实测（红线：不许新跑 agent 任务验证）：解码与
/// 累积按标准形态防御式实现，无分片时恒为空、零影响。
public struct ToolCallStreamAccumulator: Sendable {
    private struct Pending {
        var id: String = ""
        var name: String = ""
        var arguments: String = ""
    }

    private var pending: [Int: Pending] = [:]
    private var order: [Int] = []
    private var lastIndex: Int?

    public init() {}

    /// 喂入一批分片，返回本批内刚完成的调用卡
    public mutating func ingest(
        _ fragments: [ChatStreamChunk.ToolCallFragment]
    ) -> [ToolCard] {
        var completed: [ToolCard] = []
        for fragment in fragments {
            let index = fragment.index ?? lastIndex ?? 0
            if let last = lastIndex, index != last,
               let done = pending[last] {
                if let card = Self.makeCard(done, index: last) {
                    completed.append(card)
                }
                pending[last] = nil
            }
            var current = pending[index] ?? Pending()
            if let id = fragment.id, !id.isEmpty { current.id = id }
            if let name = fragment.function?.name {
                current.name += name
            }
            if let arguments = fragment.function?.arguments {
                current.arguments += arguments
            }
            pending[index] = current
            if !order.contains(index) { order.append(index) }
            lastIndex = index
        }
        return completed
    }

    /// 流结束时收尾：余下未完成的调用一并成卡
    public mutating func flush() -> [ToolCard] {
        let cards = order.compactMap { index in
            pending[index].flatMap { Self.makeCard($0, index: index) }
        }
        pending.removeAll()
        order.removeAll()
        lastIndex = nil
        return cards
    }

    private static func makeCard(
        _ pending: Pending, index: Int
    ) -> ToolCard? {
        guard !pending.name.isEmpty else { return nil }
        var name = pending.name
        var arguments = pending.arguments
        if name == "tool_call",
           let inner = ToolCardBuilder.innerCall(of: arguments) {
            name = inner.name
            arguments = inner.arguments
        }
        return ToolCard(
            id: pending.id.isEmpty ? "stream-\(index)" : pending.id,
            toolName: name,
            category: ToolCardClassifier.category(forToolName: name),
            title: ToolCardClassifier.title(
                forToolName: name, arguments: arguments
            ) ?? ToolCardClassifier.fallbackTitle(forToolName: name),
            summary: ToolCardClassifier.summary(
                forToolName: name, arguments: arguments
            ),
            result: nil,
            resultFailed: false,
            arguments: arguments.isEmpty ? nil : arguments
        )
    }
}
