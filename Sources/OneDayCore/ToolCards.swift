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
        fallbackTitle(locale: AppLocale.uiLocale)
    }

    /// 类名的目录取词形（0.42.1 国际化长尾包）
    public func fallbackTitle(locale: Locale) -> String {
        switch self {
        case .browser: return L10n.string("浏览器操作", locale: locale)
        case .desktop: return L10n.string("电脑操作", locale: locale)
        case .search: return L10n.string("搜索查找", locale: locale)
        case .file: return L10n.string("文件操作", locale: locale)
        case .terminal: return L10n.string("运行命令", locale: locale)
        case .memory: return L10n.string("记忆操作", locale: locale)
        case .skill: return L10n.string("技能操作", locale: locale)
        case .vision: return L10n.string("看图分析", locale: locale)
        case .task: return L10n.string("任务操作", locale: locale)
        case .connection: return L10n.string("连接管理", locale: locale)
        case .device: return L10n.string("手机设备", locale: locale)
        case .other: return L10n.string("工具调用", locale: locale)
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
            || short.hasPrefix("home_") || short.hasPrefix("device_")
            || short.hasPrefix("clipboard_") || short.hasPrefix("files_")
            || short.hasPrefix("alarm_") || short.hasPrefix("notify_")
            || short.hasPrefix("open_")
            || short.hasPrefix("camera_") || short.hasPrefix("translate_")
            || short.hasPrefix("ondevice_") || short.hasPrefix("auth_")
            || short == "vision_ocr" || short == "vision_scan_code"
            || short == "vision_document_scan"
            // 批四日常面：前缀五组＋无前缀四件逐名
            // （file_preview/file_print 须抢在下方
            // contains("file") 的文件类之前落设备类）
            || short.hasPrefix("location_") || short.hasPrefix("media_")
            || short.hasPrefix("compose_") || short.hasPrefix("shortcut_")
            || short == "call_start" || short == "share_sheet"
            || short == "file_preview" || short == "file_print" {
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
        forToolName name: String, arguments: String,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        let short = shortName(forToolName: name)
        let dict = ToolArguments.dictionary(from: arguments)
        switch short {
        case "browser_navigate": return L10n.string("打开网页", locale: locale)
        case "browser_back", "browser_forward", "browser_reload":
            return L10n.string("浏览器导航", locale: locale)
        case "browser_click": return L10n.string("点击页面", locale: locale)
        case "browser_type": return L10n.string("在页面输入", locale: locale)
        case "browser_snapshot", "browser_get_content",
             "browser_read", "browser_tabs":
            return L10n.string("读取页面", locale: locale)
        case "box_status": return L10n.string("查看云电脑状态", locale: locale)
        case "box_list": return L10n.string("查看云电脑", locale: locale)
        case "screenshot", "computer_state":
            return L10n.string("查看电脑画面", locale: locale)
        case "computer_act": return L10n.string("操作电脑", locale: locale)
        case "box_view": return L10n.string("打开电脑画面", locale: locale)
        case "shell": return L10n.string("在云电脑运行命令", locale: locale)
        case "terminal": return L10n.string("运行命令", locale: locale)
        case "execute_code": return L10n.string("运行代码", locale: locale)
        case "vision_analyze": return L10n.string("看图分析", locale: locale)
        case "tool_search": return L10n.string("查找工具", locale: locale)
        case "manage_connections": return L10n.string("管理连接", locale: locale)
        case "device_status": return L10n.string("查看设备状态", locale: locale)
        case "calendar_list_events": return L10n.string("查询日历日程", locale: locale)
        case "calendar_create_event": return L10n.string("新建日程", locale: locale)
        case "calendar_update_event": return L10n.string("修改日程", locale: locale)
        case "reminders_list": return L10n.string("查看提醒事项", locale: locale)
        case "reminders_create": return L10n.string("新建提醒", locale: locale)
        case "reminders_complete": return L10n.string("完成提醒", locale: locale)
        case "contacts_search": return L10n.string("查通讯录", locale: locale)
        case "clipboard_get": return L10n.string("读取剪贴板", locale: locale)
        case "clipboard_set": return L10n.string("写入剪贴板", locale: locale)
        case "files_list": return L10n.string("查看文件列表", locale: locale)
        case "files_read": return L10n.string("读取文件", locale: locale)
        case "files_write": return L10n.string("写入文件", locale: locale)
        case "alarm_set": return L10n.string("设定闹钟", locale: locale)
        case "alarm_list": return L10n.string("查看闹钟", locale: locale)
        case "alarm_cancel": return L10n.string("取消闹钟", locale: locale)
        case "notify_post": return L10n.string("发送本地通知", locale: locale)
        case "open_target": return L10n.string("打开指定页面", locale: locale)
        case "camera_capture": return L10n.string("拍照", locale: locale)
        case "vision_ocr": return L10n.string("识别图片文字", locale: locale)
        case "vision_scan_code": return L10n.string("扫描条码", locale: locale)
        case "vision_document_scan": return L10n.string("扫描文档", locale: locale)
        case "translate_text": return L10n.string("翻译文字", locale: locale)
        case "ondevice_model_run": return L10n.string("端上智能回答", locale: locale)
        case "auth_biometric": return L10n.string("本人确认", locale: locale)
        case "location_current": return L10n.string("查看当前位置", locale: locale)
        case "location_search_places": return L10n.string("搜索附近地点", locale: locale)
        case "location_geocode": return L10n.string("地址坐标换算", locale: locale)
        case "media_library_search": return L10n.string("搜索媒体库", locale: locale)
        case "media_playlists": return L10n.string("查看歌单", locale: locale)
        case "media_playlist_create": return L10n.string("新建歌单", locale: locale)
        case "media_playback_control": return L10n.string("控制音乐播放", locale: locale)
        case "call_start": return L10n.string("拨打电话", locale: locale)
        case "compose_sms": return L10n.string("写短信", locale: locale)
        case "compose_email": return L10n.string("写邮件", locale: locale)
        case "share_sheet": return L10n.string("分享内容", locale: locale)
        case "shortcut_run": return L10n.string("运行快捷指令", locale: locale)
        case "device_info": return L10n.string("查看设备信息", locale: locale)
        case "file_preview": return L10n.string("预览文件", locale: locale)
        case "file_print": return L10n.string("打印文件", locale: locale)
        case "health_daily_summary": return L10n.string("查看健康摘要", locale: locale)
        case "home_status": return L10n.string("查看家庭状态", locale: locale)
        case "web_search": return L10n.string("联网搜索", locale: locale)
        case "tool_describe": return L10n.string("查阅工具说明", locale: locale)
        case "tool_call": return L10n.string("调用工具", locale: locale)
        case "read_file": return L10n.string("读取文件", locale: locale)
        case "write_file": return L10n.string("写入文件", locale: locale)
        case "kanban_complete": return L10n.string("完成任务", locale: locale)
        case "memory":
            switch ToolArguments.string(
                ToolArguments.firstOperation(dict), "action"
            ) {
            case "add": return L10n.string("写入记忆", locale: locale)
            case "replace", "update": return L10n.string("更新记忆", locale: locale)
            case "remove", "delete": return L10n.string("删除记忆", locale: locale)
            case "search": return L10n.string("查找记忆", locale: locale)
            default: return L10n.string("记忆操作", locale: locale)
            }
        case "skill_manage":
            switch ToolArguments.string(
                ToolArguments.firstOperation(dict), "action"
            ) {
            case "create": return L10n.string("新建技能", locale: locale)
            case "update", "patch": return L10n.string("更新技能", locale: locale)
            case "delete", "remove": return L10n.string("删除技能", locale: locale)
            default: return L10n.string("技能操作", locale: locale)
            }
        default:
            if short.hasPrefix("browser") {
                return L10n.string("浏览器操作", locale: locale)
            }
            if short.hasPrefix("kanban") {
                return L10n.string("任务操作", locale: locale)
            }
            return nil
        }
    }

    /// 标题回落（0.36.10，诊断 D3-3）：映射表与服务
    /// 端 label 都没有时，用分类的中文类名——英文短
    /// 名从此不上卡面（只进详情的「工具名」行）
    public static func fallbackTitle(
        forToolName name: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
        category(forToolName: name).fallbackTitle(locale: locale)
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
    public static func commandSummary(
        _ command: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
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
            L10n.format(
                "%lld 条命令 · %@", locale: locale, segments.count, first
            )
        )
    }

    /// 关键参数摘要：按工具取最能说明「在干什么」的一个
    /// 字段；取不到给空串（卡面只剩标题，不编造）
    public static func summary(
        forToolName name: String, arguments: String,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let short = shortName(forToolName: name)
        let dict = ToolArguments.dictionary(from: arguments)
        let raw: String?
        switch short {
        case "terminal":
            // 复合命令走命令摘要（N 条命令 · 首条），
            // 不整段直出（0.36.10，诊断 D3-5）
            if let command = ToolArguments.string(dict, "command") {
                return commandSummary(command, locale: locale)
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
    public static func statusLine(
        of card: ToolCard, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch state(of: card) {
        case .running:
            return L10n.string("进行中", locale: locale)
        case .failed:
            if let reason = firstMeaningfulLine(of: card.result) {
                return L10n.format("失败 · %@", locale: locale, reason)
            }
            return L10n.string("失败", locale: locale)
        case .succeeded:
            return firstMeaningfulLine(of: card.result)
                ?? L10n.string("（无输出）", locale: locale)
        }
    }

    /// 组头摘要（诊断 D3-8）：同轮连续 ≥2 张卡收成
    /// 一组，组头一行说清总数与命运分布；失败不隐藏
    /// （D3-9），进行中如实计数
    public static func groupHeader(
        cards: [ToolCard], locale: Locale = AppLocale.uiLocale
    ) -> String {
        let total = cards.count
        let running = cards.filter { $0.result == nil }.count
        let failed = cards.filter {
            $0.result != nil && $0.resultFailed
        }.count
        var parts = [
            L10n.format("调用了 %lld 个工具", locale: locale, total)
        ]
        if running > 0 {
            parts.append(
                L10n.format("%@ 个进行中", locale: locale, String(running))
            )
            if failed > 0 {
                parts.append(
                    L10n.format("%@ 个失败", locale: locale, String(failed))
                )
            }
        } else if failed > 0 {
            parts.append(
                L10n.format("%@ 个失败", locale: locale, String(failed))
            )
        } else {
            parts.append(L10n.string("全部完成", locale: locale))
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

// MARK: - 网关附件展开块

/// 网关把 user 消息尾的 `@file:` 引用展开成给模型看的
/// 指令块、并把展开全文存进会话记录（0.46.1 热修，
/// 生产样本＝消息 947）：头部＝用户正文＋独立成行的
/// `@file:` 引用行，`--- Attached Context ---` 行之后
/// 是逐条 `📎 @file:` 附件说明＋英文指令全文。展开块
/// 是给模型的脚手架、不是用户的话——导入与对账判同
/// 都先过本解析还原成（干净正文，附件路径两分）。
/// 解析保守：无分隔块且无独立成行 `@file:` 引用、或
/// 剥不出任何路径时，原文逐字返回（正文里的行内
/// `@file:` 提及不动）。0.46.1 扩围 A 补全形态（网关
/// context_references.py 源码五形态）：📄 文本内联块
/// （头行收路径、围栏全文不进显示、切块围栏感知）、
/// `--- Context Warnings ---` 警告块整段剥离、📁/🌐/
/// 📌 块只剥不出牌、块头与头部路径的行段后缀剥离、
/// 📎 文本过大变体（描述段 `text file, approximately
/// … tokens`）同 📎 收路径。
public enum AttachedContextRef {
    public struct Parsed: Equatable, Sendable {
        public let text: String
        public let imagePaths: [String]
        public let fileRefs: [String]

        public init(
            text: String, imagePaths: [String], fileRefs: [String]
        ) {
            self.text = text
            self.imagePaths = imagePaths
            self.fileRefs = fileRefs
        }
    }

    /// 分隔行原文（网关展开块的头尾分界）
    public static let separatorLine = "--- Attached Context ---"

    /// 警告块分隔行（网关在展开失败/超限时追加给模型
    /// 的系统行，0.46.1 扩围 A：整段剥离不渲染）
    public static let warningsLine = "--- Context Warnings ---"

    /// 尾部块头标记：📎＝二进制/过大文本的在盘说明、
    /// 📄＝文本全文内联；📁（文件夹）/🌐（网址）/
    /// 📌（插件）为跨端可带入的形态——只剥不出牌
    private static let pathBlockMarkers: Set<Character> = ["📎", "📄"]
    private static let stripOnlyBlockMarkers: Set<Character> = [
        "📁", "🌐", "📌",
    ]

    public static func parse(_ content: String) -> Parsed {
        guard content.contains("@file:")
            || content.contains("@folder:")
            || content.contains(separatorLine)
            || content.contains(warningsLine)
        else {
            return Parsed(text: content, imagePaths: [], fileRefs: [])
        }
        let lines = content.components(separatedBy: "\n")
        var headLines = lines
        var tailLines: [String] = []
        // touched＝确实动过脚手架（分隔块/警告块/块头
        // 任一出现）：📁 等无路径块也必须剥干净，不能
        // 因剥不出路径就把整段列举原文回给气泡
        var touched = false
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces)
                == separatorLine
        }) {
            headLines = Array(lines[..<index])
            tailLines = Array(lines[(index + 1)...])
            touched = true
        }
        var paths: [String] = []
        var seen = Set<String>()
        func collect(_ rawPath: String) {
            // 行段后缀（@file:<路径>:10-20）不是路径的
            // 一部分，出牌前剥掉（扩围 A-④）
            let path = stripLineRange(rawPath)
            guard !path.isEmpty else { return }
            if seen.insert(path).inserted { paths.append(path) }
        }
        // 头部：独立成行的 @file 引用行剥掉收路径，其
        // 余行即用户正文（保原序原样）；警告块整段丢
        // 弃——标记行起其后头部行全是系统行（网关把
        // 警告追加在正文与展开块之间，正文恒在前）
        var kept: [String] = []
        var headInWarnings = false
        for line in headLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == warningsLine {
                headInWarnings = true
                touched = true
                continue
            }
            if headInWarnings { continue }
            if isStandaloneFolderRef(trimmed) {
                // 文件夹引用行同为脚手架：剥掉不出牌
                // （文件夹没有可下载的文件牌形态）
                touched = true
                continue
            }
            if let path = standaloneFileRef(in: line) {
                collect(path)
            } else {
                kept.append(line)
            }
        }
        // 尾部：整段是脚手架、永不进正文；只按块头收
        // 路径——📎（含文本过大变体，描述段不同、路径
        // 位置不变）与 📄（其后 ``` 围栏是文件全文，
        // 只取头行路径）。切块须围栏感知：围栏内的空
        // 行/形似 📎 的代码行不许误切误收；📁/🌐/📌
        // 块头只标记剥离、不出牌；警告块内不收路径
        var inFence = false
        var tailInWarnings = false
        for line in tailLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if trimmed == warningsLine {
                tailInWarnings = true
                touched = true
                continue
            }
            guard let marker = trimmed.first else { continue }
            if pathBlockMarkers.contains(marker)
                || stripOnlyBlockMarkers.contains(marker) {
                tailInWarnings = false
                touched = true
                if pathBlockMarkers.contains(marker),
                   let path = blockLinePath(in: line) {
                    collect(path)
                }
                continue
            }
            if tailInWarnings { continue }
            // 其余尾行（指令句/列举行/内联正文的非围栏
            // 部分）一律丢弃，不进正文
        }
        // 什么脚手架都没碰到、也没剥出路径＝不是展开
        // 块形态（如正文里行内提及 @file:），保守回
        // 原文逐字不变
        guard touched || !paths.isEmpty else {
            return Parsed(text: content, imagePaths: [], fileRefs: [])
        }
        // 引用行抽走后收拾空行（与 AttachedImageRef 同
        // 口径：三连换行压两连、去首尾空白）
        var text = kept.joined(separator: "\n")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var imagePaths: [String] = []
        var fileRefs: [String] = []
        for path in paths {
            if FileRefDetector.isImagePath(path) {
                imagePaths.append(path)
            } else {
                fileRefs.append(path)
            }
        }
        return Parsed(
            text: text, imagePaths: imagePaths, fileRefs: fileRefs
        )
    }

    /// 独立成行的 `@file:` 引用（头部形态）：整行只有
    /// 引用本身——直写形 `@file:<路径>`（路径不含空白）
    /// 或带引号形 `@file:"<路径>"`（FileSendAssembly 对
    /// 含空格/括号路径的包裹形）；两种形态尾巴都只许
    /// 带行段后缀 `:10-20`（collect 时剥掉）
    private static func standaloneFileRef(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@file:") else { return nil }
        let rest = String(trimmed.dropFirst("@file:".count))
        if rest.hasPrefix("\"") {
            let after = rest.dropFirst()
            guard let close = after.firstIndex(of: "\"") else {
                return nil
            }
            let tail = after[after.index(after: close)...]
            guard tail.isEmpty || isLineRangeSuffix(String(tail))
            else { return nil }
            let inner = String(after[..<close])
            return inner.isEmpty ? nil : inner
        }
        guard !rest.isEmpty,
              !rest.contains(where: { $0.isWhitespace })
        else { return nil }
        return rest
    }

    /// 尾部块头行（`📎 @file:`/`📄 @file:`）的路径：
    /// 路径在 `@file:` 后——带引号形取引号内、直写形
    /// 取首个空白前一段（其后是括号里的 MIME/大小/
    /// token 数与指令句，不入路径）
    private static func blockLinePath(in line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first,
              pathBlockMarkers.contains(marker) else { return nil }
        trimmed = String(trimmed.dropFirst())
            .trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@file:") else { return nil }
        let rest = String(trimmed.dropFirst("@file:".count))
        if rest.hasPrefix("\"") {
            let after = rest.dropFirst()
            guard let close = after.firstIndex(of: "\"") else {
                return nil
            }
            let inner = String(after[..<close])
            return inner.isEmpty ? nil : inner
        }
        let path = String(rest.prefix(while: { !$0.isWhitespace }))
        return path.isEmpty ? nil : path
    }

    /// 独立成行的 `@folder:` 引用（头部形态）：整行
    /// 只有引用本身（直写形或带引号形）
    private static func isStandaloneFolderRef(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("@folder:") else { return false }
        let rest = trimmed.dropFirst("@folder:".count)
        guard !rest.isEmpty else { return false }
        if rest.hasPrefix("\"") {
            return rest.count >= 2 && rest.hasSuffix("\"")
        }
        return !rest.contains(where: { $0.isWhitespace })
    }

    /// 行段后缀形态 `:10` 或 `:10-20`（网关行范围引用
    /// 的写法，附在路径尾、不是路径的一部分）
    private static func isLineRangeSuffix(_ tail: String) -> Bool {
        guard tail.hasPrefix(":") else { return false }
        let body = tail.dropFirst()
        guard !body.isEmpty else { return false }
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }

    /// 剥路径尾的行段后缀；尾段不是行段形态（如文件
    /// 名本身带冒号段）时原样返回
    private static func stripLineRange(_ path: String) -> String {
        guard let colon = path.lastIndex(of: ":") else { return path }
        let tail = String(path[path.index(after: colon)...])
        guard isLineRangeSuffix(":" + tail) else { return path }
        return String(path[..<colon])
    }
}

// MARK: - 文件引用探测

/// 从消息文本里探测可预览的服务端文件路径（绝对路径＋
/// 扩展名形态）。文件消息在现有历史里无样本（2026-11-09
/// 全扫零命中），本探测按实查路径形态（/opt/data/cache/
/// documents、/opt/data/… 的 agent 产出）施工：命中即
/// 文件牌，点击走既有 /api/files/download 取回预览。
/// §129 分层：detect/detectAnchored 是原始扫描口
/// （什么像路径就报什么）；聊天成牌改走 detect-
/// StandaloneAnchored（单独成行＋下载根内），渲染
/// 前再经 App 层存在性校验——生产抽检曾有约 38%
/// 助手侧牌点开必 404（拟议未落盘/截断假路径/设备
/// 路径，诊断 file-ref-404-diagnosis-20261111）。
public enum FileRefDetector {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic",
    ]

    // 0.46.1：路径段字符集扩 Unicode（\u0080–\uFFFF）——
    // 中文名文件（如 /opt/data/attachments/三藏.zip）
    // 此前探不到、不出牌。扩围 B：扩展名白名单删除，
    // 改「扩展名形态 [A-Za-z0-9]{1,12}」即命中——白
    // 名单永远漏新类型（.mq5/.mqh/.py/.rar 上轮全漏）。
    // 尾界负向断言：扩展名后不得紧跟字母数字（防截
    // 断）、不得紧跟 /（防把 v1.2 这类带点目录段当文
    // 件）、不得紧跟「.＋字母数字」（防 a.tar.gz 只
    // 截到 .tar）。其余护栏不变：冒号前置跳 URL 残
    // 段、// 开头跳过、至少一层目录、excluding 去重
    // §129：匹配量词由懒惰 +? 改贪婪 +（截断 bug 终
    // 修，诊断 file-ref-404-diagnosis-20261111 主因
    // B）：懒惰匹配取最短「扩展名形结尾」，文件名中
    // 段出现「.数字」且其后跟 - 时提前收尾——真文件
    // /opt/data/kimi-k3.1-pro-….md 被截成假路径
    // /opt/data/kimi-k3.1 成牌、点开必 404。贪婪先
    // 吞到终止符为止、再回认最长合法结尾；尾界断言
    // 另加「-＋字母数字」（候选结尾后紧跟 - 且其后
    // 还有路径字符＝还没到真结尾，继续吞）
    private static let pattern =
        #"/[A-Za-z0-9_\-./\u0080-\uFFFF]+\.[A-Za-z0-9]{1,12}(?![A-Za-z0-9/]|\.[A-Za-z0-9]|-[A-Za-z0-9])"#

    // §125 搭车：路径后可跟 ekko 式行号锚点 `#L12`
    // 或 `#L12-L20`（捕获组 1）；锚点不入路径本体，
    // detect 丢弃、detectAnchored 单列返回
    private static let anchoredPattern =
        Self.pattern + #"(#L[0-9]+(?:-L?[0-9]+)?)?"#

    /// §157（2026-11-11）：图案与选项恒定，编译结果提
    /// 升为静态单例（Swift 静态量一次性线程安全初始
    /// 化）。旧写法在 scan 内每次调用现编译 NSRegular-
    /// Expression，而 scan 位于助手气泡 body 求值路
    /// 径（detectStandaloneAnchored／inlineImage-
    /// Candidates），滚动与流式期被反复触发；匹配语
    /// 义逐字不变。诊断见 chat-scroll-diagnosis-
    /// 20261111.md 病因 C
    private static let anchoredRegex: NSRegularExpression? =
        try? NSRegularExpression(
            pattern: anchoredPattern, options: [.caseInsensitive]
        )

    public static func detect(
        in text: String, excluding excluded: [String] = []
    ) -> [String] {
        scan(in: text, excluding: excluded).map(\.path)
    }

    /// 锚点感知探测（§125）：与 detect 同护栏同去重，
    /// 额外带回每条路径的行号锚点（无锚点为 nil）
    public static func detectAnchored(
        in text: String, excluding excluded: [String] = []
    ) -> [FileAnchoredRef] {
        scan(in: text, excluding: excluded)
    }

    /// 文件下载根（与服务端 files.py 的 locked_root
    /// 同口径，生产实查 /opt/data）：根外路径天然不
    /// 可下载（设备路径、系统路径一类），不成牌
    public static let downloadRoot = "/opt/data"

    /// 路径是否严格位于下载根内：前缀须为「根＋/」
    /// （防 /opt/database 这类前缀陷阱），且不许带
    /// .. 穿越段（字面在根内、解析后逃出去的不算）
    public static func isInDownloadRoot(_ path: String) -> Bool {
        guard path.hasPrefix(downloadRoot + "/") else { return false }
        return !path.contains("/../") && !path.hasSuffix("/..")
    }

    /// 成牌口探测（§129，诊断主因 A/C 的收口）：助
    /// 手正文里只有「单独成行」的路径才够格成牌——
    /// 行内提及（拟议目标、举例、说明句中的路径）一
    /// 律纯文本。单独成行的判据：整行修剪后恰好是一
    /// 条路径（可带 #L 锚点），允许一层常见行首/包
    /// 裹（列表符 -、*、•、引用符 >、反引号、**粗
    /// 体**）；一行里有两条路径或路径之外还有别的
    /// 字，都不算。候选另须过下载根（根外天然不可
    /// 下载）。detect/detectAnchored 是原始扫描口
    /// （其余消费方与钉测在用），成牌只许走本口；
    /// 存在性校验在 App 层渲染前另核（见 §129.2）
    public static func detectStandaloneAnchored(
        in text: String, excluding excluded: [String] = []
    ) -> [FileAnchoredRef] {
        guard text.contains("/") else { return [] }
        var seen: Set<String> = Set(excluded)
        var found: [FileAnchoredRef] = []
        for line in text.components(separatedBy: "\n") {
            let candidate = standaloneLineCandidate(line)
            guard !candidate.isEmpty else { continue }
            let refs = scan(in: candidate)
            guard refs.count == 1, let ref = refs.first
            else { continue }
            // 整行恰好是这一条路径：路径之后只许留
            // 它自己的 #L 锚点原文，不许有别的字
            guard candidate.hasPrefix(ref.path) else { continue }
            let remainder = String(candidate.dropFirst(ref.path.count))
            if !remainder.isEmpty {
                guard remainder.hasPrefix("#"),
                      FileLineAnchor.parse(remainder) == ref.anchor
                else { continue }
            }
            guard isInDownloadRoot(ref.path) else { continue }
            if seen.insert(ref.path).inserted {
                found.append(ref)
            }
        }
        return found
    }

    /// 单独成行候选的解包：修剪空白后，循环剥一层
    /// 行首标记（-、*、•、>）与包裹（`、`**`），直
    /// 到不再变化；剥完仍含别的字由调用方按「整行
    /// 恰好一条路径」判据否决
    private static func standaloneLineCandidate(
        _ line: String
    ) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for marker in ["- ", "* ", "• ", "> "] where
                text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count))
                    .trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if text.count >= 2, text.hasPrefix("`"),
               text.hasSuffix("`") {
                text = String(text.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if text.count >= 4, text.hasPrefix("**"),
               text.hasSuffix("**") {
                text = String(text.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return text
    }

    private static func scan(
        in text: String, excluding excluded: [String] = []
    ) -> [FileAnchoredRef] {
        guard text.contains("/") else { return [] }
        // §157：编译结果已提升为静态单例 anchoredRegex
        guard let regex = Self.anchoredRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen: Set<String> = Set(excluded)
        var found: [FileAnchoredRef] = []
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text)
            else { continue }
            // URL/域名的路径段不是服务端文件：前一字
            // 符是冒号（:// 的一部分）时跳过。§129 扩
            // 围：前一字符是 ASCII 字母/数字或 . 时同
            // 样跳过——那是更长词元的尾巴（域名片段
            // huggingface.co/moonshotai/… 、IP:端口后
            // 的段），不是独立路径的开头（诊断主因
            // B 之二）。只认 ASCII：中文正文里「在
            // /opt/…」这类汉字紧贴不许误伤（汉字
            // isLetter 为真，故须先过 isASCII）
            if matchRange.lowerBound > text.startIndex {
                let before = text[text.index(
                    before: matchRange.lowerBound
                )]
                if before == ":" || before == "." { continue }
                if before.isASCII,
                   before.isLetter || before.isNumber { continue }
            }
            // 锚点组（组 1）位于匹配尾部：路径＝全匹配
            // 去掉锚点后缀
            var path = String(text[matchRange])
            var anchor: FileLineAnchor?
            let anchorRange = match.range(at: 1)
            if anchorRange.location != NSNotFound,
               anchorRange.length > 0,
               let anchorSwiftRange = Range(anchorRange, in: text) {
                // 锚点形态的后缀恒不属于路径本体：无论
                // 行号语义合法与否都从路径剥离，非法只
                // 是不带锚点（parse 回 nil）
                let fragment = String(text[anchorSwiftRange])
                anchor = FileLineAnchor.parse(fragment)
                path = String(path.dropLast(fragment.count))
            }
            // "//…" 是 URL 的残段不是路径；至少含一层目录
            // （裸 "/x.pdf" 不是服务端产出形态）
            guard !path.hasPrefix("//"),
                  path.dropFirst().contains("/") else { continue }
            if seen.insert(path).inserted {
                found.append(
                    FileAnchoredRef(path: path, anchor: anchor)
                )
            }
        }
        return found
    }

    public static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    // MARK: - §143 内联图片候选

    /// §143：助手正文里「裸路径图片」的内联候选——
    /// 路径本体（出现序去重）＋它是不是独立成行
    /// （整行恰是这一条路径，含 §129 的一层行首/
    /// 包裹剥离；段内单独成词为 false）
    public struct InlineImageRef: Equatable, Sendable {
        public let path: String
        public let isStandaloneLine: Bool

        public init(path: String, isStandaloneLine: Bool) {
            self.path = path
            self.isStandaloneLine = isStandaloneLine
        }
    }

    /// 段内「单独成词」的前界字符集（§143）：路径
    /// 前一字符必须是行首、空白或标点分隔，才算单
    /// 独成词；紧贴汉字/字母数字的提及不算（§129
    /// 纪律：语义不明的行内提及维持纯文本）。不收
    /// ASCII 冒号（与 scan 的 URL 护栏同判），全角
    /// 冒号收——中文正文「图在这：/opt/…」是主形
    /// 态、且绝不出现在 URL 里
    private static let wordPrecedingDelimiters: Set<Character> = [
        " ", "\t", "，", "。", "、", "；", "：", "？", "！",
        "·", "—", "…", "「", "『", "（", "【", "《", "〈", "﹝",
        "(", "[", "{", "<", "\"", "'", "`", "*",
    ]

    /// 段内「单独成词」的后界字符集（§143）：路径
    /// （含其 #L 锚点原文）后一字符必须是行尾、空
    /// 白或标点分隔；紧跟字母数字/下划线/路径字符
    /// 的是更长词元的一部分，不算
    private static let wordFollowingDelimiters: Set<Character> = [
        " ", "\t", "，", "。", "、", "；", "：", "？", "！",
        "·", "—", "…", "」", "』", "）", "】", "》", "〉", "﹞",
        ")", "]", "}", ">", "\"", "'", "`", "*",
        ",", ";", ":", "!", "?", ".",
    ]

    /// 内联图片候选探测（§143，用户 2026-11-11
    /// 17:13 报障）：助手侧图片此前只有两条内联通
    /// 道——落盘登记的 remoteImagePaths 与 §136 的
    /// MEDIA: 标记行；裸写在正文里的图片路径（独
    /// 立成行或段内单独成词）一律落文件牌链、出通
    /// 用文件卡，点开才看得见（生产实证：state.db
    /// 消息 1775 的截图路径独立成行、文件真实存
    /// 在，仍只出文件牌）。本口把图片从文件牌链分
    /// 出来：扩展名是图片（imageExtensions）＋在下
    /// 载根内＋形态二选一（独立成行／段内单独成
    /// 词），即为内联候选；是否真出图由 App 层按
    /// §129 三分存在性判定（Core 不判存在性，与
    /// MediaMarker 同分工）。§129 的门一项不松：
    /// 根外路径不收、围栏内不收、紧贴正文的提及
    /// 不收、拟议未落盘的由存在性门在 App 层挡；
    /// 非图片文件完全不走本口，独立成行判据与成
    /// 牌链逐字不变
    public static func inlineImageCandidates(
        in text: String, excluding excluded: [String] = []
    ) -> [InlineImageRef] {
        guard text.contains("/") else { return [] }
        var collected: [InlineImageRef] = []
        var indexByPath: [String: Int] = [:]
        var seen: Set<String> = Set(excluded)
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            // 独立成行：整行恰一条路径（复用 §129
            // 成牌口的整行判据，含下载根校验）
            let standalone = detectStandaloneAnchored(in: line)
            if standalone.count == 1, let ref = standalone.first {
                // 整行多图粘连形先于单条判：两条绝对
                // 路径被中文标点粘成一条正则词元时，
                // 拆回逐条收（各自再过图片＋根内门）
                if degluedPathPieces(ref.path).count > 1 {
                    if let glued = gluedStandalonePieces(in: line) {
                        for piece in glued
                        where isImagePath(piece)
                            && isInDownloadRoot(piece) {
                            if seen.insert(piece).inserted {
                                indexByPath[piece] = collected.count
                                collected.append(
                                    InlineImageRef(
                                        path: piece,
                                        isStandaloneLine: true
                                    )
                                )
                            } else if let idx = indexByPath[piece],
                                      !collected[idx].isStandaloneLine {
                                collected[idx] = InlineImageRef(
                                    path: piece,
                                    isStandaloneLine: true
                                )
                            }
                        }
                    }
                    continue
                }
                if isImagePath(ref.path) {
                    if seen.insert(ref.path).inserted {
                        indexByPath[ref.path] = collected.count
                        collected.append(
                            InlineImageRef(
                                path: ref.path, isStandaloneLine: true
                            )
                        )
                    } else if let idx = indexByPath[ref.path],
                              !collected[idx].isStandaloneLine {
                        // 同路径先以段内词出现、后又独立
                        // 成行：升级标记——App 层据此在确
                        // 证存在后摘除那一行
                        collected[idx] = InlineImageRef(
                            path: ref.path, isStandaloneLine: true
                        )
                    }
                    continue
                }
            }
            // 段内单独成词：原始扫描后逐条验边界；
            // 扫描词元先拆粘连（中文列表句里两条绝
            // 对路径会被 §116 扩过的路径字符集粘成
            // 一条词元，见 degluedPathPieces）
            let refs = scan(in: line, excluding: Array(seen))
            for ref in refs {
                let pieces = degluedPathPieces(ref.path)
                for piece in pieces
                where isImagePath(piece)
                    && isInDownloadRoot(piece) {
                    guard isStandaloneWord(
                        path: piece,
                        hasAnchor: pieces.count == 1
                            && ref.anchor != nil,
                        in: line
                    ) else { continue }
                    if seen.insert(piece).inserted {
                        indexByPath[piece] = collected.count
                        collected.append(
                            InlineImageRef(
                                path: piece, isStandaloneLine: false
                            )
                        )
                    }
                }
            }
        }
        return collected
    }

    /// 段内单独成词判定：路径在行内的某处出现，其
    /// 前一字符是行首或前界分隔符、后一字符（带锚
    /// 点时跳过 #L 锚点原文）是行尾或后界分隔符；
    /// 任一处出现满足即算
    private static func isStandaloneWord(
        path: String, hasAnchor: Bool, in line: String
    ) -> Bool {
        var searchFrom = line.startIndex
        while let range = line.range(
            of: path, range: searchFrom..<line.endIndex
        ) {
            let beforeOK: Bool
            if range.lowerBound == line.startIndex {
                beforeOK = true
            } else {
                let before = line[line.index(
                    before: range.lowerBound
                )]
                beforeOK = wordPrecedingDelimiters.contains(before)
            }
            var tail = range.upperBound
            if hasAnchor {
                tail = line.index(
                    range.upperBound,
                    offsetBy: anchorFragmentLength(
                        in: line, from: range.upperBound
                    )
                )
            }
            let afterOK: Bool
            if tail == line.endIndex {
                afterOK = true
            } else {
                afterOK = wordFollowingDelimiters.contains(line[tail])
            }
            if beforeOK && afterOK { return true }
            searchFrom = range.upperBound
        }
        return false
    }

    /// 路径尾 #L 锚点原文的长度（#L12／#L12-L20
    /// 形态）；不是锚点形态回 0
    private static func anchorFragmentLength(
        in line: String, from start: String.Index
    ) -> Int {
        var idx = start
        guard idx < line.endIndex, line[idx] == "#" else { return 0 }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == "L" else { return 0 }
        idx = line.index(after: idx)
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber {
            idx = line.index(after: idx)
            digits += 1
        }
        guard digits > 0 else { return 0 }
        if idx < line.endIndex, line[idx] == "-" {
            var tail = line.index(after: idx)
            if tail < line.endIndex, line[tail] == "L" {
                tail = line.index(after: tail)
            }
            var tailDigits = 0
            while tail < line.endIndex, line[tail].isNumber {
                tail = line.index(after: tail)
                tailDigits += 1
            }
            if tailDigits > 0 { idx = tail }
        }
        return line.distance(from: start, to: idx)
    }

    /// 拆粘连词元（§143）：路径字符集含 \u0080–
    /// \uFFFF（§116 为中文文件名扩的），中文列表
    /// 句里两条绝对路径会被正则粘成一条词元（形
    /// 如 a.png、/opt/… 连写）。在「中文标点＋紧
    /// 跟 /」处切开——那是第二条绝对路径的起点；
    /// 单个文件名内部的标点后不接 /、不误伤。拆
    /// 不出（≤1 段）原样返回单元素数组
    private static func degluedPathPieces(
        _ path: String
    ) -> [String] {
        let separators: Set<Character> = [
            "、", "，", "。", "；", "：", "？", "！", "·",
        ]
        let chars = Array(path)
        var pieces: [String] = []
        var current = ""
        for i in chars.indices {
            let c = chars[i]
            if separators.contains(c), !current.isEmpty,
               i + 1 < chars.count, chars[i + 1] == "/" {
                pieces.append(current)
                current = ""
                continue
            }
            current.append(c)
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.count > 1 ? pieces : [path]
    }

    /// 整行多图粘连形的拆分（§143）：一行经整行
    /// 判据剥壳后只剩一条扫描词元、且该词元可拆
    /// 成多条路径、行内除这些路径外只剩空白与分
    /// 隔标点时，返回拆出的路径组；否则 nil
    private static func gluedStandalonePieces(
        in line: String
    ) -> [String]? {
        let candidate = standaloneLineCandidate(line)
        guard !candidate.isEmpty else { return nil }
        let refs = scan(in: candidate)
        guard refs.count == 1,
              let ref = refs.first else { return nil }
        let pieces = degluedPathPieces(ref.path)
        guard pieces.count > 1 else { return nil }
        var rest = candidate
        for piece in pieces {
            guard let range = rest.range(of: piece)
            else { return nil }
            rest.removeSubrange(range)
        }
        let clean = rest.allSatisfy {
            $0.isWhitespace
                || wordPrecedingDelimiters.contains($0)
                || wordFollowingDelimiters.contains($0)
        }
        return clean ? pieces : nil
    }

    /// 摘除独立成行的路径行（§143）：paths 内的路
    /// 径若在正文里独立成行（§129 整行判据、围栏
    /// 内除外），整行摘除并收拾空行（MediaMarker
    /// 同款：三连换行压一个空行、首尾修剪）；段内
    /// 提及同路径不动（句子完整性优先）。App 层只
    /// 对「存在性已确证」的独立行图片调用本函数
    /// ——查无此图的路径行不摘、维持纯文本（§129
    /// 降级口径：内容不许凭空消失）
    public static func strippingStandaloneLines(
        in text: String, paths: Set<String>
    ) -> String {
        guard !paths.isEmpty, text.contains("/") else { return text }
        var kept: [String] = []
        var removed = false
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                kept.append(line)
                continue
            }
            if !inFence {
                let refs = detectStandaloneAnchored(in: line)
                if refs.count == 1, let ref = refs.first,
                   paths.contains(ref.path) {
                    removed = true
                    continue
                }
                // 整行多图粘连形：拆出的路径全在摘
                // 除集内才整行摘（混着没确证的图或
                // 非图文件时整行保留、内容不消失）
                if let glued = gluedStandalonePieces(in: line),
                   glued.allSatisfy({ paths.contains($0) }) {
                    removed = true
                    continue
                }
            }
            kept.append(line)
        }
        guard removed else { return text }
        var result = kept.joined(separator: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(
                of: "\n\n\n", with: "\n\n"
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
