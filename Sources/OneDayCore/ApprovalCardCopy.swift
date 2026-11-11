import Foundation

/// 就地审批卡文案模板（0.36.21，规格 approval-card-
/// design §2/§3）：标题问句与后果说明由记录的结构化
/// 字段拼装——动作取有效 op（桥结构化 op 优先、回落
/// 顶层 action）、对象取子系统与目标，原始 summary/
/// payload 绝不上卡面（宪法 §8：零行话零外文漏出；
/// 原始串只进「查看详情」内的原始信息区）。纯函数、
/// 钉测把守，视图层不许另拼文案。
public enum ApprovalCardCopy {
    /// 人话标题问句：「允许智能体…？」
    public static func question(
        for record: WriteGateRecord,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let op = record.effectiveOp.lowercased()
        switch record.subsystem {
        case .memory:
            switch op {
            case "add", "create", "append", "new":
                return L10n.string("允许智能体新增一条长期记忆？", locale: locale)
            case "replace", "edit", "update", "modify":
                return L10n.string("允许智能体修改一条长期记忆？", locale: locale)
            case "remove", "delete":
                return L10n.string("允许智能体删除一条长期记忆？", locale: locale)
            default:
                return L10n.string("允许智能体写入长期记忆？", locale: locale)
            }
        case .skills:
            switch op {
            case "create", "add", "new":
                return L10n.string("允许智能体新建一个技能？", locale: locale)
            case "delete", "remove":
                return L10n.string("允许智能体删除整个技能？", locale: locale)
            case "remove_file":
                return L10n.string("允许智能体删除技能里的一个文件？", locale: locale)
            case "batch":
                return L10n.string("允许智能体批量修改技能文件？", locale: locale)
            default:
                return L10n.string("允许智能体修改技能文件？", locale: locale)
            }
        case .unknown:
            return L10n.string("允许智能体执行这项写入？", locale: locale)
        }
    }

    /// 一句后果说明：批准与驳回各发生什么，一行说清
    public static func consequence(
        for record: WriteGateRecord,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let op = record.effectiveOp.lowercased()
        switch record.subsystem {
        case .memory:
            switch op {
            case "add", "create", "append", "new":
                return L10n.string(
                    "批准后这条记忆会保存下来、长期生效；驳回则不会保存。",
                    locale: locale
                )
            case "replace", "edit", "update", "modify":
                return L10n.string(
                    "批准后原有记忆会被新内容替换；驳回则保持原样。",
                    locale: locale
                )
            case "remove", "delete":
                return L10n.string(
                    "批准后这条记忆会被删除；驳回则保持原样。",
                    locale: locale
                )
            default:
                return L10n.string(
                    "批准后写入会生效；驳回则不会写入。", locale: locale
                )
            }
        case .skills:
            switch op {
            case "create", "add", "new":
                return L10n.string(
                    "批准后新技能会创建并生效；驳回则不会创建。",
                    locale: locale
                )
            case "delete", "remove":
                return L10n.string(
                    "批准后整个技能会被删除；驳回则保持原样。",
                    locale: locale
                )
            case "remove_file":
                return L10n.string(
                    "批准后这个文件会被删除；驳回则保持原样。",
                    locale: locale
                )
            default:
                return L10n.string(
                    "批准后修改会写入技能并生效；驳回则保持原样。",
                    locale: locale
                )
            }
        case .unknown:
            return L10n.string(
                "批准后写入会生效；驳回则不会写入。", locale: locale
            )
        }
    }

    /// 「总是允许这一类」的范围说明：子系统＋来源，
    /// 与桥规则键（subsystem, origin）同一口径的人话
    /// 呈现——用户点之前就知道记住的是哪一类
    public static func alwaysAllowScope(
        for record: WriteGateRecord,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        "\(record.subsystem.badgeLabel(locale: locale)) · \(record.originLabel(locale: locale))"
    }

    /// 卡面说明行（一行口径，样式二期 S2-02）：头条为
    /// 主体——它是记录特异信息；内容预览存在、与头
    /// 条不同且未被头条包含时，以「：」衔接在后（视
    /// 图层一行截断时先被挤掉的是预览尾巴，头条恒完
    /// 整可见；记忆类头条已内嵌同一预览，包含判定防
    /// 重复拼两遍）。后果句与来源不再上卡面：裁决钮
    /// 与确认弹窗已表意、来源只进详情原始信息区
    /// （审计 S2-02 收敛口径）
    public static func summaryLine(
        for record: WriteGateRecord,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let headline = record.headline(locale: locale)
        guard let preview = record.previewLine,
              preview != headline,
              !headline.contains(preview)
        else { return headline }
        return L10n.format(
            "%@：%@", locale: locale, headline, preview
        )
    }
}
