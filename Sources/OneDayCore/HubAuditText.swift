import Foundation

/// §477 审核页呈现层人话映射（2026-11-24 全抄）：
/// 授权行的 scope/来源枚举在此收口成中文——写闸子
/// 系统仅 memory/skills 两类、来源仅 foreground/
/// background_review/assistant_tool/oneday_app 四类
/// （2026-11-24 实查服务端 write_gate_gateway.py 与
/// grant_projection.py 的枚举全集，scope_label 拼法
/// ＝「子系统 · 来源」）。未知值不许英文原文上列
/// 表：一律回落通用中文类别词，原文只进详情。已决
/// 行的头条与说明行不在此重造——走 ApprovalHead-
/// line 单源（与待批卡同模板、同口径）。
public enum HubAuditText {

    // MARK: - 授权行

    /// 授权行标题：exec ＝命令模式键本身（授权对象、
    /// 用户可读的命令形，如参照以对象作题）；写闸＝
    /// 「子系统 · 来源」中文化（两类行靠标题即可分
    /// 辨，不再出现 skills/memory 英文枚举）
    public static func grantTitle(_ entry: GrantEntry) -> String {
        switch entry.source {
        case .exec:
            return entry.scopeLabel
        case .writegate, .other:
            let parts = entry.scopeLabel
                .components(separatedBy: " · ")
            let subsystem = parts.first
                .flatMap { subsystemWord($0) }
            let origin = parts.count > 1
                ? originWord(parts[1]) : nil
            switch (subsystem, origin) {
            case let (sub?, origin?):
                return "\(sub) · \(origin)"
            case let (sub?, nil):
                return L10n.format("%@写闸规则", sub)
            case (nil, _):
                return L10n.string("写闸规则")
            }
        }
    }

    /// 授权行说明（一句人话说清这条授权放行什么）
    public static func grantDescription(
        _ entry: GrantEntry
    ) -> String {
        switch entry.source {
        case .exec:
            return L10n.string("已授权直接执行匹配的命令，不再逐次询问")
        case .writegate, .other:
            return L10n.string("命中规则的写入自动放行，不再逐次询问")
        }
    }

    /// 授权行元信息：处置词承载「长期授权」语义
    /// （对参照「始终允许网站 · 4小时前」形态）＋
    /// 相对时间（无回读时刻不编造、只给处置词）
    public static func grantMeta(
        _ entry: GrantEntry, now: Date = Date()
    ) -> String {
        let kindWord: String
        switch entry.source {
        case .exec:
            kindWord = L10n.string("命令授权")
        case .writegate, .other:
            kindWord = L10n.string("写闸规则")
        }
        var meta = L10n.format("始终允许 · %@", kindWord)
        if let grantedAt = entry.grantedAt {
            meta += " · " + ApprovalTimeText.relative(
                grantedAt, now: now
            )
        }
        return meta
    }

    // MARK: - 已决行

    /// 已决行说明：ApprovalHeadline.previewLine（内
    /// 容预览优先、英文运维串宁缺勿漏）；头条已内
    /// 嵌同一预览时（记忆类头条「动作：预览」形）
    /// 不重复呈一遍
    public static func decisionDescription(
        _ record: WriteGateDecisionRecord
    ) -> String? {
        guard let line = ApprovalHeadline.previewLine(
            contentPreview: record.contentPreview,
            summary: record.summary
        ) else { return nil }
        if record.headline.hasSuffix(line) { return nil }
        return line
    }

    // MARK: - 词表（枚举全集，逐类覆盖）

    static func subsystemWord(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "memory": return L10n.string("记忆")
        case "skills": return L10n.string("技能")
        default: return nil
        }
    }

    static func originWord(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "background_review": return L10n.string("后台复核")
        case "assistant_tool": return L10n.string("助手工具调用")
        case "oneday_app": return L10n.string("App 内操作")
        case "foreground": return L10n.string("对话中")
        default: return nil
        }
    }
}
