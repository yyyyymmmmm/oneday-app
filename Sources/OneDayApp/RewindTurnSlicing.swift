import Foundation

/// D3/D2 的轮次切分纯函数（DESIGN §352）：rewind 的
/// 目标/段/计数全部在此单点裁决——ChatView 的编辑
/// 重发与重新生成两条流共用，不许各写一份（切错一
/// 格＝截错一轮）。输入恒为 thread.sortedEntries
/// （时序正序）；条目身份以 id 比对、行 id 以
/// serverRowID 为准
enum RewindTurnSlicing {

    /// target 条目在正序条目列中的下标（不在列返回
    /// nil，调用方据此放弃整条流）
    static func index(
        of entryID: UUID, in entries: [ChatEntry]
    ) -> Int? {
        entries.firstIndex { $0.id == entryID }
    }

    /// target 起至尾的全部条目（D3 乐观隐藏集＋
    /// rewind 成功后的存储真删集，同一份名单两用）
    static func tail(
        from entryID: UUID, in entries: [ChatEntry]
    ) -> [ChatEntry] {
        guard let idx = index(of: entryID, in: entries)
        else { return [] }
        return Array(entries[idx...])
    }

    /// target 之前最近一条已钉桩条目的服务端行 id
    /// （rewind 对账的尾行期望值）；无已钉桩前行返回
    /// nil——语义是「截断后服务端应为空尾」，与客户
    /// 端对账口径（predecessorRowID=nil＝尾为空）同
    static func predecessorRowID(
        before entryID: UUID, in entries: [ChatEntry]
    ) -> Int? {
        guard let idx = index(of: entryID, in: entries)
        else { return nil }
        return entries[..<idx].last {
            $0.serverRowID != nil
        }?.serverRowID
    }

    /// target 之后已落定 user 条目数＝编辑非末轮确认
    /// 弹窗的「共 {N} 轮」（DESIGN §352 §五：将被删
    /// 除的轮数实算——只数 user 行、一行一轮；工具/
    /// 助手行是轮内成分不另计）。target 本身是最后
    /// 一条 user 条目时为 0＝不弹确认、直走
    static func roundsAfter(
        target entryID: UUID, in entries: [ChatEntry]
    ) -> Int {
        guard let idx = index(of: entryID, in: entries)
        else { return 0 }
        return entries[(idx + 1)...].filter {
            $0.role == "user"
        }.count
    }

    /// 本线程最后一条已落定助手条目（D2 入口的呈现
    /// 时刻判定）：正序扫描取最后一条过条目级门控
    /// （canRegenerateCandidate）的 assistant 行
    static func lastSettledAssistant(
        in entries: [ChatEntry]
    ) -> ChatEntry? {
        entries.last { $0.canRegenerateCandidate }
    }

    /// D2 的一轮切分：给定末条助手条目 → 其轮 user
    /// 条目（向前最近一条 user 行）＋助手段（user
    /// 条目之后至尾的全部条目，含目标助手条目本
    /// 人）。user 条目未钉桩（serverRowID=nil）→
    /// nil：rewind 无的放矢、整条流不出（服务端只
    /// 认本会话 active 的 user 行 id，绝不允许拿助
    /// 手行 id 顶替——服务端必拒 invalid_params）
    static func regenerationTurn(
        assistant entryID: UUID, in entries: [ChatEntry]
    ) -> (user: ChatEntry, segment: [ChatEntry])? {
        guard let aIdx = index(of: entryID, in: entries),
              let user = entries[..<aIdx].last(where: {
                  $0.role == "user"
              }),
              user.serverRowID != nil,
              let uIdx = index(of: user.id, in: entries)
        else { return nil }
        return (user, Array(entries[(uIdx + 1)...]))
    }
}
