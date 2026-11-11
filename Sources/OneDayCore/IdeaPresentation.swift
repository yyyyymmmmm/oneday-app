import Foundation

/// 点子行首 emoji 的解析口径（0.47.0，§117）：桥按内
/// 容选定的 emoji 是内容数据、优先原样呈现；旧记录没
/// 有时按锚点 kind 给缺省——手记恒 ✏️，生成卡按素材
/// 来源分（会话💬/目标🎯/监测📡/任务✅/记忆🧠），解
/// 不出锚点时回 💡。本口径只管点子页（§117.5 宪法记
/// 账：内容 emoji 不进界面图标语言）。
public enum IdeaEmoji {
    /// 桥值优先：非空（去空白后）即原样用
    public static func resolve(
        emoji: String?,
        evidenceRef: String?,
        anchorId: String?,
        source: IdeaSource
    ) -> String {
        if let emoji {
            let trimmed = emoji.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallback(
            kind: kind(evidenceRef: evidenceRef, anchorId: anchorId),
            source: source
        )
    }

    /// 锚点 kind：anchorId（跨轮真锚）优先、evidenceRef
    /// （轮内编号）兜底；都解不出为 nil
    public static func kind(
        evidenceRef: String?, anchorId: String?
    ) -> IdeaMaterialKind? {
        if let anchor = IdeaAnchor(anchorId: anchorId) {
            return anchor.kind
        }
        if let anchor = IdeaAnchor(evidenceRef: evidenceRef) {
            return anchor.kind
        }
        return nil
    }

    public static func fallback(
        kind: IdeaMaterialKind?, source: IdeaSource
    ) -> String {
        if source == .manual {
            return "✏️"
        }
        switch kind {
        case .session: return "💬"
        case .goal: return "🎯"
        case .monitor: return "📡"
        case .kanban: return "✅"
        case .memory: return "🧠"
        case .unknown, nil: return "💡"
        }
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
