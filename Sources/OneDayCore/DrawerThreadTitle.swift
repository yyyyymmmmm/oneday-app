import Foundation

/// 抽屉旁聊行的本地线程显示名解析（0.20.0，用户
/// 2026-11-09 23:32 第三条「旁聊标题要 AI 生成」）。
///
/// 定因：本地线程的 title 在建线程后只被写过两次——
/// 导入时刻的服务端快照（SessionHistoryImport
/// .threadTitle）与首条消息发送时的首消息派生
/// （ChatView.sendMessage，title==「新会话」时取前
/// 20 字后定格）；此后服务端会话的 AI 标题（title
/// 字段、title_source=llm）再刷新也不回流本地线程，
/// 抽屉名单又只读本地 title——标题管线在「服务端
/// 标题 → 本地线程」这一环断开，抽屉永远停在派生值。
///
/// 修法口径（与服务端 resolvedTitle 同序，0.18.0
/// 管线向本地线程延伸）：本地手改名（titleIsManual）
/// ＞ 服务端标题（title_source=user 的手改与 llm
/// 生成同存于 title 字段、对本地派生快照一律优先）
/// ＞ 本地标题（导入快照/首消息派生）。纯本地线程
/// （无关联服务端会话）serverTitle 恒 nil、自然回
/// 落本地标题。手改标记为准：手改过的本地名永不被
/// 服务端标题覆盖（与服务端 user 标题永不被人覆盖
/// 同一红线）。
public enum DrawerThreadTitle {
    public static func resolve(
        localTitle: String,
        titleIsManual: Bool,
        serverTitle: String?
    ) -> String {
        if titleIsManual {
            return localTitle
        }
        if let serverTitle {
            let trimmed = serverTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return localTitle
    }
}
