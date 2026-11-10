import OneDayCore
import OneDayDesign
import SwiftUI

/// 通知 sheet（0.6.0 一期，总览桥）：版式对照 OpenMuse
/// 通知 sheet 转译为原生 List——未读在前、点开即向桥标
/// 已读（OverviewBridgeStore.markRead 确认后才改本地态）。
/// 桥不可达时明示「暂时联系不上」，不拿空列表冒充没有
/// 通知；真空态文案只在加载成功且确为空时出现。
struct NotificationsView: View {
    let store: OverviewBridgeStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !store.notificationsLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.notificationsFailed {
                    ContentUnavailableView {
                        Label("暂时联系不上", systemImage: "bell.slash")
                    } description: {
                        Text("通知暂时读不到，请稍后再试。")
                    } actions: {
                        Button("重试") {
                            Task { await store.loadNotifications(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if store.notifications.isEmpty {
                    ContentUnavailableView(
                        "暂无通知",
                        systemImage: "bell",
                        description: Text("任务状态变化与审批结果会出现在这里")
                    )
                } else {
                    List {
                        ForEach(store.notifications) { item in
                            notificationRow(item)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await store.loadNotifications(appState: appState)
                    }
                }
            }
            .background(Palette.pageBG)
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await store.loadNotifications(appState: appState)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func notificationRow(
        _ item: OverviewNotification
    ) -> some View {
        Button {
            Task { await store.markRead(appState: appState, id: item.id) }
        } label: {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
                Circle()
                    .fill(item.read ? Palette.inkMuted.opacity(0.35) : Palette.primary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(3)
                    }
                    Text(Self.displayTime(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            item.read ? item.title : "未读，\(item.title)"
        )
    }

    /// 桥的 createdAt 是 ISO8601 字符串：能解析则按本地
    /// 相对时间呈现，解析不了原样呈现（不编造时间）。
    private static func displayTime(_ raw: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: raw) ?? plain.date(from: raw) else {
            return raw
        }
        return date.formatted(.relative(presentation: .named))
    }
}
