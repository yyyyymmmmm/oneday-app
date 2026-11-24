import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// A-11 结构拆分（2026-11-16）：自 GoalsView.swift 按职责拆出（目标详情呈现页），内容逐字未改、零行为变更（DESIGN §311）。

/// 目标详情（0.33.0 P2 呈现页）：打开是「看」不是
/// 「改」——头部分区顺序照设计档 §2.4 定版：头部（标题
/// ＋状态 chip＋里程碑进度条）→ 简报（最新一封信卡）→
/// 里程碑（就地勾选即存）→ 进展（时间线＋记一条）→
/// 子目标 → 状态与危险动作。编辑走右上角「编辑」的
/// 独立 sheet（GoalEditView）。数据全读桥现值，写后
/// 回读确认（GoalsStore 口径）
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
    /// 关联段与委派的对侧数据面（0.40.0）：点子/监测/
    /// 任务板各有自己的 Store 真源，详情页只读拼装
    /// （GoalAssociations），不建本地副本账；委派建卡
    /// 走 kanban 这一个实例，与点子采纳同路
    /// 台账 199：点子店改走 AppState 共享单例（§259
    /// 先例补齐），与点子格／动态格同一份
    private var ideasStore: IdeasStore {
        appState.sharedIdeasStore()
    }
    /// §259 三店合一：监测/任务两店走 AppState 共享
    /// 单例，与枢纽/动态/点子各面同一份，不再随详情
    /// 页私建（委派建卡与点子采纳同路同实例）
    private var monitorsStore: MonitorsStore {
        appState.sharedMonitorsStore()
    }
    private var kanban: KanbanStore {
        appState.sharedKanbanStore()
    }
    @State private var showDelegate = false

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

    /// 关联段三路数据各自回各自的真源刷新（失败保持旧
    /// 数据不翻空，各 Store 自己的口径）
    /// 关联三路：三店同由新鲜度门分流（点子 §367.5、
    /// 监测/看板 §416 收编）——进面（.task）走
    /// loadIfNeeded、下拉强制走 load
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

    /// 委派回响物化（§123 H1）：三路真源（归属行＋任务
    /// 板＋目标本体）都到位后，按 Core GoalEcho 规划把
    /// 还没落过的回响按序落进绑定线程。触发点只有详情
    /// 的首载与下拉刷新这两处——无 APNs 的现实下，回响
    /// 在用户下次打开这个目标时补齐（与动态角标的轮询
    /// 延迟同级约束，§123 记账）；没绑线程的目标（没在
    /// 这里安排过事）直接跳过，不为看一眼详情就建线程
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

    /// 打开这个目标的进展对话（绑定线程）：与点子采纳
    /// 开旁聊同一条切格通道
    private func openGoalThread() {
        guard let threadID = appState.sessionLedger
            .threadID(forGoalID: goalID) else { return }
        appState.router.drawerThreadSelection = threadID
        appState.router.mainTabSwitchRequest = .chat
    }

    var body: some View {
        Group {
            if let goal {
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingL
                    ) {
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
                        if let note = store.notes[goalID] {
                            InlineError(note)
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.top, OneDayMetrics.spacingM)
                    .padding(.bottom, OneDayMetrics.spacingXL)
                }
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
            }
        }
        .background(Palette.pageBG)
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
            // G-3a（2026-11-24）：详情可见期间每 30 秒指
            // 纹重验——本目标指纹变了 store 会回拉条目流，
            // 智能体新记的进展不用退出重进就能看见
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

    // MARK: 头部（标题＋状态在此安家；G-6 后无进度条）

    private func headerSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text(goal.title)
                // 0.41.0（P6）：详情页题收编 FontRoles
                // .detailTitle 定点（值不变）——本页唯
                // 一的第一级，其余全压回角色表
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
                if let parentID = goal.parentId,
                   let parent = store.goal(id: parentID) {
                    NavigationLink {
                        GoalDetailView(store: store, goalID: parent.id)
                    } label: {
                        Label(
                            "所属目标：\(parent.title)",
                            systemImage: "arrow.turn.up.left"
                        )
                        .font(.footnote)
                    }
                    .buttonStyle(.odPressable)
                }
            }
            if !goal.note.isEmpty {
                Text(goal.note)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    // MARK: 活动（GD-1 呈现：桥派生的关联任务活动）

    /// 活动段：状态词＋label 一行（状态点同列表行口
    /// 径），驱动当前状态的那件任务与派生缺口注记在
    /// 下。无关联任务且无注记时整段不显（不摆空壳）；
    /// 旧桥无 activity 时同样不显——活动态只认桥派
    /// 生，不在本地按任务板另算第二份
    @ViewBuilder
    private func activitySection(_ goal: BridgeGoal) -> some View {
        if let activity = goal.activity,
           activity.linkedCount > 0 || activity.note != nil {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("活动")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingS
                ) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Circle()
                            .fill(
                                goalActivityDotColor(activity.state)
                            )
                            .frame(width: 8, height: 8)
                        Text(activity.state.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.bodyInk)
                        if !activity.label.isEmpty {
                            Text(activity.label)
                                .font(.body)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
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
            }
        }
    }

    // MARK: 简报（最新一封信卡，点开读全部）

    @ViewBuilder
    private func briefingSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("简报")
                .padding(.bottom, OneDayMetrics.spacingS)
            if let latest = briefings.first {
                NavigationLink {
                    GoalBriefingsView(store: store, goalID: goalID)
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        HStack {
                            Text(latest.title)
                                // 0.41.0（C14）：链接行题归
                                // .rowTitle
                                .font(.rowTitle)
                                .foregroundStyle(Palette.bodyInk)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            DisclosureChevron(font: .footnote.weight(.semibold))
                        }
                        // GD-3：列表行只给首句摘要
                        // （≤40 字，纯函数口径），全文
                        // 进信件页读，卡面不铺全文
                        Text(BriefingPresentation.summary(of: latest.body))
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(briefingDateLine(latest))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
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
                }
                .buttonStyle(.odPressable)
            } else if detailLoaded {
                Text("还没有简报。每周一早上，系统会按这个目标这周的进展、任务和监测变化写一封；没有进展的那周不会硬凑。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ProgressView()
            }
        }
    }

    private func briefingDateLine(_ briefing: BridgeBriefing) -> String {
        let date = Date(timeIntervalSince1970: briefing.createdAt)
        return "\(ChatTimeline.dividerText(for: date, now: Date())) · \(briefing.period)"
    }

    /// 关联任务行小字（GD-2）：状态（任务板现值）＋
    /// 最近变化时刻（读面一的 updatedAt）；桥没观察
    /// 到过这条任务的变化时只给状态，时刻不编
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
        // 最近变化时刻就在归属行上（GD-2 面一，§308 后
        // 行与关联同为一物，不再跨面回查）
        guard let updatedAt = linked.row.updatedAt
        else { return status }
        let when = ChatTimeline.dividerText(
            for: Date(timeIntervalSince1970: updatedAt), now: Date()
        )
        return "\(status) · \(when)"
    }

    // MARK: 委派（安排一件事，0.40.0 欠账补落）

    /// 目标下直接委派：入口开 GoalDelegateView 表单，提交
    /// 走 GoalsStore.delegateTask（桥一次调用建卡＋写
    /// goalId 字段＋回读确认，§308 单轨）。任务办完后
    /// 桥会在进展里自动记一条事实（来源「智能体记的」）
    private func delegationSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("安排一件事")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                Button {
                    showDelegate = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: "plus.circle")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                        Text("安排一件事")
                            .font(.body)
                            .foregroundStyle(Palette.bodyInk)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
                .buttonStyle(.odPressable)
                .disabled(acting)
                // §123（H1）：已绑进展对话时给入口——回响
                // 落在对话里，用户得有路点进去（新面准
                // 入四问①：有落点必须有入口）
                if appState.sessionLedger.threadID(forGoalID: goal.id) != nil {
                    GroupDivider()
                    Button {
                        openGoalThread()
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                            Text("进展对话")
                                .font(.body)
                                .foregroundStyle(Palette.bodyInk)
                            Spacer()
                            DisclosureChevron(font: .system(size: 13, weight: .regular))
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                    }
                    .buttonStyle(.odPressable)
                }
            }
            .odGroup()
            Text("把这个目标下的一件事放上任务板交给智能体办，并和这个目标关联起来；开始、办完或失败，都会记进这个目标的进展对话，进展里也会留一条。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
        }
    }

    // MARK: 关联（0.40.0 欠账补落：客户端拼装、零新端点）

    /// 挂靠点子（ideas 按 goalId 过滤）＋关联任务（任务
    /// 的 goalId 字段经桥 GD-2 行投影、再拼任务板现值）
    /// ＋挂靠监测（monitor.goalId），三路只读呈现、点行
    /// 各自跳到对方详情/管理；全空时整段不出现，不留
    /// 空壳标题
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
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("关联")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(
                        Array(ideas.enumerated()), id: \.element.id
                    ) { index, idea in
                        if index > 0 {
                            GroupDivider()
                        }
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
                        .buttonStyle(.odPressable)
                    }
                    ForEach(
                        Array(tasks.enumerated()),
                        id: \.element.row.id
                    ) { index, linked in
                        if index > 0 || !ideas.isEmpty {
                            GroupDivider()
                        }
                        NavigationLink {
                            KanbanTaskDetailView(
                                store: kanban,
                                taskID: linked.row.taskId
                            )
                        } label: {
                            associationRow(
                                symbol: "checklist",
                                title: linked.title ?? "任务",
                                detail: associationTaskDetail(
                                    linked
                                )
                            )
                        }
                        .buttonStyle(.odPressable)
                    }
                    ForEach(
                        Array(monitors.enumerated()),
                        id: \.element.id
                    ) { index, monitor in
                        if index > 0 || !ideas.isEmpty
                            || !tasks.isEmpty {
                            GroupDivider()
                        }
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
                        .buttonStyle(.odPressable)
                    }
                }
                .odGroup()
            }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DisclosureChevron(font: .footnote.weight(.semibold))
        }
        .contentShape(Rectangle())
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
    }

    // MARK: 进展（时间线＋记一条）

    private func entriesSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("进展")
                .padding(.bottom, OneDayMetrics.spacingS)
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
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .odGroup()
            if !detailLoaded {
                ProgressView()
                    .padding(.top, OneDayMetrics.spacingSM)
            } else if entries.isEmpty {
                Text("还没有进展记录。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingSM)
            } else {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    ForEach(entries.reversed()) { entry in
                        entryRow(entry)
                    }
                }
                .padding(.top, OneDayMetrics.spacingSM)
            }
        }
    }

    private func entryRow(_ entry: BridgeGoalEntry) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(entry.source == .user ? "你记的" : "智能体记的")
                    // 0.41.0（P6）：元信息标回收 footnote
                    // regular，与同行时间戳同级
                    .font(.footnote)
                    .foregroundStyle(
                        entry.source == .user
                            ? Palette.bodyInk : Palette.inkSecondary
                    )
                Text(
                    ChatTimeline.dividerText(
                        for: Date(timeIntervalSince1970: entry.createdAt),
                        now: Date()
                    )
                )
                .font(.footnote)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

    // MARK: 子目标（一层封顶）

    private func subgoalsSection(_ goal: BridgeGoal) -> some View {
        let children = store.children(of: goalID)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("子目标")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.element.id) {
                    index, child in
                    if index > 0 {
                        GroupDivider()
                    }
                    HStack(
                        alignment: .top, spacing: OneDayMetrics.spacingS
                    ) {
                        GoalCheckBox(done: child.status == .completed) {
                            Task {
                                _ = await store.setStatus(
                                    appState: appState, goalID: child.id,
                                    status: child.status == .completed
                                        ? .active : .completed
                                )
                            }
                        }
                        .disabled(store.actingIDs.contains(child.id))
                        NavigationLink {
                            GoalDetailView(store: store, goalID: child.id)
                        } label: {
                            VStack(
                                alignment: .leading, spacing: OneDayMetrics.stackGap
                            ) {
                                Text(child.title)
                                    // 0.41.0（C14）：行题归
                                    // .rowTitle
                                    .font(.rowTitle)
                                    .foregroundStyle(Palette.bodyInk)
                                    .multilineTextAlignment(.leading)
                                let summary = GoalBoard.summary(
                                    for: child,
                                    latestEntry: child.latestEntry
                                )
                                if !summary.isEmpty {
                                    Text(summary)
                                        .font(.footnote)
                                        .foregroundStyle(
                                            Palette.inkSecondary
                                        )
                                        .lineLimit(1)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(
                                maxWidth: .infinity, alignment: .leading
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
                if !children.isEmpty {
                    GroupDivider()
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
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingSM)
            }
            .odGroup()
            if let subgoalError {
                Text(subgoalError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .padding(.top, OneDayMetrics.spacingS)
            }
            Text("子目标只分一层；完成子目标不会自动完成这个目标。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
        }
    }

    // MARK: 状态与危险动作

    private func actionsSection(_ goal: BridgeGoal) -> some View {
        VStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                Task {
                    _ = await store.setStatus(
                        appState: appState, goalID: goalID,
                        status: goal.status == .completed
                            ? .active : .completed
                    )
                }
            } label: {
                Text(
                    goal.status == .completed
                        ? "重新打开" : "标为完成"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(acting)
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Text("删除目标")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(acting)
        }
    }
}

