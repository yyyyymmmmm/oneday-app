import SwiftUI
import OneDayCore

/// 菜单栏状态店（棒 1，对位 M1 基础形态）：连接四
/// 态（Core ConnectionStatus 同口径：未连接/连接
/// 中/已连接/联系不上）＋待批数；30 秒轮询探活与
/// 待批（拟案保底段口径），App 前台常驻期间运行。
@MainActor
@Observable
final class MacStatusStore {
    private(set) var status = ConnectionStatus()
    private(set) var pendingApprovals: Int?
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

    func refresh(session: SessionStore) async {
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            if status.phase != .notConnected {
                status = ConnectionStatus()
            }
            pendingApprovals = nil
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
        pendingApprovals = try? await session.chatClient
            .pendingApprovalCount(config: config, apiKey: key)
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
            Divider()
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
        .frame(width: 260)
        .task {
            await statusStore.refresh(session: session)
        }
    }
}
