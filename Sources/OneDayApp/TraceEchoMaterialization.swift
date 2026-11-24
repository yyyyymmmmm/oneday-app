import Foundation
import OneDayCore
import SwiftData

/// 留痕回响物化（§229）：聊天页每轮留痕刷新成功后
/// 触发一次——按 Core TraceEchoMaterialization.plan
/// 把作用域内还没落过盘的留痕落成回响条目，落进当
/// 前线程的消息流（与 §165 ApprovalAnchorMateri-
/// alization 同构的执行件：Core 只规划、本件只落盘）。
///
/// 纪律：
/// - 去重按线程：existingKeys 只取目标线程既有条目
///   的 traceKey——同一留痕在主线（总账面）与它指
///   向的旁聊（出生卡面）各落一条（旧呈现的双面可
///   见语义），同线程内永不重复，已物化过的旧回响
///   不重出；
/// - 条目 createdAt 改写为留痕的事件时间：sorted-
///   Entries 按它排序，条目落进事件发生的那一轮、
///   新消息自然顶上去，不再恒挂流尾；
/// - thread.updatedAt 不动：物化不是用户活动，不
///   许把老对话顶到抽屉前列（同 §165 纪律）；
/// - 只由刷新成功路径触发（拉取失败保留旧值、不
///   调用本步），桥一时不通不污染条目面。
@MainActor
enum TraceEchoMaterializationRunner {
    static func run(
        traces: [BridgeTrace],
        thread: ChatThread,
        isMainThread: Bool,
        agentName: String,
        context: ModelContext
    ) {
        let existingKeys = Set(
            thread.entries.compactMap(\.traceKey)
        )
        let planned = TraceEchoMaterialization.plan(
            traces: traces,
            isMainThread: isMainThread,
            currentServerSessionID: thread.serverSessionID,
            existingKeys: existingKeys,
            agentName: agentName
        )
        guard !planned.isEmpty else { return }
        for item in planned {
            let entry = ChatEntry(
                role: "assistant",
                content: item.snapshot.headline,
                thread: thread,
                traceKey: item.key,
                traceSnapshot: item.snapshot
            )
            entry.createdAt = item.createdAt
            context.insert(entry)
        }
        try? context.save()
    }
}
