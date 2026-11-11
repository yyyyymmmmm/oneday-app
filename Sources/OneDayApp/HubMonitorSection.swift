import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页监测段（0.12.0 P6 客户端先行）：活动格监测
/// 唯一落位（不双挂应用格）。数据源定案见契约档
/// monitor-bridge-contract-20261109.md——桥未扩展
/// /monitors 时如实露「监测数据源未开通」，零假数据；
/// 开通后本段即真列表：监测卡＝卡骨架＋状态点＋最近
/// 变化行（设计标准 §7 P6 锚），点卡进详情看变化
/// 记录与前后差异。0.12.1 桥上线后补控制接线：
/// 新建入口（空态与列表顶各一）＋长按菜单（立即
/// 检查/暂停恢复/删除，删除先确认），动作全走
/// MonitorsStore 回读确认，未确认/失败人话留卡面。
struct HubMonitorSection: View {
    @Environment(AppState.self) private var appState
    @State private var store = MonitorsStore()
    @State private var showingCreate = false
    /// 待确认删除的监测（破坏性动作先确认再发）
    @State private var pendingDelete: BridgeMonitor?

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notConnected(let message):
                ContentUnavailableView {
                    Label("还没连上你的服务", systemImage: "link.badge.plus")
                } description: {
                    Text(message)
                } actions: {
                    Button("重新检查") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.bordered)
                }
            case .sourceNotOpened(let message):
                ContentUnavailableView {
                    Label("监测数据源未开通", systemImage: "eye.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("重新检查") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.bordered)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("监测没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.bordered)
                }
            case .ready:
                readyContent
            }
        }
        .task {
            await store.load(appState: appState)
        }
        .sheet(isPresented: $showingCreate) {
            MonitorCreateView(store: store)
        }
        .confirmationDialog(
            "删除这条监测？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { monitor in
            Button("删除监测", role: .destructive) {
                Task {
                    _ = await store.delete(
                        appState: appState, monitorID: monitor.id
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: { monitor in
            Text("「\(monitor.name)」删除后，它的变化记录也会一并删掉。")
        }
    }

    // MARK: - 就绪态

    @ViewBuilder
    private var readyContent: some View {
        if store.monitors.isEmpty {
            ContentUnavailableView {
                Label("暂无监测", systemImage: "eye")
            } description: {
                Text("还没有盯着的页面或对象。")
            } actions: {
                Button {
                    showingCreate = true
                } label: {
                    Label("新建监测", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: OneDayMetrics.spacingSM) {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("新建监测", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.odPressable)
                    .foregroundStyle(Palette.primary)
                    if store.totalUnread > 0 {
                        Text("\(store.totalUnread) 条变化未读")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(store.sortedMonitors) { monitor in
                        NavigationLink {
                            MonitorDetailView(store: store, monitorID: monitor.id)
                        } label: {
                            MonitorCardView(
                                monitor: monitor,
                                note: store.notes[monitor.id],
                                isActing: store.actingIDs
                                    .contains(monitor.id)
                            )
                        }
                        .buttonStyle(.odPressable)
                        .contextMenu {
                            monitorActions(monitor)
                        }
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .refreshable {
                await store.load(appState: appState)
            }
        }
    }

    /// 行内控制（长按菜单）：与详情页同一套动作、
    /// 同一回读确认口径；动作进行中整组禁用，失败
    /// 人话由卡面 note 呈现（409 已暂停亦走此路）
    @ViewBuilder
    private func monitorActions(_ monitor: BridgeMonitor) -> some View {
        let acting = store.actingIDs.contains(monitor.id)
        Button {
            Task {
                await store.checkNow(
                    appState: appState, monitorID: monitor.id
                )
            }
        } label: {
            Label("立即检查", systemImage: "arrow.clockwise")
        }
        .disabled(acting)
        if monitor.enabled {
            Button {
                Task {
                    await store.setEnabled(
                        appState: appState, monitorID: monitor.id,
                        enabled: false
                    )
                }
            } label: {
                Label("暂停监测", systemImage: "pause.circle")
            }
            .disabled(acting)
        } else {
            Button {
                Task {
                    await store.setEnabled(
                        appState: appState, monitorID: monitor.id,
                        enabled: true
                    )
                }
            } label: {
                Label("恢复监测", systemImage: "play.circle")
            }
            .disabled(acting)
        }
        Button(role: .destructive) {
            pendingDelete = monitor
        } label: {
            Label("删除监测", systemImage: "trash")
        }
        .disabled(acting)
    }
}

/// 监测卡（§7 P6 锚：卡骨架＋状态点＋最近变化行）：
/// 名称/盯什么/频率/最近检查时刻＋结果三分/未读数
/// 五件必含；结果三分（有变化/无变化/检查失败）以
/// 状态点颜色＋文字双通道呈现，不许混淆
struct MonitorCardView: View {
    let monitor: BridgeMonitor
    /// 行内提示（控制动作未确认/失败的人话，0.12.1）
    var note: String? = nil
    /// 控制动作进行中（转圈替代箭头，不假装已完成）
    var isActing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(monitor.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(1)
                Spacer()
                if monitor.unreadChanges > 0 {
                    Text("\(monitor.unreadChanges)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.onPrimary)
                        .padding(.horizontal, OneDayMetrics.rowInnerGap)
                        .padding(.vertical, OneDayMetrics.spacingMicro)
                        .background(
                            Palette.primary, in: Capsule()
                        )
                        .accessibilityLabel("\(monitor.unreadChanges) 条未读变化")
                }
                if isActing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            if !monitor.target.isEmpty {
                Text(monitor.target)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Text(metaLine)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            if MonitorPresentation.status(of: monitor) == .failed,
               let error = monitor.lastError, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
            } else if let summary = monitor.latestChangeSummary,
                      !summary.isEmpty {
                Text(latestChangeLine(summary))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .lineLimit(3)
            }
        }
        .padding(OneDayMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner,
                style: .continuous
            )
        )
        .opacity(monitor.enabled ? 1 : 0.6)
    }

    private var statusColor: Color {
        switch MonitorPresentation.status(of: monitor) {
        case .changed: return Palette.primary
        case .unchanged: return Palette.success
        case .failed: return Palette.danger
        case .neverChecked, .unknown, .paused: return Palette.inkMuted
        }
    }

    /// 频率 · 最近检查时刻＋结果（还没检查过时不编时刻）
    private var metaLine: String {
        var parts: [String] = []
        if !monitor.scheduleText.isEmpty {
            parts.append(monitor.scheduleText)
        }
        let status = MonitorPresentation.status(of: monitor)
        if status == .neverChecked {
            parts.append("还没检查过")
        } else if let checkedAt = monitor.lastCheckedAt {
            let time = DisplayDate.dateTime(
                Date(timeIntervalSince1970: checkedAt)
            )
            parts.append("上次检查 \(time)·\(MonitorPresentation.statusText(of: monitor))")
        } else {
            parts.append(MonitorPresentation.statusText(of: monitor))
        }
        return parts.joined(separator: " · ")
    }

    private func latestChangeLine(_ summary: String) -> String {
        if let changedAt = monitor.latestChangeAt {
            let time = DisplayDate.dateTime(
                Date(timeIntervalSince1970: changedAt)
            )
            return "最近变化：\(summary)（\(time)）"
        }
        return "最近变化：\(summary)"
    }
}
