import Foundation

/// 会话历史双向同步的纯判定（根治版包 2，DESIGN
/// §331）：发送解门后，历史不再是发送前置——服务
/// 端→本地靠后台分页回补、本地→服务端靠后台种子
/// 同步，两条都只剩「状态记账」问题。本文件收两件
/// 纯函数面：种子同步态的枚举口径、回补落盘的指纹
/// 去重。网络与落盘动作在 App 层（SessionHistory-
/// Backfiller / SessionSeedSyncer）。

/// 种子同步态（本地独有历史上行的义务账）：
/// - notOwed：无种子义务——线程出生即带服务端历
///   史（导入线程）或从未攒过本地独有历史；
/// - pending：待导入——义务在册、后台任务未跑或
///   排队中；
/// - importing：导入中；
/// - syncedTextOnly：种子已落定。种子转录天生只
///   留 user/assistant 纯文本（SideChatLink.seed-
///   Transcript 口径），落定即「仅文本」——与服务
///   端回补的全量历史严格区分、不许冒充全量；
/// - serverHeld：服务端已持该会话历史（认领/回读
///   确认），种子义务消解；
/// - localOnly：服务端已另有新内容（回读计数 >0
///   且非种子所落），种子不再上行——本地历史仅
///   保存在本机，如实标记、不许静默当已同步；
/// - failed：导入失败待重试（原因另有留痕面）。
public enum SeedSyncState: String, Equatable, Sendable {
    case notOwed
    case pending
    case importing
    case syncedTextOnly
    case serverHeld
    case localOnly
    case failed

    /// 落盘原文 → 态：未知原文一律回 notOwed（旧库
    /// 无此字段/原文损坏时不许把义务凭空造出来）
    public init(storedValue: String?) {
        self = storedValue.flatMap(
            SeedSyncState.init(rawValue:)
        ) ?? .notOwed
    }

    /// 本态下种子是否还欠一轮同步尝试（调度触发点
    /// 的统一判据：待导入与失败待重试才排队）
    public var needsSyncAttempt: Bool {
        self == .pending || self == .failed
    }
}

/// 回补落盘指纹（服务端历史 → 既有本地线程的去重
/// 键）：角色＋服务端时刻（epoch 秒取整）＋正文＋
/// 附件路径集＋工具卡 id。拉回的富内容项（Session-
/// HistoryImport.RichItem）与本地已落盘条目（Chat-
/// Entry）两侧按同一口径组装才可比——组装函数只
/// 收零件、两侧各自喂入，口径漂移无处藏。
public struct HistoryFingerprint: Hashable, Sendable {
    public let role: String
    public let epochSeconds: Int
    public let content: String
    public let attachmentPaths: [String]
    public let toolCardID: String?

    public init(
        role: String, date: Date?, content: String,
        attachmentPaths: [String], toolCardID: String?
    ) {
        self.role = role
        // 无服务端时刻的条目以 0 记：这类条目回补重
        // 拉时同样无时刻、指纹仍可比；本地落盘时刻
        // 是插入时刻、与 0 不等——故无时刻条目在重
        // 补时可能重复落一次，是已知边界（服务端消
        // 息恒带时间戳，此路只在桩/异常数据上出现）
        self.epochSeconds = date.map {
            Int($0.timeIntervalSince1970.rounded())
        } ?? 0
        self.content = content
        self.attachmentPaths = attachmentPaths
        self.toolCardID = toolCardID
    }
}

public enum SessionHistorySync {
    /// 拉回项 → 指纹（富内容项口径：附件集＝图片＋
    /// 文件引用，工具卡以其稳定 id 记）
    public static func fingerprint(
        of item: SessionHistoryImport.RichItem
    ) -> HistoryFingerprint {
        HistoryFingerprint(
            role: item.role, date: item.date,
            content: item.content,
            attachmentPaths: item.imagePaths + item.fileRefs,
            toolCardID: item.toolCard?.id
        )
    }

    /// 一批拉回项里本地还没有的（回补落盘的过滤
    /// 口：已落盘指纹集由调用方从线程条目组装；批
    /// 内自重也一并去重——分页边界重叠页同理）
    public static func unseenItems(
        _ items: [SessionHistoryImport.RichItem],
        existing: Set<HistoryFingerprint>
    ) -> [SessionHistoryImport.RichItem] {
        var seen = existing
        return items.filter { item in
            let print = fingerprint(of: item)
            guard !seen.contains(print) else { return false }
            seen.insert(print)
            return true
        }
    }

    /// 回补进度文案口径：分子＝本地现有条目数、分
    /// 母＝服务端原始消息总数（含工具/系统行，与分
    /// 子不同单位）——两数分开报、不许拼成同单位
    /// 比例冒充精确进度；总数未知（0）时只报已载入
    public static func progressText(
        loaded: Int, serverTotal: Int
    ) -> String {
        if serverTotal > 0 {
            return "已载入 \(loaded) 条（服务端共 \(serverTotal) 条）"
        }
        return "已载入 \(loaded) 条"
    }
}
