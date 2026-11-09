import OneDayCore
import OneDayDesign
import SwiftUI

/// 监测详情（0.12.0 P6）：监测本体信息（盯什么/频率/
/// 状态/最近检查与失败原因）＋变化记录列表（时刻＋
/// 摘要＋未读点）；点一条变化进差异页。记录只读服务
/// 端数据，有什么呈现什么，不拼假 diff。
struct MonitorDetailView: View {
    let store: MonitorsStore
    let monitorID: String

    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let monitor = store.monitor(id: monitorID) {
                content(monitor)
            } else {
                ContentUnavailableView(
                    "监测已不在",
                    systemImage: "eye.slash",
                    description: Text("这条监测已经不在列表里了。")
                )
            }
        }
        .navigationTitle(store.monitor(id: monitorID)?.name ?? "监测")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadChanges(appState: appState, monitorID: monitorID)
        }
        .refreshable {
            await store.load(appState: appState)
            await store.loadChanges(appState: appState, monitorID: monitorID)
        }
    }

    @ViewBuilder
    private func content(_ monitor: BridgeMonitor) -> some View {
        List {
            Section {
                infoRow("盯什么", monitor.target)
                if !monitor.scheduleText.isEmpty {
                    infoRow("频率", monitor.scheduleText)
                }
                infoRow(
                    "状态",
                    MonitorPresentation.statusText(of: monitor)
                )
                if let checkedAt = monitor.lastCheckedAt {
                    infoRow(
                        "最近检查",
                        Date(timeIntervalSince1970: checkedAt)
                            .formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if MonitorPresentation.status(of: monitor) == .failed,
                   let error = monitor.lastError, !error.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("失败原因")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            Section("变化记录") {
                changesContent(monitor)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func changesContent(_ monitor: BridgeMonitor) -> some View {
        if store.changesLoading.contains(monitorID),
           store.changes[monitorID] == nil {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if let error = store.changesErrors[monitorID] {
            Text(error)
                .font(.footnote)
                .foregroundStyle(Palette.danger)
        } else if let changes = store.changes[monitorID] {
            if changes.isEmpty {
                Text("还没有检出过变化。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(changes) { change in
                    NavigationLink {
                        MonitorChangeDetailView(
                            store: store, monitorID: monitorID,
                            changeID: change.id
                        )
                    } label: {
                        changeRow(change)
                    }
                }
            }
        }
    }

    private func changeRow(_ change: BridgeMonitorChange) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            if !change.read {
                Circle()
                    .fill(Palette.primary)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("未读")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(change.summary)
                    .font(.subheadline)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                Text(
                    Date(timeIntervalSince1970: change.detectedAt)
                        .formatted(date: .abbreviated, time: .shortened)
                )
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Palette.bodyInk)
                .textSelection(.enabled)
        }
    }
}

/// 变化差异页（0.12.0 P6）：摘要＋变化前/后原文块——
/// 有什么给什么；桥没存原文时明说没有保存原文，
/// 绝不拿摘要拼成假 diff。打开即标记已读（回读
/// 列表对账未读数在 MonitorsStore）。
struct MonitorChangeDetailView: View {
    let store: MonitorsStore
    let monitorID: String
    let changeID: String

    @Environment(AppState.self) private var appState

    private var change: BridgeMonitorChange? {
        store.changes[monitorID]?.first { $0.id == changeID }
    }

    var body: some View {
        Group {
            if let change {
                let rows = MonitorChangeDetail.rows(for: change)
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rows.summary)
                                .font(.body)
                                .foregroundStyle(Palette.bodyInk)
                            Text(
                                Date(timeIntervalSince1970: change.detectedAt)
                                    .formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                            )
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    if let before = rows.before {
                        Section("变化前") {
                            originalText(before)
                        }
                    }
                    if let after = rows.after {
                        Section("变化后") {
                            originalText(after)
                        }
                    }
                    if !rows.hasOriginalText {
                        Section {
                            Text("这次变化没有保存变化前后的原文，只有上面的摘要。")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView(
                    "记录已不在",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("这条变化记录已经不在列表里了。")
                )
            }
        }
        .navigationTitle("变化详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.markRead(
                appState: appState, monitorID: monitorID,
                changeID: changeID
            )
        }
    }

    private func originalText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Palette.bodyInk)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
