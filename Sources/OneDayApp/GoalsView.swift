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
/// 建段共用同一条流（分类组件
/// GoalCategoryRowsView 共用）；表单降为介绍卡上
/// 的次级入口「直接填写」，不删
/// §485（2026-11-24 全抄修复）：页头改兄弟页同款
/// 身份胶囊簇（资源库 identityHeader 同构）、撤自
/// 带工具栏孤悬＋钮与系统 largeTitle、页题改
/// ≈24pt 粗体档；创建入口收唯一＝列表底创建段
/// （点段进分类 sheet），段内七分类行摘除
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

/// 目标页页题（§485）：24pt 粗体——24 无文本样式
/// 档，照 drawerTitle 先例以 Title2 为锚相对缩放
/// 承载（规格单源 Core TypeRole.pageTitle：title2/
/// 24/bold）；独立成件供量测测直接渲染对账
/// （GoalsCopy478MeasureTests）
struct GoalsPageTitle: View {
    @ScaledMetric(relativeTo: .title2)
    private var pointSize: CGFloat = 24

    var body: some View {
        Text("目标")
            .font(.system(size: pointSize, weight: .bold))
            .foregroundStyle(Palette.bodyInk)
    }
}

/// 折叠行把手字形（§485）：3 列×2 行实心点阵——照
/// Muse 目标页段尾行参照帧实形（审计 §四.8：
/// ellipsis 换把手点阵；SF 无 3×2 点阵字形，程序
/// 绘制六点，§452 文件图标程序绘制先例）
struct GoalFoldHandleGlyph: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Palette.inkMuted)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            }
        }
    }
}

struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    /// 台账 199：目标店走 AppState 共享单例（§259
    /// 先例补齐），与动态格同一份，不再私建
    private var store: GoalsStore {
        appState.sharedGoalsStore()
    }
    @State private var createSheet: GoalCreateSheet?
    @State private var expandedActive = false
    @State private var showCompletedGroup = false
    @State private var expandedCompleted = false
    @State private var editTarget: BridgeGoal?
    @State private var deleteTarget: BridgeGoal?

    /// 身份簇点按进中枢（§498：ContentPageHeader 的
    /// onOpenHub 落点，与动态/点子同式——原 §485 小
    /// 胶囊在本页不可点，收编后同义补齐）
    @State private var showHub = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                identityHeader
                pageTitleRow
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            // §485：自带导航栏隐藏（页头簇自理，资源
            // 库同例）；详情页 push 后目的地各自的栏
            // 由目的地自理（GoalDetailView/Ungrou-
            // pedTasksView 均自带 navigationTitle）
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showHub) {
                AgentHubView()
            }
            .task {
                await store.loadIfNeeded(appState: appState)
            }
            .task {
                // G-3a（2026-11-24）：目标面可见期间每
                // 30 秒指纹重验，指纹没变零扰动；智能
                // 体新记的进展不用退出重进就能看见
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if Task.isCancelled { break }
                    await store.revalidateFingerprints(
                        appState: appState
                    )
                }
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
        appState.pendingQuotes.sourceQuotesByThread[fresh.id] =
            .goal(GoalQuote(category: category))
        appState.router.drawerThreadSelection = fresh.id
        appState.router.mainTabSwitchRequest = .chat
        createSheet = nil
    }

    /// 页头簇（§498 收编）：ContentPageHeader 共同簇
    /// 本体（与聊天基准/动态/点子/资源库同件同数），
    /// 取代 §485 的 IdentityAnchor 小横胶囊自写簇。
    /// 右侧不设圆钮：目标页无页级菜单动作，参照右
    /// 钮（···）功能单帧未验证（审计 §六），造空菜
    /// 单违僵尸禁令——§498 右位登记为空
    private var identityHeader: some View {
        ContentPageHeader(onOpenHub: { showHub = true }) {
            EmptyView()
        }
    }

    /// 页题行（§485）：「目标」≈24pt 粗体档（照
    /// Muse 量测、非系统 largeTitle 34，审计
    /// D2/R3），置页头簇下、间距 spacingSM（簇底
    /// 垫 spacingXS 4＋本行上垫 12＋字墨迹内偏
    /// ≈2＝簇底→题墨迹 ≈18pt，审计 R2）
    private var pageTitleRow: some View {
        GoalsPageTitle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingSM)
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
                            // §485：段名「进行中」→
                            // 「追踪」（照 Muse 参照
                            // 的动作命名，审计 D3/R4）
                            title: "追踪", completed: false,
                            goals: groups.active,
                            expanded: $expandedActive
                        )
                    }
                    if !groups.completed.isEmpty {
                        completedGroup(goals: groups.completed)
                    }
                    if !store.ungroupedTasks.isEmpty
                        || store.ungroupedNote != nil {
                        ungroupedEntryRow
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
    /// §485：组内距 spacingSM 12→spacingM 16——行
    /// pitch 合成口径（审计 §四.7：行高 ≈86＋组内
    /// 距 ≈16＝102±6；本实现行实高 83［标题行 24
    /// ＋gap 3＋摘要块 56］，组内距取审计的 16 合
    /// 成 99 落带内；已完成组同口径）
    private func goalGroup(
        title: String, completed: Bool, goals: [BridgeGoal],
        expanded: Binding<Bool>
    ) -> some View {
        let folded = GoalBoard.folded(goals, expanded: expanded.wrappedValue)
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
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
                    Label {
                        Text("显示另外\(folded.hiddenCount)项")
                    } icon: {
                        GoalFoldHandleGlyph()
                    }
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                }
                .buttonStyle(.odPressable)
            }
        }
    }

    /// 已完成组：默认收起，点头展开（组内同样 4 条折叠）
    /// §485：组内距同 goalGroup 改 spacingM（pitch
    /// 合成口径见 goalGroup 注）
    private func completedGroup(goals: [BridgeGoal]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            Button {
                showCompletedGroup.toggle()
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    GoalGroupHeader(
                        title: "已完成", completed: true
                    )
                    Text("\(goals.count)")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
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
                        Label {
                            Text("显示另外\(folded.hiddenCount)项")
                        } icon: {
                            GoalFoldHandleGlyph()
                        }
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
    }

    /// 未归类任务入口行（§453，用户 2026-11-24 亲
    /// 点）：GD-2 整区（说明段＋逐条归组行）原占目标页
    /// 主体——Muse 目标页是干净的目标列表（追踪中＋已
    /// 完成折叠），归类杂务不占主体。整区移入独立管理
    /// 页 UngroupedTasksView，主体只留此一行入口（有
    /// 任务或有失败注记时才出现，口径同旧区）
    private var ungroupedEntryRow: some View {
        NavigationLink {
            UngroupedTasksView()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "checklist")
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 24)
                Text("未归类任务")
                    .font(.body)
                    .foregroundStyle(Palette.bodyInk)
                if !store.ungroupedTasks.isEmpty {
                    Text("\(store.ungroupedTasks.count)")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                DisclosureChevron(
                    font: .system(size: 14, weight: .regular)
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            "未归类任务，\(store.ungroupedTasks.count) 条"
        )
    }

    /// 列表底常驻创建段（照 Muse 目标页图位置）：
    /// 分隔线下「创建目标」标题＋一句说明一段，仅此
    /// 两件（参照 R12）。§485：段内直铺的七分类行
    /// 摘除（§453 旧形态），点段（标题/说明区整块）
    /// 进既有分类选择 sheet 流（createSheet.
    /// categories，与空态分类流同一条 §238 三步
    /// 流）；工具栏＋已随页头改造撤销——全页创建
    /// 入口唯一就是本段。说明文案保留自家口径不
    /// 逐字抄参照（偏离 P2：参照文案承诺「制定个
    /// 性化方案」与自家「对话里聊定」流程不符）
    private var createArea: some View {
        Button {
            createSheet = .categories
        } label: {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                Divider()
                Text("创建目标")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.bodyInk)
                Text("先选一个类别，再到对话里把目标聊定。定好之后它会出现在这里，进展和简报会慢慢长出来。")
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .padding(.top, OneDayMetrics.spacingS)
    }
}

