import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页任务段（0.10.0 P3 转正）：活动格任务区由
/// 无面转真列表——kanban 专属板 oneday 的任务按呈现
/// 态分组（等你回答→待审批→进行中→失败→已阻塞→
/// 排队中→已排期→待整理→已完成），卡给标题/状态/
/// 最近摘要，点行进详情看证据、执行控制动作。
/// 专属板未开通如实露未开通态、不给假数据（建板属
/// 生产写操作，不在本包——另行授权后由服务端线办）。
struct HubTaskSection: View {
    @Environment(AppState.self) private var appState
    @State private var store = KanbanStore()
    @State private var showCreate = false

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notProvisioned:
                ContentUnavailableView {
                    Label("任务板未开通", systemImage: "checklist")
                } description: {
                    Text("专属任务板还没有在服务器上开通。开通后，你委派的任务会出现在这里。")
                } actions: {
                    Button("重新检查") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.bordered)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("任务读取失败", systemImage: "exclamationmark.triangle")
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
            await store.runVisibleLoop(appState: appState)
        }
        .sheet(isPresented: $showCreate) {
            KanbanCreateTaskView(store: store)
        }
    }

    // MARK: - 就绪态

    @ViewBuilder
    private var readyContent: some View {
        VStack(spacing: 0) {
            if appState.boxTakeoverActive {
                banner(
                    icon: "hand.tap",
                    text: "接管中 · 任务派发已暂停",
                    detail: "你正在操作云电脑，新建与继续类动作暂时禁用，交还后恢复。"
                )
            }
            if store.readOnly {
                banner(
                    icon: "eye",
                    text: "任务系统版本变化，当前只读",
                    detail: nil
                )
            }
            createRow
            if store.groups.isEmpty {
                ContentUnavailableView(
                    "暂无任务",
                    systemImage: "checklist",
                    description: Text("点上方「新建任务」委派第一个任务")
                )
            } else {
                List {
                    ForEach(store.groups, id: \.presentation) { group in
                        Section(group.presentation.label) {
                            ForEach(group.tasks) { task in
                                NavigationLink {
                                    KanbanTaskDetailView(
                                        store: store, taskID: task.id
                                    )
                                } label: {
                                    taskRow(task)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await store.load(appState: appState)
                }
            }
        }
    }

    private func banner(
        icon: String, text: String, detail: String?
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.fieldFill)
    }

    private var createRow: some View {
        let gate = KanbanActionPolicy.gate(
            action: .create,
            takeoverActive: appState.boxTakeoverActive,
            readOnly: store.readOnly
        )
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                showCreate = true
            } label: {
                Label("新建任务", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!gate.enabled)
            if !gate.enabled, let reason = gate.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    // MARK: - 任务行（卡面三件：标题/状态/最近摘要）

    private func taskRow(_ task: KanbanTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                Text(task.displayTitle)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                statusChip(task.presentation)
            }
            if let summary = task.summaryText {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                if let created = task.createdAt {
                    Text(AdminFormat.short(created))
                }
                if let assignee = task.displayAssignee {
                    Text("执行：\(assignee)")
                }
                if task.presentation == .failed,
                   let error = task.lastFailureError {
                    Text(error)
                        .foregroundStyle(Palette.danger)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
    }

    /// 状态 chip：需人处理/活跃/终态给色面，其余中性
    /// （设计纪律：框架无色、内容有色，克制优先）
    private func statusChip(
        _ presentation: KanbanStatusPresentation
    ) -> some View {
        Text(presentation.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, OneDayMetrics.stackGap)
            .background(chipFill(presentation), in: Capsule())
            .foregroundStyle(chipInk(presentation))
    }

    private func chipFill(
        _ presentation: KanbanStatusPresentation
    ) -> Color {
        switch presentation {
        case .needsInput, .blocked: return Palette.tintOrange
        case .review: return Palette.tintLavender
        case .running: return Palette.tintSky
        case .failed: return Palette.errorSurface
        case .done: return Palette.tintGreen
        case .queued, .scheduled, .triage, .archived, .unknown:
            return Palette.fieldFill
        }
    }

    private func chipInk(
        _ presentation: KanbanStatusPresentation
    ) -> Color {
        switch presentation {
        case .failed: return Palette.danger
        case .queued, .scheduled, .triage, .archived, .unknown:
            return Palette.inkSecondary
        default:
            return Palette.ink
        }
    }
}

/// 新建任务表单（标题＋说明 → 建卡＋dispatch＋回板
/// 确认，未确认不关表单——KanbanStore.createTask）
private struct KanbanCreateTaskView: View {
    let store: KanbanStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""

    private var gate: KanbanActionPolicy.Gate {
        KanbanActionPolicy.gate(
            action: .create,
            takeoverActive: appState.boxTakeoverActive,
            readOnly: store.readOnly
        )
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                }
                Section("说明") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                }
                if !gate.enabled, let reason = gate.reason {
                    Section {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                if let error = store.createError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("委派") {
                        Task {
                            let ok = await store.createTask(
                                appState: appState,
                                title: trimmedTitle,
                                body: bodyText.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            )
                            if ok { dismiss() }
                        }
                    }
                    .disabled(
                        trimmedTitle.isEmpty || store.creating
                            || !gate.enabled
                    )
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
