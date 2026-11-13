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
        case (.active, .registered(let id)):
            // 在线中重注册（权限/开关变化刷新桥侧快照
            // 的设计内高频路径）：桥已用新会话顶替旧会
            // 话，必须迁到新 id 并重启轮询——本组合曾
            // 落 default 被丢弃、新会话双环永不重启，
            // 45 秒后被桥判离线（2026-11-13 实案定因）
            phase = .active(sessionID: id)
            return .poll
        case (.executing(_, let callID), .registered(let id)):
            // 执行期重注册同理迁 id：在途调用的回执由
            // 轮询环自带会话 id 发出、成败落调用日志；
            // 状态机保留 callID，respondFinished 仍落
            // 回新会话的 active 继续轮询（回执路径不断）
            phase = .executing(sessionID: id, callID: callID)
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
        if case .number(let raw)? = args["afterSeconds"] {
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
        if case .number(let raw)? = args["delaySeconds"] {
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

// MARK: - 批三·在场交互与端上智能参数（相机/识别/翻译/端上模型/本人确认）

/// 批三的量级收敛（粒度在 App 侧执行的既有口径）：
/// 识别只吃 OneDay 文件夹里的图片（路径与 files_read
/// 同一套 SandboxPath 规范化），图片字节上限与聊天
/// 图片链的 20 MB 对齐；翻译/端上模型是短文本活，
/// 输入上限在解析层就拒、不把超长文本递进框架；
/// 本人确认的理由要直接显示在系统验证框里，短句为宜
public enum PresenceLimits {
    /// 识别输入图片上限（20 MB，与聊天图片链同）
    public static let maxImageBytes = 20 * 1024 * 1024
    /// 识别结果文字上限：超了截断并在回执标 truncated
    public static let maxRecognizedTextChars = 20_000
    /// 识别结果行数上限
    public static let maxRecognizedLines = 300
    /// 翻译单次文本上限（字）
    public static let maxTranslateChars = 4_000
    /// 端上模型单次提示上限（字）：端上上下文约
    /// 4096 token（含指令与回答），字数先行收敛、
    /// 框架仍有 exceededContextWindowSize 兜底
    public static let maxPromptChars = 3_000
    /// 端上模型指令（系统提示）上限（字）
    public static let maxInstructionsChars = 1_000
    /// 本人确认理由上限（字）
    public static let maxReasonChars = 120
}

/// camera_capture 参数：拍照没有别的入参——拍什么、
/// 什么时候按快门都由用户当面决定，智能体只负责
/// 发起。它在文件夹里落一份新图片（状态变化），
/// 照写工具带防重复键：桥重发同键时回放已存的那
/// 张、不许把取景框再弹第二次
public struct CameraCaptureArgs: Equatable, Sendable {
    public let idempotencyKey: String

    public init(idempotencyKey: String) {
        self.idempotencyKey = idempotencyKey
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> CameraCaptureArgs {
        CameraCaptureArgs(
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public var humanSummary: String { "拍照：请你当面拍一张照片" }
}

/// vision_document_scan 参数：与拍照同理——扫描几
/// 页、怎么摆都由用户当面在系统扫描界面里完成；
/// 落多页图片文件，照写工具带防重复键
public struct VisionDocumentScanArgs: Equatable, Sendable {
    public let idempotencyKey: String

    public init(idempotencyKey: String) {
        self.idempotencyKey = idempotencyKey
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> VisionDocumentScanArgs {
        VisionDocumentScanArgs(
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public var humanSummary: String { "扫描文档：请你当面扫描这份文档" }
}

/// vision_ocr 参数：只认 OneDay 文件夹内的图片路径
/// （与 files_read 同一套规范化，越界在解析层拒）
public struct VisionOCRArgs: Equatable, Sendable {
    public let path: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> VisionOCRArgs {
        VisionOCRArgs(
            path: try SandboxPath.normalizeFilePath(
                requiredString(args, "path", "图片路径")
            )
        )
    }
}

/// vision_scan_code 参数：同 vision_ocr 的路径口径
public struct VisionScanCodeArgs: Equatable, Sendable {
    public let path: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> VisionScanCodeArgs {
        VisionScanCodeArgs(
            path: try SandboxPath.normalizeFilePath(
                requiredString(args, "path", "图片路径")
            )
        )
    }
}

/// 语言代码校验（translate_text 的 source/target）：
/// 只放行 BCP 47 骨架字符（字母/数字/连字符），形
/// 不对在解析层拒，不把乱码递给系统翻译框架
private func validatedLanguageCode(
    _ raw: String, field: String
) throws -> String {
    let code = raw.trimmingCharacters(in: .whitespaces)
    guard code.count >= 2, code.count <= 35,
          code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
          code.first?.isLetter == true
    else {
        throw DeviceToolError.invalidArguments(
            "\(field)不是合法的语言代码（如 zh-Hans、en、ja）"
        )
    }
    return code
}

/// translate_text 参数：原文与源语言必填；目标语言
/// 可缺省（执行层按源语言定缺省目标：源是中文→英
/// 文，其余→简体中文，回执里如实回明实际目标语言，
/// 不让调用方猜）。无头会话必须先知道源语言，没法
/// 靠自动识别兜底（iOS 26 的 installedSource 构造式
/// 要求源语言明确），所以源语言不设缺省
public struct TranslateTextArgs: Equatable, Sendable {
    public let text: String
    public let source: String
    public let target: String?

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> TranslateTextArgs {
        let text = try requiredString(args, "text", "要翻译的文字")
        guard text.count <= PresenceLimits.maxTranslateChars
        else {
            throw DeviceToolError.invalidArguments(
                "要翻译的文字超过 \(PresenceLimits.maxTranslateChars) 字上限"
            )
        }
        let source = try validatedLanguageCode(
            requiredString(args, "source", "源语言"),
            field: "源语言"
        )
        var target: String?
        if let rawTarget = optionalString(args, "target") {
            target = try validatedLanguageCode(rawTarget, field: "目标语言")
        }
        return TranslateTextArgs(
            text: text, source: source, target: target
        )
    }

    public var humanSummary: String {
        "翻译一段文字（\(source)→\(target ?? "缺省目标")）"
    }
}

/// ondevice_model_run 参数：单次问答——每次调用都
/// 是新会话、不带上文（契约写明，免得调用方以为它
/// 记得前文）；instructions 是可选的系统指令
public struct OnDeviceModelArgs: Equatable, Sendable {
    public let prompt: String
    public let instructions: String?

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> OnDeviceModelArgs {
        let prompt = try requiredString(args, "prompt", "问题")
        guard prompt.count <= PresenceLimits.maxPromptChars
        else {
            throw DeviceToolError.invalidArguments(
                "问题超过 \(PresenceLimits.maxPromptChars) 字上限"
            )
        }
        let instructions = optionalString(args, "instructions")
        if let instructions,
           instructions.count > PresenceLimits.maxInstructionsChars {
            throw DeviceToolError.invalidArguments(
                "指令超过 \(PresenceLimits.maxInstructionsChars) 字上限"
            )
        }
        return OnDeviceModelArgs(
            prompt: prompt, instructions: instructions
        )
    }
}

/// auth_biometric 参数：reason 是给用户看的确认理
/// 由、会原样显示在系统验证框里（「为什么要验你」
/// 必须由发起方说清，不许空着让用户对着空白框验
/// 身份）。不带 idempotencyKey（理由见
/// DeviceToolSpec 的批三注记）
public struct BiometricAuthArgs: Equatable, Sendable {
    public let reason: String

    /// 详情页本地试确认也要构造（理由由页面写明）
    public init(reason: String) {
        self.reason = reason
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> BiometricAuthArgs {
        let reason = try requiredString(args, "reason", "确认理由")
        guard reason.count <= PresenceLimits.maxReasonChars
        else {
            throw DeviceToolError.invalidArguments(
                "确认理由超过 \(PresenceLimits.maxReasonChars) 字上限"
            )
        }
        return BiometricAuthArgs(reason: reason)
    }

    public var humanSummary: String { "本人确认：\(reason)" }
}

// MARK: - 批四·日常面参数（定位/媒体库/撰写/快捷指令/设备信息/文件呈现）

/// 批四的量级收敛（粒度在 App 侧执行的既有口径）：
/// 检索类一律有条数上限并在回执标 truncated；撰写
/// 类的预填文本有字数上限（撰写面是给人当场改的，
/// 不是长文投递口）；快捷指令名/输入、电话号码都
/// 在解析层收敛，形不对不下发执行层
public enum EverydayLimits {
    /// 附近地点检索的条数上限
    public static let maxPlaces = 20
    /// 媒体书目检索的条数上限
    public static let maxMediaResults = 50
    /// 歌单列表的条目上限（超出截断并标明）
    public static let maxPlaylists = 200
    /// 歌单名上限（字）
    public static let maxPlaylistNameChars = 100
    /// 电话号码上限（字符，含 + 与分隔符）
    public static let maxPhoneNumberChars = 32
    /// 短信预填正文上限（字）
    public static let maxSMSBodyChars = 2_000
    /// 邮件主题上限（字）
    public static let maxEmailSubjectChars = 200
    /// 邮件预填正文上限（字）
    public static let maxEmailBodyChars = 5_000
    /// 分享文字上限（字）
    public static let maxShareTextChars = 4_000
    /// 快捷指令名上限（字）
    public static let maxShortcutNameChars = 100
    /// 快捷指令文本输入上限（字）
    public static let maxShortcutInputChars = 2_000
}

/// 收件人数组解析（compose_sms/compose_email 共
/// 用）：必须是字符串数组、至少一个、逐个去空白；
/// 元素形不对在解析层拒（不把乱码递进系统撰写面）
private func requiredRecipients(
    _ args: [String: JSONValue], _ key: String, _ field: String
) throws -> [String] {
    guard case .array(let values)? = args[key] else {
        throw DeviceToolError.invalidArguments("缺少必填参数：\(field)")
    }
    let cleaned = values.compactMap { $0.stringValue }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard cleaned.count == values.count, !cleaned.isEmpty else {
        throw DeviceToolError.invalidArguments("\(field)至少要有一个有效的")
    }
    return cleaned
}

/// 电话号码形态校验：只许数字与 +、空格、连字符、
/// 括号，且至少含一位数字；字母与其余符号在解析
/// 层拒（tel: 地址不许被塞进别的东西）
private func validatedPhoneNumber(
    _ raw: String, field: String
) throws -> String {
    let number = raw.trimmingCharacters(in: .whitespaces)
    let allowed = CharacterSet(
        charactersIn: "0123456789+*#-() "
    )
    guard !number.isEmpty,
          number.count <= EverydayLimits.maxPhoneNumberChars,
          number.unicodeScalars.allSatisfy({ allowed.contains($0) }),
          number.contains(where: { $0.isNumber })
    else {
        throw DeviceToolError.invalidArguments(
            "\(field)不是合法的电话号码"
        )
    }
    return number
}

/// location_current 参数：没有入参——读哪儿、何时
/// 读由系统定位服务当下决定，智能体只负责问一次
public struct LocationCurrentArgs: Equatable, Sendable {
    /// 详情页本地试读也要构造（与 BiometricAuthArgs
    /// 的公开 init 同例）
    public init() {}

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> LocationCurrentArgs {
        LocationCurrentArgs()
    }

    public var humanSummary: String { "查看当前位置" }
}

/// location_search_places 参数：关键词必填；条数
/// 缺省 10、收敛到 1...20（粒度在 App 侧收敛）
public struct LocationSearchPlacesArgs: Equatable, Sendable {
    public let query: String
    public let limit: Int

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> LocationSearchPlacesArgs {
        var limit = 10
        if case .number(let raw)? = args["limit"] {
            limit = Int(raw)
        }
        return LocationSearchPlacesArgs(
            query: try requiredString(args, "query", "搜索关键词"),
            limit: min(max(limit, 1), EverydayLimits.maxPlaces)
        )
    }

    public var humanSummary: String { "搜索附近地点：\(query)" }
}

/// location_geocode 参数：正向（地址→坐标）与逆向
/// （坐标→地址）恰给其一——同给必有歧义、同缺无
/// 从换算，解析层直接拒；坐标范围逐个校验
public struct LocationGeocodeArgs: Equatable, Sendable {
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> LocationGeocodeArgs {
        let address = optionalString(args, "address")
        var latitude: Double?
        var longitude: Double?
        if case .number(let raw)? = args["latitude"] {
            latitude = raw
        }
        if case .number(let raw)? = args["longitude"] {
            longitude = raw
        }
        let hasAddress = address != nil
        let hasCoordinate = latitude != nil && longitude != nil
        if (latitude == nil) != (longitude == nil) {
            throw DeviceToolError.invalidArguments(
                "纬度与经度要成对给"
            )
        }
        guard hasAddress != hasCoordinate else {
            throw DeviceToolError.invalidArguments(
                "地址与坐标只能给一个"
            )
        }
        if let latitude, latitude < -90 || latitude > 90 {
            throw DeviceToolError.invalidArguments("纬度超出范围")
        }
        if let longitude, longitude < -180 || longitude > 180 {
            throw DeviceToolError.invalidArguments("经度超出范围")
        }
        return LocationGeocodeArgs(
            address: address, latitude: latitude, longitude: longitude
        )
    }

    public var humanSummary: String {
        if let address { return "查这个地址的坐标：\(address)" }
        return "查这个坐标是什么地方"
    }
}

/// 媒体书目类别（media_library_search 的 kind）：
/// 封闭枚举，表外值在解析层拒、不下发执行层猜
public enum MediaSearchKind: String, Equatable, Sendable {
    case song
    case album
    case artist
    case playlist
    case podcast
    case any
}

/// media_library_search 参数：关键词必填；类别缺
/// 省 any（歌/专辑/艺人/歌单/播客都查）；条数缺
/// 省 20、收敛到 1...50
public struct MediaLibrarySearchArgs: Equatable, Sendable {
    public let query: String
    public let kind: MediaSearchKind
    public let limit: Int

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> MediaLibrarySearchArgs {
        var kind: MediaSearchKind = .any
        if let raw = optionalString(args, "kind") {
            guard let parsed = MediaSearchKind(rawValue: raw) else {
                throw DeviceToolError.invalidArguments(
                    "类别只能是 song/album/artist/playlist/podcast/any"
                )
            }
            kind = parsed
        }
        var limit = 20
        if case .number(let raw)? = args["limit"] {
            limit = Int(raw)
        }
        return MediaLibrarySearchArgs(
            query: try requiredString(args, "query", "搜索关键词"),
            kind: kind,
            limit: min(
                max(limit, 1), EverydayLimits.maxMediaResults
            )
        )
    }

    public var humanSummary: String { "搜索媒体库：\(query)" }
}

/// media_playlists 参数：没有入参——全量列歌单
/// （上限在执行层收敛、超了标 truncated）
public struct MediaPlaylistsArgs: Equatable, Sendable {
    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> MediaPlaylistsArgs {
        MediaPlaylistsArgs()
    }
}

/// media_playlist_create 参数：歌单名必填且有字数
/// 收敛；建歌单在资料库里留一份新歌单（状态变
/// 化），照写工具带防重复键——同键重发回放已建的
/// 那一份，不许再建第二个同名歌单
public struct MediaPlaylistCreateArgs: Equatable, Sendable {
    public let name: String
    public let idempotencyKey: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> MediaPlaylistCreateArgs {
        let name = try requiredString(args, "name", "歌单名")
        guard name.count <= EverydayLimits.maxPlaylistNameChars
        else {
            throw DeviceToolError.invalidArguments(
                "歌单名超过 \(EverydayLimits.maxPlaylistNameChars) 字上限"
            )
        }
        return MediaPlaylistCreateArgs(
            name: name,
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public var humanSummary: String { "新建歌单：\(name)" }
}

/// 播放动作（media_playback_control 的 action）：
/// 封闭枚举，表外值在解析层拒
public enum MediaPlaybackAction: String, Equatable, Sendable {
    case play
    case pause
    case stop
    case next
    case previous
}

/// media_playback_control 参数：动作必填；query 只
/// 对 play 有意义（先按关键词在资料库里找到那首
/// 歌再播）；控制会真改变播放状态，照写工具带防
/// 重复键——桥重发同键时回放上次回执，不许把「下
/// 一首」按两次
public struct MediaPlaybackControlArgs: Equatable, Sendable {
    public let action: MediaPlaybackAction
    public let query: String?
    public let idempotencyKey: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> MediaPlaybackControlArgs {
        let raw = try requiredString(args, "action", "播放动作")
        guard let action = MediaPlaybackAction(rawValue: raw) else {
            throw DeviceToolError.invalidArguments(
                "播放动作只能是 play/pause/stop/next/previous"
            )
        }
        return MediaPlaybackControlArgs(
            action: action,
            query: optionalString(args, "query"),
            idempotencyKey: try requiredString(
                args, "idempotencyKey", "幂等键"
            )
        )
    }

    public var humanSummary: String {
        switch action {
        case .play:
            if let query { return "播放：\(query)" }
            return "继续播放"
        case .pause: return "暂停播放"
        case .stop: return "停止播放"
        case .next: return "下一首"
        case .previous: return "上一首"
        }
    }
}

/// call_start 参数：号码必填且过形态校验。拨号只
/// 把系统确认面弹出来，拨不拨由用户当场点——不带
/// 幂等键、不入写集（定性见 DeviceToolSpec 批四注记）
public struct CallStartArgs: Equatable, Sendable {
    public let number: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> CallStartArgs {
        CallStartArgs(
            number: try validatedPhoneNumber(
                requiredString(args, "number", "电话号码"),
                field: "电话号码"
            )
        )
    }

    public var humanSummary: String { "拨打电话：\(number)" }
}

/// compose_sms 参数：收件人至少一个（逐个过电话
/// 号码形态校验）、正文可选且有字数收敛。撰写面
/// 预填后由用户亲手改与发——不带幂等键、不入写集
public struct ComposeSMSArgs: Equatable, Sendable {
    public let recipients: [String]
    public let body: String?

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ComposeSMSArgs {
        let recipients = try requiredRecipients(
            args, "recipients", "收件人"
        ).map {
            try validatedPhoneNumber($0, field: "收件人号码")
        }
        let body = optionalString(args, "body")
        if let body, body.count > EverydayLimits.maxSMSBodyChars {
            throw DeviceToolError.invalidArguments(
                "短信正文超过 \(EverydayLimits.maxSMSBodyChars) 字上限"
            )
        }
        return ComposeSMSArgs(recipients: recipients, body: body)
    }

    public var humanSummary: String {
        "写短信给 \(recipients.joined(separator: "、"))"
    }
}

/// compose_email 参数：收件人至少一个（逐个粗验含
/// @、不做投递性验证）、主题/正文可选且有字数收
/// 敛。同 compose_sms 口径：不带幂等键、不入写集
public struct ComposeEmailArgs: Equatable, Sendable {
    public let recipients: [String]
    public let subject: String?
    public let body: String?

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ComposeEmailArgs {
        let recipients = try requiredRecipients(
            args, "to", "收件人"
        )
        for recipient in recipients {
            guard recipient.contains("@"),
                  recipient.count <= 254 else {
                throw DeviceToolError.invalidArguments(
                    "收件人「\(recipient)」不像邮箱地址"
                )
            }
        }
        let subject = optionalString(args, "subject")
        if let subject,
           subject.count > EverydayLimits.maxEmailSubjectChars {
            throw DeviceToolError.invalidArguments(
                "邮件主题超过 \(EverydayLimits.maxEmailSubjectChars) 字上限"
            )
        }
        let body = optionalString(args, "body")
        if let body, body.count > EverydayLimits.maxEmailBodyChars {
            throw DeviceToolError.invalidArguments(
                "邮件正文超过 \(EverydayLimits.maxEmailBodyChars) 字上限"
            )
        }
        return ComposeEmailArgs(
            recipients: recipients, subject: subject, body: body
        )
    }

    public var humanSummary: String {
        "写邮件给 \(recipients.joined(separator: "、"))"
    }
}

/// share_sheet 参数：文字与文件至少给一样（文件走
/// OneDay 文件夹的沙盒路径、与 files_read 同一套
/// 规范化）。分享面递到用户手上、发不发由他决定
/// ——不带幂等键、不入写集
public struct ShareSheetArgs: Equatable, Sendable {
    public let text: String?
    public let path: String?

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ShareSheetArgs {
        let text = optionalString(args, "text")
        if let text, text.count > EverydayLimits.maxShareTextChars {
            throw DeviceToolError.invalidArguments(
                "分享文字超过 \(EverydayLimits.maxShareTextChars) 字上限"
            )
        }
        var path: String?
        if let rawPath = optionalString(args, "path") {
            path = try SandboxPath.normalizeFilePath(rawPath)
        }
        guard text != nil || path != nil else {
            throw DeviceToolError.invalidArguments(
                "要分享的文字与文件至少给一样"
            )
        }
        return ShareSheetArgs(text: text, path: path)
    }

    public var humanSummary: String {
        if let path { return "分享文件：\(path)" }
        return "分享一段文字"
    }
}

/// shortcut_run 参数：名字必填（系统只能按名运
/// 行、不能枚举，见表面图 A22/C7）、文本输入可
/// 选且有字数收敛。成败以 x-callback 回执为准，
/// 没有回执只报「已发起」——不带幂等键、不入写集
public struct ShortcutRunArgs: Equatable, Sendable {
    public let name: String
    public let input: String?

    /// 详情页本地运行也要构造（名字由用户在页面里
    /// 亲手填，与 BiometricAuthArgs 的公开 init 同例）
    public init(name: String, input: String?) {
        self.name = name
        self.input = input
    }

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> ShortcutRunArgs {
        let name = try requiredString(args, "name", "快捷指令名")
        guard name.count <= EverydayLimits.maxShortcutNameChars
        else {
            throw DeviceToolError.invalidArguments(
                "快捷指令名超过 \(EverydayLimits.maxShortcutNameChars) 字上限"
            )
        }
        let input = optionalString(args, "input")
        if let input,
           input.count > EverydayLimits.maxShortcutInputChars {
            throw DeviceToolError.invalidArguments(
                "输入文字超过 \(EverydayLimits.maxShortcutInputChars) 字上限"
            )
        }
        return ShortcutRunArgs(name: name, input: input)
    }

    public var humanSummary: String { "运行快捷指令：\(name)" }
}

/// file_preview 参数：只认 OneDay 文件夹内的路径
/// （与 files_read 同一套规范化，越界在解析层拒）
public struct FilePreviewArgs: Equatable, Sendable {
    public let path: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> FilePreviewArgs {
        FilePreviewArgs(
            path: try SandboxPath.normalizeFilePath(
                requiredString(args, "path", "文件路径")
            )
        )
    }

    public var humanSummary: String { "预览文件：\(path)" }
}

/// file_print 参数：同 file_preview 的路径口径；
/// 打印面由系统拉起、打不打由用户在面上决定
public struct FilePrintArgs: Equatable, Sendable {
    public let path: String

    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> FilePrintArgs {
        FilePrintArgs(
            path: try SandboxPath.normalizeFilePath(
                requiredString(args, "path", "文件路径")
            )
        )
    }

    public var humanSummary: String { "打印文件：\(path)" }
}

/// device_info 参数：没有入参——全部免权限现读，
/// 读哪项由执行层固定清单决定，不开任意查询口
public struct DeviceInfoArgs: Equatable, Sendable {
    public static func parse(
        _ args: [String: JSONValue]
    ) throws -> DeviceInfoArgs {
        DeviceInfoArgs()
    }
}
