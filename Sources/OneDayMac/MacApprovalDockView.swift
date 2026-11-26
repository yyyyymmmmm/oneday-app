import SwiftUI
import OneDayCore
import OneDayDesign

/// 聊天停靠区（棒 2，对位 #18；与 iOS v3 定版同
/// 构）：固定在输入栏上方、原地换内容、顶部标待批
/// 进度、一次只活一张——活卡取本会话待批队列第一
/// 条（写闸走 Core ApprovalZoneQueue 派生口径：先
/// 进先审；执行批准同法取最先一条），其余收成计
/// 数。两族都有待批时先写闸后执行（与 App 卡面先
/// 后同序：写入审批是聊天内生卡，执行批准随后）。
struct MacApprovalDockView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: MacApprovalStore
    let sessionID: String?

    var body: some View {
        let gateQueue = store.gatePending(forSessionID: sessionID)
        let execQueue = store.execPending(forSessionID: sessionID)
        let total = gateQueue.count + execQueue.count
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                progressRow(
                    total: total,
                    gateCount: gateQueue.count,
                    execCount: execQueue.count
                )
                if let record = gateQueue.first {
                    MacWriteGateCardView(
                        record: record,
                        note: store.cardNotes[record.id],
                        isDeciding: store.decidingIDs.contains(record.id),
                        onApprove: {
                            Task {
                                await store.decideGate(
                                    record, approve: true, session: session
                                )
                            }
                        },
                        onAlways: {
                            Task {
                                await store.decideAlways(
                                    record, session: session
                                )
                            }
                        },
                        onReject: {
                            Task {
                                await store.decideGate(
                                    record, approve: false, session: session
                                )
                            }
                        }
                    )
                } else if let record = execQueue.first {
                    MacExecApprovalCardView(
                        record: record,
                        isDeciding: store.decidingIDs.contains(record.id),
                        onDecide: { choice in
                            Task {
                                await store.decideExec(
                                    record, choice: choice,
                                    session: session
                                )
                            }
                        }
                    )
                }
                if let toast = store.alwaysAllowToast {
                    alwaysAllowToastRow(toast)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.05))
        }
    }

    /// 进度行：待批总数＋构成＋打开批准面入口
    private func progressRow(
        total: Int, gateCount: Int, execCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.orange)
            Text("待批 \(total) 件")
                .font(.callout.weight(.semibold))
            if gateCount > 0 {
                Text("写入 \(gateCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if execCount > 0 {
                Text("命令 \(execCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("全部待批") {
                openWindow(id: "approvals")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    /// 「总是允许」轻通知（可撤销、5 秒自动收起，与
    /// iOS 同语义：撤销只删规则、不回滚已批准那条）
    private func alwaysAllowToastRow(
        _ toast: MacAlwaysAllowToast
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("已批准 · 已记住这一类（\(toast.scopeLabel)）")
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("撤销") {
                Task { await store.undoAlwaysAllow(session: session) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button {
                store.dismissAlwaysAllowToast()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
