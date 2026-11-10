import Foundation

// MARK: - Kanban 契约模型（P3 任务，2026-11-09 冻结）
//
// 路线＝kanban-spike-20261109.md 定案：任务执行面直接
// 用 Hermes 自带 kanban 插件（9119 dashboard 插件面
// /api/plugins/kanban，48 条路由），App 只做薄适配；
// 数据面隔离＝专属板 slug「oneday」（独立 db），不碰
// 用户 default 板。响应体在 OpenAPI 里未定型，故本层
// 全部走 JSONValue 宽容提取（键名多拼写兜底），形状
// 漂移只许落空/降级、不许硬崩（spike 缺口补法 5）。
// 状态译名与控制映射逐条照 spike 档「接口契约要点」：
// 无 pause 动词（停止＝terminate/reclaim）、失败无终
// 态列（blocked＋transient＋last_failure_error 翻译）、
// 答题＝comment 注入＋PATCH ready（worker 上下文注入
// 最近 30 条 comments）。

/// 冻结常量（spike 契约）：专属板、默认执行档案、
/// App 答题作者标记、互斥/只读的人话原因
public enum KanbanContract {
    public static let boardSlug = "oneday"
    public static let defaultAssignee = "default"
    public static let answerAuthor = "oneday"
    /// 人工来源作者集（pendingQuestion 提取时排除）
    public static let humanAuthors: Set<String> = ["oneday", "dashboard"]
    public static var takeoverReason: String {
        takeoverReason(locale: AppLocale.uiLocale)
    }

    public static var readOnlyReason: String {
        readOnlyReason(locale: AppLocale.uiLocale)
    }

    /// 闸门原因的目录取词形（0.42.1 国际化长尾包）
    public static func takeoverReason(locale: Locale) -> String {
        L10n.string(
            "接管中：你正在操作云电脑，任务派发已暂停，交还后可继续。",
            locale: locale
        )
    }

    public static func readOnlyReason(locale: Locale) -> String {
        L10n.string("任务系统版本变化，当前只读。", locale: locale)
    }
}

// MARK: - JSONValue 宽容提取（本文件内共用）

private extension JSONValue {
    var objectDict: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    var arrayValues: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// 整数提取：数字直取，字符串数字也认（服务端序列化口径不一）
    var intValue: Int? {
        if let number = numberValue { return Int(number) }
        if let string = stringValue { return Int(string) }
        return nil
    }
}

/// 宽容时间戳：kanban.db 的时间列口径未冻结——纪元秒
/// （数字/数字串）与 ISO8601 串都认，认不出返回 nil
/// 不许猜（BoxISO8601 同科）
public enum KanbanTime {
    public static func parse(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .number(let seconds):
            return Date(timeIntervalSince1970: seconds)
        case .string(let raw):
            if let date = BoxISO8601.parse(raw) { return date }
            if let seconds = Double(raw) {
                return Date(timeIntervalSince1970: seconds)
            }
            return nil
        default:
            return nil
        }
    }
}

/// 字段提取器：同一语义多拼写键按序兜底（snake_case
/// 为实测 db 列名优先，其余为序列化变体防漂移）
private struct KanbanFields {
    let dict: [String: JSONValue]

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = dict[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            if let value = dict[key]?.intValue { return value }
        }
        return nil
    }

    func time(_ keys: String...) -> Date? {
        for key in keys {
            if let date = KanbanTime.parse(dict[key]) { return date }
        }
        return nil
    }

    func array(_ keys: String...) -> [JSONValue] {
        for key in keys {
            if let values = dict[key]?.arrayValues { return values }
        }
        return []
    }
}

// MARK: - 状态呈现（译名表，spike 冻结）

/// App 展示态：kanban 八列＋archived 过滤态经 spike
/// 译名表翻译——ready＝排队中、running＝进行中、
/// review＝待审批、blocked＋needs_input＝等你回答、
/// blocked＋transient＋失败原文＝失败、其余 blocked
/// ＝已阻塞、done＝已完成、scheduled＝已排期、
/// todo/triage＝待整理
public enum KanbanStatusPresentation: Equatable, Hashable, Sendable {
    case needsInput
    case review
    case running
    case failed
    case blocked
    case queued
    case scheduled
    case triage
    case done
    case archived
    case unknown(String)

    public var label: String { label(locale: AppLocale.uiLocale) }

    /// 状态名的目录取词形（0.42.1 国际化长尾包）：
    /// unknown 的 raw 是服务端原值（内容），原样直通
    public func label(locale: Locale) -> String {
        switch self {
        case .needsInput: return L10n.string("等你回答", locale: locale)
        case .review: return L10n.string("待审批", locale: locale)
        case .running: return L10n.string("进行中", locale: locale)
        case .failed: return L10n.string("失败", locale: locale)
        case .blocked: return L10n.string("已阻塞", locale: locale)
        case .queued: return L10n.string("排队中", locale: locale)
        case .scheduled: return L10n.string("已排期", locale: locale)
        case .triage: return L10n.string("待整理", locale: locale)
        case .done: return L10n.string("已完成", locale: locale)
        case .archived: return L10n.string("已归档", locale: locale)
        case .unknown(let raw):
            return raw.isEmpty ? L10n.string("未知状态", locale: locale) : raw
        }
    }

    /// 列表分组序：等用户处理的在前、活跃居中、终态在后
    public var groupOrder: Int {
        switch self {
        case .needsInput: return 0
        case .review: return 1
        case .running: return 2
        case .failed: return 3
        case .blocked: return 4
        case .queued: return 5
        case .scheduled: return 6
        case .triage: return 7
        case .done: return 8
        case .archived: return 9
        case .unknown: return 10
        }
    }

    public static func resolve(
        status: String, blockKind: String?, lastFailureError: String?
    ) -> KanbanStatusPresentation {
        switch status {
        case "done": return .done
        case "running": return .running
        case "review": return .review
        case "ready": return .queued
        case "scheduled": return .scheduled
        case "todo", "triage": return .triage
        case "archived": return .archived
        case "blocked":
            if blockKind == "needs_input" { return .needsInput }
            if blockKind == "transient",
               let error = lastFailureError, !error.isEmpty {
                return .failed
            }
            return .blocked
        default:
            return .unknown(status)
        }
    }
}

// MARK: - 任务

/// kanban 任务行（tasks 表语义子集）：解码以 spike
/// 实测字段为准（title/body/status/assignee/latest_
/// summary/last_failure_error/consecutive_failures/
/// current_run_id/block_kind），全字段宽容落空
public struct KanbanTask: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    /// 服务端原生列名（triage/todo/scheduled/ready/
    /// running/blocked/review/done），原样保留不翻译
    public let status: String
    public let assignee: String?
    public let tenant: String?
    public let priority: Int
    /// 完成证据正文（complete 时强制非空，spike 对照 3）
    public let result: String?
    public let blockKind: String?
    /// 宽容解码保留，但**不是问题原文来源**：P3 生
    /// 产验收实查 task 对象键全集无 block_reason，
    /// 问题原文在详情 events/runs（见 KanbanTask-
    /// Detail.blockDetailText，0.18.0 定案）
    public let blockReason: String?
    public let lastFailureError: String?
    public let consecutiveFailures: Int
    public let currentRunId: Int?
    /// 最近一次运行摘要（worker 真回复，卡片副题源）
    public let latestSummary: String?
    public let workspaceKind: String?
    public let idempotencyKey: String?
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?

    public init(
        id: String, title: String = "", body: String = "",
        status: String = "", assignee: String? = nil,
        tenant: String? = nil, priority: Int = 0,
        result: String? = nil, blockKind: String? = nil,
        blockReason: String? = nil, lastFailureError: String? = nil,
        consecutiveFailures: Int = 0, currentRunId: Int? = nil,
        latestSummary: String? = nil, workspaceKind: String? = nil,
        idempotencyKey: String? = nil, createdAt: Date? = nil,
        startedAt: Date? = nil, completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.assignee = assignee
        self.tenant = tenant
        self.priority = priority
        self.result = result
        self.blockKind = blockKind
        self.blockReason = blockReason
        self.lastFailureError = lastFailureError
        self.consecutiveFailures = consecutiveFailures
        self.currentRunId = currentRunId
        self.latestSummary = latestSummary
        self.workspaceKind = workspaceKind
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    /// JSONValue 提取：创建回执可能以 {task: {...}}
    /// 包裹，先拆包裹再读字段
    public init(jsonValue: JSONValue) {
        var dict = jsonValue.objectDict ?? [:]
        if let wrapped = dict["task"]?.objectDict {
            dict = wrapped
        }
        let fields = KanbanFields(dict: dict)
        id = fields.string("id") ?? ""
        title = fields.string("title") ?? ""
        body = fields.string("body") ?? ""
        status = fields.string("status") ?? ""
        assignee = fields.string("assignee")
        tenant = fields.string("tenant")
        priority = fields.int("priority") ?? 0
        result = fields.string("result")
        blockKind = fields.string("block_kind", "blockKind", "block_type")
        blockReason = fields.string("block_reason", "blockReason")
        lastFailureError = fields.string(
            "last_failure_error", "lastFailureError"
        )
        consecutiveFailures = fields.int(
            "consecutive_failures", "consecutiveFailures"
        ) ?? 0
        currentRunId = fields.int("current_run_id", "currentRunId")
        latestSummary = fields.string(
            "latest_summary", "latestSummary", "summary"
        )
        workspaceKind = fields.string("workspace_kind", "workspaceKind")
        idempotencyKey = fields.string("idempotency_key", "idempotencyKey")
        createdAt = fields.time("created_at", "createdAt")
        startedAt = fields.time("started_at", "startedAt")
        completedAt = fields.time("completed_at", "completedAt")
    }

    public var presentation: KanbanStatusPresentation {
        KanbanStatusPresentation.resolve(
            status: status, blockKind: blockKind,
            lastFailureError: lastFailureError
        )
    }

    public var displayTitle: String {
        displayTitle(locale: AppLocale.uiLocale)
    }

    /// 标题的目录取词形（0.42.1 国际化长尾包）：任务
    /// 标题是内容原样直通，只空标题兜底词走目录
    public func displayTitle(locale: Locale) -> String {
        title.isEmpty ? L10n.string("未命名任务", locale: locale) : title
    }

    /// 卡片摘要行：最近运行摘要优先，其次完成结果，
    /// 都没有就空（视图不渲染空行，不许拿正文冒充）
    public var summaryText: String? {
        if let latestSummary, !latestSummary.isEmpty {
            return latestSummary
        }
        if let result, !result.isEmpty { return result }
        return nil
    }
}

// MARK: - 板快照与分组

/// GET /board 回执：上游文档口径「按状态列分组＋
/// latest_event_id 增量游标」。分组形态未冻结为单
/// 一形状，三形都收：{tasks:[...]} 平铺、{columns:
/// [{..., tasks:[...]}]} 列数组、{columns:{列名:
/// [...]}} 列字典；{board:{...}} 包裹再递归一层
public struct KanbanBoardSnapshot: Decodable, Equatable, Sendable {
    public let tasks: [KanbanTask]
    public let latestEventId: Int?

    public init(tasks: [KanbanTask], latestEventId: Int?) {
        self.tasks = tasks
        self.latestEventId = latestEventId
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        let extracted = Self.extractTasks(from: jsonValue)
        tasks = extracted.tasks
        latestEventId = extracted.eventId
    }

    private static func extractTasks(
        from value: JSONValue
    ) -> (tasks: [KanbanTask], eventId: Int?) {
        let dict = value.objectDict ?? [:]
        let fields = KanbanFields(dict: dict)
        let eventId = fields.int("latest_event_id", "latestEventId")
        if let flat = dict["tasks"]?.arrayValues {
            return (flat.map { KanbanTask(jsonValue: $0) }, eventId)
        }
        if let columns = dict["columns"] {
            var collected: [KanbanTask] = []
            if let list = columns.arrayValues {
                for column in list {
                    let colFields = KanbanFields(
                        dict: column.objectDict ?? [:]
                    )
                    collected += colFields.array("tasks").map {
                        KanbanTask(jsonValue: $0)
                    }
                }
            } else if let byStatus = columns.objectDict {
                for (_, columnTasks) in byStatus {
                    if let list = columnTasks.arrayValues {
                        collected += list.map {
                            KanbanTask(jsonValue: $0)
                        }
                    }
                }
            }
            if !collected.isEmpty {
                return (
                    collected.filter { !$0.id.isEmpty }, eventId
                )
            }
        }
        if let board = dict["board"] {
            let inner = extractTasks(from: board)
            return (inner.tasks, eventId ?? inner.eventId)
        }
        return ([], eventId)
    }
}

/// 列表分组（呈现态 → 任务）：组序按 groupOrder，
/// 组内按创建时间倒序（无时刻的垫底、id 兜底排序
/// 保证稳定）
public struct KanbanTaskGroup: Equatable, Sendable {
    public let presentation: KanbanStatusPresentation
    public let tasks: [KanbanTask]

    public init(
        presentation: KanbanStatusPresentation, tasks: [KanbanTask]
    ) {
        self.presentation = presentation
        self.tasks = tasks
    }
}

public enum KanbanBoardGrouping {
    public static func group(_ tasks: [KanbanTask]) -> [KanbanTaskGroup] {
        let grouped = Dictionary(grouping: tasks) { $0.presentation }
        return grouped
            .map { entry in
                KanbanTaskGroup(
                    presentation: entry.key,
                    tasks: entry.value.sorted(by: taskOrder)
                )
            }
            .sorted {
                $0.presentation.groupOrder < $1.presentation.groupOrder
            }
    }

    private static func taskOrder(
        _ lhs: KanbanTask, _ rhs: KanbanTask
    ) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (left?, right?):
            if left != right { return left > right }
            return lhs.id < rhs.id
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.id < rhs.id
        }
    }
}

// MARK: - 板清单与版本探针

/// GET /boards 回执提取：裸数组或 {boards:[...]}，
/// 元素取 slug（字符串元素直取）
public enum KanbanBoardList {
    public static func slugs(from value: JSONValue) -> [String] {
        var items: [JSONValue] = []
        if let array = value.arrayValues {
            items = array
        } else if let dict = value.objectDict,
                  let array = dict["boards"]?.arrayValues {
            items = array
        }
        return items.compactMap { item in
            item.objectDict?["slug"]?.stringValue ?? item.stringValue
        }
    }
}

/// GET /workflow 回执：列集合提取（columns/statuses/
/// states 任一键；元素为字符串或 {key|name|status|
/// id} 对象）。提取不到＝nil（形状未认出，不等于漂移）
public struct KanbanWorkflow: Decodable, Equatable, Sendable {
    public let statusNames: Set<String>?

    public init(statusNames: Set<String>?) {
        self.statusNames = statusNames
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        statusNames = Self.extractNames(from: jsonValue)
    }

    private static func extractNames(from value: JSONValue) -> Set<String>? {
        let dict = value.objectDict ?? [:]
        for key in ["columns", "statuses", "states"] {
            guard let items = dict[key]?.arrayValues else { continue }
            let names = items.compactMap { item -> String? in
                if let raw = item.stringValue { return raw }
                let fields = KanbanFields(dict: item.objectDict ?? [:])
                return fields.string("key", "name", "status", "id")
            }
            if !names.isEmpty { return Set(names) }
        }
        if let nested = dict["workflow"] {
            return extractNames(from: nested)
        }
        return nil
    }
}

/// 版本探针（spike 缺口补法 5）：workflow 列集合缺
/// 核心列＝枚举漂移 → 适配层降级只读；形状未认出
/// （statusNames 为 nil）不判漂移——拿不准不硬崩、
/// 不假报，照常读写
public enum KanbanProbe {
    public static let requiredColumns: Set<String> = [
        "ready", "running", "blocked", "review", "done",
    ]

    public static func isDrifted(_ workflow: KanbanWorkflow) -> Bool {
        guard let names = workflow.statusNames else { return false }
        return !requiredColumns.isSubset(of: names)
    }
}

// MARK: - 详情（评论/事件/运行/证据）

/// 评论行：答题的载体——worker（再）派发时上下文
/// 注入最近 30 条（spike 对照 6 实证）
public struct KanbanComment: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let author: String
    public let body: String
    public let createdAt: Date?

    public init(id: String, author: String, body: String, createdAt: Date?) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        let fields = KanbanFields(dict: jsonValue.objectDict ?? [:])
        if let rawId = fields.string("id") {
            id = rawId
        } else if let numericId = fields.int("id") {
            id = String(numericId)
        } else {
            id = ""
        }
        author = fields.string("author") ?? ""
        body = fields.string("body") ?? ""
        createdAt = fields.time("created_at", "createdAt")
    }
}

/// 事件行（task_events 审计流）：kind 为原生事件名
/// （created/claimed/completed/...），原样保留。
/// 0.18.0：blocked 事件的 payload 是待答问题原文的
/// 真实存放处（P3 生产验收实查：payload＝{reason:
/// "你的幸运数字是多少？", kind:"needs_input"}；
/// task 对象本身没有 block_reason 字段）——payload
/// 的 reason/kind 单独解出，不再让问题原文埋在事件
/// 文本里取不到。
public struct KanbanEvent: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let text: String?
    public let createdAt: Date?
    /// payload.reason（blocked 事件＝阻塞/提问原文）
    public let payloadReason: String?
    /// payload.kind（blocked 事件＝needs_input 等）
    public let payloadKind: String?

    public init(
        id: String, kind: String, text: String?,
        createdAt: Date?, payloadReason: String? = nil,
        payloadKind: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.payloadReason = payloadReason
        self.payloadKind = payloadKind
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        let fields = KanbanFields(dict: jsonValue.objectDict ?? [:])
        if let rawId = fields.string("id") {
            id = rawId
        } else if let numericId = fields.int("id") {
            id = String(numericId)
        } else {
            id = ""
        }
        kind = fields.string("kind", "type", "event") ?? ""
        text = fields.string("message", "detail", "summary")
        createdAt = fields.time("created_at", "createdAt")
        // payload 子字典（验收实形）；顶层 reason 只作
        // 形态兜底（个别事件把 reason 平铺在行上）
        let payload = KanbanFields(
            dict: jsonValue.objectDict?["payload"]?.objectDict ?? [:]
        )
        payloadReason = payload.string("reason")
            ?? fields.string("reason")
        payloadKind = payload.string("kind")
    }
}

/// 运行行（task_runs）：一次派发尝试——status 为列
/// 状态、outcome 为结果（failed/crashed/timed_out/
/// spawn_failed 等，spike 对照 4g）
public struct KanbanRun: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let status: String?
    public let outcome: String?
    public let summary: String?
    public let startedAt: Date?
    public let endedAt: Date?

    public init(
        id: Int, status: String?, outcome: String?,
        summary: String?, startedAt: Date?, endedAt: Date?
    ) {
        self.id = id
        self.status = status
        self.outcome = outcome
        self.summary = summary
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        let fields = KanbanFields(dict: jsonValue.objectDict ?? [:])
        id = fields.int("id") ?? 0
        status = fields.string("status")
        outcome = fields.string("outcome")
        summary = fields.string("summary")
        startedAt = fields.time("started_at", "startedAt")
        endedAt = fields.time("ended_at", "endedAt", "finished_at")
    }
}

/// run 结果译名（原生值小表，其余原样）
public enum KanbanRunOutcome {
    public static func label(
        for run: KanbanRun, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch run.outcome ?? run.status {
        case "completed", "succeeded", "success", "done":
            return L10n.string("完成", locale: locale)
        case "failed": return L10n.string("失败", locale: locale)
        case "crashed": return L10n.string("崩溃", locale: locale)
        case "timed_out": return L10n.string("超时", locale: locale)
        case "spawn_failed": return L10n.string("启动失败", locale: locale)
        case "running": return L10n.string("运行中", locale: locale)
        case nil: return L10n.string("运行记录", locale: locale)
        case .some(let raw): return raw
        }
    }
}

/// 证据条目（spike 对照 3：证据面＝result＋runs＋
/// events＋attachments 拼装）：结果置顶、运行与事件
/// 各按时刻倒序
public struct KanbanEvidenceItem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case result
        case run
        case event
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String?
    public let at: Date?

    public init(
        id: String, kind: Kind, title: String,
        detail: String?, at: Date?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.at = at
    }
}

/// GET /tasks/{id} 回执：task（可能裸行、也可能
/// {task:{...}} 包裹）＋comments＋events＋runs＋
/// attachments（spike 契约＋上游文档口径）
public struct KanbanTaskDetail: Decodable, Equatable, Sendable {
    public let task: KanbanTask
    public let comments: [KanbanComment]
    public let events: [KanbanEvent]
    public let runs: [KanbanRun]
    public let attachmentNames: [String]

    public init(
        task: KanbanTask, comments: [KanbanComment],
        events: [KanbanEvent], runs: [KanbanRun],
        attachmentNames: [String]
    ) {
        self.task = task
        self.comments = comments
        self.events = events
        self.runs = runs
        self.attachmentNames = attachmentNames
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.objectDict ?? [:]
        let fields = KanbanFields(dict: dict)
        task = KanbanTask(jsonValue: jsonValue)
        comments = fields.array("comments").map {
            KanbanComment(jsonValue: $0)
        }
        events = fields.array("events").map {
            KanbanEvent(jsonValue: $0)
        }
        runs = fields.array("runs").map {
            KanbanRun(jsonValue: $0)
        }
        attachmentNames = fields.array("attachments").compactMap {
            item -> String? in
            if let raw = item.stringValue { return raw }
            let itemFields = KanbanFields(dict: item.objectDict ?? [:])
            return itemFields.string("filename", "name")
        }
    }

    /// 最新一条 blocked 事件的原文（0.18.0，P3 生产
    /// 验收定案）：待答问题存放在详情 events 里
    /// blocked 事件的 payload.reason——task 对象本
    /// 身没有 block_reason 字段（验收实查键全集确
    /// 认），0.10.0「取 block_reason」的口径恒落空、
    /// 就此更正
    public var latestBlockedEventReason: String? {
        events
            .filter { $0.kind == "blocked" }
            .sorted {
                ($0.createdAt ?? .distantPast)
                    > ($1.createdAt ?? .distantPast)
            }
            .lazy
            .compactMap { $0.payloadReason }
            .first { !$0.isEmpty }
    }

    /// blocked 那条 run 的 summary（验收实查与事件
    /// payload.reason 同文，作第二来源）：按结束/开始
    /// 时刻取最近一条 blocked run
    public var latestBlockedRunSummary: String? {
        runs
            .filter { $0.status == "blocked" || $0.outcome == "blocked" }
            .sorted {
                ($0.endedAt ?? $0.startedAt ?? .distantPast)
                    > ($1.endedAt ?? $1.startedAt ?? .distantPast)
            }
            .lazy
            .compactMap { $0.summary }
            .first { !$0.isEmpty }
    }

    /// 阻塞原文（详情头部与待答区共用）：blocked 事
    /// 件 payload.reason ＞ blocked run 的 summary；
    /// 都无＝nil——视图如实显「问题原文未取到」，不
    /// 许拿任务标题或评论冒充问题
    public var blockDetailText: String? {
        latestBlockedEventReason ?? latestBlockedRunSummary
    }

    /// 待回答的问题（0.18.0 改源）：blocked 事件
    /// payload.reason ＞ blocked run 的 summary ＞
    /// 执行方最近一条非人工评论；都无＝nil（视图回
    /// 落通用文案，不许编问题）
    public var pendingQuestion: String? {
        guard task.presentation == .needsInput else { return nil }
        if let text = blockDetailText { return text }
        return comments.last {
            !KanbanContract.humanAuthors.contains($0.author)
        }?.body
    }

    /// 证据拼装：完成结果置顶 → 运行记录（新→旧）→
    /// 事件流（新→旧，上限 50 条防长尾淹没）
    public var evidenceItems: [KanbanEvidenceItem] {
        evidenceItems(locale: AppLocale.uiLocale)
    }

    /// 证据拼装的目录取词形（0.42.1 国际化长尾包）：
    /// 条目标题模板走目录；result/summary/text 与
    /// event.kind 是服务端内容、原样直通不译
    public func evidenceItems(locale: Locale) -> [KanbanEvidenceItem] {
        var items: [KanbanEvidenceItem] = []
        if let result = task.result, !result.isEmpty {
            items.append(KanbanEvidenceItem(
                id: "result", kind: .result,
                title: L10n.string("完成结果", locale: locale),
                detail: result, at: task.completedAt
            ))
        }
        let sortedRuns = runs.sorted { lhs, rhs in
            (lhs.endedAt ?? lhs.startedAt ?? .distantPast)
                > (rhs.endedAt ?? rhs.startedAt ?? .distantPast)
        }
        for run in sortedRuns {
            items.append(KanbanEvidenceItem(
                id: "run-\(run.id)", kind: .run,
                title: L10n.format(
                    "运行 · %@", locale: locale,
                    KanbanRunOutcome.label(for: run, locale: locale)
                ),
                detail: run.summary,
                at: run.endedAt ?? run.startedAt
            ))
        }
        let sortedEvents = events
            .sorted {
                ($0.createdAt ?? .distantPast)
                    > ($1.createdAt ?? .distantPast)
            }
            .prefix(50)
        for event in sortedEvents {
            items.append(KanbanEvidenceItem(
                id: "event-\(event.id)", kind: .event,
                title: event.kind.isEmpty
                    ? L10n.string("事件", locale: locale) : event.kind,
                detail: event.text, at: event.createdAt
            ))
        }
        return items
    }
}

// MARK: - 派发回执

/// POST /dispatch 回执（spike 实测）：{spawned:
/// [[task_id, profile, workspace], ...]}——只取
/// 催生条数；形态变体（数字/计数键）兜底
public struct KanbanDispatchReceipt: Decodable, Equatable, Sendable {
    public let spawnedCount: Int

    public init(spawnedCount: Int) {
        self.spawnedCount = spawnedCount
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        self.init(jsonValue: value)
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.objectDict ?? [:]
        let fields = KanbanFields(dict: dict)
        if let spawned = dict["spawned"]?.arrayValues {
            spawnedCount = spawned.count
        } else if let count = fields.int("spawned", "spawned_count") {
            spawnedCount = count
        } else {
            spawnedCount = 0
        }
    }
}

// MARK: - 控制动作（映射与策略，spike 冻结）

/// App 控制动作：文案与落点逐条照 spike「控制映射」
/// ——无「暂停」（无动词），停止＝terminate/reclaim；
/// 继续/重试/打回＝PATCH ready；批准＝PATCH done；
/// 取消＝（运行中先 terminate）＋DELETE；答题＝
/// comment＋PATCH ready
public enum KanbanAction: String, CaseIterable, Equatable, Sendable {
    case create
    case stop
    case resume
    case retry
    case cancel
    case approve
    case requestChanges
    case answer

    public var title: String { title(locale: AppLocale.uiLocale) }

    /// 动作名的目录取词形（0.42.1 国际化长尾包）
    public func title(locale: Locale) -> String {
        switch self {
        case .create: return L10n.string("新建任务", locale: locale)
        case .stop: return L10n.string("停止", locale: locale)
        case .resume: return L10n.string("继续", locale: locale)
        case .retry: return L10n.string("重试", locale: locale)
        case .cancel: return L10n.string("取消任务", locale: locale)
        case .approve: return L10n.string("批准", locale: locale)
        case .requestChanges: return L10n.string("打回", locale: locale)
        case .answer: return L10n.string("回答", locale: locale)
        }
    }

    public var systemImage: String {
        switch self {
        case .create: return "plus"
        case .stop: return "stop.circle"
        case .resume: return "play.circle"
        case .retry: return "arrow.clockwise"
        case .cancel: return "trash"
        case .approve: return "checkmark.circle"
        case .requestChanges: return "arrow.uturn.backward.circle"
        case .answer: return "text.bubble"
        }
    }

    /// 派发类动作（效果＝让 worker 动起来）：接管
    /// 互斥只闸这一类（施工图 §4.3 产品层约定）；
    /// 停止/取消/批准是收束动作、接管中照常可用
    public var isDispatchClass: Bool {
        switch self {
        case .create, .resume, .retry, .answer, .requestChanges:
            return true
        case .stop, .cancel, .approve:
            return false
        }
    }

    public var isDestructive: Bool { self == .cancel }
}

/// 控制计划的原子步：动作 → HTTP 动词序列的纯映射，
/// 执行与回读确认在 App 层 KanbanStore
public enum KanbanControlStep: Equatable, Sendable {
    case terminateRun(Int)
    case reclaim(taskID: String)
    case patchStatus(taskID: String, status: String)
    case deleteTask(taskID: String)
    case comment(taskID: String)
    case dispatch
}

public enum KanbanControlPlan {
    public static func steps(
        action: KanbanAction, task: KanbanTask
    ) -> [KanbanControlStep] {
        switch action {
        case .create:
            return []
        case .stop:
            if let runId = task.currentRunId {
                return [.terminateRun(runId)]
            }
            return [.reclaim(taskID: task.id)]
        case .cancel:
            if task.presentation == .running {
                if let runId = task.currentRunId {
                    return [
                        .terminateRun(runId),
                        .deleteTask(taskID: task.id),
                    ]
                }
                return [
                    .reclaim(taskID: task.id),
                    .deleteTask(taskID: task.id),
                ]
            }
            return [.deleteTask(taskID: task.id)]
        case .resume, .retry, .requestChanges:
            return [.patchStatus(taskID: task.id, status: "ready")]
        case .approve:
            return [.patchStatus(taskID: task.id, status: "done")]
        case .answer:
            return [
                .comment(taskID: task.id),
                .patchStatus(taskID: task.id, status: "ready"),
            ]
        }
    }

    /// 新建任务的固定序列：建卡（回执 id）→ 催派 →
    /// 回板确认出现（App 层执行，此处只立语义锚；
    /// 文案走用户语言，接口细节不进呈现文案，§8）
    public static var createFlowDescription: String {
        createFlowDescription(locale: AppLocale.uiLocale)
    }

    /// 流程说明的目录取词形（0.42.1 国际化长尾包）
    public static func createFlowDescription(locale: Locale) -> String {
        L10n.string("建卡 → 催派 → 回到看板确认出现", locale: locale)
    }
}

/// 动作可用性策略：按呈现态给动作集；闸门两条——
/// 版本漂移只读（全闸）、接管互斥（只闸派发类）
public enum KanbanActionPolicy {
    public static func actions(for task: KanbanTask) -> [KanbanAction] {
        switch task.presentation {
        case .running:
            return [.stop, .cancel]
        case .review:
            return [.approve, .requestChanges, .cancel]
        case .needsInput:
            return [.answer, .cancel]
        case .failed:
            return [.retry, .cancel]
        case .blocked:
            return [.resume, .cancel]
        case .queued:
            return [.cancel]
        case .scheduled, .triage:
            return [.resume, .cancel]
        case .done, .archived, .unknown:
            return []
        }
    }

    public struct Gate: Equatable, Sendable {
        public let enabled: Bool
        public let reason: String?

        public init(enabled: Bool, reason: String?) {
            self.enabled = enabled
            self.reason = reason
        }
    }

    public static func gate(
        action: KanbanAction, takeoverActive: Bool, readOnly: Bool
    ) -> Gate {
        if readOnly {
            return Gate(enabled: false, reason: KanbanContract.readOnlyReason)
        }
        if takeoverActive, action.isDispatchClass {
            return Gate(
                enabled: false, reason: KanbanContract.takeoverReason
            )
        }
        return Gate(enabled: true, reason: nil)
    }
}
