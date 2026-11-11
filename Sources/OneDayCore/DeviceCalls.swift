import Foundation

/// 设备工具调用的纯逻辑（0.34.0 批一）：结构化错误
/// 映射、调用参数解析（桥 arguments 是动态 JSON，逐
/// 工具在此收敛成强类型并校验）、设备会话状态机、
/// 写工具 App 侧幂等账本、调用元数据条目。框架执行
/// 与网络在 App 层，这里只做可单测的判定——口径与
/// device-bridge 契约逐字对齐（错误码/device_offline
/// 等由桥定义，本文件只产出 App 回给桥的错误）。

// MARK: - 结构化错误（respond 的 error 体）

/// App 执行一次调用失败时回给桥的错误：code 供智能
/// 体如实转述、message 是人话。不许吞错装成功。
public enum DeviceToolError: Error, Equatable, Sendable {
    /// 该件系统权限不可用（执行时复查仍非 granted/
    /// limited；桥侧一般先行拦截，此为手机侧兜底）
    case permissionDenied(String)
    /// 该件调用开关已关或工具未接线（执行时复查）
    case toolUnavailable(String)
    /// 参数缺失/非法（人话指明哪一项）
    case invalidArguments(String)
    /// 写目标越界（改他人共享日历上的他人事件等，
    /// 设计档 §5 红线：只许动本机日历与本人事件）
    case updateNotAllowed(String)
    /// 其余执行失败（框架错误原文的人话化）
    case failed(String)

    public var code: String {
        switch self {
        case .permissionDenied: return "permission_denied"
        case .toolUnavailable: return "tool_unavailable"
        case .invalidArguments: return "invalid_arguments"
        case .updateNotAllowed: return "update_not_allowed"
        case .failed: return "device_error"
        }
    }

    public var message: String {
        switch self {
        case .permissionDenied(let text),
             .toolUnavailable(let text),
             .invalidArguments(let text),
             .updateNotAllowed(let text),
             .failed(let text):
            return text
        }
    }
}

// MARK: - ISO 8601 时刻（桥契约的时刻格式）

public enum DeviceISO8601 {
    // ISO8601DateFormatter 非 Sendable，Swift 6 下不许
    // 作静态共享——按次构造（调用频度低、成本可忽略）
    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    /// 解析桥下发的 ISO 8601 时刻（带/不带小数秒、
    /// 带时区偏移均可）；解析不了回 nil，不猜
    public static func parse(_ text: String) -> Date? {
        makeFormatter(fractional: true).date(from: text)
            ?? makeFormatter(fractional: false).date(from: text)
    }

    /// 出参时刻统一带小数秒的 ISO 8601（UTC）
    public static func format(_ date: Date) -> String {
        makeFormatter(fractional: true).string(from: date)
    }
}

// MARK: - 参数解析（arguments: [String: JSONValue] → 强类型）

private func requiredString(
    _ args: [String: JSONValue], _ key: String, _ field: String
) throws -> String {
    guard let value = args[key]?.stringValue,
          !value.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw DeviceToolError.invalidArguments("缺少必填参数：\(field)")
    }
    return value
}

private func optionalString(
    _ args: [String: JSONValue], _ key: String
) -> String? {
    guard let value = args[key]?.stringValue,
          !value.trimmingCharacters(in: .whitespaces).isEmpty else {
        return nil
    }
    return value
}

private func requiredDate(
    _ args: [String: JSONValue], _ key: String, _ field: String
) throws -> Date {
    let text = try requiredString(args, key, field)
    guard let date = DeviceISO8601.parse(text) else {
        throw DeviceToolError.invalidArguments("\(field)不是合法的 ISO 8601 时刻")
    }
    return date
}

private func optionalDate(
    _ args: [String: JSONValue], _ key: String, _ field: String
) throws -> Date? {
    guard let text = optionalString(args, key) else { return nil }
    guard let date = DeviceISO8601.parse(text) else {
        throw DeviceToolError.invalidArguments("\(field)不是合法的 ISO 8601 时刻")
    }
    return date
}

/// calendar_list_events 的查询窗口：粒度上限在 App
/// 侧执行（设计档 §3.1）——窗口最长 14 天，超了把
/// end 收到 start＋14 天并标 clamped，不许一次调用
/// 拖全量历史
public struct CalendarListWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let wasClamped: Bool

    public static let maxWindowSeconds: TimeInterval = 14 * 24 * 3600

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> CalendarListWindow {
        let start = try requiredDate(args, "start", "开始时刻")
        let end = try requiredDate(args, "end", "结束时刻")
        guard end > start else {
            throw DeviceToolError.invalidArguments("结束时刻必须晚于开始时刻")
        }
        if end.timeIntervalSince(start) > maxWindowSeconds {
            return CalendarListWindow(
                start: start,
                end: start.addingTimeInterval(maxWindowSeconds),
                wasClamped: true
            )
        }
        return CalendarListWindow(start: start, end: end, wasClamped: false)
    }
}

public struct CalendarCreateArgs: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let calendarName: String?
    public let location: String?
    public let notes: String?
    public let idempotencyKey: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> CalendarCreateArgs {
        let title = try requiredString(args, "title", "标题")
        let start = try requiredDate(args, "start", "开始时刻")
        let end = try requiredDate(args, "end", "结束时刻")
        guard end > start else {
            throw DeviceToolError.invalidArguments("结束时刻必须晚于开始时刻")
        }
        return CalendarCreateArgs(
            title: title, start: start, end: end,
            allDay: args["allDay"]?.boolValue ?? false,
            calendarName: optionalString(args, "calendarName"),
            location: optionalString(args, "location"),
            notes: optionalString(args, "notes"),
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }
}

public struct CalendarUpdateArgs: Equatable, Sendable {
    public let eventID: String
    public let title: String?
    public let start: Date?
    public let end: Date?
    public let location: String?
    public let notes: String?
    public let idempotencyKey: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> CalendarUpdateArgs {
        let parsed = CalendarUpdateArgs(
            eventID: try requiredString(args, "eventId", "事件 id"),
            title: optionalString(args, "title"),
            start: try optionalDate(args, "start", "开始时刻"),
            end: try optionalDate(args, "end", "结束时刻"),
            location: optionalString(args, "location"),
            notes: optionalString(args, "notes"),
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
        if let start = parsed.start, let end = parsed.end, end <= start {
            throw DeviceToolError.invalidArguments("结束时刻必须晚于开始时刻")
        }
        return parsed
    }
}

public struct ReminderCreateArgs: Equatable, Sendable {
    public let title: String
    public let due: Date?
    public let listName: String?
    public let notes: String?
    public let idempotencyKey: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ReminderCreateArgs {
        ReminderCreateArgs(
            title: try requiredString(args, "title", "标题"),
            due: try optionalDate(args, "due", "到期时刻"),
            listName: optionalString(args, "listName"),
            notes: optionalString(args, "notes"),
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }
}

public struct ReminderCompleteArgs: Equatable, Sendable {
    public let reminderID: String
    public let idempotencyKey: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ReminderCompleteArgs {
        ReminderCompleteArgs(
            reminderID: try requiredString(args, "reminderId", "提醒 id"),
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }
}

public struct ContactsSearchArgs: Equatable, Sendable {
    public let query: String
    public let limit: Int

    /// limit 缺省 20、收敛到 1...50（粒度在 App 侧收敛）
    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ContactsSearchArgs {
        var limit = 20
        if case .number(let raw)? = args["limit"] {
            limit = Int(raw)
        }
        return ContactsSearchArgs(
            query: try requiredString(args, "query", "搜索关键词"),
            limit: min(max(limit, 1), 50)
        )
    }
}

// MARK: - 剪贴板与沙盒文件参数（设备扩容批一）

/// 沙盒路径规范化（纯函数，钉测防越界）：入参是桥
/// 下发的相对路径——只许在 App 自有 Documents 区内
/// 活动。规则：去首尾空白；以 / 开头（绝对路径）直
/// 接拒；按 / 切段，空段与 "." 段丢弃，".." 段弹栈、
/// 栈空还弹＝越界拒；含 NUL 拒。返回规范相对路径
/// （""＝根目录本身）。App 层解析 URL 后再做一次标
/// 准化前缀校验（双保险，见 SandboxFilesEngine）。
public enum SandboxPath {
    /// 单次读/写文本的字节上限（256 KB）：文件工具只
    /// 碰文本，超限如实报错、不静默截断
    public static let maxContentBytes = 256 * 1024
    /// 单次列目录的条目上限：超了截断并在结果里标明
    public static let maxListEntries = 500

    public static func normalize(_ raw: String) throws -> String {
        if raw.contains("\0") {
            throw DeviceToolError.invalidArguments("路径含有非法字符")
        }
        let trimmed = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.hasPrefix("/") {
            throw DeviceToolError.invalidArguments(
                "路径要从 OneDay 文件夹根算起，不能以 / 开头"
            )
        }
        var stack: [String] = []
        for part in trimmed.split(
            separator: "/", omittingEmptySubsequences: true
        ) {
            let component = String(part)
            if component == "." { continue }
            if component == ".." {
                guard !stack.isEmpty else {
                    throw DeviceToolError.invalidArguments(
                        "路径越出了 OneDay 文件夹的范围"
                    )
                }
                stack.removeLast()
                continue
            }
            stack.append(component)
        }
        return stack.joined(separator: "/")
    }

    /// 读/写目标必须是具体文件：规范化后为空（根目
    /// 录本身）不许当文件用
    public static func normalizeFilePath(
        _ raw: String
    ) throws -> String {
        let path = try normalize(raw)
        guard !path.isEmpty else {
            throw DeviceToolError.invalidArguments(
                "缺少必填参数：文件路径"
            )
        }
        return path
    }
}

public struct ClipboardSetArgs: Equatable, Sendable {
    public let text: String
    public let idempotencyKey: String

    /// text 必须在场（空串合法＝把剪贴板设为空，
    /// 与「没给参数」是两回事）；幂等键必填（写纪
    /// 律与既有四件同）
    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ClipboardSetArgs {
        guard let text = args["text"]?.stringValue else {
            throw DeviceToolError.invalidArguments(
                "缺少必填参数：文字内容"
            )
        }
        return ClipboardSetArgs(
            text: text,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }
}

public struct FilesListArgs: Equatable, Sendable {
    /// 规范相对路径；缺省 ""＝根目录
    public let path: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> FilesListArgs {
        FilesListArgs(
            path: try SandboxPath.normalize(
                optionalString(args, "path") ?? ""
            )
        )
    }
}

public struct FilesReadArgs: Equatable, Sendable {
    public let path: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> FilesReadArgs {
        FilesReadArgs(
            path: try SandboxPath.normalizeFilePath(
                requiredString(args, "path", "文件路径")
            )
        )
    }
}

public struct FilesWriteArgs: Equatable, Sendable {
    public let path: String
    public let content: String
    public let idempotencyKey: String

    /// content 必须在场（空串合法＝写空文件）；超
    /// 256 KB 在解析层就拒（粒度在 App 侧收敛）
    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> FilesWriteArgs {
        let path = try SandboxPath.normalizeFilePath(
            requiredString(args, "path", "文件路径")
        )
        guard let content = args["content"]?.stringValue else {
            throw DeviceToolError.invalidArguments(
                "缺少必填参数：文件内容"
            )
        }
        guard content.utf8.count <= SandboxPath.maxContentBytes
        else {
            throw DeviceToolError.invalidArguments(
                "文件内容超过 256 KB 上限"
            )
        }
        return FilesWriteArgs(
            path: path, content: content,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }
}

// MARK: - 设备会话状态机（客户端生命周期）

/// 设备会话的纯状态机：桥契约的生命周期——注册→长
/// 轮询→领调用→执行回执→继续轮询；轮询 409（会话被
/// 顶替/过期）或心跳 404 一律回注册；断开请求落回
/// offline。网络动作由 App 层按 handle 返回的动作执
/// 行，状态只此一处演进、便于单测钉死。
public enum DeviceSessionPhase: Equatable, Sendable {
    case offline
    case registering
    case active(sessionID: String)
    case executing(sessionID: String, callID: String)
}

public enum DeviceSessionEvent: Equatable, Sendable {
    case startRequested
    case registered(sessionID: String)
    case registrationFailed
    case pollReturnedCall(callID: String)
    case pollReturnedEmpty
    case respondFinished
    case pollUnknownSession
    case disconnectRequested
}

public enum DeviceSessionAction: Equatable, Sendable {
    case none
    case register
    case poll
    case disconnect
}

public struct DeviceSessionMachine: Equatable, Sendable {
    public private(set) var phase: DeviceSessionPhase = .offline

    public init() {}

    public var sessionID: String? {
        switch phase {
        case .offline, .registering: return nil
        case .active(let id), .executing(let id, _): return id
        }
    }

    public var isOnline: Bool { sessionID != nil }

    @discardableResult
    public mutating func handle(
        _ event: DeviceSessionEvent
    ) -> DeviceSessionAction {
        switch (phase, event) {
        case (.offline, .startRequested):
            phase = .registering
            return .register
        case (.registering, .registered(let id)):
            phase = .active(sessionID: id)
            return .poll
        case (.registering, .registrationFailed):
            phase = .offline
            return .none
        case (.active(let id), .pollReturnedCall(let callID)):
            phase = .executing(sessionID: id, callID: callID)
            return .none
        case (.active, .pollReturnedEmpty):
            return .poll
        case (.executing(let id, _), .respondFinished):
            phase = .active(sessionID: id)
            return .poll
        case (.active, .pollUnknownSession),
             (.executing, .pollUnknownSession):
            // 会话被顶替或已过期：旧 id 作废、重新注册
            phase = .registering
            return .register
        case (.offline, .disconnectRequested):
            return .none
        case (.registering, .disconnectRequested):
            phase = .offline
            return .none
        case (.active, .disconnectRequested),
             (.executing, .disconnectRequested):
            phase = .offline
            return .disconnect
        default:
            // 其余组合是时序噪声（如已在注册中又收到
            // start）：不演进、不发动作
            return .none
        }
    }
}

// MARK: - 写工具幂等账本（App 侧第二层防重，设计档 §5）

/// 已执行写键记录：只存 key 与对象 id（＋工具名与时
/// 刻），不存任何内容。桥侧已有一层去重（write-keys），
/// 本账本是手机侧保险：同 key 24 小时内重复到达直接
/// 回原对象 id、不再真写第二次。
public struct WriteKeyRecord: Codable, Equatable, Sendable {
    public let key: String
    public let tool: String
    public let objectID: String?
    public let executedAt: TimeInterval

    public init(
        key: String, tool: String, objectID: String?,
        executedAt: TimeInterval
    ) {
        self.key = key
        self.tool = tool
        self.objectID = objectID
        self.executedAt = executedAt
    }
}

public enum WriteKeyLedger {
    public static let windowSeconds: TimeInterval = 24 * 3600

    /// 查 key 是否在窗口内已执行（命中即回原记录）
    public static func lookup(
        _ records: [WriteKeyRecord], key: String, now: Date
    ) -> WriteKeyRecord? {
        records.first {
            $0.key == key
                && now.timeIntervalSince(
                    Date(timeIntervalSince1970: $0.executedAt)
                ) < windowSeconds
        }
    }

    /// 记一笔并清掉过期记录（同 key 覆盖旧记录）
    public static func recording(
        _ records: [WriteKeyRecord], key: String, tool: String,
        objectID: String?, now: Date
    ) -> [WriteKeyRecord] {
        var kept = pruned(records, now: now).filter { $0.key != key }
        kept.append(WriteKeyRecord(
            key: key, tool: tool, objectID: objectID,
            executedAt: now.timeIntervalSince1970
        ))
        return kept
    }

    public static func pruned(
        _ records: [WriteKeyRecord], now: Date
    ) -> [WriteKeyRecord] {
        records.filter {
            now.timeIntervalSince(
                Date(timeIntervalSince1970: $0.executedAt)
            ) < windowSeconds
        }
    }
}

// MARK: - 调用元数据（详情页「最近调用」的数据源）

/// 一次工具调用的元数据条目：工具名/时刻/成败/错误
/// 码——只记元数据、永不记参数与结果内容（与桥审计
/// 同纪律）。详情页呈现最近一次调用结果用它。
public struct DeviceCallLogEntry: Codable, Equatable, Sendable {
    public let tool: String
    public let source: DeviceSourceID
    public let at: TimeInterval
    public let succeeded: Bool
    public let errorCode: String?

    public init(
        tool: String, source: DeviceSourceID, at: TimeInterval,
        succeeded: Bool, errorCode: String?
    ) {
        self.tool = tool
        self.source = source
        self.at = at
        self.succeeded = succeeded
        self.errorCode = errorCode
    }

    /// 呈现人话：成功＝「调用成功」；失败带错误码原
    /// 文（如实，不粉饰）
    public var summaryLine: String {
        if succeeded { return "最近调用：成功" }
        return "最近调用：失败（\(errorCode ?? "device_error")）"
    }
}

// MARK: - 批二·授权状态机（系统授权铁律的纯函数落点）

/// 授权决策（批二）：引擎的授权请求函数一律先过
/// 本门再动作，把「系统授权铁律」落进代码而不是
/// 靠调用方自觉——
/// - proceed：现态可用（granted/limited/
///   notApplicable），直达业务，永不重走异步请求；
/// - requestOnce：只有未决定（notDetermined）才发
///   那一次系统请求；
/// - degrade：已拒绝/受限/只写——不请求、不重复弹
///   窗，引擎如实回权限错误，由呈现层给「去设置里
///   打开」的人话降级。
/// 纯函数钉测（DeviceCallsTests 全档覆盖）。
public enum DevicePermissionGate {
    public enum Decision: Equatable, Sendable {
        case proceed
        case requestOnce
        case degrade
    }

    public static func decision(
        for state: DevicePermissionState
    ) -> Decision {
        switch state {
        case .granted, .limited, .notApplicable:
            return .proceed
        case .notDetermined:
            return .requestOnce
        case .denied, .restricted, .writeOnly:
            return .degrade
        }
    }
}

// MARK: - 批二·动作型工具参数（闹钟/通知/打开目标）

/// 时长人话（秒数 → 「45 秒后」「10 分钟后」
/// 「1 小时 30 分后」）：动作回执的人话摘要共用，
/// 纯拼接、执行层回执不入 L10n 目录（§111.4 先例）
public func deviceDurationText(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) 秒后" }
    let minutes = total / 60
    let restSeconds = total % 60
    if minutes < 60 {
        return restSeconds > 0
            ? "\(minutes) 分 \(restSeconds) 秒后"
            : "\(minutes) 分钟后"
    }
    let hours = minutes / 60
    let restMinutes = minutes % 60
    return restMinutes > 0
        ? "\(hours) 小时 \(restMinutes) 分后"
        : "\(hours) 小时后"
}

/// alarm_set 参数：时刻（at）与倒计时（afterSeconds）
/// 恰给其一——两者都是「什么时候响」的唯一口径，
/// 同给必有歧义、同缺无从设定，解析层直接拒。
/// 倒计时收敛在 5 秒～24 小时（再远的用定点时刻）。
public struct AlarmSetArgs: Equatable, Sendable {
    public let title: String
    public let at: Date?
    public let afterSeconds: TimeInterval?
    public let idempotencyKey: String

    public static let minCountdownSeconds: TimeInterval = 5
    public static let maxCountdownSeconds: TimeInterval = 86_400

    public init(
        title: String, at: Date?, afterSeconds: TimeInterval?,
        idempotencyKey: String
    ) {
        self.title = title
        self.at = at
        self.afterSeconds = afterSeconds
        self.idempotencyKey = idempotencyKey
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> AlarmSetArgs {
        let title = try requiredString(args, "title", "闹钟标题")
        let at = try optionalDate(args, "at", "定点时刻")
        var afterSeconds: TimeInterval?
        if let raw = args["afterSeconds"]?.numberValue {
            guard raw >= Self.minCountdownSeconds,
                  raw <= Self.maxCountdownSeconds
            else {
                throw DeviceToolError.invalidArguments(
                    "倒计时秒数要在 5 秒到 24 小时之间"
                )
            }
            afterSeconds = raw
        }
        guard (at == nil) != (afterSeconds == nil) else {
            throw DeviceToolError.invalidArguments(
                "定点时刻与倒计时秒数只能给一个"
            )
        }
        return AlarmSetArgs(
            title: title, at: at, afterSeconds: afterSeconds,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    /// 复述确认/回执摘要（四纪律之复述确认的载荷）
    public var humanSummary: String {
        if let at {
            return "设定闹钟：\(title)，\(DisplayDate.dateTime(at))响"
        }
        return "设定倒计时：\(title)，"
            + deviceDurationText(afterSeconds ?? 0) + "响"
    }
}

/// alarm_cancel 参数：按系统闹钟 id 取消（id 必须是
/// UUID 形——AlarmKit 闹钟 id 就是 UUID，形不对的
/// 在解析层拒，不许拿着乱码去系统里找）。取消是
/// 改变系统状态的动作，照写工具带防重复键。
public struct AlarmCancelArgs: Equatable, Sendable {
    public let alarmID: String
    public let idempotencyKey: String

    public init(alarmID: String, idempotencyKey: String) {
        self.alarmID = alarmID
        self.idempotencyKey = idempotencyKey
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> AlarmCancelArgs {
        let raw = try requiredString(args, "alarmId", "闹钟编号")
        guard UUID(uuidString: raw) != nil else {
            throw DeviceToolError.invalidArguments(
                "闹钟编号不是有效的编号"
            )
        }
        return AlarmCancelArgs(
            alarmID: raw,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public func humanSummary(title: String?) -> String {
        if let title, !title.isEmpty {
            return "取消闹钟：\(title)"
        }
        return "取消闹钟（编号 \(alarmID)）"
    }
}

/// notify_post 参数：标题＋正文必填，延迟秒可选
/// （缺省/0＝立即发）；延迟上限 7 天（再远的提醒
/// 该用闹钟或日历，不塞进待发通知队列）。
public struct NotifyPostArgs: Equatable, Sendable {
    public let title: String
    public let body: String
    public let delaySeconds: TimeInterval
    public let idempotencyKey: String

    public static let maxDelaySeconds: TimeInterval = 604_800

    public init(
        title: String, body: String, delaySeconds: TimeInterval,
        idempotencyKey: String
    ) {
        self.title = title
        self.body = body
        self.delaySeconds = delaySeconds
        self.idempotencyKey = idempotencyKey
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> NotifyPostArgs {
        let title = try requiredString(args, "title", "通知标题")
        let body = try requiredString(args, "body", "通知正文")
        var delaySeconds: TimeInterval = 0
        if let raw = args["delaySeconds"]?.numberValue {
            guard raw >= 0, raw <= Self.maxDelaySeconds else {
                throw DeviceToolError.invalidArguments(
                    "延迟秒数要在 0 到 7 天之间"
                )
            }
            delaySeconds = raw
        }
        return NotifyPostArgs(
            title: title, body: body, delaySeconds: delaySeconds,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public var humanSummary: String {
        if delaySeconds > 0 {
            return "发送通知：\(title)，"
                + deviceDurationText(delaySeconds) + "送达"
        }
        return "发送通知：\(title)，立即送达"
    }
}

// MARK: - 批二·拉起白名单（open_target 的封闭目标表）

/// 拉起目标条目：id 是智能体能点的唯一名字，任意
/// URL 直开在目录层就没有入口；urlString 只许四类
/// 已审计形态（系统设置根页 App-prefs、OneDay 自家
/// 设置页哨兵、本机常用应用的公开 scheme），钉测
/// 逐条守。kind 决定执行层的校验路：设置页恒在、
/// 直接开；应用先探装没装，没装如实报错。
public struct OpenTarget: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case settings
        case app
    }

    public let id: String
    /// 名称简体源串（目录键，三语经 L10n 取词）
    public let nameSource: String
    public let urlString: String
    public let kind: Kind

    /// OneDay 自家系统设置页的哨兵值：App 层解析为
    /// UIApplication.openSettingsURLString，不写死串
    public static let appSettingsSentinel = "app-settings"

    public func name(locale: Locale) -> String {
        L10n.string(nameSource, locale: locale)
    }
}

public enum OpenTargetCatalog {
    public static let all: [OpenTarget] = [
        OpenTarget(
            id: "settings.app", nameSource: "OneDay 设置页",
            urlString: OpenTarget.appSettingsSentinel,
            kind: .settings
        ),
        OpenTarget(
            id: "settings.wifi", nameSource: "Wi-Fi 设置",
            urlString: "App-prefs:root=WIFI", kind: .settings
        ),
        OpenTarget(
            id: "settings.bluetooth", nameSource: "蓝牙设置",
            urlString: "App-prefs:root=Bluetooth",
            kind: .settings
        ),
        OpenTarget(
            id: "settings.cellular", nameSource: "蜂窝网络设置",
            urlString: "App-prefs:root=MOBILE_DATA_SETTINGS_ID",
            kind: .settings
        ),
        OpenTarget(
            id: "settings.general", nameSource: "通用设置",
            urlString: "App-prefs:root=General", kind: .settings
        ),
        OpenTarget(
            id: "settings.display", nameSource: "显示与亮度设置",
            urlString: "App-prefs:root=DISPLAY", kind: .settings
        ),
        OpenTarget(
            id: "settings.sounds", nameSource: "声音与触感设置",
            urlString: "App-prefs:root=Sounds", kind: .settings
        ),
        OpenTarget(
            id: "settings.notifications",
            nameSource: "通知设置",
            urlString: "App-prefs:root=NOTIFICATIONS_ID",
            kind: .settings
        ),
        OpenTarget(
            id: "settings.battery", nameSource: "电池设置",
            urlString: "App-prefs:root=BATTERY_USAGE",
            kind: .settings
        ),
        OpenTarget(
            id: "settings.privacy", nameSource: "隐私与安全性设置",
            urlString: "App-prefs:root=Privacy", kind: .settings
        ),
        OpenTarget(
            id: "app.weixin", nameSource: "微信",
            urlString: "weixin://", kind: .app
        ),
        OpenTarget(
            id: "app.alipay", nameSource: "支付宝",
            urlString: "alipay://", kind: .app
        ),
        OpenTarget(
            id: "app.amap", nameSource: "高德地图",
            urlString: "iosamap://", kind: .app
        ),
        OpenTarget(
            id: "app.maps", nameSource: "苹果地图",
            urlString: "maps://", kind: .app
        ),
    ]

    public static func target(_ id: String) -> OpenTarget? {
        all.first { $0.id == id }
    }
}

/// open_target 参数：target 必须命中白名单目录，
/// 未命中在解析层就拒（不下发执行层、不给任何试
/// 错空间）；带防重复键（打开即离开 App，回执要能
/// 在重连后安全重放、不重复跳）。
public struct OpenTargetArgs: Equatable, Sendable {
    public let target: OpenTarget
    public let idempotencyKey: String

    public init(target: OpenTarget, idempotencyKey: String) {
        self.target = target
        self.idempotencyKey = idempotencyKey
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> OpenTargetArgs {
        let raw = try requiredString(args, "target", "打开目标")
        guard let found = OpenTargetCatalog.target(raw) else {
            throw DeviceToolError.invalidArguments(
                "这个目标不在可打开的名单里"
            )
        }
        return OpenTargetArgs(
            target: found,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public var humanSummary: String {
        "打开\(target.name(locale: AppLocale.uiLocale))"
    }
}
