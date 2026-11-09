import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页监测段（0.12.0 P6 客户端先行）：活动格监测
/// 唯一落位（不双挂应用格）。数据源定案见契约档
/// monitor-bridge-contract-20261109.md——桥未扩展
/// /monitors 时如实露「监测数据源未开通」，零假数据；
/// 开通后本段即真列表：监测卡＝卡骨架＋状态点＋最近
/// 变化行（设计标准 §7 P6 锚），点卡进详情看变化
/// 记录与前后差异。
struct HubMonitorSection: View {
    @Environment(AppState.self) private var appState
    @State private var store = MonitorsStore()

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notConnected(let message):
                ContentUnavailableView {
                    Label("数据桥未连接", systemImage: "link.badge.plus")
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
                    Label("监测读取失败", systemImage: "exclamationmark.triangle")
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
    }

    // MARK: - 就绪态

    @ViewBuilder
    private var readyContent: some View {
        if store.monitors.isEmpty {
            ContentUnavailableView(
                "暂无监测",
                systemImage: "eye",
                description: Text("还没有盯着的页面或对象。")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: OneDayMetrics.spacingSM) {
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
                            MonitorCardView(monitor: monitor)
                        }
                        .buttonStyle(.plain)
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
}

/// 监测卡（§7 P6 锚：卡骨架＋状态点＋最近变化行）：
/// 名称/盯什么/频率/最近检查时刻＋结果三分/未读数
/// 五件必含；结果三分（有变化/无变化/检查失败）以
/// 状态点颜色＋文字双通道呈现，不许混淆
struct MonitorCardView: View {
    let monitor: BridgeMonitor

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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Palette.primary, in: Capsule()
                        )
                        .accessibilityLabel("\(monitor.unreadChanges) 条未读变化")
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkMuted)
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
            let time = Date(timeIntervalSince1970: checkedAt)
                .formatted(date: .abbreviated, time: .shortened)
            parts.append("上次检查 \(time)·\(MonitorPresentation.statusText(of: monitor))")
        } else {
            parts.append(MonitorPresentation.statusText(of: monitor))
        }
        return parts.joined(separator: " · ")
    }

    private func latestChangeLine(_ summary: String) -> String {
        if let changedAt = monitor.latestChangeAt {
            let time = Date(timeIntervalSince1970: changedAt)
                .formatted(date: .abbreviated, time: .shortened)
            return "最近变化：\(summary)（\(time)）"
        }
        return "最近变化：\(summary)"
    }
}
