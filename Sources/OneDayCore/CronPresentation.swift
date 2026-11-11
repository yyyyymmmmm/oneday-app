import Foundation

/// 定时任务面的原始值收口（§123 N2，闭环包）：三处原文
/// 直印改人话——①运行记录的 endReason（会话结束原因）
/// ②详情的 deliver（投递目标）③详情的 lastError（错误
/// 原文，正文位只留摘要、全文进折叠）。
///
/// 映射表口径（2026-11-11 生产实查＋Hermes 源码核对）：
/// - endReason 生产 state.db 实际 distinct 只有
///   ws_orphan_reap（13 条）与 NULL；表按 Hermes 源码里
///   end_reason 的全部赋值字面量建全集（cron_complete /
///   cron_incomplete_no_output / idle_timeout / lru_evict /
///   onboarding_restart / session_reset /
///   superseded_by_resume / tui_close / tui_shutdown /
///   ws_disconnect / compression / branched ＋既有
///   completed），未知值一律落「已结束」，不直印原值；
/// - deliver 源码值域：origin（回原对话）/ local（不投
///   递）/ log（仅记日志）/「平台:会话 id」形目标，未知
///   值落「指定渠道」，不直印原值。
public enum CronPresentation {
    /// 会话结束原因译名；nil/空串返回 nil（调用方不拼
    /// 这一段），未知值落人话兜底
    public static func endReasonLabel(
        _ raw: String?, locale: Locale = AppLocale.uiLocale
    ) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "completed", "cron_complete":
            return L10n.string("已完成", locale: locale)
        case "cron_incomplete_no_output":
            return L10n.string("已结束（没产出内容）", locale: locale)
        case "idle_timeout":
            return L10n.string("空闲超时结束", locale: locale)
        case "lru_evict":
            return L10n.string("会话被系统回收", locale: locale)
        case "onboarding_restart":
            return L10n.string("初始化重启后结束", locale: locale)
        case "session_reset":
            return L10n.string("会话已重置", locale: locale)
        case "superseded_by_resume":
            return L10n.string("已被续聊接替", locale: locale)
        case "tui_close", "tui_shutdown":
            return L10n.string("终端里关掉的", locale: locale)
        case "ws_disconnect":
            return L10n.string("连接断开后结束", locale: locale)
        case "ws_orphan_reap":
            return L10n.string("连接失效后被回收", locale: locale)
        case "compression":
            return L10n.string("上下文压缩后结束", locale: locale)
        case "branched":
            return L10n.string("已分出新会话", locale: locale)
        default:
            return L10n.string("已结束", locale: locale)
        }
    }

    /// 投递目标译名；nil/空串返回 nil（调用方不显这行）
    public static func deliverLabel(
        _ raw: String?, locale: Locale = AppLocale.uiLocale
    ) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "origin":
            return L10n.string("原对话", locale: locale)
        case "local":
            return L10n.string("不投递", locale: locale)
        case "log":
            return L10n.string("仅记日志", locale: locale)
        default:
            if let sep = raw.firstIndex(of: ":"),
               sep != raw.startIndex {
                // 「平台:会话 id」形：平台是专名（如
                // telegram），照原样给＋「对话」后缀，
                // 会话 id 是内部编号、不上行面
                let platform = String(raw[..<sep])
                return L10n.format(
                    "%@ 对话", locale: locale, platform
                )
            }
            return L10n.string("指定渠道", locale: locale)
        }
    }

    /// 错误摘要：错误原文的第一行（原文自己的话，不加
    /// 工改写），超长时在句界附近截断并带省略号；全文
    /// 由调用方放进折叠区。空/纯空白落「运行出错」兜底
    public static func errorSummary(
        _ raw: String, limit: Int = 90,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let firstLine = raw
            .split(separator: "\n", maxSplits: 1,
                   omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? raw
        let line = firstLine.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !line.isEmpty else {
            return L10n.string("运行出错", locale: locale)
        }
        guard line.count > limit else { return line }
        let prefix = String(line.prefix(limit))
        var cut = prefix
        if let idx = prefix.lastIndex(of: "。") ?? prefix.lastIndex(of: "，"),
           prefix.distance(from: prefix.startIndex, to: idx) >= limit / 2 {
            cut = String(prefix[...idx])
        }
        return cut + "…"
    }
}
