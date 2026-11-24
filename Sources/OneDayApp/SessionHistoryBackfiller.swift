import Foundation
import OneDayCore
import SwiftData

/// 导入落盘单点（§331 自 ChatView.insertImported-
/// Entries 收口）：富内容项 → ChatEntry 的组装只此
/// 一份——导入首开（ChatView 分页路）与后台回补
/// （SessionHistoryBackfiller）共用，组装口径漂移
/// 无处藏。口径（0.8.0 P1 不变）：工具调用成卡、
/// 图片标记剥成路径、服务端时刻落 createdAt；工
/// 具卡 role="tool" 不进发送上下文（send 组装只
/// 取 user/assistant 正文）。
enum SessionHistoryInserter {
    /// 一页原始消息落盘（导入首开口径：不过滤、全
    /// 落——去重在消息 id 层由调用方先行）
    @discardableResult
    static func insert(
        messages: [SessionMessage], into thread: ChatThread,
        context: ModelContext
    ) -> Int {
        insert(
            items: SessionHistoryImport.richItems(from: messages),
            into: thread, context: context
        )
    }

    /// 富内容项落盘（回补口径：指纹过滤在调用方，
    /// 此处只管组装插入）
    @discardableResult
    static func insert(
        items: [SessionHistoryImport.RichItem],
        into thread: ChatThread, context: ModelContext
    ) -> Int {
        for item in items {
            let chatEntry = ChatEntry(
                role: item.role, content: item.content,
                thread: thread, toolCard: item.toolCard,
                remoteImagePaths: item.imagePaths,
                remoteFilePaths: item.fileRefs
            )
            if let date = item.date {
                chatEntry.createdAt = date
            }
            // 台账 187：落盘同点钉桩＋反应镜像（坐标
            // 与真源镜像随条目出生即在位，呈现构建时
            // 同步已知、无异步补钉翻转）
            chatEntry.serverRowID = item.serverRowID
            // 收敛包（P3-1）：引用槽位随落盘回填——
            // 正文已是拆净的干净正文，引用走槽位呈
            // 现，不再把线格式原文直写 content
            if let quote = item.quote {
                chatEntry.quoteRole = quote.role
                chatEntry.quoteContent = quote.content
            }
            chatEntry.applyReactions(item.reactions)
            context.insert(chatEntry)
        }
        return items.count
    }

    /// 回补对账（台账 187）：拉回项与既有条目按回补
    /// 指纹配对——命中且未钉桩则补钉 serverRowID；
    /// 反应镜像恒以服务端值覆写（真源覆写自愈，
    /// applyReactions 同值不落写）。同指纹多条目按
    /// 序逐个配对（队列消费）：一条项只配一条目，
    /// 不许覆写两处。指纹口径与去重同源（Session-
    /// HistorySync.fingerprint），不另起配对口径
    static func reconcileReactions(
        items: [SessionHistoryImport.RichItem],
        entries: [ChatEntry]
    ) {
        var byFingerprint: [HistoryFingerprint: [ChatEntry]] = [:]
        for entry in entries {
            byFingerprint[fingerprint(of: entry), default: []]
                .append(entry)
        }
        for item in items {
            guard let rowID = item.serverRowID else { continue }
            let print = SessionHistorySync.fingerprint(of: item)
            guard var queue = byFingerprint[print],
                  !queue.isEmpty
            else { continue }
            let entry = queue.removeFirst()
            byFingerprint[print] = queue
            if entry.serverRowID == nil {
                entry.serverRowID = rowID
            }
            entry.applyReactions(item.reactions)
        }
    }

    /// 本地条目 → 回补指纹（组装单点在 Core
    /// SessionHistorySync.fingerprint(role:…)，本
    /// 处只喂零件：干净正文＋引用槽位＋附件路径
    /// 集——与拉回项同口径，见 P4-1）
    static func fingerprint(
        of entry: ChatEntry
    ) -> HistoryFingerprint {
        SessionHistorySync.fingerprint(
            role: entry.role, date: entry.createdAt,
            content: entry.content, quote: entry.quote,
            attachmentPaths: entry.remoteImagePaths
                + entry.remoteFilePaths,
            toolCardID: entry.toolCard?.id
        )
    }

    /// 存量收敛（收敛包，2026-11-24）：修复前落盘的
    /// 线格式原文行在下一次回补时就地治，不等新数据
    /// 触发。两步：
    /// ①原地规范化：user 行、无引用槽位、正文能拆出
    /// 引用块的（修复前回补落的原文行），就地拆回
    /// （干净正文＋引用槽位）；单行无孪生也治——换
    /// 机导入的孤行靠这步回正呈现；
    /// ②同指纹合并：指纹全等的条目只留一条。留存
    /// 序：有引用槽位者胜（结构在位）→ serverRowID
    /// 在位者胜（服务端锚）→ createdAt 早者胜。被
    /// 并条目的 serverRowID 转移给留存者（留存者已
    /// 有则不动）；反应镜像只在留存者为空时接（两
    /// 行同为一服务端行的镜像，下轮对账恒以服务端
    /// 真源覆写自愈，不在此拼凑）；被并条目删除。
    /// 同一性定义与去重同源：指纹即 unseenItems 的
    /// 判同口径——系统本就把同指纹两行视作同一行，
    /// 合并只是把既成定义落到存量数据上，不新造判
    /// 断。返回删除条数（观测/钉测用）
    @discardableResult
    static func convergeStockDuplicates(
        entries: [ChatEntry], context: ModelContext
    ) -> Int {
        // ① 原地规范化（校验集＝本线程各行正文：被
        // 引消息多半同线程在场）
        let knownQuoteTexts = Set(entries.map(\.content))
        for entry in entries
        where entry.role == "user" && entry.quote == nil {
            guard let parsed = MessageQuote.parse(
                wireContent: entry.content,
                knownQuoteTexts: knownQuoteTexts
            ) else { continue }
            entry.content = parsed.body
            entry.quoteRole = parsed.quote.role
            entry.quoteContent = parsed.quote.content
        }
        // ② 同指纹合并＋删除被并条目
        var groups: [HistoryFingerprint: [ChatEntry]] = [:]
        for entry in entries {
            groups[fingerprint(of: entry), default: []]
                .append(entry)
        }
        var removed = 0
        for group in groups.values where group.count > 1 {
            let ranked = group.sorted { lhs, rhs in
                if (lhs.quote != nil) != (rhs.quote != nil) {
                    return lhs.quote != nil
                }
                if (lhs.serverRowID != nil)
                    != (rhs.serverRowID != nil) {
                    return lhs.serverRowID != nil
                }
                return lhs.createdAt < rhs.createdAt
            }
            let keeper = ranked[0]
            for duplicate in ranked.dropFirst() {
                if keeper.serverRowID == nil {
                    keeper.serverRowID = duplicate.serverRowID
                }
                if keeper.reactions.isEmpty,
                   !duplicate.reactions.isEmpty {
                    keeper.applyReactions(duplicate.reactions)
                }
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }
}

/// 历史回补一轮的结果：complete＝分页拉尽且处理
/// 量对齐服务端总数；partial＝中途失败/处理量未
/// 对齐，已落部分保留、待下轮续补；failed＝一页
/// 都没拉动（多为未登录/未连接，状态原样待触发）
enum HistoryPullOutcome: Equatable {
    case complete
    case partial
    case failed
}

/// 服务端历史后台回补（根治版包 2，DESIGN §331）：
/// §190 大厂对位——历史是渐进补齐的后台义务、不
/// 是打开/发送的前置（Muse／ChatGPT 同形态：
/// 先给可用会话、历史随后到齐）。一轮＝从头分页
/// 全拉（order=latest），逐页按指纹去重落盘到既
/// 有线程；指纹对账使重拉天然幂等：已落条目不重
/// 复落、分页窗口漂移不丢不重。状态落线程三字段
/// （historyUnsynced/historyServerCount/history-
/// LoadedCount），呈现层据此安静标记、不弹窗。
@MainActor
final class SessionHistoryBackfiller {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// 回补一轮。调用方负责触发时机与防重入（同一
    /// 线程同时只许一轮）；本函数只管拉与落
    @discardableResult
    /// 选择框播种收尾（§441）：候选行已落本地线
    /// 程且其后无 user 条目才入覆盖层——服务端是
    /// 唯一真源，本机只持瞬态呈现；线程尾位已变
    /// （本地更新）则不播种，失效侧安全
    private func finalizeOptionsSeed(
        thread: ChatThread,
        candidate: (serverRowID: Int, options: MessageOptions)?
    ) {
        guard let candidate else { return }
        let entries = thread.sortedEntries
        guard let index = entries.firstIndex(where: {
            $0.serverRowID == candidate.serverRowID
        }), !entries[(index + 1)...].contains(where: {
            $0.role == "user"
        }) else { return }
        appState.optionsOverlay.seed(
            threadID: thread.id,
            card: .init(
                serverRowID: candidate.serverRowID,
                options: candidate.options
            )
        )
    }

    func backfill(
        thread: ChatThread, context: ModelContext
    ) async -> HistoryPullOutcome {
        guard let sessionID = thread.serverSessionID,
              !sessionID.isEmpty,
              !SideChatLink.isMergeBucket(sessionID),
              appState.config != nil
        else { return .failed }
        // 分母先行：回读会话行刷新服务端总数（失败
        // 不拦拉取——总数未知时以分页拉尽判齐）
        if let session = try? await appState.performAdmin(
            { client, config in
                try await client.serverSession(
                    config: config, id: sessionID
                )
            }
        ) {
            thread.historyServerCount = session.messageCount ?? 0
        }
        var offset = 0
        var processed = 0
        // 台账 117 降级（§389）：分页被服务端以 400
        // invalid_pagination 拒时，本轮只许降级一次
        // 无参全量拉取（与打开链 §331 首屏降级同口
        // 径）；全量也失败才走既有部分/失败收尾
        var paginationFallbackUsed = false
        // 一页（或全量降级的一整批）的落盘单点：对账
        // →指纹去重→落新项，分页与降级共用、不许两
        // 份实现漂移
        // §441：选择框播种候选——逐页按尾位规则
        // 更新（后页更新、末页为准）；收尾时再对
        // 本地线程尾位复核才入覆盖层
        var seedCandidate: (serverRowID: Int, options: MessageOptions)?
        func ingest(_ page: [SessionMessage]) {
            let ordered = SessionHistoryPagePlanner
                .chronological(page)
            seedCandidate = OptionsCardLogic
                .seedCandidate(in: ordered)
            let items = SessionHistoryImport.richItems(
                from: ordered
            )
            // 台账 187：先对账（既有条目补钉＋镜像覆
            // 写）再落新项——新项落盘自带钉桩/镜像，
            // 不走对账口（防同页内自配）
            SessionHistoryInserter.reconcileReactions(
                items: items, entries: thread.entries
            )
            let existing = Set(thread.entries.map {
                SessionHistoryInserter.fingerprint(of: $0)
            })
            let unseen = SessionHistorySync.unseenItems(
                items, existing: existing
            )
            SessionHistoryInserter.insert(
                items: unseen, into: thread, context: context
            )
            // 收敛包：存量原文行/重复行每页落盘后顺
            // 手收敛（原地规范化＋同指纹合并）——修
            // 复前落的账不许等新数据触发才治；下方
            // 计数在收敛后取、据实
            SessionHistoryInserter.convergeStockDuplicates(
                entries: thread.entries, context: context
            )
            processed += page.count
            // 进度分子＝本地现有条目数（用户屏幕上实
            // 有的量）；处理量只作下方对齐判据
            thread.historyLoadedCount = thread.entries.count
            try? context.save()
        }
        while true {
            let page: [SessionMessage]
            do {
                page = try await appState.performAdmin { client, config in
                    try await client.sessionMessagesPage(
                        config: config, id: sessionID,
                        limit: SessionHistoryPagePlanner.pageSize,
                        offset: offset
                    )
                }
            } catch {
                // 台账 117：分页契约被拒（400 invalid_
                // pagination）先降级全量——服务端分页
                // 口径漂移不许让历史回补整轮瘫痪
                if !paginationFallbackUsed,
                   let hermesError = error as? HermesError,
                   hermesError.isPaginationRejected,
                   let full = try? await appState.performAdmin(
                       { client, config in
                           try await client.sessionMessages(
                               config: config, id: sessionID
                           )
                       }
                   ) {
                    paginationFallbackUsed = true
                    ingest(full)
                    break
                }
                // 降级口径：已落部分保留、未同步标记
                // 在位，整段失败呈现就此退役（§331）
                thread.historyUnsynced = true
                thread.historyLoadedCount = thread.entries.count
                try? context.save()
                finalizeOptionsSeed(thread: thread, candidate: seedCandidate)
                return processed > 0 ? .partial : .failed
            }
            ingest(page)
            guard let next = SessionHistoryPagePlanner.nextOffset(
                currentOffset: offset, receivedCount: page.count
            ) else { break }
            offset = next
        }
        finalizeOptionsSeed(thread: thread, candidate: seedCandidate)
        // 拉齐判据：分页已尽，且处理量对齐已知总数
        // （总数未知时以拉尽为准）。未对齐多因拉取
        // 期间会话又长了——保持未同步、下轮再对账
        if thread.historyServerCount == 0
            || processed >= thread.historyServerCount {
            thread.historyUnsynced = false
            thread.historyLoadedCount = thread.entries.count
            try? context.save()
            return .complete
        }
        thread.historyUnsynced = true
        try? context.save()
        return .partial
    }
}
