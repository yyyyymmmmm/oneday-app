import Foundation

/// GD-3 简报呈现纯函数（列表摘要 / 信件周次）与
/// GD-2 未归类面的来源文案。只做呈现拼装，不碰
/// 网络与存储；周次与摘要的口径由单测钉死
public enum BriefingPresentation {

    /// 列表行摘要：正文首句，至多 limit 字。
    /// 取法：正文先按段落切，取第一段非空文本；
    /// 再截到第一个句末标点（。！？.!?，含标点）
    /// ——首句本身超限时按字数截断并加省略号。
    /// 空正文回空串（行上只剩标题与日期，不造占位）
    public static func summary(of body: String, limit: Int = 40) -> String {
        let firstParagraph = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !firstParagraph.isEmpty else { return "" }
        var sentence = firstParagraph
        if let end = firstParagraph.firstIndex(where: {
            "。！？.!?".contains($0)
        }) {
            sentence = String(firstParagraph[...end])
        }
        guard sentence.count > limit else { return sentence }
        return String(sentence.prefix(limit)) + "…"
    }

    /// 第 N 周：这封信是该目标的第几封简报（按
    /// createdAt 升序计，首封＝第 1 周）。入参可为
    /// 任意顺序（桥下发为降序，函数内部自排序）；
    /// createdAt 相同以 id 定序，保证结果稳定。
    /// id 不在列表里回 nil（称呼行就不提周次）
    public static func weekIndex(
        of briefingID: String, in briefings: [BridgeBriefing]
    ) -> Int? {
        let ordered = briefings.sorted {
            ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
        }
        guard let position = ordered.firstIndex(where: {
            $0.id == briefingID
        }) else { return nil }
        return position + 1
    }
}

/// GD-2 未归类任务的来源文案（列表行小字）。来源
/// 只认桥侧登记（采纳/对话派发），呈现层不猜
public enum UngroupedTaskPresentation {

    public static func originLabel(
        _ origin: BridgeUngroupedTask.Origin
    ) -> String {
        switch origin {
        case .adopted: return L10n.string("来自点子采纳")
        case .chat: return L10n.string("来自对话安排")
        }
    }
}
