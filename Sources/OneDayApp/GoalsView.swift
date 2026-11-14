import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 目标格（0.11.0 P4 转正；0.33.0 P2 改呈现形态）：列表
/// 照 Muse 目标行实测形态——状态分组（色点组头）＋扁平
/// 行（22pt 方形勾选框＝完成开关、标题、进展摘要、⋮
/// 菜单），里程碑进度条退出列表行、移详情头部；详情改
/// 「呈现页」（简报/里程碑/进展时间线/子目标/状态动作），
/// 编辑收进独立编辑 sheet。桥未连接/未开通如实露、零假
/// 数据；写动作全部走 GoalsStore 的回读确认口径。
/// 创建流（0.40.0 两步：选分类→表单；§238 改三步
/// 终局：选分类→介绍卡→开目标旁聊在对话里聊定，
/// GA-1/GA-2 定版）——空态整页与有目标时的底部创
/// 建区/工具栏共用同一条流（分类组件
/// GoalCategoryRowsView 共用）；表单降为介绍卡上
/// 的次级入口「直接填写」，不删
private enum GoalCreateSheet: Identifiable {
    case categories
    case intro(GoalCategory)
    case form(GoalCategory?)

    var id: String {
        switch self {
        case .categories:
            return "categories"
        case .intro(let category):
            return "intro-\(category.rawValue)"
        case .form(let category):
            return "form-\(category?.rawValue ?? "none")"
        }
    }
}

struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var store = GoalsStore()
    @State private var createSheet: GoalCreateSheet?
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
                        Label("还没连上你的服务", systemImage: "link.badge.plus")
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
                        Label("目标没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
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
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            .navigationTitle("目标")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createSheet = .categories
                    } label: {
                        Label("新建目标", systemImage: "plus")
                    }
                }
            }
            .task {
                await store.load(appState: appState)
            }
            .sheet(item: $createSheet) { sheet in
                switch sheet {
                case .categories:
                    GoalCategorySheetView { category in
                        createSheet = .intro(category)
                    }
                case .intro(let category):
                    GoalIntroView(
                        category: category,
                        onStart: { openGoalChat(category) },
                        onForm: { createSheet = .form(category) }
                    )
                case .form(let category):
                    GoalCreateView(
                        store: store, presetCategory: category
                    )
                }
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

    /// 开目标旁聊（GA-1/GA-2 终局，§238）：新建一条旁
    /// 聊线程（本地出生记录，与点子开旁聊同一条链），
    /// 目标创建引用直写其待发状态（§219 引用道：不代
    /// 发、不写草稿账），切聊天格。目标本体不在这里
    /// 建——在对话里聊定后由智能体经 goals_create 落
    /// 桥（source=chat），回目标页回读列表见它出现才
    /// 算落定，不在此假报已创建
    private func openGoalChat(_ category: GoalCategory) {
        let fresh = ChatThread()
        modelContext.insert(fresh)
        try? modelContext.save()
        appState.pendingSourceQuotesByThread[fresh.id] =
            .goal(GoalQuote(category: category))
        appState.drawerThreadSelection = fresh.id
        appState.mainTabSwitchRequest = .chat
        createSheet = nil
    }

    @ViewBuilder
    private var readyContent: some View {
        if store.goals.isEmpty {
            categoryCreateFlow
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
                    if !store.ungroupedTasks.isEmpty
                        || store.ungroupedNote != nil {
                        ungroupedSection
                    }
                    createArea
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .refreshable {
                await store.load(appState: appState)
            }
            // §170（用户 2026-11-11 23:28 亲定）：底部导
            // 航栏同档收边（与输入框下方收边同档）——本页根 Scroll-
            // View 底缘挂 .hard，口径与映射见 FeedView
            // 同注与 DESIGN §170.2
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    /// 无目标态整页＝分类创建流（0.40.0，规格第三章；
    /// §238 改三步终局）：「＋创建目标」标题行＋一句实
    /// 话说明＋七分类行；点一行先出该分类的介绍卡，
    /// 「开始吧」开目标旁聊在对话里聊定（GA-1/GA-2），
    /// 表单是介绍卡上的次级入口。普通空态（「暂无目
    /// 标」＋单个按钮）自 0.40.0 废弃
    private var categoryCreateFlow: some View {
        ScrollView {
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingL
            ) {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingS
                ) {
                    Label("创建目标", systemImage: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.bodyInk)
                    Text("选一个类别，接下来在对话里把目标聊定。定好之后，它的进展、任务和简报会慢慢长出来。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                GoalCategoryRowsView { category in
                    createSheet = .intro(category)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingM)
        }
        .refreshable {
            await store.load(appState: appState)
        }
        // §170：无目标态（分类创建流）与有目标态同为本
        // 格根滚动面，底缘同挂 .hard（口径见 ready-
        // Content 同注）
        // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
        .scrollEdgeEffectStyle(.soft, for: .bottom)
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

    /// 未归类任务区（GD-2，调和读法）：你在对话里安
    /// 排的、采纳点子时生成的任务，还没归到任何目标
    /// 下的集中在这里，点「归组」选一个目标即可；归
    /// 组后它的进展会记到那个目标里。纯系统/定时任
    /// 务不在此面（归台账）。此区只呈现＋用户点归，
    /// 系统不自动归组【归类口径：2026-11-14 19:05
    /// 用户拍板，按审计提案落码视同已追认】
    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("未归类任务")
                .padding(.bottom, OneDayMetrics.spacingXS)
            Text("在对话里安排的、采纳点子时生成的任务，还没归到目标下。归组后，它的进展会记到那个目标里。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(store.ungroupedTasks, id: \.taskId) { row in
                    if row.taskId
                        != store.ungroupedTasks.first?.taskId {
                        GroupDivider()
                    }
                    UngroupedTaskRowView(
                        row: row,
                        detail: ungroupedRowDetail(row),
                        targets: store.goals.filter {
                            $0.status == .active
                        }
                    ) { goalID in
                        Task {
                            await store.assignUngroupedTask(
                                appState: appState,
                                taskID: row.taskId,
                                toGoalID: goalID
                            )
                        }
                    }
                }
            }
            if let note = store.ungroupedNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .padding(.top, OneDayMetrics.spacingS)
            }
        }
    }

    /// 未归类行小字：状态（桥给的原生状态经既有状态
    /// 呈现解析）＋来源；状态缺失时只给来源，不编
    private func ungroupedRowDetail(
        _ row: BridgeUngroupedTask
    ) -> String {
        let origin = UngroupedTaskPresentation.originLabel(row.origin)
        guard let status = row.status else { return origin }
        let label = KanbanStatusPresentation.resolve(
            status: status, blockKind: nil, lastFailureError: nil
        ).label
        return "\(label) · \(origin)"
    }

    /// 列表底常驻创建区（照 Muse 目标页图位置）：分隔线
    /// 下「＋ 创建目标」＋一句说明；点入先出分类选择（与
    /// 空态同一分类组件），选完出介绍卡（§238 三步流）
    private var createArea: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider()
            Button {
                createSheet = .categories
            } label: {
                Label("创建目标", systemImage: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.bodyInk)
            }
            .buttonStyle(.odPressable)
            Text("先选一个类别，再到对话里把目标聊定。定好之后它会出现在这里，进展和简报会慢慢长出来。")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }
}

/// 未归类任务行（GD-2）：标题＋状态/来源小字＋右端
/// 「归组」菜单（选进行中目标即归组，动作经 onAssign
/// 回到列表页的 Store 调用）。独立成 View 与列表页
/// 解耦（同 GoalRowView 的拆分先例）
struct UngroupedTaskRowView: View {
    let row: BridgeUngroupedTask
    let detail: String
    let targets: [BridgeGoal]
    let onAssign: (String) -> Void

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "checklist")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(targets, id: \.id) { goal in
                    Button(goal.title) {
                        onAssign(goal.id)
                    }
                }
            } label: {
                Text("归组")
                    .font(.body)
                    .foregroundStyle(Palette.primary)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingSM)
    }
}

/// 分类七行（0.40.0）：图标＋类名＋右端「＋」，空态整页
/// 与分类选择 sheet 共用同一组件（规格第三章：同一分类
/// 组件两处复用）。图标走 SF Symbols 同语义位（宪法
/// §4），不仿绘参照图的 3D/字形原图
struct GoalCategoryRowsView: View {
    var onPick: (GoalCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(GoalCategory.creationOrder.enumerated()),
                id: \.element
            ) { index, category in
                if index > 0 {
                    GroupDivider()
                }
                Button {
                    onPick(category)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: category.symbolName)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 24)
                        Text(category.title)
                            .font(.body)
                            .foregroundStyle(Palette.bodyInk)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
                .buttonStyle(.odPressable)
            }
        }
        .odGroup()
    }
}

/// 分类选择 sheet（有目标时从底部创建区/工具栏进入）：
/// 选完把分类交给上层换成介绍卡（同一个 sheet 内换
/// 内容，不叠第二层 sheet；§238 前是换新建表单）
struct GoalCategorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (GoalCategory) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    Text("选一个类别，接下来在对话里把目标聊定。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    GoalCategoryRowsView(onPick: onPick)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("创建目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// 分类介绍卡（GA-1，§238）：点分类后的第二步——
/// 分类图标＋「创建X目标」题＋介绍文（Core introLead
/// 首句＋流程说明两句），说清这一类会怎么聊定、定
/// 好之后长在哪里。主钮「开始吧」＝开目标旁聊在对
/// 话里聊定（GA-2 终局：目标由智能体在对话里经
/// goals_create 落桥、source=chat）；次级入口
/// 「直接填写」走现行表单（不会聊的用户有退路，
/// 规格 GA-1 定版——表单不删、只降次级）
struct GoalIntroView: View {
    @Environment(\.dismiss) private var dismiss
    let category: GoalCategory
    var onStart: () -> Void
    var onForm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        Image(systemName: category.symbolName)
                            .font(.title)
                            .foregroundStyle(Palette.primary)
                            .frame(width: 52, height: 52)
                            .background(
                                Palette.fieldFill,
                                in: Circle()
                            )
                        Text("创建\(category.title)目标")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.bodyInk)
                        Text(category.introLead)
                            .font(.body)
                            .foregroundStyle(Palette.bodyInk)
                        Text("点「开始吧」会打开一条新对话，在对话里把这个目标聊定——想达成什么、怎么衡量、拆成哪些里程碑。聊定之后，目标会出现在这里，它的进展、任务和简报会慢慢长出来。")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    VStack(spacing: OneDayMetrics.spacingS) {
                        Button {
                            onStart()
                        } label: {
                            Text("开始吧")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    Palette.primary, in: Capsule()
                                )
                        }
                        .buttonStyle(.odPressable)
                        Button {
                            onForm()
                        } label: {
                            Text("直接填写")
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.odPressable)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("创建目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
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
                // 0.41.0（C14 同账）：组头回收 regular，
                // 分段靠状态色与位置、不靠字重
                .font(.body)
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
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
                    .fill(done ? Palette.ink : Color.clear)
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
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
            // 命中域 44×44（视觉框 22 不变）：-11 内
            // 边距抵消额外命中域、不改行布局
            // （0.36.0，无障碍 A11Y-V1/T1）
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(-11)
        }
        .buttonStyle(.odPressable)
        // 开关语义（A11Y-V5）：动作标签＋状态值，
        // VoiceOver 能读出「这是什么开关、现在什么
        // 状态」，不再是无标签裸按钮
        .accessibilityLabel(done ? "重新打开目标" : "标记目标完成")
        .accessibilityValue(done ? "已完成" : "未完成")
        // 触感矩阵（0.36.2，规格 §2.3/§2.5）：勾选
        // 完成＝notification success；只在 未完成→
        // 完成 边沿响（done 是回读确认后的真状态，
        // 响在落定刻）；取消勾选不对称、不加
        .sensoryFeedback(.success, trigger: done) { old, new in
            !old && new
        }
    }
}

/// 目标扁平行：勾选框（状态开关）＋标题/进展摘要（点进
/// 详情）＋⋮ 菜单（编辑/状态/删除收进菜单，照设计档）
/// 活动状态点色（GD-1 呈现）：正在办＝主色、卡住
/// 了＝危险色、等着/闲置＝弱灰（与组头状态点同语
/// 义：色只表状态、不作装饰）
private func goalActivityDotColor(
    _ state: GoalActivityState
) -> Color {
    switch state {
    case .running: return Palette.primary
    case .blocked: return Palette.danger
    case .waiting, .idle: return Palette.inkMuted
    }
}

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
            .padding(.top, OneDayMetrics.spacingMicro)
            NavigationLink {
                GoalDetailView(store: store, goalID: goal.id)
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                    Text(goal.title)
                        // 0.41.0（C14）：列表行题归角色表
                        // .rowTitle（Body regular），全 App
                        // 行题单轨
                        .font(.rowTitle)
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
                    // 活动行（GD-1 呈现，§238）：桥派生
                    // 的关联任务活动——状态点＋label 一
                    // 行（照 Linear 名单行 health 信号
                    // 的摆法：小状态信号＋最近进展）。
                    // 只对进行中目标且真有关联任务时
                    // 显；无关联/旧桥无 activity 时整行
                    // 不出，不拿别的数据脑补
                    if goal.status == .active,
                       let activity = goal.activity,
                       activity.linkedCount > 0 {
                        HStack(
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Circle()
                                .fill(
                                    goalActivityDotColor(
                                        activity.state
                                    )
                                )
                                .frame(width: 7, height: 7)
                            Text(activity.label)
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                                .lineLimit(1)
                        }
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
            // 0.43.0（A11Y-V6）：⋮ 菜单钮补标签（文件
            // 行同钮已有「更多操作」先例，此处对齐）
            .accessibilityLabel("更多操作")
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
                    RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
                        .fill(done ? Palette.ink : Color.clear)
                    RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
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
        // 0.36.0（无障碍 A11Y-V5）：补状态值，
        // VoiceOver 能读出里程碑当前勾选状态
        .accessibilityValue(done ? "已完成" : "未完成")
        // 触感矩阵（0.36.2，规格 §2.3）：里程碑勾选
        // 完成与目标同档＝notification success，同
        // 样只在 未完成→完成 边沿响、取消不响
        .sensoryFeedback(.success, trigger: done) { old, new in
            !old && new
        }
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
    @State private var ideasStore = IdeasStore()
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
    private func loadAssociationStores() async {
        await ideasStore.load(appState: appState)
        await monitorsStore.load(appState: appState)
        await kanban.load(appState: appState)
    }

    /// 委派回响物化（§123 H1）：三路真源（关联账＋任务
    /// 板＋目标本体）都到位后，按 Core GoalEcho 规划把
    /// 还没落过的回响按序落进绑定线程。触发点只有详情
    /// 的首载与下拉刷新这两处——无 APNs 的现实下，回响
    /// 在用户下次打开这个目标时补齐（与动态角标的轮询
    /// 延迟同级约束，§123 记账）；没绑线程的目标（没在
    /// 这里安排过事）直接跳过，不为看一眼详情就建线程
    private func materializeGoalEchoes() {
        guard let threadID = appState.sideChats
            .threadID(forGoalID: goalID) else { return }
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == threadID }
        )
        guard let thread = try? modelContext.fetch(descriptor).first
        else { return }
        let linked = GoalAssociations.linkedTasks(
            links: store.taskLinksByGoal[goalID] ?? [],
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
        guard let threadID = appState.sideChats
            .threadID(forGoalID: goalID) else { return }
        appState.drawerThreadSelection = threadID
        appState.mainTabSwitchRequest = .chat
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
                        milestonesSection(goal)
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
                    await loadAssociationStores()
                    materializeGoalEchoes()
                }
                .sheet(isPresented: $showDelegate) {
                    GoalDelegateView(
                        store: store, goal: goal, kanban: kanban
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
            await loadAssociationStores()
            materializeGoalEchoes()
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
                            .foregroundStyle(Palette.inkMuted)
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
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.inkMuted)
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

    /// 关联任务行小字（GD-2）：状态（任务板现值）＋
    /// 最近变化时刻（读面一的 updatedAt）；桥没观察
    /// 到过这条任务的变化时只给状态，时刻不编
    private func associationTaskDetail(
        _ linked: GoalAssociations.LinkedTask,
        goalTaskRows: [BridgeGoalTask]
    ) -> String {
        let status = linked.task.map { task in
            KanbanStatusPresentation.resolve(
                status: task.status,
                blockKind: task.blockKind,
                lastFailureError: task.lastFailureError
            ).label
        } ?? "任务"
        guard let updatedAt = goalTaskRows.first(where: {
            $0.taskId == linked.link.taskId
        })?.updatedAt else { return status }
        let when = ChatTimeline.dividerText(
            for: Date(timeIntervalSince1970: updatedAt), now: Date()
        )
        return "\(status) · \(when)"
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
                            GroupDivider()
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

    // MARK: 委派（安排一件事，0.40.0 欠账补落）

    /// 目标下直接委派：入口开 GoalDelegateView 表单，提交
    /// 走 GoalsStore.delegateTask（任务板建卡＋桥侧关联
    /// 回写＋回读确认，与点子采纳同一条链）。任务办完后
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
                if appState.sideChats.threadID(forGoalID: goal.id) != nil {
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
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Palette.inkMuted)
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
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, OneDayMetrics.spacingS)
        }
    }

    // MARK: 关联（0.40.0 欠账补落：客户端拼装、零新端点）

    /// 挂靠点子（ideas 按 goalId 过滤）＋关联任务（经桥
    /// goal_task_links 反查任务板现值）＋挂靠监测
    /// （monitor.goalId），三路只读呈现、点行各自跳到
    /// 对方详情/管理；全空时整段不出现，不留空壳标题
    @ViewBuilder
    private func associationSection(_ goal: BridgeGoal) -> some View {
        let ideas = GoalAssociations.ideas(
            for: goalID, in: ideasStore.ideas
        )
        let monitors = GoalAssociations.monitors(
            for: goalID, in: monitorsStore.monitors
        )
        let tasks = GoalAssociations.linkedTasks(
            links: store.taskLinksByGoal[goalID] ?? [],
            tasks: kanban.snapshot?.tasks ?? []
        )
        // GD-2 读面一：关联任务的最近变化时刻（状态
        // 仍读任务板现值，时刻只作行小字补充）
        let goalTaskRows = store.goalTasksByGoal[goalID] ?? []
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
                        id: \.element.link.id
                    ) { index, linked in
                        if index > 0 || !ideas.isEmpty {
                            GroupDivider()
                        }
                        NavigationLink {
                            KanbanTaskDetailView(
                                store: kanban,
                                taskID: linked.link.taskId
                            )
                        } label: {
                            associationRow(
                                symbol: "checklist",
                                title: linked.title ?? "任务",
                                detail: associationTaskDetail(
                                    linked, goalTaskRows: goalTaskRows
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
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkMuted)
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
        HStack(spacing: OneDayMetrics.iconTextGap) {
            Circle()
                .fill(
                    goal.status == .completed
                        ? Palette.inkMuted : Palette.success
                )
                .frame(width: 6.5, height: 6.5)
            Text(label)
                // 0.41.0（P6）：chip 字回收 footnote
                // regular，状态靠色与点、不靠字重
                .font(.footnote)
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

/// 简报列表页（GD-3）：一行一封信——标题＋首句摘要
/// （≤40 字）＋日期，不在列表铺全文；点行进信件页
/// 读全文。只读——简报正文不许在客户端改（设计档
/// 状态机口径，纠错靠新条目）
struct GoalBriefingsView: View {
    let store: GoalsStore
    let goalID: String

    private var briefings: [BridgeBriefing] {
        store.briefingsByGoal[goalID] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if briefings.isEmpty {
                    Text("还没有简报。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                ForEach(
                    Array(briefings.enumerated()), id: \.element.id
                ) { index, briefing in
                    if index > 0 {
                        GroupDivider()
                    }
                    NavigationLink {
                        GoalBriefingLetterView(
                            store: store, goalID: goalID,
                            briefingID: briefing.id
                        )
                    } label: {
                        HStack(
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            VStack(
                                alignment: .leading, spacing: 3
                            ) {
                                Text(briefing.title)
                                    .font(.rowTitle)
                                    .foregroundStyle(Palette.bodyInk)
                                    .multilineTextAlignment(.leading)
                                Text(
                                    BriefingPresentation.summary(
                                        of: briefing.body
                                    )
                                )
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                Text(
                                    "\(ChatTimeline.dividerText(for: Date(timeIntervalSince1970: briefing.createdAt), now: Date())) · \(briefing.period)"
                                )
                                .font(.footnote)
                                .foregroundStyle(Palette.inkMuted)
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.inkMuted)
                        }
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("简报")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 简报信件页（GD-3 信纸排版）：一封信一页——信纸
/// 面（与页面底色区分的纸面）＋称呼行（目标名＋第
/// N 周）＋信体分段（纯文本段落，不进表格/列表渲
/// 染）＋信尾短注＋落款行（日期＋「OneDay 目标简
/// 报」）。打开即把打开时刻记到桥上——只供台账看
/// 「写了没看」，本页不呈现任何已读/未读标记
struct GoalBriefingLetterView: View {
    @Environment(AppState.self) private var appState

    let store: GoalsStore
    let goalID: String
    let briefingID: String

    private var briefing: BridgeBriefing? {
        store.briefingsByGoal[goalID]?.first { $0.id == briefingID }
    }

    private var week: Int? {
        BriefingPresentation.weekIndex(
            of: briefingID, in: store.briefingsByGoal[goalID] ?? []
        )
    }

    var body: some View {
        ScrollView {
            if let briefing {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingM
                ) {
                    // 称呼行：写给哪个目标的第几封信
                    HStack(spacing: OneDayMetrics.spacingS) {
                        if let goal = store.goal(id: goalID) {
                            Text("《\(goal.title)》")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Palette.bodyInk)
                        }
                        if let week {
                            Text(L10n.format("第 %lld 周", week))
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Text(briefing.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.bodyInk)
                    // 信体：按段落分段的纯文本
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingSM
                    ) {
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
                    // 信尾短注：这封信依据了哪些真实
                    // 变化（桥按计数拼装，安静一行）
                    if let note = briefing.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    // 落款行
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(
                            ChatTimeline.dividerText(
                                for: Date(
                                    timeIntervalSince1970:
                                        briefing.createdAt
                                ),
                                now: Date()
                            )
                        )
                        Text("OneDay 目标简报")
                    }
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
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            } else {
                Text("这封信已经不在了。")
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(OneDayMetrics.pageGutter)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle("简报")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.markBriefingOpened(
                appState: appState, goalID: goalID,
                briefingID: briefingID
            )
        }
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
    @State private var category: GoalCategory?
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
        _category = State(initialValue: goal?.category)
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
                GroupDivider()
                FieldRow(label: "备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                GroupDivider()
                FieldRow(label: "类别") {
                    Picker("类别", selection: $category) {
                        Text("未分类")
                            .tag(GoalCategory?.none)
                        ForEach(
                            GoalCategory.creationOrder, id: \.self
                        ) { option in
                            Text(option.title)
                                .tag(GoalCategory?.some(option))
                        }
                    }
                    .labelsHidden()
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
                        GroupDivider()
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
                    GroupDivider()
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
        guard ok else {
            saveError = store.notes[goalID]
            return
        }
        // 类别是独立动作：全量编辑不带类别字段，草稿与
        // 服务端现值不一致时再走专用 PATCH＋回读确认
        // （存量目标补分类也走这一条，用户自选）
        if store.goal(id: goalID)?.category != category {
            let categoryOK = await store.setCategory(
                appState: appState, goalID: goalID, category: category
            )
            guard categoryOK else {
                saveError = store.notes[goalID]
                    ?? "分类更新失败，请稍后再试。"
                return
            }
        }
        dismiss()
    }
}

/// 新建目标（sheet）：标题＋备注＋里程碑标题行（可多
/// 行添加），创建走 GoalsStore 的回读确认——确认出现
/// 才关表单，未确认原因留表单内。0.40.0：从分类流进来
/// 时类别已预置（presetCategory），表单里有类别行可
/// 改可清；不经分类流的入口类别行为未分类
struct GoalCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: GoalsStore
    let presetCategory: GoalCategory?

    @State private var title = ""
    @State private var note = ""
    @State private var category: GoalCategory?
    @State private var milestoneTitles: [String] = []

    init(store: GoalsStore, presetCategory: GoalCategory? = nil) {
        self.store = store
        self.presetCategory = presetCategory
        _category = State(initialValue: presetCategory)
    }

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
                            GroupDivider()
                            FieldRow(label: "备注") {
                                TextField("可选", text: $note, axis: .vertical)
                                    .lineLimit(2...5)
                            }
                            GroupDivider()
                            FieldRow(label: "类别") {
                                Picker("类别", selection: $category) {
                                    Text("未分类")
                                        .tag(GoalCategory?.none)
                                    ForEach(
                                        GoalCategory.creationOrder,
                                        id: \.self
                                    ) { option in
                                        Text(option.title)
                                            .tag(GoalCategory?.some(option))
                                    }
                                }
                                .labelsHidden()
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
                                    GroupDivider()
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
                                GroupDivider()
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
                                note: note,
                                milestoneTitles: milestoneTitles,
                                category: category
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

/// 委派表单（sheet，0.40.0）：一件事的标题＋可挂的里程
/// 碑；提交走 GoalsStore.delegateTask（任务板建卡→桥侧
/// 关联回写→回读确认），确认落定才关表单，失败原因留
/// 表单内——与新建目标同一纪律
struct GoalDelegateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let store: GoalsStore
    let goal: BridgeGoal
    let kanban: KanbanStore

    @State private var title = ""
    @State private var milestoneId: String?
    @State private var isSubmitting = false
    @State private var submitError: String?

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("要办的事")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            FieldRow(label: "事情") {
                                TextField(
                                    "如：把发言稿打印两份",
                                    text: $title, axis: .vertical
                                )
                                .lineLimit(1...3)
                            }
                            if !goal.milestones.isEmpty {
                                GroupDivider()
                                FieldRow(label: "挂到里程碑（可选）") {
                                    Picker(
                                        "里程碑",
                                        selection: $milestoneId
                                    ) {
                                        Text("不挂")
                                            .tag(String?.none)
                                        ForEach(
                                            goal.milestones,
                                            id: \.id
                                        ) { milestone in
                                            Text(milestone.title)
                                                .tag(
                                                    String?.some(
                                                        milestone.id
                                                    )
                                                )
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }
                        }
                        .odGroup()
                    }
                    Text("提交后会在任务板上建一张卡，并和目标《\(goal.title)》关联起来；开始、办完或失败，都会记进这个目标的进展对话。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    if let submitError {
                        InlineError(submitError)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("安排一件事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "安排中…" : "安排") {
                        Task { await submit() }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
    }

    /// 进展对话绑定（§123 H1）：委派确认落定后给目标绑
    /// 一个旁聊（没有才建、已有复用），绑定落盘在
    /// SideChatStore.goalThreadIDs。线程以目标名为题并
    /// 钉住标题（titleIsManual）——它在抽屉里的身份就
    /// 是这个目标，不让服务端 AI 标题改掉；回响条目本
    /// 身由目标详情的物化点按真源补落（GoalEcho），这
    /// 里只立绑定，不预写任何状态
    private func ensureGoalThread() {
        if appState.sideChats.threadID(forGoalID: goal.id) != nil {
            return
        }
        let thread = ChatThread(title: goal.title)
        thread.titleIsManual = true
        modelContext.insert(thread)
        try? modelContext.save()
        appState.sideChats.linkThread(thread.id, forGoalID: goal.id)
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        let ok = await store.delegateTask(
            appState: appState, goalID: goal.id, title: title,
            milestoneId: milestoneId, kanban: kanban
        )
        if ok {
            ensureGoalThread()
            dismiss()
        } else {
            submitError = store.notes[goal.id]
                ?? "安排失败，请稍后再试。"
        }
    }
}
