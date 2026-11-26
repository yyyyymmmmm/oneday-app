import SwiftUI
import OneDayCore

/// 菜单栏状态店（棒 1，对位 M1 基础形态；棒 2 扩
/// 待批口径）：连接四态（Core ConnectionStatus 同
/// 口径：未连接/连接中/已连接/联系不上）＋待批数
/// （两族真待批：执行批准 pending＋写闸 pending，
/// 棒 1 的宽容计数把已决记录也算在内、棒 2 按逐条
/// 记录状态改真口径）；30 秒轮询探活与待批（拟案
/// 保底段口径），App 前台常驻期间运行。新待批喂
/// 本地通知（M3），待批＋未读喂 Dock 角标（M5）。
@MainActor
@Observable
final class MacStatusStore {
    private(set) var status = ConnectionStatus()
    private(set) var pendingApprovals: Int?
    /// 轮询带回的队首待批（菜单栏小面板快捷裁决用）
    private(set) var topExecPending: MacExecApproval?
    private(set) var topGatePending: WriteGateRecord?
    private var unreadCount = 0
    private var pollTask: Task<Void, Never>?

    var phase: ConnectionPhase { status.phase }

    var statusText: String { status.phaseWord }

    /// 状态点色：已连接绿、连接/重连中黄、联系不上
    /// 红、未连接灰
    var dotColor: Color {
        switch status.phase {
        case .online: return .green
        case .probing, .retrying: return .yellow
        case .offline: return .red
        case .notConnected: return .gray
        }
    }

    func start(session: SessionStore) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(session: session)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 未读总数由主壳喂入（会话列表店在主壳手里），
    /// 与待批合成 Dock 角标（M5）
    func noteUnread(_ count: Int) {
        unreadCount = count
        updateDockBadge()
    }

    private func updateDockBadge() {
        let total = (pendingApprovals ?? 0) + unreadCount
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }

    func refresh(session: SessionStore) async {
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            if status.phase != .notConnected {
                status = ConnectionStatus()
            }
            pendingApprovals = nil
            topExecPending = nil
            topGatePending = nil
            updateDockBadge()
            return
        }
        status.beginProbe(at: Date())
        do {
            let health = try await session.chatClient.health(
                config: config
            )
            if ServiceHealth.from(health: health) == .up {
                status.probeSucceeded(at: Date())
            } else {
                status.probeFailed(
                    attempt: status.attempt + 1,
                    reason: "服务未就绪", settledOffline: false,
                    at: Date()
                )
            }
        } catch {
            status.probeFailed(
                attempt: status.attempt + 1,
                reason: "联系不上服务器", settledOffline: true,
                at: Date()
            )
        }
        var execPending: [MacExecApproval] = []
        if let response = try? await session.chatClient
            .approvalsList(config: config, apiKey: key) {
            execPending = response.approvals.filter { $0.isPending }
        }
        var gatePending: [WriteGateRecord] = []
        if let pending = try? await session.chatClient
            .writeGatePending(config: config, apiKey: key) {
            gatePending = pending.records
        }
        pendingApprovals = execPending.count + gatePending.count
        topExecPending = execPending.first { $0.answerable }
        topGatePending = gatePending.first
        updateDockBadge()
        MacNotifier.shared.notePending(
            exec: execPending, gate: gatePending
        )
    }
}

/// 菜单栏小面板（M1）：状态摘要＋待批数＋打开主窗
struct MacMenuBarView: View {
    @Environment(SessionStore.self) private var session
    @Environment(MacStatusStore.self) private var statusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusStore.dotColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusStore.statusText)
                        .font(.headline)
                    Text(session.config?.host ?? "未连接服务器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let pending = statusStore.pendingApprovals {
                Label(
                    pending > 0
                        ? "待批 \(pending) 件" : "没有待批事项",
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                .foregroundStyle(
                    pending > 0 ? .orange : .secondary
                )
            }
            if let name = session.agentDisplayName {
                Label(name, systemImage: "person.crop.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            quickActions
            Divider()
            Button("打开批准面") {
                openWindow(id: "approvals")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("打开主窗") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            if session.isConnected {
                Button("断开连接", role: .destructive) {
                    session.disconnect()
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .task {
            await statusStore.refresh(session: session)
        }
    }

    /// 队首待批快捷裁决（M1 增强）：写闸给批准/驳
    /// 回、执行给批准/拒绝，一次点按直裁、裁完即刷
    /// （与批准面同一组端点同一语义；「总是允许」
    /// 不上小面板，去批准面办）
    @ViewBuilder
    private var quickActions: some View {
        if let record = statusStore.topGatePending {
            Divider()
            Text(ApprovalCardCopy.question(for: record))
                .font(.callout)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button("批准") {
                    quickGateDecide(record, approve: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("驳回") {
                    quickGateDecide(record, approve: false)
                }
                .controlSize(.small)
                Spacer()
            }
        } else if let record = statusStore.topExecPending {
            Divider()
            Text(
                record.description.isEmpty
                    ? record.command : record.description
            )
            .font(.callout)
            .lineLimit(2)
            HStack(spacing: 8) {
                Button("批准") {
                    quickExecDecide(record, choice: "once")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("拒绝") {
                    quickExecDecide(record, choice: "deny")
                }
                .controlSize(.small)
                Spacer()
            }
        }
    }

    private func quickGateDecide(
        _ record: WriteGateRecord, approve: Bool
    ) {
        guard let config = session.config, let key = session.apiKey
        else { return }
        Task {
            _ = try? await session.chatClient.writeGateDecide(
                config: config, apiKey: key,
                subsystem: record.subsystem, id: record.id,
                approve: approve
            )
            await statusStore.refresh(session: session)
        }
    }

    private func quickExecDecide(
        _ record: MacExecApproval, choice: String
    ) {
        guard let config = session.config, let key = session.apiKey
        else { return }
        Task {
            _ = try? await session.chatClient.resolveApproval(
                config: config, apiKey: key, requestID: record.id,
                choice: choice, reason: nil
            )
            await statusStore.refresh(session: session)
        }
    }
}
