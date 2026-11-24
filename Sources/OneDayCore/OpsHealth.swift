import Foundation

// MARK: - Hermes ops 体检端点 DTO（H1-a 体检面，台账 158）
//
// 契约据 2026-11-19 H1-0 探活实测冻结（pkg-hermes-ops-
// probe-20261119）：doctor / security-audit 不是同步出结
// 果的 POST，而是「POST 触发后台动作（立即回执 {ok,pid,
// name}）→ 轮询 GET /api/actions/{name}/status 读文本日
// 志」两段式。检查结果没有服务端结构化版本——DoctorRun
// / SecurityAuditRun 是客户端从日志文本解析出的派生结构，
// 解析器是纯函数、按探活样本冻结（改解析先对样本）。

/// POST /api/ops/doctor、/api/ops/security-audit 的触发回执
public struct OpsSpawnResponse: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let pid: Int?
    public let name: String
    /// 仅 backup 回执带（产物绝对路径）；体检两端点恒 nil
    public let archive: String?

    public init(ok: Bool, pid: Int?, name: String, archive: String?) {
        self.ok = ok
        self.pid = pid
        self.name = name
        self.archive = archive
    }
}

/// GET /api/actions/{name}/status：动作状态＋日志尾。
/// lines 是追加式多方共享日志的文件尾——会混入别轮次
/// 输出，消费前必须经 OpsActionLog.slice 切出本轮（探
/// 活报告附带观察：探活窗口内每份日志都混有他人轮次）。
public struct OpsActionStatus: Decodable, Sendable, Equatable {
    public let name: String
    public let running: Bool
    public let exitCode: Int?
    public let pid: Int?
    public let lines: [String]

    enum CodingKeys: String, CodingKey {
        case name, running, pid, lines
        case exitCode = "exit_code"
    }

    public init(
        name: String, running: Bool, exitCode: Int?,
        pid: Int?, lines: [String]
    ) {
        self.name = name
        self.running = running
        self.exitCode = exitCode
        self.pid = pid
        self.lines = lines
    }
}

/// 动作日志切片：日志按轮追加、状态端点只回文件尾，
/// 本轮输出＝最后一个 `=== <name> started ===` 标记之后
/// 的全部行。找不到标记返回 nil——本轮记录还没落盘或
/// 已被挤出尾窗，调用方不许拿整段尾巴冒充本轮（会把
/// 别轮的检查计数混进结论）。
public enum OpsActionLog {
    /// 全部 started 标记的行下标（升序）
    static func markerIndices(
        lines: [String], actionName: String
    ) -> [Int] {
        lines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isMarker = trimmed.contains("===")
                && trimmed.contains(actionName)
                && trimmed.contains("started")
            return isMarker ? index : nil
        }
    }

    /// 尾窗内 started 标记总数（引擎防串轮对账用：
    /// 触发前先数一遍，本轮标记必在基线之后）
    public static func markerCount(
        lines: [String], actionName: String
    ) -> Int {
        markerIndices(lines: lines, actionName: actionName).count
    }

    /// 切出最后一个 started 标记之后的本轮输出；
    /// 无标记返回 nil
    public static func slice(
        lines: [String], actionName: String
    ) -> [String]? {
        guard let marker = markerIndices(
            lines: lines, actionName: actionName
        ).last else { return nil }
        return Array(lines[(marker + 1)...])
    }

    /// 切出第 `ordinal`（0 起）个 started 标记之后的
    /// 输出——引擎等本轮专用：触发前已有 N 个标记时传
    /// N，只认第 N 个（本轮新落的那个）之后的内容，
    /// 旧轮的「已完成」状态不会被误收。标记不足返回 nil
    public static func sliceAfterMarker(
        lines: [String], actionName: String, ordinal: Int
    ) -> [String]? {
        let indices = markerIndices(
            lines: lines, actionName: actionName
        )
        guard indices.indices.contains(ordinal) else { return nil }
        return Array(lines[(indices[ordinal] + 1)...])
    }

    /// 第 `index`（0 起）个 started 标记的整行文本
    /// （去首尾空白）；越界返回 nil。标记行自带秒级
    /// 时间戳，整行文本即这一轮的身份
    public static func markerLine(
        lines: [String], actionName: String, at index: Int
    ) -> String? {
        let indices = markerIndices(
            lines: lines, actionName: actionName
        )
        guard indices.indices.contains(index) else { return nil }
        return lines[indices[index]]
            .trimmingCharacters(in: .whitespaces)
    }

    /// 最后一个 started 标记的整行文本；无标记 nil
    public static func lastMarkerLine(
        lines: [String], actionName: String
    ) -> String? {
        guard let marker = markerIndices(
            lines: lines, actionName: actionName
        ).last else { return nil }
        return lines[marker].trimmingCharacters(in: .whitespaces)
    }

    /// 按标记身份认本轮（引擎现行口径，替代序号认
    /// 轮）：`baselineMarkerLine` 是触发前最后一个标
    /// 记的整行文本；当前窗口最后一个标记与它不同
    /// （基线为 nil 时只要有标记）才算本轮已落盘，
    /// 切出该标记之后的内容；最后一个标记仍是基线
    /// 本人（或窗口无标记）返回 nil。
    /// 为什么弃序号：状态端点只回文件尾的滑动窗口，
    /// 本轮输出会把旧标记挤出窗口，序号在窗口内永远
    /// 凑不齐——2026-11-20 真机定因：doctor 日志被本
    /// 轮从 362 行推到 518 行、首标记滑出 500 行窗，
    /// 结果已落盘 App 却判超时（诊断报告 pkg-h1-
    /// device-diagnosis-20261120 A 节）。
    public static func sliceForNewRound(
        lines: [String], actionName: String,
        baselineMarkerLine: String?
    ) -> [String]? {
        guard let marker = markerIndices(
            lines: lines, actionName: actionName
        ).last else { return nil }
        let lastLine = lines[marker]
            .trimmingCharacters(in: .whitespaces)
        if let baselineMarkerLine, lastLine == baselineMarkerLine {
            return nil
        }
        return Array(lines[(marker + 1)...])
    }
}

// MARK: - 结论四态

/// 体检结论四态（纯客户端映射）：正常／注意／异常／没跑完。
/// 「没跑完」与「查出异常」必须分开——检查器自身崩溃
/// （探活实测：doctor 在现役实例上固定崩尾 exit 1）不是
/// 「服务器查出异常」，混报会天天误报。
public enum HealthVerdict: String, Codable, Sendable, Equatable {
    case ok
    case attention
    case problem
    case incomplete

    /// 一词结论（状态行与次入口用）
    public var word: String {
        switch self {
        case .ok: return "正常"
        case .attention: return "注意"
        case .problem: return "异常"
        case .incomplete: return "没跑完"
        }
    }

    /// 合成优先级：异常 > 没跑完 > 注意 > 正常
    var severityRank: Int {
        switch self {
        case .ok: return 0
        case .attention: return 1
        case .incomplete: return 2
        case .problem: return 3
        }
    }
}

// MARK: - doctor 日志解析

public struct DoctorItem: Sendable, Equatable {
    public enum Level: String, Sendable, Equatable {
        case pass, warn, fail
    }
    public var level: Level
    public var text: String
    /// 缩进 `→` 明细行原文（折叠里保留原文，结论行用人话）
    public var details: [String]

    public init(level: Level, text: String, details: [String] = []) {
        self.level = level
        self.text = text
        self.details = details
    }
}

public struct DoctorSection: Sendable, Equatable {
    /// 服务端原名（英文 CLI 分组名）
    public var title: String
    public var items: [DoctorItem]

    public init(title: String, items: [DoctorItem] = []) {
        self.title = title
        self.items = items
    }

    public var passCount: Int { items.count { $0.level == .pass } }
    public var warnCount: Int { items.count { $0.level == .warn } }
    public var failCount: Int { items.count { $0.level == .fail } }
    /// 分组的人话名（已知分组查表，未知原样）
    public var displayTitle: String {
        DoctorLogParser.displayTitle(for: title)
    }
}

/// 一轮 doctor 的解析结果。verdict 口径（探活 §四冻结）：
/// 检出 Traceback 或 exit≠0 → 没跑完（该 CLI 迄今观测
/// 到的 exit≠0 唯一成因是检查器自身崩溃；查出的问题以
/// ✗ 项呈现、整轮仍 exit 0）；否则按 ✗/⚠ 计数定档。
public struct DoctorRun: Sendable, Equatable {
    public var sections: [DoctorSection]
    public var crashed: Bool
    public var exitCode: Int?
    /// 崩溃异常行原文（如 PermissionError: …），只进明细折叠
    public var crashErrorLine: String?

    public init(
        sections: [DoctorSection], crashed: Bool,
        exitCode: Int?, crashErrorLine: String? = nil
    ) {
        self.sections = sections
        self.crashed = crashed
        self.exitCode = exitCode
        self.crashErrorLine = crashErrorLine
    }

    public var passCount: Int { sections.reduce(0) { $0 + $1.passCount } }
    public var warnCount: Int { sections.reduce(0) { $0 + $1.warnCount } }
    public var failCount: Int { sections.reduce(0) { $0 + $1.failCount } }

    public var verdict: HealthVerdict {
        if crashed { return .incomplete }
        if failCount > 0 { return .problem }
        if warnCount > 0 { return .attention }
        return .ok
    }

    public var headline: String {
        switch verdict {
        case .ok:
            return passCount > 0
                ? "自检通过，\(passCount) 项都正常"
                : "自检通过，没有发现问题"
        case .attention:
            return "自检有 \(warnCount) 项要注意"
        case .problem:
            return "自检发现 \(failCount) 项异常"
        case .incomplete:
            return "自检没跑完"
        }
    }

    /// 没跑完的人话原因：说清停在哪一组、为什么停，
    /// 且明确已完成部分仍作数、这一项不作数（探活 §四
    /// 指定的文案形态）。非没跑完态为 nil。
    public var incompleteReason: String? {
        guard verdict == .incomplete else { return nil }
        guard let last = sections.last, !last.title.isEmpty else {
            return "检查器刚启动就停住了，这次没有可用结论。"
        }
        let group = last.displayTitle
        if let error = crashErrorLine,
           error.hasPrefix("PermissionError") {
            return "大部分检查已完成，在「\(group)」一项上，检查器读不到"
                + "服务器上的一个文件（权限不对）就停住了——这一项的结果不作数。"
        }
        if crashErrorLine != nil {
            return "大部分检查已完成，在「\(group)」一项上检查器自身出错"
                + "就停住了——这一项的结果不作数。"
        }
        return "在「\(group)」一项附近停住了，没有留下完整结论——"
            + "已完成部分的结果仍作数。"
    }

    public var groupSummary: HealthGroupSummary {
        HealthGroupSummary(
            verdict: verdict, headline: headline,
            passCount: passCount, warnCount: warnCount,
            failCount: failCount
        )
    }
}

/// doctor 富文本日志解析器：`◆ ` 切分组、行首 ✓/⚠/✗ 定
/// 档、缩进 `→` 行归上一项明细、Traceback 段整段吞掉只
/// 留异常行。规则据探活样本（32✓/4⚠＋崩尾形态）冻结。
public enum DoctorLogParser {
    /// 已知分组的人话名（探活实测 10 组全集）
    static let sectionTitleMap: [String: String] = [
        "Security Advisories": "安全公告",
        "MCP Server Security": "MCP 安全",
        "Python Environment": "Python 环境",
        "SSL / CA Certificates": "证书",
        "Required Packages": "依赖包",
        "Configuration Files": "配置文件",
        "xAI Model Retirement": "模型退役提醒",
        "Session Reset": "会话重置",
        "Auth Providers": "登录提供方",
        "Directory Structure": "目录结构",
    ]

    public static func displayTitle(for title: String) -> String {
        if title.isEmpty { return "未分组" }
        return sectionTitleMap[title] ?? title
    }

    public static func parse(
        lines: [String], exitCode: Int?
    ) -> DoctorRun {
        var sections: [DoctorSection] = []
        var sawTraceback = false
        var inTraceback = false
        var crashErrorLine: String?

        func appendItem(_ item: DoctorItem) {
            if sections.isEmpty {
                sections.append(DoctorSection(title: ""))
            }
            sections[sections.count - 1].items.append(item)
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("Traceback (most recent call last)") {
                sawTraceback = true
                inTraceback = true
                continue
            }
            if inTraceback {
                // 异常行形态：PermissionError: [Errno 13] …
                if line.range(
                    of: #"^[A-Za-z_][A-Za-z0-9_.]*(Error|Exception):"#,
                    options: .regularExpression
                ) != nil {
                    crashErrorLine = line
                    inTraceback = false
                }
                continue
            }
            if line.hasPrefix("◆") {
                let title = String(line.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                sections.append(DoctorSection(title: title))
                continue
            }
            if line.hasPrefix("→") {
                let detail = String(line.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                if !sections.isEmpty,
                   !sections[sections.count - 1].items.isEmpty {
                    sections[sections.count - 1]
                        .items[sections[sections.count - 1].items.count - 1]
                        .details.append(detail)
                }
                continue
            }
            let level: DoctorItem.Level?
            if line.hasPrefix("✓") {
                level = .pass
            } else if line.hasPrefix("⚠") {
                level = .warn
            } else if line.hasPrefix("✗") || line.hasPrefix("✘") {
                level = .fail
            } else {
                level = nil
            }
            if let level {
                let text = String(line.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                appendItem(DoctorItem(level: level, text: text))
            }
            // 其余行（横幅/空行/说明）不入账
        }

        // exit≠0 与 Traceback 同判没跑完（判读口径见
        // DoctorRun 头注）；exit 为 nil（未知）时只认
        // Traceback 实证
        let crashed = sawTraceback || (exitCode != nil && exitCode != 0)
        return DoctorRun(
            sections: sections, crashed: crashed,
            exitCode: exitCode, crashErrorLine: crashErrorLine
        )
    }
}

// MARK: - security-audit 日志解析

public struct AuditFinding: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        case critical, high, moderate, low

        public var word: String {
            switch self {
            case .critical: return "严重"
            case .high: return "高危"
            case .moderate: return "中危"
            case .low: return "低危"
            }
        }
    }
    public var severity: Severity
    public var packageName: String
    public var installedVersion: String?
    public var fixedIn: String?
    public var ghsa: String?
    /// 条目原文（明细折叠保留原文）
    public var rawLine: String

    public init(
        severity: Severity, packageName: String,
        installedVersion: String? = nil, fixedIn: String? = nil,
        ghsa: String? = nil, rawLine: String
    ) {
        self.severity = severity
        self.packageName = packageName
        self.installedVersion = installedVersion
        self.fixedIn = fixedIn
        self.ghsa = ghsa
        self.rawLine = rawLine
    }
}

/// 一轮 security-audit 的解析结果：首行汇总给总数与组件
/// 数，条目按级别 token＋包名==版本抽取（位置无关，格
/// 式微漂移不整段失效）。总数以汇总行为准，条目解析不
/// 全时结论计数仍按总数走、明细只呈解析到的条目。
public struct SecurityAuditRun: Sendable, Equatable {
    public var totalFindings: Int
    public var componentCount: Int?
    public var findings: [AuditFinding]
    public var exitCode: Int?

    public init(
        totalFindings: Int, componentCount: Int?,
        findings: [AuditFinding], exitCode: Int?
    ) {
        self.totalFindings = totalFindings
        self.componentCount = componentCount
        self.findings = findings
        self.exitCode = exitCode
    }

    /// exit≠0＝审计自身没跑完（实测正常轮 exit 0）
    public var incomplete: Bool {
        exitCode != nil && exitCode != 0
    }

    public func count(of severity: AuditFinding.Severity) -> Int {
        findings.count { $0.severity == severity }
    }
    public var highOrAboveCount: Int {
        count(of: .critical) + count(of: .high)
    }

    public var verdict: HealthVerdict {
        if incomplete { return .incomplete }
        if highOrAboveCount > 0 { return .problem }
        if totalFindings > 0 { return .attention }
        return .ok
    }

    public var headline: String {
        switch verdict {
        case .incomplete:
            return "安全审计没跑完"
        case .ok:
            if let componentCount {
                return "安全审计通过：检查了 \(componentCount) 个组件，没有已知漏洞"
            }
            return "安全审计通过，没有已知漏洞"
        case .attention, .problem:
            var parts: [String] = []
            for severity in [AuditFinding.Severity.critical, .high, .moderate, .low] {
                let n = count(of: severity)
                if n > 0 { parts.append("\(severity.word) \(n)") }
            }
            var text = "发现 \(totalFindings) 个已知漏洞"
            if !parts.isEmpty {
                text += "（" + parts.joined(separator: "、") + "）"
            }
            if findings.count == totalFindings, totalFindings > 0,
               findings.allSatisfy({ $0.fixedIn != nil }) {
                text += "，都有修复版本"
            }
            return text
        }
    }

    public var groupSummary: HealthGroupSummary {
        HealthGroupSummary(
            verdict: verdict, headline: headline,
            findingCount: totalFindings,
            highCount: highOrAboveCount,
            moderateCount: count(of: .moderate),
            lowCount: count(of: .low)
        )
    }
}

/// security-audit 日志解析器（据探活样本冻结：首行
/// `Found N known vulnerability finding(s) across M
/// component(s)`＋逐条级别/包/GHSA/fixed in）。
public enum SecurityAuditLogParser {
    public static func parse(
        lines: [String], exitCode: Int?
    ) -> SecurityAuditRun {
        var total: Int?
        var components: Int?
        var findings: [AuditFinding] = []

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let match = firstMatch(
                #"Found\s+(\d+)\s+known vulnerability"#, in: line
            ) {
                total = Int(match)
            }
            if let match = firstMatch(
                #"across\s+(\d+)\s+component"#, in: line
            ) {
                components = Int(match)
            }
            if line.lowercased().contains("no known vulnerabilities") {
                if total == nil { total = 0 }
            }
            if let finding = parseFinding(line) {
                findings.append(finding)
            }
        }

        return SecurityAuditRun(
            totalFindings: total ?? findings.count,
            componentCount: components,
            findings: findings,
            exitCode: exitCode
        )
    }

    /// 条目行：含级别词＋`包名==版本` 才认（汇总行与说明
    /// 行天然不带 ==，不会误入）
    private static func parseFinding(_ line: String) -> AuditFinding? {
        let severity: AuditFinding.Severity?
        if firstMatch(#"\bCRITICAL\b"#, in: line) != nil {
            severity = .critical
        } else if firstMatch(#"\bHIGH\b"#, in: line) != nil {
            severity = .high
        } else if firstMatch(#"\bMODERATE\b"#, in: line) != nil {
            severity = .moderate
        } else if firstMatch(#"\bLOW\b"#, in: line) != nil {
            severity = .low
        } else {
            severity = nil
        }
        guard let severity else { return nil }
        guard let packageMatch = firstMatchWithGroups(
            #"([A-Za-z0-9_.\-]+)==([A-Za-z0-9_.\-+!]+)"#, in: line
        ) else { return nil }
        return AuditFinding(
            severity: severity,
            packageName: packageMatch[0],
            installedVersion: packageMatch[1],
            fixedIn: firstMatch(
                #"fixed in:?\s+([0-9][0-9A-Za-z.\-]*)"#, in: line
            ),
            ghsa: firstMatch(
                #"GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}"#, in: line
            ),
            rawLine: line
        )
    }

    private static func firstMatch(
        _ pattern: String, in text: String
    ) -> String? {
        firstMatchWithGroups(pattern, in: text)?.first
    }

    /// 返回捕获组数组（不含整段匹配）；无捕获组时返回
    /// [整段匹配]
    private static func firstMatchWithGroups(
        _ pattern: String, in text: String
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else { return nil }
        if match.numberOfRanges > 1 {
            return (1..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard let swiftRange = Range(range, in: text) else { return "" }
                return String(text[swiftRange])
            }
        }
        let range = match.range
        guard let swiftRange = Range(range, in: text) else { return nil }
        return [String(text[swiftRange])]
    }
}

// MARK: - 留痕摘要（只存结论，不存原始日志）

/// 单组留痕：结论＋计数。原始日志可能含敏感路径/配置
/// 值，永不落盘（施工图 2.3 留痕口径）。
public struct HealthGroupSummary: Codable, Sendable, Equatable {
    public var verdict: HealthVerdict
    public var headline: String
    public var passCount: Int?
    public var warnCount: Int?
    public var failCount: Int?
    public var findingCount: Int?
    /// 高危＋严重合计（异常计数合成用）
    public var highCount: Int?
    public var moderateCount: Int?
    public var lowCount: Int?

    public init(
        verdict: HealthVerdict, headline: String,
        passCount: Int? = nil, warnCount: Int? = nil,
        failCount: Int? = nil, findingCount: Int? = nil,
        highCount: Int? = nil, moderateCount: Int? = nil,
        lowCount: Int? = nil
    ) {
        self.verdict = verdict
        self.headline = headline
        self.passCount = passCount
        self.warnCount = warnCount
        self.failCount = failCount
        self.findingCount = findingCount
        self.highCount = highCount
        self.moderateCount = moderateCount
        self.lowCount = lowCount
    }
}

/// 一次体检的留痕（按服务器存一份最新）：顶部结论卡与
/// 状态页次入口共读同一份。总判定与一句话结论是派生
/// 值、不落盘第二份真源。
public struct HealthCheckSummary: Codable, Sendable, Equatable {
    public var date: Date
    public var serverBase: String
    public var doctor: HealthGroupSummary?
    public var audit: HealthGroupSummary?
    /// 身份对账组（H1-d）：旧留痕没有这个键，解码回
    /// nil——合成时按「这组没跑过」处理，不造假结论
    public var identity: HealthGroupSummary?

    public init(
        date: Date, serverBase: String,
        doctor: HealthGroupSummary? = nil,
        audit: HealthGroupSummary? = nil,
        identity: HealthGroupSummary? = nil
    ) {
        self.date = date
        self.serverBase = serverBase
        self.doctor = doctor
        self.audit = audit
        self.identity = identity
    }

    /// 总判定：已跑组里取最重一档（异常 > 没跑完 >
    /// 注意 > 正常）；一组都没跑过按没跑完
    public var overall: HealthVerdict {
        let verdicts = [doctor?.verdict, audit?.verdict, identity?.verdict]
            .compactMap { $0 }
        guard let worst = verdicts.max(by: {
            $0.severityRank < $1.severityRank
        }) else { return .incomplete }
        return worst
    }

    /// 顶部一句话结论（施工图 2.3 合成口径＋没跑完态）
    public var headline: String {
        switch overall {
        case .ok:
            return "体检通过，没有发现问题"
        case .attention:
            let n = (doctor?.warnCount ?? 0)
                + (audit?.findingCount ?? 0)
                + (identity?.warnCount ?? 0)
            return n > 0
                ? "能用，但有 \(n) 项要注意"
                : "能用，但有几项要注意"
        case .problem:
            let n = (doctor?.failCount ?? 0)
                + (audit?.highCount ?? 0)
                + (identity?.failCount ?? 0)
            if n > 0 { return "发现 \(n) 项异常，建议处理" }
            let culprit = [doctor, audit, identity]
                .compactMap { $0 }
                .first { $0.verdict == .problem }
            return culprit?.headline ?? "发现异常，建议处理"
        case .incomplete:
            return "体检没跑完，结论不完整"
        }
    }
}
