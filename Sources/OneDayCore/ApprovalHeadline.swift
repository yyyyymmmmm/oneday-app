import Foundation

/// 审批面头条模板（0.36.21，宪法 §8 收口）：用户面标
/// 题一律由结构化字段（子系统/有效 op/目标名/批量计
/// 数/记忆目标/内容预览）在本处拼中文人话。服务端原
/// 始 summary 是英文运维串（如 "batch(3 ops: patch,
/// patch, patch) on X"、"add to memory: …"），**不许
/// 当头条**（P-16）；它只许出现在「查看详情」的原始
/// 信息区（默认折叠，给排障）。桥未部署结构化字段前
/// 字段缺失，模板退到通用中文句（动词＋类别），同样
/// 不回落英文原串。
public enum ApprovalHeadline {
    /// 头条预览的最大字数（超出截断加省略号）
    static let previewLimit = 30

    public static func title(
        subsystem: WriteGateSubsystem, op: String,
        targetName: String?, opCount: Int?, opKinds: [String]?,
        memTarget: String?, contentPreview: String?
    ) -> String {
        switch subsystem {
        case .memory:
            return memoryTitle(
                op: op, memTarget: memTarget,
                contentPreview: contentPreview
            )
        case .skills:
            return skillsTitle(
                op: op, targetName: targetName,
                opCount: opCount, opKinds: opKinds
            )
        case .unknown:
            // 子系统都认不出时只给类别名，不硬拼动词
            // （这类记录本就不支持 App 内审批，见卡面去向）
            return "其他写入"
        }
    }

    // MARK: - memory

    private static func memoryTitle(
        op: String, memTarget: String?, contentPreview: String?
    ) -> String {
        let isUser = memTarget == "user"
        let preview = previewText(contentPreview)
        let suffix = preview.map { "：\($0)" } ?? ""
        switch op.lowercased() {
        case "add", "create", "append", "new":
            return isUser
                ? "新增一条个人资料\(suffix)"
                : "新增一条记忆\(suffix)"
        case "replace", "edit", "update", "modify":
            return isUser
                ? "修改个人资料\(suffix)"
                : "修改一条记忆\(suffix)"
        case "remove", "delete":
            return isUser
                ? "从个人资料删除\(suffix)"
                : "删除一条记忆\(suffix)"
        default:
            let verb = WriteGateLabels.actionVerb(op)
            return isUser ? "\(verb)个人资料\(suffix)"
                : "\(verb)一条记忆\(suffix)"
        }
    }

    // MARK: - skills

    private static func skillsTitle(
        op: String, targetName: String?,
        opCount: Int?, opKinds: [String]?
    ) -> String {
        let name = targetName?.trimmingCharacters(in: .whitespaces)
        let target = (name?.isEmpty == false) ? "技能《\(name!)》" : "一个技能"
        switch op.lowercased() {
        case "batch":
            guard let count = opCount, count > 0 else {
                return "批量修改\(target)"
            }
            let kinds = Set((opKinds ?? []).map { $0.lowercased() })
            if kinds == ["create"] {
                return "新建\(target)：共 \(count) 项"
            }
            if kinds == ["delete"] || kinds == ["remove_file"] {
                return "删除\(target)：共 \(count) 项"
            }
            // patch/edit/write_file 占多数或混合：一律
            // 「修改…共 N 处改动」（口径示例同用户截图）
            return "修改\(target)：共 \(count) 处改动"
        case "create", "add", "new":
            return "新建\(target)"
        case "edit", "update", "modify", "patch":
            return "修改\(target)"
        case "write_file", "write":
            return "修改\(target)的文件"
        case "delete", "remove":
            return "删除\(target)"
        case "remove_file":
            return "删除\(target)里的文件"
        default:
            return "\(WriteGateLabels.actionVerb(op))\(target)"
        }
    }

    // MARK: - 说明行与预览

    /// 头条下的说明行：内容预览优先（截断收口）；无预
    /// 览时，原始摘要已是中文主导才用它（存量中文摘要
    /// 不浪费）；摘要是英文运维串则返回 nil——宁可没
    /// 有说明行，不漏英文原串
    public static func previewLine(
        contentPreview: String?, summary: String
    ) -> String? {
        if let preview = previewText(contentPreview) {
            return preview
        }
        let trimmed = summary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty, isChineseDominant(trimmed) else {
            return nil
        }
        return trimmed
    }

    /// 预览收口：折空白、截断到 previewLimit 字加省略号
    static func previewText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = raw.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !folded.isEmpty else { return nil }
        if folded.count <= previewLimit { return folded }
        return String(folded.prefix(previewLimit)) + "…"
    }

    /// 中文主导判定：汉字数多于拉丁字母数（存量中文摘
    /// 要与英文运维串的分界，纯启发式、只决定说明行取
    /// 舍，不决定头条——头条永远走模板）
    static func isChineseDominant(_ text: String) -> Bool {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(Int(scalar.value)) {
                cjk += 1
            } else if (0x41...0x5A).contains(Int(scalar.value))
                || (0x61...0x7A).contains(Int(scalar.value)) {
                latin += 1
            }
        }
        return cjk > latin
    }
}

/// 审批面相对时间（0.36.21）：当年显式钉 zh_CN
/// locale，不跟随设备默认口径（用户真机相对时间漏
/// 英文 "44 minutes ago" 的定案）。0.42.0 国际化包
/// 续编：钉的改为 App 界面语言本身（AppLocale.
/// uiLocale）——界面中文时仍是中文、英文时是英文，
/// 漏出异语言的混排在三语下都不发生。审批面（待
/// 批卡/就地卡/已决历史）的时间一律走本处；其他面
/// 的同类呈现清单见 DESIGN §87（本包不扩围改）。
public enum ApprovalTimeText {
    public static func relative(
        _ date: Date, now: Date = Date(),
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
