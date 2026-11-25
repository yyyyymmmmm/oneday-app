import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 目标详情（统一原生 iOS 26 List(.insetGrouped) + SettingsSectionHeader）：
/// 头部（标题＋状态＋分类＋备注）→ 活动 → 简报 → 安排一件事 → 进展 → 子目标 → 关联 → 状态与危险动作。
struct GoalDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let store: GoalsStore
    let goalID: String

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var newEntryBody = ""
    @State private var newSubgoalTitle = ""
    @State private var subgoalError: String?
    @State private var showDelegate = false

    private var ideasStore: IdeasStore {
        appState.sharedIdeasStore()
    }
    private var monitorsStore: MonitorsStore {
        appState.sharedMonitorsStore()
    }
    private var kanban: KanbanStore {
        appState.sharedKanbanStore()
    }

    private var goal: BridgeGoal? { store.goal(id: goalID) }
    private var acting: Bool { store.actingIDs.contains(goalID) }
    private var entries: [BridgeGoalEntry] {
        store.entriesByGoal[goalID] ?? []
    }
    private var briefings: [BridgeBriefing] {
        store.briefingsByGoal[goalID] ?? []
    }
    private var detailLoaded: Bool {
        store.detailLoadedIDs.contains(goalID)
    }

    private func loadAssociationStores(force: Bool) async {
        if force {
            await ideasStore.load(appState: appState)
            await monitorsStore.load(appState: appState)
            await kanban.load(appState: appState)
        } else {
            await ideasStore.loadIfNeeded(appState: appState)
            await monitorsStore.loadIfNeeded(appState: appState)
            await kanban.loadIfNeeded(appState: appState)
        }
    }

    private func materializeGoalEchoes() {
        guard let threadID = appState.sessionLedger
            .threadID(forGoalID: goalID) else { return }
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == threadID }
        )
        guard let thread = try? modelContext.fetch(descriptor).first
        else { return }
        let linked = GoalAssociations.linkedTasks(
            goalID: goalID,
            rows: store.goalTasksByGoal[goalID] ?? [],
            tasks: kanban.snapshot?.tasks ?? []
        )
        let existing = Set(thread.entries.compactMap(\.echoKey))
        let planned = GoalEcho.plan(
            linkedTasks: linked, existingKeys: existing
        )
        guard !planned.isEmpty else { return }
        for item in planned {
            let entry = ChatEntry(
                role: "assistant",
                content: GoalEcho.text(
                    kind: item.kind, taskTitle: item.taskTitle
                ),
                thread: thread, echoKey: item.key
            )
            modelContext.insert(entry)
        }
        thread.updatedAt = Date()
        try? modelContext.save()
    }

    private func openGoalThread() {
        guard let threadID = appState.sessionLedger
            .threadID(forGoalID: goalID) else { return }
        appState.router.drawerThreadSelection = threadID
        appState.router.mainTabSwitchRequest = .chat
    }

    var body: some View {
        Group {
            if let goal {
                List {
                    headerSection(goal)
                    activitySection(goal)
                    briefingSection(goal)
                    delegationSection(goal)
                    entriesSection(goal)
                    if goal.parentId == nil {
                        subgoalsSection(goal)
                    }
                    associationSection(goal)
                    actionsSection(goal)
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
                .scrollContentBackground(.hidden)
                .background(Palette.settingsBG)
                .refreshable {
                    await store.load(appState: appState)
                    await store.loadDetail(
                        appState: appState, goalID: goalID
                    )
                    await loadAssociationStores(force: true)
                    materializeGoalEchoes()
                }
                .sheet(isPresented: $showDelegate) {
                    GoalDelegateView(
                        store: store, goal: goal
                    )
                }
            } else {
                ContentUnavailableView(
                    "目标已不在",
                    systemImage: "questionmark.folder",
                    description: Text("这个目标可能已被删除，返回列表刷新看看。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.settingsBG)
            }
        }
        .navigationTitle("目标详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showEdit = true }
                    .disabled(goal == nil)
            }
        }
        .task {
            await store.loadDetail(appState: appState, goalID: goalID)
            await loadAssociationStores(force: false)
            materializeGoalEchoes()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await store.revalidateFingerprints(appState: appState)
            }
        }
        .sheet(isPresented: $showEdit) {
            GoalEditView(store: store, goalID: goalID)
        }
        .confirmationDialog(
            "删除这个目标？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除目标", role: .destructive) {
                Task {
                    if await store.delete(
                        appState: appState, goalID: goalID
                    ) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("子目标、进展记录与简报会一并删除。挂在这个目标上的点子会解除关联（点子本身保留）。")
        }
    }

    // MARK: 头部

    private func headerSection(_ goal: BridgeGoal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                Text(goal.title)
                    .font(.detailTitle)
                    .foregroundStyle(Palette.bodyInk)
                HStack(spacing: OneDayMetrics.spacingS) {
                    GoalStatusChip(goal: goal)
                    if goal.source == .chat {
                        Text("对话创建")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let category = goal.category {
                        Label(
                            category.title,
                            systemImage: category.symbolName
                        )
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if !goal.note.isEmpty {
                    Text(goal.note)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, 4)

            if let parentID = goal.parentId,
               let parent = store.goal(id: parentID) {
                NavigationLink {
                    GoalDetailView(store: store, goalID: parent.id)
                } label: {
                    Label("所属目标：\(parent.title)", systemImage: "arrow.turn.up.left")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                }
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: 活动

    @ViewBuilder
    private func activitySection(_ goal: BridgeGoal) -> some View {
        if let activity = goal.activity,
           activity.linkedCount > 0 || activity.note != nil {
            Section {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Circle()
                            .fill(goalActivityDotColor(activity.state))
                            .frame(width: 8, height: 8)
                        Text(activity.state.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.bodyInk)
                        if !activity.label.isEmpty {
                            Text(activity.label)
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    if let focus = activity.focusTask,
                       !focus.title.isEmpty {
                        Text("眼下这件：《\(focus.title)》")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let note = activity.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                SettingsSectionHeader("活动")
            }
            .listRowBackground(Palette.surface)
        }
    }

    // MARK: 简报

    @ViewBuilder
    private func briefingSection(_ goal: BridgeGoal) -> some View {
        Section {
            if let latest = briefings.first {
                NavigationLink {
                    GoalBriefingsView(store: store, goalID: goalID)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latest.title)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.bodyInk)
                            .multilineTextAlignment(.leading)
                        Text(BriefingPresentation.summary(of: latest.body))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(briefingDateLine(latest))
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if detailLoaded {
                Text("还没有简报。每周一早上，系统会按这个目标这周的进展、任务和监测变化写一封；没有进展的那周不会硬凑。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取简报…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            SettingsSectionHeader("简报")
        }
        .listRowBackground(Palette.surface)
    }

    private func briefingDateLine(_ briefing: BridgeBriefing) -> String {
        let date = Date(timeIntervalSince1970: briefing.createdAt)
        return "\(ChatTimeline.dividerText(for: date, now: Date())) · \(briefing.period)"
    }

    private func associationTaskDetail(
        _ linked: GoalAssociations.LinkedTask
    ) -> String {
        let status = linked.task.map { task in
            KanbanStatusPresentation.resolve(
                status: task.status,
                blockKind: task.blockKind,
                lastFailureError: task.lastFailureError
            ).label
        } ?? "任务"
        guard let updatedAt = linked.row.updatedAt
        else { return status }
        let when = ChatTimeline.dividerText(
            for: Date(timeIntervalSince1970: updatedAt), now: Date()
        )
        return "\(status) · \(when)"
    }

    // MARK: 委派

    private func delegationSection(_ goal: BridgeGoal) -> some View {
        Section {
            Button {
                showDelegate = true
            } label: {
                Label("安排一件事", systemImage: "plus.circle")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.primary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .disabled(acting)

            if appState.sessionLedger.threadID(forGoalID: goal.id) != nil {
                Button {
                    openGoalThread()
                } label: {
                    HStack {
                        Label("进展对话", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.bodyInk)
                        Spacer()
                        DisclosureChevron(font: .footnote.weight(.semibold))
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            }
        } header: {
            SettingsSectionHeader("委派与对话")
        } footer: {
            Text("把这个目标下的一件事放上任务板交给智能体办，并和这个目标关联起来；开始、办完或失败，都会记进这个目标的进展对话，进展里也会留一条。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: 关联

    @ViewBuilder
    private func associationSection(_ goal: BridgeGoal) -> some View {
        let ideas = GoalAssociations.ideas(
            for: goalID, in: ideasStore.ideas
        )
        let monitors = GoalAssociations.monitors(
            for: goalID, in: monitorsStore.monitors
        )
        let tasks = GoalAssociations.linkedTasks(
            goalID: goalID,
            rows: store.goalTasksByGoal[goalID] ?? [],
            tasks: kanban.snapshot?.tasks ?? []
        )
        if !GoalAssociations.isEmpty(
            ideas: ideas, tasks: tasks, monitors: monitors
        ) {
            Section {
                ForEach(ideas) { idea in
                    NavigationLink {
                        IdeaDetailView(
                            store: ideasStore, kanban: kanban,
                            ideaID: idea.id
                        )
                    } label: {
                        associationRow(
                            symbol: "lightbulb",
                            title: idea.title,
                            detail: "点子"
                        )
                    }
                }
                ForEach(tasks, id: \.row.id) { linked in
                    NavigationLink {
                        KanbanTaskDetailView(
                            store: kanban,
                            taskID: linked.row.taskId
                        )
                    } label: {
                        associationRow(
                            symbol: "checklist",
                            title: linked.title ?? "任务",
                            detail: associationTaskDetail(linked)
                        )
                    }
                }
                ForEach(monitors) { monitor in
                    NavigationLink {
                        MonitorDetailView(
                            store: monitorsStore,
                            monitorID: monitor.id
                        )
                    } label: {
                        associationRow(
                            symbol: "eye",
                            title: monitor.name,
                            detail: monitor.unreadChanges > 0
                                ? "监测 · \(monitor.unreadChanges) 条未读变化"
                                : "监测"
                        )
                    }
                }
            } header: {
                SettingsSectionHeader("关联")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private func associationRow(
        symbol: String, title: String, detail: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 进展

    private func entriesSection(_ goal: BridgeGoal) -> some View {
        Section {
            HStack(spacing: OneDayMetrics.spacingS) {
                TextField("记一条进展", text: $newEntryBody, axis: .vertical)
                    .lineLimit(1...4)
                Button("记录") {
                    let body = newEntryBody
                    Task {
                        if await store.addEntry(
                            appState: appState, goalID: goalID, body: body
                        ) {
                            newEntryBody = ""
                        }
                    }
                }
                .disabled(
                    acting || newEntryBody.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }

            if !detailLoaded {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取进展…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if entries.isEmpty {
                Text("还没有进展记录。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(entries.reversed()) { entry in
                    entryRow(entry)
                }
            }
        } header: {
            SettingsSectionHeader("进展")
        }
        .listRowBackground(Palette.surface)
    }

    private func entryRow(_ entry: BridgeGoalEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(entry.source == .user ? "你记的" : "智能体记的")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        entry.source == .user
                            ? Palette.primary : Palette.inkSecondary
                    )
                Text(
                    ChatTimeline.dividerText(
                        for: Date(timeIntervalSince1970: entry.createdAt),
                        now: Date()
                    )
                )
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            }
            if let entryTitle = entry.title, !entryTitle.isEmpty {
                Text(entryTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.bodyInk)
            }
            Text(entry.body)
                .font(.body)
                .foregroundStyle(Palette.bodyInk)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    _ = await store.deleteEntry(
                        appState: appState, goalID: goalID,
                        entryID: entry.id
                    )
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    _ = await store.deleteEntry(
                        appState: appState, goalID: goalID,
                        entryID: entry.id
                    )
                }
            } label: {
                Label("删除这条进展", systemImage: "trash")
            }
        }
    }

    // MARK: 子目标

    private func subgoalsSection(_ goal: BridgeGoal) -> some View {
        let children = store.children(of: goalID)
        return Section {
            ForEach(children) { child in
                HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
                    GoalCheckBox(done: child.status == .completed) {
                        Task {
                            _ = await store.setStatus(
                                appState: appState, goalID: child.id,
                                status: child.status == .completed
                                    ? .active : .completed
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.actingIDs.contains(child.id))

                    NavigationLink {
                        GoalDetailView(store: store, goalID: child.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.title)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.bodyInk)
                                .multilineTextAlignment(.leading)
                            let summary = GoalBoard.summary(
                                for: child,
                                latestEntry: child.latestEntry
                            )
                            if !summary.isEmpty {
                                Text(summary)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: OneDayMetrics.spacingS) {
                TextField("新增子目标", text: $newSubgoalTitle)
                Button("添加") {
                    let title = newSubgoalTitle
                    Task {
                        subgoalError = nil
                        if await store.create(
                            appState: appState, title: title, note: "",
                            parentId: goalID
                        ) {
                            newSubgoalTitle = ""
                        } else {
                            subgoalError = store.createError
                        }
                    }
                }
                .disabled(
                    store.creating || newSubgoalTitle.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        } header: {
            SettingsSectionHeader("子目标")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let subgoalError {
                    Text(subgoalError)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                Text("子目标只分一层；完成子目标不会自动完成这个目标。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: 状态与危险动作

    private func actionsSection(_ goal: BridgeGoal) -> some View {
        Section {
            Button {
                Task {
                    _ = await store.setStatus(
                        appState: appState, goalID: goalID,
                        status: goal.status == .completed
                            ? .active : .completed
                    )
                }
            } label: {
                HStack {
                    Spacer()
                    Text(goal.status == .completed ? "重新打开" : "标为完成")
                        .font(.rowTitleL.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .disabled(acting)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("删除目标")
                        .font(.rowTitleL.weight(.medium))
                        .foregroundStyle(Palette.danger)
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .disabled(acting)
        } footer: {
            if let note = store.notes[goalID] {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .listRowBackground(Palette.surface)
    }
}
