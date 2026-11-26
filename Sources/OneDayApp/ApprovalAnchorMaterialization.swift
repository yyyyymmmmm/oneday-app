import Foundation
import OneDayCore
import SwiftData

/// 审批锚定条目物化（§165，规格 §4.2）：共享审批 store
/// 每次刷新（枢纽 loadApproval／聊天 refreshApproval-
/// ForChat）成功拿到 pending 现态后触发一次——按 Core
/// ApprovalAnchor.plan 把带锚且本机有对应线程的记录落
/// 成锚定条目，并回写已落锚记录集供审批区去重。
///
/// 纪律：
/// - 找不到绑定该服务端会话的本地线程 → 不物化、不
///   建空线程（与 GoalEcho 同口径）；anchor 为 nil 的
///   记录 plan 恒不收，行为退回现行形态；
/// - 冻结：plan 以全线程既有 approvalKey 为 existing-
///   Keys，已落锚的记录永不再规划——后续 anchor 变
///   null/变会话都不迁移；
/// - 条目 createdAt 改写为记录 created_at：sorted-
///   Entries 按它排序，条目落进发起那一轮的位置；
///   thread.updatedAt 不动（物化不是用户活动，不许
///   把老对话顶到抽屉前列）；
/// - 桥错误/未接通时不调用本步（调用方只在 pending
///   拉成功后触发）。
@MainActor
enum ApprovalAnchorMaterialization {
    static func run(store: AgentHubStore, context: ModelContext) {
        guard case .ready(let pending) = store.approvalState
        else { return }
        let threads = (try? context.fetch(
            FetchDescriptor<ChatThread>()
        )) ?? []
        var threadIDBySession: [String: UUID] = [:]
        var threadByID: [UUID: ChatThread] = [:]
        var existingKeys: Set<String> = []
        for thread in threads {
            threadByID[thread.id] = thread
            if let sessionID = thread.serverSessionID,
               !sessionID.isEmpty {
                threadIDBySession[sessionID] = thread.id
            }
            for entry in thread.entries {
                if let key = entry.approvalKey {
                    existingKeys.insert(key)
                }
            }
        }
        // 已决集读 store 单源合成面（§259：近窗∪宽窗
        // 一处合成；旧「宽窗就绪只读宽窗、未就绪以近
        // 窗代用」的二选一口径退役——合成集只增不减，
        // 带锚回溯随任一窗到位即在本轮补齐）
        let decisions = store.decidedRecords
        let planned = ApprovalAnchor.plan(
            pending: pending, decisions: decisions,
            existingKeys: existingKeys, now: Date()
        )
        var didInsert = false
        for item in planned {
            guard let threadID = threadIDBySession[item.sessionID],
                  let thread = threadByID[threadID]
            else { continue }
            let entry = ChatEntry(
                role: "assistant", content: item.headline,
                thread: thread, approvalKey: item.key
            )
            entry.createdAt = item.createdAt
            context.insert(entry)
            existingKeys.insert(item.key)
            didInsert = true
        }
        if didInsert {
            try? context.save()
        }
        store.anchoredRecordIDs = ApprovalAnchor.anchoredRecordIDs(
            keys: existingKeys
        )
    }
}
