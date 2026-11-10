import OneDayCore
import OneDayDesign
import SwiftUI

/// 目标格（0.11.0 P4 转正；0.33.0 P2 改呈现形态）：列表
/// 照 Muse 目标行实测形态——状态分组（色点组头）＋扁平
/// 行（22pt 方形勾选框＝完成开关、标题、进展摘要、⋮
/// 菜单），里程碑进度条退出列表行、移详情头部；详情改
/// 「呈现页」（简报/里程碑/进展时间线/子目标/状态动作），
/// 编辑收进独立编辑 sheet。桥未连接/未开通如实露、零假
/// 数据；写动作全部走 GoalsStore 的回读确认口径。
struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = GoalsStore()
    @State private var showCreate = false
    @State private var expandedActive = false
    @State private var showCompletedGroup = false
    @State private var expandedCompleted = false
    @State private var editTarget: BridgeGoal?
    @State private var deleteTarget: BridgeGoal?

    var body: some View {
        NavigationStack {
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
                case .failed(let message):
                    ContentUnavailableView {
                        Label("目标读取失败", systemImage: "exclamationmark.triangle")
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
            .background(Palette.pageBG)
            .navigationTitle("目标")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建目标", systemImage: "plus")
                    }
                }
            }
            .task {
                await store.load(appState: appState)
            }
            .sheet(isPresented: $showCreate) {
                GoalCreateView(store: store)
            }
            .sheet(item: $editTarget) { goal in
                GoalEditView(store: store, goalID: goal.id)
            }
            .confirmationDialog(
                "删除这个目标？",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { goal in
                Button("删除目标", role: .destructive) {
                    Task {
                        _ = await store.delete(
                            appState: appState, goalID: goal.id
                        )
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("子目标、进展记录与简报会一并删除。挂在这个目标上的点子会解除关联（点子本身保留）。")
            }
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if store.goals.isEmpty {
            ContentUnavailableView(
                "暂无目标",
                systemImage: "checklist",
                description: Text("点右上角＋新建第一个目标")
            )
        } else {
            let groups = GoalBoard.grouped(store.goals)
            ScrollView {
                LazyVStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    if !groups.active.isEmpty {
                        goalGroup(
                            title: "进行中", completed: false,
                            goals: groups.active,
                            expanded: $expandedActive
                        )
                    }
                    if !groups.completed.isEmpty {
                        completedGroup(goals: groups.completed)
                    }
                    createArea
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .refreshable {
                await store.load(appState: appState)
            }
        }
    }

    /// 状态分组（照 Muse 行形态）：色点组头＋扁平行，
    /// 超过 4 条折叠为「显示另外N项」
    private func goalGroup(
        title: String, completed: Bool, goals: [BridgeGoal],
        expanded: Binding<Bool>
    ) -> some View {
        let folded = GoalBoard.folded(goals, expanded: expanded.wrappedValue)
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            GoalGroupHeader(title: title, completed: completed)
            ForEach(folded.visible) { goal in
                GoalRowView(
                    store: store,
                    goal: goal,
                    summary: GoalBoard.summary(
                        for: goal, latestEntry: goal.latestEntry
                    ),
                    acting: store.actingIDs.contains(goal.id),
                    onToggleStatus: {
                        Task {
                            _ = await store.setStatus(
                                appState: appState, goalID: goal.id,
                                status: goal.status == .completed
                                    ? .active : .completed
                            )
                        }
                    },
                    onEdit: { editTarget = goal },
                    onDelete: { deleteTarget = goal }
                )
                if let note = store.notes[goal.id] {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if folded.hiddenCount > 0 {
                Button {
                    expanded.wrappedValue = true
                } label: {
                    Label(
                        "显示另外\(folded.hiddenCount)项",
                        systemImage: "ellipsis"
                    )
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                }
                .buttonStyle(.odPressable)
            }
        }
    }

    /// 已完成组：默认收起，点头展开（组内同样 4 条折叠）
    private func completedGroup(goals: [BridgeGoal]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            Button {
                showCompletedGroup.toggle()
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    GoalGroupHeader(
                        title: "已完成", completed: true
                    )
                    Text("\(goals.count)")
                        .font(.body)
                        .foregroundStyle(Palette.inkMuted)
                    Spacer()
                    Image(systemName: showCompletedGroup
                          ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            if showCompletedGroup {
                let folded = GoalBoard.folded(
                    goals, expanded: expandedCompleted
                )
                ForEach(folded.visible) { goal in
                    GoalRowView(
                        store: store,
                        goal: goal,
                        summary: GoalBoard.summary(
                            for: goal, latestEntry: goal.latestEntry
                        ),
                        acting: store.actingIDs.contains(goal.id),
                        onToggleStatus: {
                            Task {
                                _ = await store.setStatus(
                                    appState: appState, goalID: goal.id,
                                    status: .active
                                )
                            }
                        },
                        onEdit: { editTarget = goal },
                        onDelete: { deleteTarget = goal }
                    )
                    if let note = store.notes[goal.id] {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                            .frame(
                                maxWidth: .infinity, alignment: .leading
                            )
                    }
                }
                if folded.hiddenCount > 0 {
                    Button {
                        expandedCompleted = true
                    } label: {
                        Label(
                            "显示另外\(folded.hiddenCount)项",
                            systemImage: "ellipsis"
                        )
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
    }

    /// 列表底常驻创建区（照 Muse 目标页图位置）：分隔线
    /// 下「＋ 创建目标」＋一句说明；点入走新建表单 sheet
    private var createArea: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider()
            Button {
                showCreate = true
            } label: {
                Label("创建目标", systemImage: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.bodyInk)
            }
            .buttonStyle(.odPressable)
            Text("起个名字、写下备注和里程碑，目标就会出现在这里，进展和简报会慢慢长出来。")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }
}

/// 分组头：浅色圆底＋状态点＋组名（进行中绿系、已完成
/// 灰系——已完成形态图上未见，色口径为推定，照设计档
/// §2.4 登记）
struct GoalGroupHeader: View {
    let title: String
    let completed: Bool

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            ZStack {
                Circle()
                    .fill(completed ? Palette.surface : Palette.tintGreen)
                    .frame(width: 17, height: 17)
                Circle()
                    .fill(completed ? Palette.inkMuted : Palette.success)
                    .frame(width: 6.5, height: 6.5)
            }
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    completed ? Palette.inkSecondary : Palette.success
                )
        }
    }
}

/// 目标方形勾选框（22pt，照 Muse 行实测）：即状态开关
/// ——点框标完成/重开，走 PATCH 回读口径（调用方负责）
struct GoalCheckBox: View {
    let done: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(done ? Palette.ink : Color.clear)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        done ? Color.clear : Palette.hairline,
                        lineWidth: 1.5
                    )
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }
}

/// 目标扁平行：勾选框（状态开关）＋标题/进展摘要（点进
/// 详情）＋⋮ 菜单（编辑/状态/删除收进菜单，照设计档）
struct GoalRowView: View {
    let store: GoalsStore
    let goal: BridgeGoal
    let summary: String
    let acting: Bool
    var onToggleStatus: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
            GoalCheckBox(done: goal.status == .completed) {
                onToggleStatus()
            }
            .disabled(acting)
            .padding(.top, 2)
            NavigationLink {
                GoalDetailView(store: store, goalID: goal.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.bodyInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("编辑目标", systemImage: "pencil")
                }
                Button {
                    onToggleStatus()
                } label: {
                    Label(
                        goal.status == .completed ? "重新打开" : "标为完成",
                        systemImage: goal.status == .completed
                            ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除目标", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .rotationEffect(.degrees(90))
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .disabled(acting)
        }
    }

}

/// 里程碑 CheckRow（设计标准 §7 P4 锚，ui.tsx CheckRow
/// 原式）：19 方框、圆角 6；勾选＝ink 底白勾；未勾＝
/// 发丝描边空格。标题可编辑时右侧跟一行输入，本组件
/// 只管勾选与标题展示/编辑的排版
struct MilestoneCheckRow: View {
    let done: Bool
    let title: String
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(done ? Palette.ink : Color.clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            done ? Color.clear : Palette.hairline,
                            lineWidth: 1.5
                        )
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 19, height: 19)
                Text(title)
                    .font(.body)
                    .foregroundStyle(
                        done ? Palette.inkSecondary : Palette.bodyInk
                    )
                    .strikethrough(done, color: Palette.inkMuted)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }
}

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

    let store: GoalsStore
    let goalID: String

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var newEntryBody = ""
    @State private var newSubgoalTitle = ""
    @State private var subgoalError: String?

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

    var body: some View {
        Group {
            if let goal {
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingL
                    ) {
                        headerSection(goal)
                        briefingSection(goal)
                        milestonesSection(goal)
                        entriesSection(goal)
                        if goal.parentId == nil {
                            subgoalsSection(goal)
                        }
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

    // MARK: 头部（标题＋状态＋进度条在此安家）

    private func headerSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text(goal.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.bodyInk)
            HStack(spacing: OneDayMetrics.spacingS) {
                GoalStatusChip(goal: goal)
                if goal.source == .chat {
                    Text("对话创建")
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
            if !goal.milestones.isEmpty {
                HStack(spacing: OneDayMetrics.spacingS) {
                    DataBar(
                        fraction: GoalProgress.fraction(of: goal),
                        height: 4
                    )
                    Text("\(GoalProgress.text(of: goal)) 里程碑")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .tabularDigits()
                }
            }
            if goal.status == .active,
               GoalBoard.allMilestonesDone(goal) {
                Label(
                    "里程碑已全部完成，可以标为完成了",
                    systemImage: "checkmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(Palette.success)
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
                                .font(.headline)
                                .foregroundStyle(Palette.bodyInk)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.inkMuted)
                        }
                        Text(latest.body)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        Text(briefingDateLine(latest))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
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

    // MARK: 里程碑（就地勾选即存）

    private func milestonesSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("里程碑")
                .padding(.bottom, OneDayMetrics.spacingS)
            if goal.milestones.isEmpty {
                Text("暂无里程碑，点右上角「编辑」添加。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(goal.milestones.enumerated()),
                        id: \.element.id
                    ) { index, milestone in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        MilestoneCheckRow(
                            done: milestone.done, title: milestone.title
                        ) {
                            Task {
                                _ = await store.toggleMilestone(
                                    appState: appState, goalID: goalID,
                                    milestoneID: milestone.id
                                )
                            }
                        }
                        .disabled(acting)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                    }
                }
                .odGroup()
            }
        }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(entry.source == .user ? "你记的" : "智能体记的")
                    .font(.footnote.weight(.semibold))
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
                .foregroundStyle(Palette.inkMuted)
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
                        GroupDivider(inset: OneDayMetrics.spacingM)
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
                                alignment: .leading, spacing: 3
                            ) {
                                Text(child.title)
                                    .font(.body.weight(.medium))
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
                    GroupDivider(inset: OneDayMetrics.spacingM)
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    TextField("新增子目标", text: $newSubgoalTitle)
                    Button("添加") {
                        let title = newSubgoalTitle
                        Task {
                            subgoalError = nil
                            if await store.create(
                                appState: appState, title: title, note: "",
                                milestoneTitles: [], parentId: goalID
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
                .foregroundStyle(Palette.inkMuted)
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

/// 状态 chip：进行中＝绿点＋绿字浅底；已完成＝灰字，
/// 带完成时刻（桥落字的 completedAt，相对时间口径）
struct GoalStatusChip: View {
    let goal: BridgeGoal

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(
                    goal.status == .completed
                        ? Palette.inkMuted : Palette.success
                )
                .frame(width: 6.5, height: 6.5)
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    goal.status == .completed
                        ? Palette.inkSecondary : Palette.success
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            goal.status == .completed ? Palette.surface : Palette.tintGreen,
            in: Capsule()
        )
    }

    private var label: String {
        switch goal.status {
        case .active:
            return "进行中"
        case .completed:
            if let completedAt = goal.completedAt {
                let when = ChatTimeline.dividerText(
                    for: Date(timeIntervalSince1970: completedAt),
                    now: Date()
                )
                return "已完成 · \(when)"
            }
            return "已完成"
        }
    }
}

/// 简报全文页：一封一封的信（标题＋日期行＋正文段落），
/// 只读——简报正文不许在客户端改（设计档状态机口径，
/// 纠错靠新条目）
struct GoalBriefingsView: View {
    let store: GoalsStore
    let goalID: String

    private var briefings: [BridgeBriefing] {
        store.briefingsByGoal[goalID] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                if briefings.isEmpty {
                    Text("还没有简报。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(briefings) { briefing in
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        Text(briefing.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.bodyInk)
                        Text(
                            "\(ChatTimeline.dividerText(for: Date(timeIntervalSince1970: briefing.createdAt), now: Date())) · \(briefing.period)"
                        )
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        ForEach(
                            Array(
                                briefing.body
                                    .components(separatedBy: "\n\n")
                                    .enumerated()
                            ),
                            id: \.offset
                        ) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(Palette.bodyInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if briefing.id != briefings.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("简报")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 目标编辑（sheet，0.33.0 自详情拆出）：草稿全量编辑
/// ——标题/备注/里程碑勾选·改名·增删都在本地草稿里改，
/// 保存时一次 PATCH 全量替换（已有里程碑 id 原样带
/// 回）＋回读逐项对账确认（GoalsStore.saveEdits）
struct GoalEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: GoalsStore
    let goalID: String

    @State private var title: String
    @State private var note: String
    @State private var milestones: [MilestoneDraftState]
    @State private var newMilestoneTitle = ""
    @State private var isSaving = false
    @State private var saveError: String?

    init(store: GoalsStore, goalID: String) {
        self.store = store
        self.goalID = goalID
        let goal = store.goal(id: goalID)
        _title = State(initialValue: goal?.title ?? "")
        _note = State(initialValue: goal?.note ?? "")
        _milestones = State(initialValue: (goal?.milestones ?? []).map {
            MilestoneDraftState(id: $0.id, title: $0.title, done: $0.done)
        })
    }

    private var acting: Bool {
        isSaving || store.actingIDs.contains(goalID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    fieldsGroup
                    milestonesGroup
                    if let saveError {
                        InlineError(saveError)
                    }
                    if let note = store.notes[goalID] {
                        InlineError(note)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(acting || title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                }
            }
        }
    }

    private var fieldsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("目标")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                FieldRow(label: "标题") {
                    TextField("目标标题", text: $title)
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                FieldRow(label: "备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .odGroup()
        }
    }

    private var milestonesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("里程碑")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(milestones.indices, id: \.self) { index in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    HStack(spacing: OneDayMetrics.spacingS) {
                        MilestoneCheckRow(
                            done: milestones[index].done,
                            title: milestones[index].title
                        ) {
                            milestones[index].done.toggle()
                        }
                        Button(role: .destructive) {
                            milestones.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Palette.inkMuted)
                                .frame(
                                    width: OneDayMetrics.minTapTarget,
                                    height: OneDayMetrics.minTapTarget
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
                if !milestones.isEmpty {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    TextField("新增里程碑", text: $newMilestoneTitle)
                    Button("添加") {
                        let trimmed = newMilestoneTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard !trimmed.isEmpty else { return }
                        milestones.append(
                            MilestoneDraftState(
                                id: nil, title: trimmed, done: false
                            )
                        )
                        newMilestoneTitle = ""
                    }
                    .disabled(newMilestoneTitle.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingSM)
            }
            .odGroup()
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let ok = await store.saveEdits(
            appState: appState, goalID: goalID, title: title,
            note: note, milestones: milestones
        )
        if ok {
            dismiss()
        } else {
            saveError = store.notes[goalID]
        }
    }
}

/// 新建目标（sheet）：标题＋备注＋里程碑标题行（可多
/// 行添加），创建走 GoalsStore 的回读确认——确认出现
/// 才关表单，未确认原因留表单内
struct GoalCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: GoalsStore

    @State private var title = ""
    @State private var note = ""
    @State private var milestoneTitles: [String] = []

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("目标")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            FieldRow(label: "标题") {
                                TextField("如：婚礼筹备收尾", text: $title)
                            }
                            GroupDivider(inset: OneDayMetrics.spacingM)
                            FieldRow(label: "备注") {
                                TextField("可选", text: $note, axis: .vertical)
                                    .lineLimit(2...5)
                            }
                        }
                        .odGroup()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("里程碑（可选）")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            ForEach(milestoneTitles.indices, id: \.self) { index in
                                if index > 0 {
                                    GroupDivider(inset: OneDayMetrics.spacingM)
                                }
                                HStack(spacing: OneDayMetrics.spacingS) {
                                    TextField(
                                        "里程碑 \(index + 1)",
                                        text: $milestoneTitles[index]
                                    )
                                    Button(role: .destructive) {
                                        milestoneTitles.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(Palette.inkMuted)
                                            .frame(
                                                width: OneDayMetrics.minTapTarget,
                                                height: OneDayMetrics.minTapTarget
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.odPressable)
                                }
                                .padding(.horizontal, OneDayMetrics.spacingM)
                                .padding(.vertical, OneDayMetrics.spacingSM)
                            }
                            if !milestoneTitles.isEmpty {
                                GroupDivider(inset: OneDayMetrics.spacingM)
                            }
                            Button {
                                milestoneTitles.append("")
                            } label: {
                                Label("添加里程碑", systemImage: "plus.circle")
                            }
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .padding(.vertical, OneDayMetrics.spacingSM)
                        }
                        .odGroup()
                    }
                    if let error = store.createError {
                        InlineError(error)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("新建目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.creating ? "创建中…" : "创建") {
                        Task {
                            if await store.create(
                                appState: appState, title: title,
                                note: note, milestoneTitles: milestoneTitles
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValid || store.creating)
                }
            }
        }
    }
}
