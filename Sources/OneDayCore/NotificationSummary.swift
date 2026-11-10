import Foundation

/// 通知摘要的人话翻译与按日分组（0.36.7，规格
/// notifications-page-benchmark-20261110 §3.2/§3.4）。
///
/// 病根：裁决类通知的 body 是 Hermes 写入工具的暂存
/// 摘要（summary）原文——英文文法＋实现细节直出，
/// 违设计宪法 §8 与续编 S12。本层在 App 侧 Core 把
/// 可穷举的文法（记忆 4 形＋技能 1 形）翻成人话对
/// 象句；解析不出（文法不命中／op 表外值／裁决语
/// 态不明）一律禁止直出原文：摘要降级为通用句、
/// 原文收进点按展开的次级详情（rawDetail，S10）。
/// 监测类 body 是引擎成形文案，只折叠空白直通。
public struct NotificationPresentation: Equatable, Sendable {
    /// 主文案（人话摘要；空串＝不显摘要行）
    public let summary: String
    /// 次级详情原文（点按展开才见；nil＝无可展开项）
    public let rawDetail: String?

    public init(summary: String, rawDetail: String?) {
        self.summary = summary
        self.rawDetail = rawDetail
    }
}

public enum NotificationSummary {
    /// 裁决语态（自桥的结论标题派生：标题是桥对每条
    /// 记录的定性，摘要文法本身不带语态）
    private enum Decision {
        case approved, rejected, unknown
    }

    /// 对象类（同自标题派生；只喂降级通用句——模板
    /// 本体认 body 文法自带的目标，不靠标题猜对象）
    private enum Subsystem {
        case memory, skill, unknown
    }

    public static func presentation(
        kind: String, title: String, body: String
    ) -> NotificationPresentation {
        guard kind == "write_gate_decision" else {
            // 监测类（monitor_change）与未知 kind：成
            // 形文案直通，只折叠空白（超长由视图
            // lineLimit 截断，不在此截字、不解析）
            return NotificationPresentation(
                summary: foldWhitespace(body), rawDetail: nil
            )
        }
        let decision: Decision = title.contains("已被驳回")
            ? .rejected
            : (title.contains("已批准") ? .approved : .unknown)
        let subsystem: Subsystem = title.contains("记忆")
            ? .memory
            : (title.contains("技能") ? .skill : .unknown)
        // 语态不明（桥兜底标题「写入审批已处理」）时
        // 模板无从落语态——宁可降级通用句，不许拿批
        // 准式文案冒充已执行（§9 如实）
        if decision != .unknown,
           let translated = translateSummary(body, decision: decision) {
            return NotificationPresentation(
                summary: translated,
                rawDetail: body.isEmpty || body == translated ? nil : body
            )
        }
        return NotificationPresentation(
            summary: genericSentence(
                subsystem: subsystem, decision: decision
            ),
            rawDetail: body.isEmpty ? nil : body
        )
    }

    // MARK: - 文法分发

    private static func translateSummary(
        _ body: String, decision: Decision
    ) -> String? {
        if body.hasPrefix("batch(") {
            return translateSkillBatch(body, decision: decision)
        }
        return translateMemoryOps(body, decision: decision)
    }

    // MARK: - 记忆类（M1–M4）

    private static func translateMemoryOps(
        _ body: String, decision: Decision
    ) -> String? {
        if body.hasPrefix("apply ") {
            return translateApply(body, decision: decision)
        }
        if let (target, detail) = parseSimpleOp(body, verb: "add to ") {
            let d = foldDetail(detail)
            guard !d.isEmpty else { return nil }
            let verb = decision == .approved ? "已写入" : "未写入"
            return "「\(d)」\(verb)\(target)"
        }
        if let (target, detail) = parseSimpleOp(body, verb: "remove from ") {
            let d = foldDetail(detail)
            guard !d.isEmpty else { return nil }
            let verb = decision == .approved ? "已从" : "未从"
            return "「\(d)」\(verb)\(target)删除"
        }
        if body.hasPrefix("replace in ") {
            return translateReplace(body, decision: decision)
        }
        return nil
    }

    /// 文法标签 → 人话目标（§3.2 通则）
    private static func targetName(forLabel label: String) -> String? {
        switch label {
        case "memory": return "长期记忆"
        case "user profile": return "用户档案"
        default: return nil
        }
    }

    /// 解 `{verb}{label}: {detail}`（M1/M2 共用），
    /// label 只认 memory／user profile 两值
    private static func parseSimpleOp(
        _ body: String, verb: String
    ) -> (target: String, detail: String)? {
        guard body.hasPrefix(verb) else { return nil }
        let rest = body.dropFirst(verb.count)
        for label in ["user profile", "memory"] {
            let head = label + ": "
            if rest.hasPrefix(head),
               let target = targetName(forLabel: label) {
                return (target, String(rest.dropFirst(head.count)))
            }
        }
        return nil
    }

    /// M3：`replace in {label}: entry matching: {old}`
    /// 换行 `whole entry becomes: {new}`
    private static func translateReplace(
        _ body: String, decision: Decision
    ) -> String? {
        let rest = body.dropFirst("replace in ".count)
        for label in ["user profile", "memory"] {
            let head = label + ": entry matching: "
            guard rest.hasPrefix(head),
                  let target = targetName(forLabel: label)
            else { continue }
            let tail = String(rest.dropFirst(head.count))
            let parts = tail.components(
                separatedBy: "\nwhole entry becomes: "
            )
            guard parts.count == 2 else { return nil }
            let old = foldDetail(parts[0])
            let new = foldDetail(parts[1])
            guard !old.isEmpty, !new.isEmpty else { return nil }
            let verb = decision == .approved ? "已改为" : "未改为"
            return "\(target)里的「\(old)」\(verb)「\(new)」"
        }
        return nil
    }

    /// M4：`apply {N} op(s) to {label}: ` 后逐行
    /// `- {verb}: {detail}`（verb ∈ add/remove/replace）
    private static func translateApply(
        _ body: String, decision: Decision
    ) -> String? {
        var rest = body.dropFirst("apply ".count)
        var digits = ""
        while let first = rest.first, first.isNumber {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard let count = Int(digits), count > 0,
              rest.hasPrefix(" op(s) to ")
        else { return nil }
        rest = rest.dropFirst(" op(s) to ".count)
        var target: String?
        var opsText = ""
        for label in ["user profile", "memory"] {
            let head = label + ": "
            if rest.hasPrefix(head) {
                target = targetName(forLabel: label)
                opsText = String(rest.dropFirst(head.count))
                break
            }
        }
        guard let target, opsText.hasPrefix("- ") else { return nil }
        let pieces = opsText.components(separatedBy: "\n- ")
        var ops: [(verb: String, detail: String)] = []
        for (index, rawPiece) in pieces.enumerated() {
            var piece = rawPiece
            if index == 0 { piece = String(piece.dropFirst(2)) }
            guard let colon = piece.firstIndex(of: ":") else {
                return nil
            }
            let verb = String(piece[..<colon])
            guard ["add", "remove", "replace"].contains(verb) else {
                return nil
            }
            var detail = String(piece[piece.index(after: colon)...])
            if detail.hasPrefix(" ") { detail = String(detail.dropFirst()) }
            ops.append((verb, detail))
        }
        // 声明条数与实解条数不符＝文法被细节里的伪行
        // 污染，整条走兜底（不猜）
        guard ops.count == count else { return nil }
        var shorts: [String] = []
        for op in ops.prefix(2) {
            switch op.verb {
            case "add":
                let d = foldDetail(op.detail)
                guard !d.isEmpty else { return nil }
                shorts.append("新增「\(d)」")
            case "remove":
                let d = foldDetail(op.detail)
                guard !d.isEmpty else { return nil }
                shorts.append("删除「\(d)」")
            default:
                shorts.append("替换一处")
            }
        }
        let state = decision == .approved ? "已生效" : "未生效"
        var result = "对\(target)的 \(count) 处改动\(state)："
            + shorts.joined(separator: "、")
        if count > 2 { result += "等共 \(count) 处" }
        return result
    }

    // MARK: - 技能类（S1–S3）

    /// `batch({N} ops: {op, op, …}) on {name, name, …}`，
    /// op 只认 patch／write_file／create（表外整条兜底）
    private static func translateSkillBatch(
        _ body: String, decision: Decision
    ) -> String? {
        var rest = body.dropFirst("batch(".count)
        var digits = ""
        while let first = rest.first, first.isNumber {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard let total = Int(digits), total > 0,
              rest.hasPrefix(" ops: ")
        else { return nil }
        rest = rest.dropFirst(" ops: ".count)
        guard let close = rest.range(of: ") on ") else { return nil }
        let opsText = String(rest[..<close.lowerBound])
        let namesText = String(rest[close.upperBound...])
        let ops = opsText.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard ops.count == total,
              ops.allSatisfy({
                  ["patch", "write_file", "create"].contains($0)
              })
        else { return nil }
        let names = namesText.components(separatedBy: ", ")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        // 聚合计数：丢弃逐项罗列，按首次出现序成句
        var order: [String] = []
        var counts: [String: Int] = [:]
        for op in ops {
            if counts[op] == nil { order.append(op) }
            counts[op, default: 0] += 1
        }
        let quotedNames = names.prefix(2).map { "「\($0)」" }.joined()
        let namesSuffix = names.count > 2
            ? "等共 \(names.count) 个技能" : ""
        if decision == .rejected {
            // 驳回形：规格只给了 M4 的「未生效」聚合式，
            // 技能类按同式落（完成式动词不进驳回句）
            return "技能\(quotedNames)\(namesSuffix)的 \(total) 处改动未生效"
        }
        if names.count == 1, order == ["patch"], counts["patch"] == 1 {
            return "改了技能「\(names[0])」的内容"
        }
        var phrases: [String] = []
        for op in order {
            let n = counts[op] ?? 0
            switch op {
            case "patch": phrases.append("改了 \(n) 处内容")
            case "write_file": phrases.append("写了 \(n) 个文件")
            default: phrases.append("新建了 \(n) 个文件")
            }
        }
        return "更新了技能\(quotedNames)\(namesSuffix)："
            + phrases.joined(separator: "、")
    }

    // MARK: - 兜底与文本处理

    /// 解析失败的通用句（与桥自带兜底同式）：只说对
    /// 象类与裁决结论，不带任何原文
    private static func genericSentence(
        subsystem: Subsystem, decision: Decision
    ) -> String {
        switch (subsystem, decision) {
        case (.memory, .approved): return "一项记忆写入已批准"
        case (.memory, .rejected): return "一项记忆写入已被驳回"
        case (.skill, .approved): return "一项技能写入已批准"
        case (.skill, .rejected): return "一项技能写入已被驳回"
        case (.unknown, .approved): return "一项写入已批准"
        case (.unknown, .rejected): return "一项写入已被驳回"
        case (_, .unknown): return "一项写入已处理"
        }
    }

    /// 折叠空白（含换行）为单空格
    private static func foldWhitespace(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 对象文本处理（§3.2 通则）：折叠空白后取前
    /// 60 字，超出以「…」收尾（引号由模板在外层闭合）
    private static func foldDetail(_ raw: String) -> String {
        let folded = foldWhitespace(raw)
        guard folded.count > 60 else { return folded }
        return String(folded.prefix(60)) + "…"
    }
}

/// 通知按日分组（§3.4）：全表单一时间倒序、按自然
/// 日成组，组头文案走 DisplayDate.dateOnly（与聊天
/// 时间分隔条同源同口径）。createdAt 解析不了的条
/// 目不编造日期：单独成组垫底、组头即原文（沿旧版
/// 「解析不了原样呈现」口径）。
///
/// locale 注入点（0.42.0 CI 修复）：本函数初版无
/// locale 入参，组头转调 DisplayDate 时落其默认
/// AppLocale.uiLocale——逻辑测试宿主里该值随运行
/// 环境语言漂移，英文环境下星期档组头漏出
/// 「Sunday」与同组「今天/昨天」混排（run
/// 42919829466 实证）。自此组头语言随注入 locale，
/// 与侧栏分组（SidebarGrouping 同为注入式）一式。
public struct NotificationDayGroup: Equatable, Sendable, Identifiable {
    public let key: String
    public let title: String
    public let items: [OverviewNotification]

    public var id: String { key }

    public init(
        key: String, title: String, items: [OverviewNotification]
    ) {
        self.key = key
        self.title = title
        self.items = items
    }
}

public enum NotificationGrouping {
    /// 桥 createdAt（ISO8601，带/不带小数秒两形）
    public static func parseCreatedAt(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }

    public static func groups(
        notifications: [OverviewNotification],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> [NotificationDayGroup] {
        let dated = notifications.map {
            (item: $0, date: parseCreatedAt($0.createdAt))
        }
        let sorted = dated.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?), (nil, nil): return false
            }
        }
        var result: [NotificationDayGroup] = []
        for entry in sorted {
            guard let date = entry.date else {
                result.append(NotificationDayGroup(
                    key: "raw-\(entry.item.id)",
                    title: entry.item.createdAt,
                    items: [entry.item]
                ))
                continue
            }
            let dayStart = calendar.startOfDay(for: date)
            let key = "day-\(dayStart.timeIntervalSince1970)"
            if let last = result.last, last.key == key {
                result[result.count - 1] = NotificationDayGroup(
                    key: key, title: last.title,
                    items: last.items + [entry.item]
                )
            } else {
                result.append(NotificationDayGroup(
                    key: key,
                    title: DisplayDate.dateOnly(
                        date, now: now, calendar: calendar,
                        locale: locale
                    ),
                    items: [entry.item]
                ))
            }
        }
        return result
    }
}
