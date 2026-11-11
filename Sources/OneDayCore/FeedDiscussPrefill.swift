import Foundation

/// 动态「讨论」开聊预填（§123 M2，闭环包）：旧实现把原帖
/// 正文 prefix(1200) 硬截——截断无标记、读的人不知道后
/// 面还有，也没有回指原帖的线索。本枚举收口预填拼装：
/// - 正文不超限：全文进预填，尾行带原帖回指；
/// - 正文超限：在句界/行界截断（不切半句），节选前明
///   标「以下为原帖节选」，尾行带原帖回指；
/// - 正文为空：只有标题行，不带回指尾行（无正文可指）。
/// 回指是 App 内线索（标题＋「动态页」），不是链接——
/// 预填是纯文本草稿，能给的只有这行字，如实给全。
public enum FeedDiscussPrefill {
    /// 节选上限（与旧硬截同为 1200 字，口径不变、只补
    /// 标记与回指）
    public static let excerptLimit = 1200

    public static func make(
        title: String, body: String,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        var prefill = L10n.format(
            "我们来聊聊这篇动态：《%@》", locale: locale, title
        )
        let trimmed = body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return prefill }
        if trimmed.count <= excerptLimit {
            prefill += "\n\n" + trimmed
        } else {
            prefill += "\n\n"
                + L10n.string("（以下为原帖节选）", locale: locale)
                + "\n" + excerpt(trimmed)
        }
        prefill += "\n\n" + L10n.format(
            "（原帖全文在动态页：《%@》）", locale: locale, title
        )
        return prefill
    }

    /// 句界截断：先取上限内的前缀，若后半段里有句末
    /// （。/！/？）或换行就断在最后一个边界上；完全没
    /// 有边界才硬断（此时调用方已标明是节选）
    static func excerpt(_ body: String) -> String {
        let prefix = String(body.prefix(excerptLimit))
        let half = excerptLimit / 2
        var cutIndex: String.Index?
        for index in prefix.indices {
            let ch = prefix[index]
            if ch == "。" || ch == "！" || ch == "？" || ch == "\n" {
                if prefix.distance(
                    from: prefix.startIndex, to: index
                ) >= half {
                    cutIndex = prefix.index(after: index)
                }
            }
        }
        if let cutIndex {
            return String(prefix[..<cutIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix
    }
}
