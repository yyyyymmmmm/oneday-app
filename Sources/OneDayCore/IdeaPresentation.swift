import Foundation

/// 点子行首 emoji 的解析口径（§177 改判，覆盖
/// §117）：图标按**内容主题**走——桥按内容选定的
/// emoji 是内容数据、优先原样呈现；桥值缺失时的兜
/// 底统一为 💡，不再按锚点来源分档。旧口径（会话
/// 💬/目标🎯/监测📡/任务✅/记忆🧠/手记✏️）把「素材
/// 从哪来」当「卡讲什么」呈现，绝大多数卡锚在会话
/// →满屏 💬，与主题图标正相反，用户 2026-11-12
/// 亲定作废。本口径只管点子页（§117.5 宪法记账：
/// 内容 emoji 不进界面图标语言）。
public enum IdeaEmoji {
    /// 桥值缺失（nil/空/纯空白）时的统一兜底
    public static let fallback = "💡"

    /// 桥值优先：去空白后非空即原样用；否则回兜底
    public static func resolve(emoji: String?) -> String {
        if let emoji {
            let trimmed = emoji.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallback
    }
}

/// 详情 sheet「包含哪些内容」小节的呈现判定（0.47.0，
/// §117）：deliverables 为空（旧记录/生成未给）时整段
/// 不出现，不摆空清单、不编交付物。
public enum IdeaDeliverablesSection {
    public static func isVisible(
        _ deliverables: [BridgeIdeaDeliverable]
    ) -> Bool {
        deliverables.contains { !$0.name.isEmpty }
    }
}

/// 点子采纳的旁聊首条上下文（0.48.0，§122）：采纳落
/// 点改开旁聊（用户亲定，覆盖 §105 的 kanban 落点）；
/// 本函数把标题／说明／依据／交付物拼成预填草稿——
/// 只进输入舱、用户点发送为准（不代发红线，与动态
/// 「讨论」的预填口径同形）。空段整段不出现，不编
/// 内容；依据只对生成卡带（与详情页依据小节同口径）
/// §209 退役标注：make() 的注入调用方已清零（开旁
/// 聊改走 IdeaQuote 引用道，见 SourceQuote.swift）；
/// 本函数保留仅作存量清扫的逐字参照（判定见
/// IdeaPrefillDraftCleanup），与 FeedDiscussPrefill
/// 同命——参照漂移即清扫误判，故不删、逐项登记于此
public enum IdeaChatPrefill {
    public static func make(
        idea: BridgeIdea, locale: Locale = AppLocale.uiLocale
    ) -> String {
        let headline = L10n.format(
            "我们来聊聊这个点子：《%@》",
            locale: locale, idea.title
        )
        let body = IdeaChatContext.body(idea: idea, locale: locale)
        guard !body.isEmpty else { return headline }
        return headline + "\n\n" + body
    }
}

/// 点子上下文载荷组装（§209）：题头之外的全部内容
/// 段——说明／依据／包含的内容，空段整段不出现、
/// 不编内容（与 IdeaChatPrefill.make 的 parts 后段
/// 逐字同口径）。IdeaChatPrefill.make（存量清扫参
/// 照）与 IdeaQuote.body（引用载荷）共用本口，两
/// 处拼装不许漂移，故收口一处
public enum IdeaChatContext {
    public static func body(
        idea: BridgeIdea, locale: Locale = AppLocale.uiLocale
    ) -> String {
        var parts: [String] = []
        if !idea.detail.isEmpty {
            parts.append(idea.detail)
        }
        if idea.source == .generated, !idea.evidence.isEmpty {
            parts.append(L10n.format(
                "依据：%@", locale: locale, idea.evidence
            ))
        }
        let items = idea.deliverables.filter { !$0.name.isEmpty }
        if !items.isEmpty {
            var block = L10n.string("包含的内容：", locale: locale)
            for item in items {
                if item.summary.isEmpty {
                    block += "\n" + L10n.format(
                        "· %@", locale: locale, item.name
                    )
                } else {
                    block += "\n" + L10n.format(
                        "· %@：%@", locale: locale,
                        item.name, item.summary
                    )
                }
            }
            parts.append(block)
        }
        return parts.joined(separator: "\n\n")
    }
}

/// 旧预填草稿的存量判定（§209）：一段草稿是否为
/// IdeaChatPrefill.make 对某点子的机器输出——三
/// 语逐一再生、任一逐字相等才算；用户改过一字即
/// 不相等、清扫不动（判定从严，与 FeedDiscuss-
/// DraftCleanup 同式）。消费点只有 SideChatStore
/// 的点子存量清扫一处
public enum IdeaPrefillDraftCleanup {
    /// 预填的历史生成语言候选（三档显式语言；
    /// 「跟随系统」生成的实际语言同样落在这三档
    /// 的某一种里）
    public static let candidateLocales: [Locale] = [
        Locale(identifier: "zh-Hans"),
        Locale(identifier: "zh-Hant"),
        Locale(identifier: "en"),
    ]

    public static func isMachinePrefill(
        _ text: String, idea: BridgeIdea
    ) -> Bool {
        candidateLocales.contains { locale in
            IdeaChatPrefill.make(
                idea: idea, locale: locale
            ) == text
        }
    }
}
