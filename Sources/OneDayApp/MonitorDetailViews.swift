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
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    /// 通知落点深链（§123 H2）：编程式推入的变化 id
    /// （与变化行 NavigationLink 并存）
    @State private var deepLinkChangeID: String?

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
            // §123（H2）：深链对号消费——monitorID 对上
            // 且变化确在账上才继续推变化详情，消费即清
            // AppState（防下次手动进本页时旧链复活）；
            // 对不上/变化已滚没了就停在本页，如实降级
            if let deepLink = appState.monitorDeepLink,
               deepLink.monitorID == monitorID {
                appState.monitorDeepLink = nil
                if let changeID = deepLink.changeID,
                   store.changes[monitorID]?.contains(
                       where: { $0.id == changeID }
                   ) == true {
                    deepLinkChangeID = changeID
                }
            }
        }
        .navigationDestination(item: $deepLinkChangeID) { changeID in
            MonitorChangeDetailView(
                store: store, monitorID: monitorID,
                changeID: changeID
            )
        }
        .refreshable {
            await store.load(appState: appState)
            await store.loadChanges(appState: appState, monitorID: monitorID)
        }
        .confirmationDialog(
            "删除这条监测？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除监测", role: .destructive) {
                Task {
                    if await store.delete(
                        appState: appState, monitorID: monitorID
                    ) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，它的变化记录也会一并删掉。")
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
                        DisplayDate.dateTime(
                            Date(timeIntervalSince1970: checkedAt)
                        )
                    )
                }
                if MonitorPresentation.status(of: monitor) == .failed,
                   let error = monitor.lastError, !error.isEmpty {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("失败原因")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            controlsSection(monitor)
            Section("变化记录") {
                changesContent(monitor)
            }
            Section {
                Button("删除监测", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(store.actingIDs.contains(monitorID))
            }
        }
        .listStyle(.insetGrouped)
    }

    /// 控制区（0.12.1）：立即检查＋暂停/恢复，与行内
    /// 长按菜单同一套动作同一回读口径；动作中禁用，
    /// 未确认/失败的人话（已暂停 409 等）留本区内
    @ViewBuilder
    private func controlsSection(_ monitor: BridgeMonitor) -> some View {
        let acting = store.actingIDs.contains(monitorID)
        Section {
            Button {
                Task {
                    await store.checkNow(
                        appState: appState, monitorID: monitorID
                    )
                }
            } label: {
                HStack {
                    Label("立即检查", systemImage: "arrow.clockwise")
                    if acting {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(acting)
            if monitor.enabled {
                Button {
                    Task {
                        await store.setEnabled(
                            appState: appState, monitorID: monitorID,
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
                            appState: appState, monitorID: monitorID,
                            enabled: true
                        )
                    }
                } label: {
                    Label("恢复监测", systemImage: "play.circle")
                }
                .disabled(acting)
            }
            if let note = store.notes[monitorID], !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
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
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(change.summary)
                    .font(.subheadline)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                Text(
                    DisplayDate.dateTime(
                        Date(timeIntervalSince1970: change.detectedAt)
                    )
                )
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
    /// 原文展开态（§123 N3）：变化前/后各自独立开合，
    /// 默认收起只显预览
    @State private var beforeExpanded = false
    @State private var afterExpanded = false

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
                            originalBlock(
                                full: before,
                                preview: rows.beforePreview ?? before,
                                truncated: rows.beforeTruncated,
                                expanded: $beforeExpanded
                            )
                        }
                    }
                    if let after = rows.after {
                        Section("变化后") {
                            originalBlock(
                                full: after,
                                preview: rows.afterPreview ?? after,
                                truncated: rows.afterTruncated,
                                expanded: $afterExpanded
                            )
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

    /// 原文块（§123 N3）：默认只铺预览（Core 限长截
    /// 断），被截断时给「展开全文」开合钮，展开后全
    /// 文原样呈现；没截断的短原文直接全显、无多余
    /// 钮。桥没有要点数据——不编造要点，结构化只到
    /// 摘要（页头）＋预览＋原文折叠这一层
    @ViewBuilder
    private func originalBlock(
        full: String, preview: String, truncated: Bool,
        expanded: Binding<Bool>
    ) -> some View {
        if truncated {
            Text(expanded.wrappedValue ? full : preview)
                .font(.subheadline)
                .foregroundStyle(Palette.bodyInk)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                Text(
                    expanded.wrappedValue
                        ? "收起全文" : "展开全文"
                )
                .font(.footnote)
            }
            .buttonStyle(.odPressable)
        } else {
            Text(full)
                .font(.subheadline)
                .foregroundStyle(Palette.bodyInk)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
