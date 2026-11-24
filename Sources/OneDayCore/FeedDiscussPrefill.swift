import Foundation

/// 动态「讨论」开聊预填（§123 M2，闭环包）。
///
/// **§208 退役注**：注入路径已退役——讨论改走引用
/// （FeedPostQuote＋种子暂存道），不再经 setDraft 把
/// 本拼装写进草稿账（预填与亲笔在草稿账里同形、被
/// 防丢稿保活永久保护，用户 2026-11-13 点名）。
/// make() 本体保留**仅作存量清扫的逐字参照**：
/// FeedDiscussDraftCleanup 拿它对原帖再生、与落盘
/// 旧草稿逐字比对，相等才清；清扫使命结束（后续
/// 版本确认无存量）后本枚举连同清扫一并删除。现
/// 行代码不许再有任何调用方拿 make() 的输出做注
/// 入（setDraft 隔离铁律见 SideChatStore 与
/// DESIGN §208）。
///
/// 旧实现把原帖正文 prefix(1200) 硬截——截断无标
/// 记、读的人不知道后面还有，也没有回指原帖的线
/// 索。本枚举收口预填拼装：
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
