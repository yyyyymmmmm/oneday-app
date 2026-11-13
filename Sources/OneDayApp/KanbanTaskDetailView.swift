import OneDayCore
import OneDayDesign
import SwiftUI

/// 任务详情（P3，0.10.0）：头部状态＋说明＋（等答
/// 时）问题与答题框＋结果/摘要＋证据（结果/运行/
/// 事件拼装）＋评论＋控制动作。动作全走 KanbanStore
/// 的回读确认：未确认不消失、原因留在「操作」段内。
struct KanbanTaskDetailView: View {
    let store: KanbanStore
    let taskID: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var answerText = ""
    @State private var showCancelConfirm = false

    /// 当前任务：详情回读优先，列表快照兜底（刚从
    /// 列表点入时详情未到先有行可看）
    private var task: KanbanTask? {
        if let detail = store.detail, detail.task.id == taskID {
            return detail.task
        }
        return store.snapshot?.tasks.first { $0.id == taskID }
    }

    private var detail: KanbanTaskDetail? {
        guard let detail = store.detail, detail.task.id == taskID
        else { return nil }
        return detail
    }

    private var acting: Bool { store.actingIDs.contains(taskID) }

    var body: some View {
        Group {
            if let task {
                content(task)
            } else if store.detailLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "任务没读出来，可能是网络或服务暂时没响应",
                    systemImage: "exclamationmark.triangle",
                    description: Text("请返回列表刷新后重试。")
                )
            }
        }
        .background(Palette.pageBG)
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDetail(appState: appState, id: taskID)
        }
    }

    // MARK: - 内容

    private func content(_ task: KanbanTask) -> some View {
        List {
            headerSection(task)
            if !task.body.isEmpty {
                Section("说明") {
                    Text(task.body)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
            }
            if task.presentation == .needsInput {
                answerSection(task)
            }
            if let result = task.result, !result.isEmpty {
                Section("结果") {
                    Text(result)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
            }
            if let summary = task.latestSummary,
               !summary.isEmpty, summary != task.result {
                Section("最近摘要") {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
            }
            evidenceSection
            commentsSection
            if let detail, !detail.attachmentNames.isEmpty {
                Section("附件") {
                    ForEach(detail.attachmentNames, id: \.self) { name in
                        Label(name, systemImage: "paperclip")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            actionsSection(task)
        }
        .listStyle(.plain)
        .refreshable {
            await store.loadDetail(appState: appState, id: taskID)
            await store.load(appState: appState)
        }
    }

    // MARK: - 头部

    private func headerSection(_ task: KanbanTask) -> some View {
        Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.rowInnerGap) {
                Text(task.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: OneDayMetrics.rowInnerGap) {
                    Text(task.presentation.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, OneDayMetrics.stackGap)
                        .background(Palette.fieldFill, in: Capsule())
                        .foregroundStyle(Palette.inkSecondary)
                    if let assignee = task.displayAssignee {
                        Text("执行：\(assignee)")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    if let created = task.createdAt {
                        metaLine("创建", AdminFormat.short(created))
                    }
                    if let started = task.startedAt {
                        metaLine("开始", AdminFormat.short(started))
                    }
                    if let completed = task.completedAt {
                        metaLine("完成", AdminFormat.short(completed))
                    }
                    if task.consecutiveFailures > 0 {
                        metaLine(
                            "连续失败", "\(task.consecutiveFailures) 次"
                        )
                    }
                }
                if let error = task.lastFailureError, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                // 0.18.0（问题原文定案，P3 验收实查）：
                // task 对象没有 block_reason 字段，问题
                // 原文在详情 events 里 blocked 事件的
                // payload.reason（及 blocked run 的
                // summary）——改从 detail.blockDetailText
                // 取；详情未到先不显，到了仍取不到如实
                // 标注「问题原文未取到」，不许拿任务标题
                // 或其他文本冒充
                if task.presentation == .blocked, let detail {
                    Text(detail.blockDetailText ?? "问题原文未取到")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingMicro)
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.rowInnerGap) {
            Text(label)
                .foregroundStyle(Palette.inkSecondary)
            Text(value)
                .foregroundStyle(Palette.inkSecondary)
        }
        .font(.caption)
    }

    // MARK: - 答题（等你回答态）

    private func answerSection(_ task: KanbanTask) -> some View {
        let gate = KanbanActionPolicy.gate(
            action: .answer,
            takeoverActive: appState.boxTakeoverActive,
            readOnly: store.readOnly
        )
        return Section("等你回答") {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                // 问题原文（0.18.0 定案）：详情 events 的
                // blocked 事件 payload.reason 为正源；
                // 详情已到仍取不到如实标注，不冒充
                if let detail {
                    Text(detail.pendingQuestion ?? "问题原文未取到")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                } else {
                    Text("执行方在等你的回答。")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
                TextField(
                    "写下你的回答",
                    text: $answerText, axis: .vertical
                )
                .lineLimit(2...5)
                Button {
                    let answer = answerText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    Task {
                        await store.perform(
                            appState: appState, task: task,
                            action: .answer, answer: answer
                        )
                        if store.notes[taskID] == nil {
                            answerText = ""
                        }
                    }
                } label: {
                    Label("回答并继续", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    answerText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || acting || !gate.enabled
                )
                if !gate.enabled, let reason = gate.reason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingMicro)
        }
    }

    // MARK: - 证据与评论

    @ViewBuilder
    private var evidenceSection: some View {
        if let detail, !detail.evidenceItems.isEmpty {
            Section("证据") {
                ForEach(detail.evidenceItems) { item in
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        HStack(spacing: OneDayMetrics.rowInnerGap) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if let at = item.at {
                                Text(AdminFormat.short(at))
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        if let text = item.detail, !text.isEmpty {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        if let detail, !detail.comments.isEmpty {
            Section("评论") {
                ForEach(detail.comments) { comment in
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        HStack(spacing: OneDayMetrics.rowInnerGap) {
                            Text(authorLabel(comment.author))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            if let at = comment.createdAt {
                                Text(AdminFormat.short(at))
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        Text(comment.body)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    /// 评论作者呈现：App 答题标记译「我」，其余原生
    /// 档案名原样（执行方是谁要看得清）
    private func authorLabel(_ author: String) -> String {
        switch author {
        case KanbanContract.answerAuthor: return "我"
        case "dashboard": return "面板"
        case "": return "执行方"
        default: return author
        }
    }

    // MARK: - 操作

    private func actionsSection(_ task: KanbanTask) -> some View {
        // 答题走「等你回答」段的专属框，此处不重复列
        let actions = KanbanActionPolicy.actions(for: task)
            .filter { $0 != .answer }
        return Section("操作") {
            if acting {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView().controlSize(.small)
                    Text("正在执行…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            if actions.isEmpty {
                Text("当前状态没有可执行的操作。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
            ForEach(actions, id: \.self) { action in
                actionButton(task: task, action: action)
            }
            if let note = store.notes[taskID] {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    private func actionButton(
        task: KanbanTask, action: KanbanAction
    ) -> some View {
        let gate = KanbanActionPolicy.gate(
            action: action,
            takeoverActive: appState.boxTakeoverActive,
            readOnly: store.readOnly
        )
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Button(role: action.isDestructive ? .destructive : nil) {
                if action == .cancel {
                    showCancelConfirm = true
                } else {
                    Task {
                        await store.perform(
                            appState: appState, task: task, action: action
                        )
                    }
                }
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .disabled(acting || !gate.enabled)
            if !gate.enabled, let reason = gate.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .confirmationDialog(
            "取消这个任务？",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("取消任务", role: .destructive) {
                Task {
                    await store.perform(
                        appState: appState, task: task, action: .cancel
                    )
                    // 回读确认任务已消失＝取消生效，自动回列表
                    if self.task == nil {
                        dismiss()
                    }
                }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("运行中的任务会先停止，然后从任务板上删除，无法恢复。")
        }
    }
}

/// 新建任务表单（标题＋说明 → 建卡＋dispatch＋回板
/// 确认，未确认不关表单——KanbanStore.createTask）
/// §208：原属枢纽任务段，收段后随段文件退役迁来本
/// 文件——全 App 的任务新建入口只此一份，现由活动
/// 段页首菜单唤起（口径与门控原样）
struct KanbanCreateTaskView: View {
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
