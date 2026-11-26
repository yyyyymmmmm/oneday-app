import SwiftUI
import OneDayCore

/// 监控面（棒 4，对位 #54）：监控清单＋变化记录＋
/// 新建/删除，全走桥 /monitors 系（与 iOS 监控面
/// 同口；变化以桥回执为准）
struct MacHubMonitorsView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newTarget = ""
    @State private var expandedID: String?
    @State private var confirmDelete: BridgeMonitor?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "监控", count: store.monitors.count
            )
            if store.monitors.isEmpty {
                HubEmptyText(text: "暂无监控。")
            }
            ForEach(store.monitors) { monitor in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(monitor.name)
                                    .font(.callout.weight(.medium))
                                if monitor.unreadChanges > 0 {
                                    Text("\(monitor.unreadChanges) 条新变化")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Color.orange, in: Capsule()
                                        )
                                }
                            }
                            Text([
                                monitor.target,
                                monitor.scheduleText,
                                monitor.lastResult.map {
                                    "最近检查：\($0)"
                                },
                                monitor.lastError,
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(expandedID == monitor.id
                            ? "收起" : "变化") {
                            expandedID = expandedID == monitor.id
                                ? nil : monitor.id
                            if expandedID == monitor.id {
                                Task {
                                    await store.loadMonitorChanges(
                                        session: session,
                                        id: monitor.id
                                    )
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        Button("删除") { confirmDelete = monitor }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    if expandedID == monitor.id,
                       let changes = store.monitorChanges[monitor.id] {
                        if changes.isEmpty {
                            Text("暂无变化记录。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(changes) { change in
                            HStack(spacing: 8) {
                                Text(MacTimeText.short(
                                    change.detectedAt
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(change.summary)
                                    .font(.caption)
                            }
                        }
                    }
                }
                Divider()
            }
            HubSectionHeader(title: "新建监控")
            TextField("名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("目标（URL 或对象）", text: $newTarget)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("新建") {
                    Task {
                        await store.createMonitor(
                            session: session, name: newName,
                            target: newTarget
                        )
                        newName = ""
                        newTarget = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || newTarget.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个监控？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let monitor = confirmDelete {
                    Task {
                        await store.deleteMonitor(
                            session: session, id: monitor.id
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}
