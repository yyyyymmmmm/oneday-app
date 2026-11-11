import Foundation
import OneDayCore
import SwiftData

/// 审批锚定条目物化（§156，规格 §4.2）：共享审批 store
/// 每次刷新（枢纽 loadApproval／聊天 refreshApproval-
/// ForChat）成功拿到 pending 现态后触发一次——按 Core
/// ApprovalAnchor.plan 把带锚且本机有对应线程的记录落
/// 成锚定条目，并回写两份 store 侧派生状态：
/// - anchoredRecordIDs（全 App 已落锚记录集）：流末尾
///   区排除与「单源」呈现的依据；
/// - anchorMissCounts（已落锚记录的连续缺席轮数）：
///   锚定行的「已失效」判定（满两轮才转，见 Core）。
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
///   拉成功后触发），缺席计数不被网络失败污染。
@MainActor
enum ApprovalAnchorMaterialization {
    /// 触发资格＝store 已进 ready 态（pending 本轮拉成
    /// 功的同义反复——loadApproval/refreshApprovalFor-
    /// Chat 只在成功路径置 ready，失败/未接通不触发，
    /// 缺席计数不被网络失败污染）
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
        // 回溯已决走大窗口拉取（store 侧缓存，本步只在
        // 其就绪后消费——首轮未就绪时 decisions 以日常
        // 历史代用，带锚回溯随缓存到位后的刷新补齐）
        let decisions = store.anchorDecisions
            ?? store.decisionHistory
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
        // 派生状态回写（store 观察面，ChatApprovalZone
        // 与锚定行渲染消费）
        store.anchoredRecordIDs = ApprovalAnchor.anchoredRecordIDs(
            keys: existingKeys
        )
        var misses = store.anchorMissCounts
        let presentIDs = Set(pending.map(\.id))
            .union(decisions.map(\.id))
        for key in existingKeys {
            guard let recordID = ApprovalAnchor.recordID(fromKey: key)
            else { continue }
            misses[key] = ApprovalAnchor.missCountAfterRefresh(
                previous: misses[key] ?? 0,
                present: presentIDs.contains(recordID)
            )
        }
        store.anchorMissCounts = misses
    }
}
