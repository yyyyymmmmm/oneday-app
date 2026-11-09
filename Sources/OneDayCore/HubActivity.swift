import Foundation

// MARK: - 结构化日志事件（LogDisplay 的结构保留层）

public enum HubLogLevel: Equatable, Sendable {
    case critical, error, warning, info, debug, unknown
}

/// 结构化日志事件（phase3-data-design §4.2）：LogDisplay
/// 只给人话三行、丢了日期/级别/模块，不能支撑跨日合并；
/// 本类型在同一遍解析里把结构留住。标题/说明继续复用
/// LogDisplay 的人话口径，不在 View 里二次拆字符串。
public struct LogEventRecord: Equatable, Sendable {
    public let timestamp: Date?
    public let level: HubLogLevel
    public let module: String?
    public let display: LogEntryDisplay
    public let isStructured: Bool
    /// 本地去重键（标准化时间戳＋完整行），不上屏、不回传
    public let fingerprint: String
    /// 原始行（仅供副题候选的形态检查，不上屏）
    public let rawLine: String

    public init(
        timestamp: Date?, level: HubLogLevel, module: String?,
        display: LogEntryDisplay, isStructured: Bool,
        fingerprint: String, rawLine: String
    ) {
        self.timestamp = timestamp
        self.level = level
        self.module = module
        self.display = display
        self.isStructured = isStructured
        self.fingerprint = fingerprint
        self.rawLine = rawLine
    }

    /// 是否可作活动行副题候选（§4.4 第三步）：须结构化；
    /// JSON 形态、超长无空格标识符串、纯 URL 行一律排除，
    /// 避免任意原始文本包一层人话就冒充活动说明。
    public var isSubtitleCandidate: Bool {
        guard isStructured, timestamp != nil else { return false }
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.contains("{") || line.contains("}") { return false }
        let tokens = line.split(separator: " ").map(String.init)
        if tokens.count == 1,
           line.hasPrefix("http://") || line.hasPrefix("https://") {
            return false
        }
        if tokens.contains(where: { $0.count > 40 }) { return false }
        return !display.headline.isEmpty
    }
}

public enum LogEventParser {
    private static let levelTokens: [(String, HubLogLevel)] = [
        ("CRITICAL", .critical), ("ERROR", .error),
        ("WARN", .warning), ("WARNING", .warning),
        ("INFO", .info), ("DEBUG", .debug),
    ]

    public static func parse(_ rawLine: String) -> LogEventRecord {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = parseTimestamp(trimmed)
        let level = parseLevel(trimmed)
        let module = parseModule(trimmed)
        let structured = timestamp != nil && (level != .unknown || module != nil)
        let stamp = timestamp.map {
            String(Int($0.timeIntervalSince1970))
        } ?? "nil"
        return LogEventRecord(
            timestamp: timestamp,
            level: level,
            module: module,
            display: LogDisplay.parse(rawLine),
            isStructured: structured,
            fingerprint: "\(stamp)|\(trimmed)",
            rawLine: rawLine
        )
    }

    /// 行首时间戳：ISO8601（含 T 的首 token）或
    /// 「yyyy-MM-dd HH:mm:ss」双 token 形态；解析不到
    /// 日期时 nil（无时间戳日志不参与关联）
    static func parseTimestamp(_ line: String) -> Date? {
        let tokens = line.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return nil }
        if first.contains("T"), first.first?.isNumber == true {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: first) { return date }
            if let date = ISO8601DateFormatter().date(from: first) { return date }
        }
        if tokens.count >= 2,
           first.first?.isNumber == true, first.contains("-") {
            let combined = "\(tokens[0]) \(tokens[1])"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = formatter.date(from: combined) { return date }
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.date(from: combined)
        }
        return nil
    }

    static func parseLevel(_ line: String) -> HubLogLevel {
        for token in line.split(separator: " ").map(String.init) {
            let bare = token.trimmingCharacters(
                in: CharacterSet(charactersIn: "[]:")
            ).uppercased()
            if let match = levelTokens.first(where: { $0.0 == bare }) {
                return match.1
            }
        }
        return .unknown
    }

    /// 模块名启发式与 LogDisplay 同口径：形如 gateway.run:
    /// 的首段 token（带点、冒号收尾）
    static func parseModule(_ line: String) -> String? {
        // 跳过行首时间戳 token 后再找模块
        var rest = line
        let tokens = line.split(separator: " ").map(String.init)
        if let first = tokens.first,
           first.contains("T"), first.first?.isNumber == true {
            rest = String(line.dropFirst(first.count))
                .trimmingCharacters(in: .whitespaces)
        } else if tokens.count >= 2,
                  tokens[0].first?.isNumber == true, tokens[0].contains("-") {
            rest = tokens.dropFirst(2).joined(separator: " ")
        }
        if let first = rest.split(separator: " ", maxSplits: 1).first,
           first.hasSuffix(":"), first.contains("."),
           !first.contains("：") {
            return String(first.dropLast())
        }
        return nil
    }
}

// MARK: - 活动流屏上模型与组装（纯函数）

public struct HubActivityItem: Identifiable, Equatable, Sendable {
    public let sessionID: String
    public let jobID: String?
    public let title: String
    /// 日志副题：只来自 LogEntryDisplay 人话层；翻不出
    /// 人话时为 nil（留空，不贴原始日志行）
    public let subtitle: String?
    public let occurredAt: Date
    public let startedAt: Date?
    public let isActive: Bool
    public let sourceLabel: String

    public var id: String { "session:\(sessionID)" }

    public init(
        sessionID: String, jobID: String?, title: String,
        subtitle: String?, occurredAt: Date, startedAt: Date?,
        isActive: Bool, sourceLabel: String
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.title = title
        self.subtitle = subtitle
        self.occurredAt = occurredAt
        self.startedAt = startedAt
        self.isActive = isActive
        self.sourceLabel = sourceLabel
    }
}

public struct HubActivityDayGroup: Equatable, Sendable, Identifiable {
    public let label: String
    public let dayStart: Date
    public let items: [HubActivityItem]

    public var id: Date { dayStart }

    public init(label: String, dayStart: Date, items: [HubActivityItem]) {
        self.label = label
        self.dayStart = dayStart
        self.items = items
    }
}

/// 活动流降级拼装（phase3-data-design §4.4）：会话是主
/// 实体，cron run 按 session id 合并，日志只作可关联的
/// 副题证据——日志没有 session id，关联是时间窗启发式，
/// 必须保守：短窗、短会话优先、结构化门槛，宁缺毋滥。
/// 组装结果是「最近事件提示」，不是审计级归属。
public enum HubActivityAssembler {
    /// 副题候选与行数上限（§4.4 第五步：最多保留最新 50 条）
    public static let maxItems = 50

    public static func assemble(
        sessions: [ServerSession],
        runsByJobID: [String: [ServerSession]],
        jobTitles: [String: String],
        logs: [LogEventRecord],
        fetchedAt: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> [HubActivityDayGroup] {
        // 第一步：会话主表（列表版本优先，字段最全）
        var main: [String: ServerSession] = [:]
        var jobOf: [String: String] = [:]
        for session in sessions where main[session.id] == nil {
            main[session.id] = session
        }
        // cron run 合并：job id 字典序小者先认领（同一 run
        // 被两个 job 声称时取小者、丢弃后者关系）
        for jobID in runsByJobID.keys.sorted() {
            for run in runsByJobID[jobID] ?? [] {
                if main[run.id] == nil {
                    main[run.id] = run
                }
                if jobOf[run.id] == nil {
                    jobOf[run.id] = jobID
                }
            }
        }

        // 第二步：定活动时刻（起止都缺失的会话不入流，
        // 不拿抓取时刻编造活动时间）
        struct Row {
            let session: ServerSession
            let jobID: String?
            let occurredAt: Date
        }
        var rows: [Row] = []
        for (id, session) in main {
            guard let started = session.startedDate else { continue }
            let occurred = session.isActive
                ? started
                : (session.endedDate ?? started)
            rows.append(Row(session: session, jobID: jobOf[id], occurredAt: occurred))
        }

        // 第三步：日志去重（fingerprint 唯一；同分钟同标题
        // 只留最晚一条作候选）
        var byFingerprint: [String: LogEventRecord] = [:]
        for log in logs where log.isSubtitleCandidate {
            if byFingerprint[log.fingerprint] == nil {
                byFingerprint[log.fingerprint] = log
            }
        }
        var byMinuteTitle: [String: LogEventRecord] = [:]
        for log in byFingerprint.values {
            guard let stamp = log.timestamp else { continue }
            let minute = Int(stamp.timeIntervalSince1970) / 60
            let key = "\(minute)|\(log.display.headline)"
            if let existing = byMinuteTitle[key],
               let existingStamp = existing.timestamp,
               existingStamp >= stamp {
                continue
            }
            byMinuteTitle[key] = log
        }
        let candidates = byMinuteTitle.values
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        // 第四步：日志关联（一条日志最多归一个会话）
        struct Window {
            let sessionID: String
            let exactStart: Date
            let exactEnd: Date
            let relaxedStart: Date
            let relaxedEnd: Date
            let startedAt: Date
        }
        var windows: [Window] = []
        for row in rows {
            guard let started = row.session.startedDate else { continue }
            let end = row.session.endedDate ?? fetchedAt
            windows.append(Window(
                sessionID: row.session.id,
                exactStart: started,
                exactEnd: end,
                relaxedStart: started.addingTimeInterval(-60),
                relaxedEnd: end.addingTimeInterval(60),
                startedAt: started
            ))
        }
        var assigned: [String: [LogEventRecord]] = [:]
        for log in candidates {
            guard let stamp = log.timestamp else { continue }
            let eligible = windows.filter {
                stamp >= $0.relaxedStart && stamp <= $0.relaxedEnd
            }
            guard !eligible.isEmpty else { continue }
            let best = eligible.sorted { a, b in
                let aExact = stamp >= a.exactStart && stamp <= a.exactEnd
                let bExact = stamp >= b.exactStart && stamp <= b.exactEnd
                if aExact != bExact { return aExact }
                let aSpan = a.exactEnd.timeIntervalSince(a.exactStart)
                let bSpan = b.exactEnd.timeIntervalSince(b.exactStart)
                if aSpan != bSpan { return aSpan < bSpan }
                if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
                return a.sessionID < b.sessionID
            }.first
            if let best {
                assigned[best.sessionID, default: []].append(log)
            }
        }

        // 副题选择：优先不晚于 occurredAt 的最晚一条；其
        // 次取窗内（结束后 60 秒内）最早一条；活跃会话取
        // 窗内最晚一条
        func subtitle(for row: Row) -> String? {
            let logs = assigned[row.session.id] ?? []
            guard !logs.isEmpty else { return nil }
            let stamped = logs.compactMap { log -> (Date, LogEventRecord)? in
                guard let stamp = log.timestamp else { return nil }
                return (stamp, log)
            }
            guard !stamped.isEmpty else { return nil }
            let chosen: LogEventRecord
            if row.session.isActive {
                chosen = stamped.max { $0.0 < $1.0 }!.1
            } else if let before = stamped
                .filter({ $0.0 <= row.occurredAt })
                .max(by: { $0.0 < $1.0 }) {
                chosen = before.1
            } else if let after = stamped.min(by: { $0.0 < $1.0 }) {
                chosen = after.1
            } else {
                return nil
            }
            let headline = chosen.display.headline
            if !headline.isEmpty { return headline }
            if let detail = chosen.display.detail, !detail.isEmpty {
                return detail
            }
            return nil
        }

        // 标题选择（§4.4 第一步第 5 条）：会话人话名 →
        // cron job 标题（会话无内容名且来源为定时任务
        // 时）→ 人话回落（未命名会话）
        func title(for row: Row) -> String {
            if row.session.hasHumanName {
                return row.session.humanTitle
            }
            if let jobID = row.jobID, let jobTitle = jobTitles[jobID],
               !jobTitle.isEmpty {
                return jobTitle
            }
            return row.session.humanTitle
        }

        var items = rows.map { row in
            HubActivityItem(
                sessionID: row.session.id,
                jobID: row.jobID,
                title: title(for: row),
                subtitle: subtitle(for: row),
                occurredAt: row.occurredAt,
                startedAt: row.session.startedDate,
                isActive: row.session.isActive,
                sourceLabel: row.session.sourceLabel
            )
        }
        // 第五步：排序（occurredAt 倒序；同刻活跃在前、
        // 再按 session id 字典序）＋截断 50 条
        items.sort { a, b in
            if a.occurredAt != b.occurredAt { return a.occurredAt > b.occurredAt }
            if a.isActive != b.isActive { return a.isActive }
            return a.sessionID < b.sessionID
        }
        items = Array(items.prefix(maxItems))

        // 分组：今天/昨天/M月d日（自然日差口径与
        // SessionDisplay 同源，用 startOfDay 对齐）
        let monthDay = DateFormatter()
        monthDay.locale = Locale(identifier: "zh_CN")
        monthDay.dateFormat = "M月d日"
        var groups: [HubActivityDayGroup] = []
        for item in items {
            let dayStart = calendar.startOfDay(for: item.occurredAt)
            let dayDiff = calendar.dateComponents(
                [.day],
                from: dayStart,
                to: calendar.startOfDay(for: now)
            ).day ?? Int.max
            let label: String
            switch dayDiff {
            case 0: label = "今天"
            case 1: label = "昨天"
            default: label = monthDay.string(from: item.occurredAt)
            }
            if var last = groups.last, last.dayStart == dayStart {
                groups[groups.count - 1] = HubActivityDayGroup(
                    label: last.label, dayStart: last.dayStart,
                    items: last.items + [item]
                )
            } else {
                groups.append(HubActivityDayGroup(
                    label: label, dayStart: dayStart, items: [item]
                ))
            }
        }
        return groups
    }
}
