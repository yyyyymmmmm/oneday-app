import Foundation

// MARK: - 崩溃报告收集开关（DESIGN §384／总表 131 G-14）

/// 崩溃与诊断收集的开关：缺省（键不存在）＝开
/// ——MetricKit 订阅在启动时注册；显式置 false＝
/// 不注册（已注册的当场摘除）。关于页内部实验节
/// 的同键 Toggle 是唯一用户关口，与 §241.4 CI 侧
/// 仓库变量开关同义（收集侧关口），只是本旗管的
/// 是 App 运行时收集面（§241.4 当年明示缺位、本
/// 节补齐）。与聊天各施工旗独立、互不牵连。
public enum CrashCollectionFeature {
    public static let defaultsKey = "crash.collection.enabled"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let stored = defaults.object(
            forKey: defaultsKey
        ) as? Bool else { return true }
        return stored
    }
}

// MARK: - 报告种类

/// 诊断种类（MetricKit 载荷四类＋兜底）：崩溃是
/// 主线；卡死/CPU/磁盘写异常同走一条收集管线，
/// 报告面按种类分行呈现。
public enum CrashReportKind: String, Codable, Equatable, Sendable {
    case crash
    case hang
    case cpuException
    case diskWriteException
    case other

    /// 报告面行题（中文源串）
    public var title: String {
        switch self {
        case .crash: return "崩溃"
        case .hang: return "卡死"
        case .cpuException: return "CPU 异常"
        case .diskWriteException: return "磁盘写异常"
        case .other: return "诊断"
        }
    }
}

// MARK: - 隐私门（§241.4 口径的 App 侧落点）

/// 崩溃报告隐私门：与 Scripts/ci/crash_metadata.py
/// 同口径——①字段白名单（记录结构本身只有白名单
/// 字段：时刻/种类/异常类型/信号/终止命名空间与
/// 码/App 与系统版本/故障线程顶部符号名；设备名/
/// incident/二进制 UUID/寄存器/源文件路径天然不
/// 入结构）；②全文兜底清洗（用户名路径与 UUID
/// 形串两道正则，与 CI 脚本同式）；③App 侧加严
/// 一档：十六进制地址一并抹除（MetricKit 符号串
/// 可能夹地址，CI 的 .ips 提取路径天然不取、本
/// 路径须补此道）。记录只许经 make(...) 构造——
/// 构造即过门，无未脱敏记录可落盘。
public enum CrashReportPrivacy {
    /// 故障线程顶部符号上限（与 CI 脚本 TOP_FRAMES 同值）
    public static let maxTopSymbols = 8

    // 路径清洗比 CI 脚本加严一档：CI 只抹用户名
    // 段、余下路径段仍留；App 侧整条路径吞掉（报
    // 告判读不需要任何路径段，见 §384）
    private static let userPathRegex = try? NSRegularExpression(
        pattern: "/(?:Users|home)/\\S+"
    )
    private static let uuidRegex = try? NSRegularExpression(
        pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}"
            + "-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    )
    private static let addressRegex = try? NSRegularExpression(
        pattern: "0x[0-9a-fA-F]{4,}"
    )

    /// 全文兜底清洗：三道正则依次抹用户名路径、
    /// UUID 形串、十六进制地址。
    public static func scrub(_ text: String) -> String {
        var out = text
        out = replacing(userPathRegex, in: out, with: "/<redacted>")
        out = replacing(uuidRegex, in: out, with: "<redacted-uuid>")
        out = replacing(addressRegex, in: out, with: "0x<addr>")
        return out
    }

    private static func replacing(
        _ regex: NSRegularExpression?, in text: String,
        with template: String
    ) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text, range: range, withTemplate: template
        )
    }

    /// 符号列过门：逐个清洗、去空、截顶部上限。
    public static func sanitizedSymbols(_ symbols: [String]) -> [String] {
        symbols
            .map { scrub($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(maxTopSymbols)
            .map { $0 }
    }
}

// MARK: - 报告记录（白名单字段，构造即脱敏）

public struct CrashReportRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// 诊断时段终点（MetricKit 载荷时间戳；无载荷时为采集时刻）
    public let capturedAt: Date
    public let kind: CrashReportKind
    public let exceptionType: String?
    public let exceptionSignal: String?
    public let terminationNamespace: String?
    public let terminationCode: String?
    public let appVersion: String?
    public let osVersion: String?
    /// 故障线程顶部符号名（已过隐私门、上限 8）
    public let faultingTopSymbols: [String]

    /// 唯一构造口：全部字符串字段在此过隐私门，
    /// 调用方给原文即可，不许自带「已脱敏」假设。
    public static func make(
        id: UUID = UUID(),
        capturedAt: Date,
        kind: CrashReportKind,
        exceptionType: String? = nil,
        exceptionSignal: String? = nil,
        terminationNamespace: String? = nil,
        terminationCode: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        faultingTopSymbols: [String] = []
    ) -> CrashReportRecord {
        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let scrubbed = CrashReportPrivacy.scrub(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return scrubbed.isEmpty ? nil : scrubbed
        }
        return CrashReportRecord(
            id: id,
            capturedAt: capturedAt,
            kind: kind,
            exceptionType: clean(exceptionType),
            exceptionSignal: clean(exceptionSignal),
            terminationNamespace: clean(terminationNamespace),
            terminationCode: clean(terminationCode),
            appVersion: clean(appVersion),
            osVersion: clean(osVersion),
            faultingTopSymbols: CrashReportPrivacy.sanitizedSymbols(
                faultingTopSymbols
            )
        )
    }

    /// 内容相等（除本机 id）：MetricKit 同一载荷
    /// 重复投递时去重用。
    public func hasSameContent(as other: CrashReportRecord) -> Bool {
        capturedAt == other.capturedAt
            && kind == other.kind
            && exceptionType == other.exceptionType
            && exceptionSignal == other.exceptionSignal
            && terminationNamespace == other.terminationNamespace
            && terminationCode == other.terminationCode
            && appVersion == other.appVersion
            && osVersion == other.osVersion
            && faultingTopSymbols == other.faultingTopSymbols
    }

    /// 报告面/导出共用的单条文本形态（等宽呈现，
    /// 字段全是已脱敏值）。
    public func displayText(dateFormatter: DateFormatter) -> String {
        var lines: [String] = []
        lines.append(
            "\(dateFormatter.string(from: capturedAt)) · \(kind.title)"
        )
        var exceptionLine: [String] = []
        if let exceptionType { exceptionLine.append("异常 \(exceptionType)") }
        if let exceptionSignal { exceptionLine.append("信号 \(exceptionSignal)") }
        if !exceptionLine.isEmpty {
            lines.append(exceptionLine.joined(separator: " · "))
        }
        var terminationLine: [String] = []
        if let terminationNamespace {
            terminationLine.append("终止 \(terminationNamespace)")
        }
        if let terminationCode {
            terminationLine.append("码 \(terminationCode)")
        }
        if !terminationLine.isEmpty {
            lines.append(terminationLine.joined(separator: " · "))
        }
        var versionLine: [String] = []
        if let appVersion { versionLine.append("App \(appVersion)") }
        if let osVersion { versionLine.append("系统 \(osVersion)") }
        if !versionLine.isEmpty {
            lines.append(versionLine.joined(separator: " · "))
        }
        if !faultingTopSymbols.isEmpty {
            lines.append("故障线程顶部符号：")
            for (index, symbol) in faultingTopSymbols.enumerated() {
                lines.append("  \(index)  \(symbol)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 本机落盘存储

/// 崩溃报告本机存储：Application Support 下单
/// JSON 文件（原子写、上限 50 条、最新在前）。
/// 只存已过隐私门的记录；查看面（CrashReports-
/// View）与导出都只读这里——采集与呈现的唯一账。
public final class CrashReportStore: @unchecked Sendable {
    public static let shared = CrashReportStore()
    public static let maxRecords = 50

    private let fileURL: URL
    private let lock = NSLock()

    /// directory 可注入（测试用临时目录）；缺省落
    /// Application Support/OneDayDiagnostics。
    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(
            "OneDayDiagnostics", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        fileURL = dir.appendingPathComponent("crash-reports.json")
    }

    /// 全部记录（最新在前）；文件缺失/损坏回空列
    /// （报告面不许因自家账损坏崩）。
    public func all() -> [CrashReportRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    /// 追加（内容去重、截上限、最新在前一次落盘）。
    public func append(_ newRecords: [CrashReportRecord]) {
        guard !newRecords.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var existing = loadLocked()
        for record in newRecords.reversed() {
            if existing.contains(where: { $0.hasSameContent(as: record) }) {
                continue
            }
            existing.insert(record, at: 0)
        }
        existing.sort { $0.capturedAt > $1.capturedAt }
        saveLocked(Array(existing.prefix(Self.maxRecords)))
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        saveLocked([])
    }

    /// 导出全文（报告面分享口；内容即落盘记录的
    /// displayText 拼接，天然已脱敏）。
    public func exportText() -> String {
        let records = all()
        guard !records.isEmpty else { return "暂无崩溃报告" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return records
            .map { $0.displayText(dateFormatter: formatter) }
            .joined(separator: "\n\n—\n\n")
    }

    private func loadLocked() -> [CrashReportRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(
            [CrashReportRecord].self, from: data
        )) ?? []
    }

    private func saveLocked(_ records: [CrashReportRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - 服务端崩溃上报与回读模型（hermes-deploy 1.7.0+，/v1/diagnostics/crash-reports）

public struct CrashReportsUploadReceipt: Decodable, Equatable, Sendable {
    public let accepted: Int
    public let rejected: Int

    public init(accepted: Int = 0, rejected: Int = 0) {
        self.accepted = accepted
        self.rejected = rejected
    }

    private enum CodingKeys: String, CodingKey {
        case accepted, rejected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.accepted = (try? c.decode(Int.self, forKey: .accepted)) ?? 0
        self.rejected = (try? c.decode(Int.self, forKey: .rejected)) ?? 0
    }
}

public struct ServerCrashReportItem: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let capturedAt: String?
    public let receivedAt: String?
    public let kind: String
    public let exceptionType: String?
    public let exceptionSignal: String?
    public let terminationNamespace: String?
    public let terminationCode: String?
    public let appVersion: String?
    public let osVersion: String?
    public let faultingTopSymbols: [String]

    private enum CodingKeys: String, CodingKey {
        case id, capturedAt, receivedAt, kind, exceptionType, exceptionSignal
        case terminationNamespace, terminationCode, appVersion, osVersion
        case faultingTopSymbols
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.capturedAt = try? c.decode(String.self, forKey: .capturedAt)
        self.receivedAt = try? c.decode(String.self, forKey: .receivedAt)
        self.id = (try? c.decode(String.self, forKey: .id))
            ?? self.receivedAt ?? self.capturedAt ?? UUID().uuidString
        self.kind = (try? c.decode(String.self, forKey: .kind)) ?? "other"
        self.exceptionType = try? c.decode(String.self, forKey: .exceptionType)
        self.exceptionSignal = try? c.decode(String.self, forKey: .exceptionSignal)
        self.terminationNamespace = try? c.decode(String.self, forKey: .terminationNamespace)
        self.terminationCode = try? c.decode(String.self, forKey: .terminationCode)
        self.appVersion = try? c.decode(String.self, forKey: .appVersion)
        self.osVersion = try? c.decode(String.self, forKey: .osVersion)
        self.faultingTopSymbols = (try? c.decode([String].self, forKey: .faultingTopSymbols)) ?? []
    }

    public var kindTitle: String {
        CrashReportKind(rawValue: kind)?.title ?? kind
    }

    public var displayText: String {
        var lines: [String] = []
        let timeLabel = capturedAt ?? receivedAt ?? "未知时间"
        lines.append("\(timeLabel) · \(kindTitle)")
        var exc: [String] = []
        if let exceptionType { exc.append("异常 \(exceptionType)") }
        if let exceptionSignal { exc.append("信号 \(exceptionSignal)") }
        if !exc.isEmpty { lines.append(exc.joined(separator: " · ")) }
        var term: [String] = []
        if let terminationNamespace { term.append("终止 \(terminationNamespace)") }
        if let terminationCode { term.append("码 \(terminationCode)") }
        if !term.isEmpty { lines.append(term.joined(separator: " · ")) }
        var ver: [String] = []
        if let appVersion { ver.append("App \(appVersion)") }
        if let osVersion { ver.append("系统 \(osVersion)") }
        if !ver.isEmpty { lines.append(ver.joined(separator: " · ")) }
        if !faultingTopSymbols.isEmpty {
            lines.append("故障线程顶部符号：")
            for (idx, sym) in faultingTopSymbols.enumerated() {
                lines.append("  \(idx)  \(sym)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public struct ServerCrashReportsListResponse: Decodable, Equatable, Sendable {
    public let data: [ServerCrashReportItem]

    public init(data: [ServerCrashReportItem] = []) {
        self.data = data
    }
}
