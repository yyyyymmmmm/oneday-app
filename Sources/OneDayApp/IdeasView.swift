import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 点子格（0.11.0 P5 转正；0.47.0 §117 对标重做；
/// §177 分类对标改判）：形态照 Muse 点子页——行＝
/// 内容 emoji 大字（无底砖）＋semibold 标题＋次色宽
/// 松正文，行面不摆元信息；点行开底部 sheet 详情
/// （「包含哪些内容」交付物清单＋底部动作栏「开始
/// 吧」）。列表结构只有分类小节（标题＋其下卡片，
/// 分类由桥下发、App 不自判；无分类的卡不进列表，
/// 不设无分类区），页面不出现「待阅/已采纳」分区、
/// 状态字与角标（§123 M3 底栏角标随本包退役，用
/// 户 2026-11-12 亲定）。数据口径：生成卡由桥端管
/// 道每日晨间产出（source=generated、evidence 必
/// 填、14 天过期），手记保留；已转任务以桥 taskId
/// 为真源。桥未连接/未开通与目标格同口径、零假数据。
struct IdeasView: View {
    @Environment(AppState.self) private var appState
    @State private var store = IdeasStore()
    @State private var kanban = KanbanStore()
    @State private var showCreate = false
    @State private var deleteCandidate: BridgeIdea?
    /// 详情 sheet 的当前点子（0.47.0：点行不再推页）
    @State private var selectedIdeaID: String?
    /// §219：聊天里点点子引用块回跳的待决请求——名
    /// 单未就绪时挂起、就绪后由 resolveIdeaOpen 落
    /// 定（FeedView resolveFeedOpen 同式）
    @State private var pendingIdeaOpenID: String?
    /// §219：回跳的点子已不在名单（删除/过期）时的
    /// 诚实提示——引用块快照仍可读，不假定位
    @State private var ideaGoneNotice = false

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
                        Label("点子没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
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
            .navigationTitle("点子")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建点子", systemImage: "plus")
                    }
                }
            }
            .task {
                await store.load(appState: appState)
                // §177：底栏角标退役后进页不再推进
                // 「已见」水位（水位制整套随角标下线）
                if !store.adoptedIdeas.isEmpty {
                    await kanban.load(appState: appState)
                }
            }
            .sheet(isPresented: $showCreate) {
                IdeaCreateView(store: store)
            }
            .sheet(isPresented: Binding(
                get: { selectedIdeaID != nil },
                set: { if !$0 { selectedIdeaID = nil } }
            )) {
                if let selectedIdeaID {
                    IdeaDetailView(
                        store: store, kanban: kanban,
                        ideaID: selectedIdeaID
                    )
                    .presentationDetents([.large])
                    .presentationCornerRadius(28)
                }
            }
            .confirmationDialog(
                "删除这个点子？",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleteCandidate
            ) { idea in
                Button("删除点子", role: .destructive) {
                    // 触感矩阵（规格 §2.3）：删除确认
                    // 落锤＝impact heavy；删除成功后不
                    // 再叠 success（同一因果链只震一次）
                    Haptics.impact(.heavy)
                    Task { await store.delete(appState: appState, idea: idea) }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("只删点子本身；已经转成的任务不会受影响。")
            }
            // §219：聊天里点点子引用块的回跳——请求在
            // 此消费（清零先行防重入），落点判定走
            // resolveIdeaOpen（在名单开详情、名单就绪
            // 而查无给诚实提示、未就绪挂起等名单）
            .onChange(of: appState.ideaOpenRequest) { _, id in
                if let id {
                    appState.ideaOpenRequest = nil
                    pendingIdeaOpenID = id
                    resolveIdeaOpen()
                }
            }
            .onChange(of: store.ideas) { _, _ in
                resolveIdeaOpen()
            }
            .alert(
                "这个点子已不在了",
                isPresented: $ideaGoneNotice
            ) {
                Button("好", role: .cancel) {}
            }
        }
    }

    /// 点子回跳落点判定（§219，FeedView 的
    /// resolveFeedOpen 同式）：名单里有即开详情
    /// sheet；名单已就绪仍查无（点子已删/已过期）
    /// 给诚实提示；名单未就绪不判死、挂起等下一次
    /// 名单变化再试
    private func resolveIdeaOpen() {
        guard let id = pendingIdeaOpenID else { return }
        if store.ideas.contains(where: { $0.id == id }) {
            pendingIdeaOpenID = nil
            selectedIdeaID = id
        } else if case .ready = store.loadState {
            pendingIdeaOpenID = nil
            ideaGoneNotice = true
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        Group {
            readyContentBody
        }
        // 删除回响（同类面口径：文件页/交付物页删成
        // 落小字明示）：回读确认删除后，页面底部明示
        // 删了哪条；列表与空态两形态都够得着，留痕
        // （失败原因）仍走卡面 notes 不走这里
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = store.deleteNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .background(Palette.pageBG)
            }
        }
    }

    @ViewBuilder
    private var readyContentBody: some View {
        if !store.hasVisibleIdeas {
            switch store.emptyKind {
            case .neverProduced:
                ContentUnavailableView(
                    "还没有点子",
                    systemImage: "lightbulb",
                    description: Text(
                        "每天早上我会想一轮，你也可以点右上角＋先记一个"
                    )
                )
            case .cleared:
                ContentUnavailableView(
                    "这一轮的点子都处理完了",
                    systemImage: "checkmark.circle",
                    description: Text(
                        "明早会再想一轮；也可以点右上角＋自己记一个"
                    )
                )
            }
        } else {
            List {
                // §177：列表自上而下全程分类小节——
                // 状态只决定卡进不进列表（口径在 Core
                // IdeaBoard.categorySections），页面不
                // 再有状态分区
                ForEach(store.categorySections) { section in
                    Section {
                        ForEach(section.ideas) { idea in
                            ideaRow(idea)
                        }
                    } header: {
                        groupHeader(section.category.title)
                    }
                }
                Section {
                    Text(generationFootnote)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .listRowBackground(Palette.pageBG)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG)
            .refreshable {
                await store.load(appState: appState)
                if !store.adoptedIdeas.isEmpty {
                    await kanban.load(appState: appState)
                }
            }
            // §170（用户 2026-11-11 23:28 亲定）：底部导
            // 航栏同档收边（与输入框下方收边同档）——本页根 List 底
            // 缘挂 .hard，口径与映射见 FeedView 同注与
            // DESIGN §170.2
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    /// 组标题（0.47.0 §117）：照 Muse 分类组头的大
    /// 粗体——原色、非大写，压掉 List 分区头的系统小字
    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(Palette.ink)
            .textCase(nil)
            .padding(.top, OneDayMetrics.spacingS)
    }

    /// §177：左滑与长按共用动作；「忽略」（放下）只给未动手过的
    /// pending 卡，已转任务的卡放下语义归桥侧状态机，行上不给此
    /// 动作，长按菜单同口径。pending 全滑直达首个「忽略」，保留
    /// 已定版的快捷放下手势；非 pending 仅有删除，禁全滑以免误触，
    /// 删除仍须经 deleteCandidate 确认。
    private func ideaRow(_ idea: BridgeIdea) -> some View {
        rowButton(for: idea)
            .swipeActions(edge: .trailing, allowsFullSwipe: idea.status == .pending) {
                rowActions(for: idea)
            }
    }

    private func rowButton(for idea: BridgeIdea) -> some View {
        Button {
            selectedIdeaID = idea.id
        } label: {
            IdeaRowView(
                idea: idea,
                note: store.notes[idea.id]
            )
        }
        // 手感 A 档（全 App 普查 B1a）：整行补按压
        // 反馈——与目标页同式走公用按压件；行点击
        // 按表 D 防腻清单不配触感
        .buttonStyle(.odPressable)
        .listRowBackground(Palette.pageBG)
        .contextMenu {
            rowActions(for: idea)
        }
    }

    @ViewBuilder
    private func rowActions(for idea: BridgeIdea) -> some View {
        if idea.status == .pending {
            Button("忽略") {
                Task {
                    await store.dismiss(
                        appState: appState, idea: idea
                    )
                }
            }
            .tint(Palette.inkSecondary)
            if idea.source == .generated {
                Button("太泛了，忽略") {
                    Task {
                        await store.dismiss(
                            appState: appState, idea: idea,
                            tooGeneric: true
                        )
                    }
                }
                .tint(Palette.inkSecondary)
            }
        }
        Button("删除", role: .destructive) {
            deleteCandidate = idea
        }
    }

    /// 页脚节奏文案：生成节奏是运行逻辑的一部分、
    /// 明示在面上（设计档 §1.4）；上次生成时刻有账
    /// 才写、无账不编
    private var generationFootnote: String {
        var text = "点子每天早上更新一轮"
        if let last = store.generationInfo?.lastRunAt {
            text += " · 上次生成 \(Self.dayTimeText(last))"
        }
        return text
    }

    /// 行内日期口径：今天/昨天带时刻、再远只给日期
    /// （0.36.0 收编至全 App 唯一格式器 DisplayDate，
    /// 审计 C11——旧实现远期档走 .formatted 随系统
    /// locale 漏英文）
    static func dayTimeText(_ epoch: Double) -> String {
        DisplayDate.relativeDateTime(Date(timeIntervalSince1970: epoch))
    }
}

/// 点子行（0.47.0 §117 对标形态）：左侧内容 emoji
/// 大字（44pt 位、无底色瓷砖；桥按内容选定优先、
/// 缺失统一 💡 兜底——§177 改判，不再按锚点来源分，
/// 口径在 Core IdeaEmoji）＋标题（semibold、至多两
/// 行）＋正文（次色、行距放宽、至多四行）＋依据行
/// （生成卡、一次色一行）。行面不摆元信息：生成时
/// 间/到期/目标/任务状态全收进详情 sheet。行内不摆
/// 按钮：动作在详情与左滑/长按里
struct IdeaRowView: View {
    let idea: BridgeIdea
    let note: String?

    private var displayEmoji: String {
        IdeaEmoji.resolve(emoji: idea.emoji)
    }

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Text(displayEmoji)
                .font(.system(size: 38))
                .frame(width: 44, height: 44)
                // emoji 是内容不是界面图标（§117.5）；
                // 类别语义另有依据行/详情承载，对 VO
                // 隐藏免逐字念符号名
                .accessibilityHidden(true)
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingXS
            ) {
                Text(idea.title)
                    // 0.47.0（§117.5 记账）：两页行题经
                    // 用户对标指令改回 semibold（系统
                    // Headline 17），其余页面角色表不动
                    .font(.headline)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                if !idea.detail.isEmpty {
                    Text(idea.detail)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(3)
                        .lineLimit(4)
                }
                if idea.source == .generated, !idea.evidence.isEmpty {
                    Text("依据 · \(idea.evidence)")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }
}

/// 点子详情（0.47.0 §117 对标形态）：底部 sheet 呈
/// 现——标题→正文全文→依据小节→「包含哪些内容」
/// 交付物清单（蓝勾圆）→信息组小字；底部固定动作
/// 栏＝左侧浅灰圆形「···」菜单（太泛了/忽略/删除，
/// 沿用既有 store 动作）＋通栏蓝色胶囊主钮。
/// 0.48.0（§122，用户亲定）：主钮落点改开旁聊——
/// 未动手卡的「开始吧」＝做这件事的唯一主动作：后
/// 台照旧建 kanban 任务（台账记账不动），成功后新
/// 建旁聊、点子上下文预填进输入舱（不代发）、切聊
/// 天页打开；已转任务的主钮改「打开对话」回同一条
/// 旁聊（关联存 SideChatStore，存量无关联/线程已删
/// 时点按补建）。不再把用户丢进任务详情。深链落点
/// （动态 refs 点达）以同一视图推页呈现，形态与动
/// 作不变。§177：卡面与详情都不再出现「采纳」这一
/// 动作名与状态字——主钮就是「做」，没有先批后做的
/// 两段式
struct IdeaDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let store: IdeasStore
    let kanban: KanbanStore
    let ideaID: String

    @State private var confirmDelete = false

    private var idea: BridgeIdea? {
        store.ideas.first { $0.id == ideaID }
    }

    var body: some View {
        Group {
            if let idea {
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingL
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingS
                        ) {
                            Text(idea.title)
                                .font(.detailTitle)
                                .foregroundStyle(Palette.bodyInk)
                            if !idea.detail.isEmpty {
                                Text(idea.detail)
                                    .font(.body)
                                    .foregroundStyle(Palette.bodyInk)
                                    .lineSpacing(3)
                            }
                        }
                        if idea.source == .generated,
                           !idea.evidence.isEmpty {
                            GroupDivider()
                            evidenceSection(idea)
                        }
                        if IdeaDeliverablesSection.isVisible(
                            idea.deliverables
                        ) {
                            GroupDivider()
                            deliverablesSection(idea)
                        }
                        GroupDivider()
                        infoGroup(idea)
                        if let note = store.notes[idea.id] {
                            InlineError(note)
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.top, OneDayMetrics.spacingM)
                    .padding(.bottom, OneDayMetrics.spacingXL)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar(idea)
                }
            } else {
                ContentUnavailableView(
                    "这个点子已不在列表里",
                    systemImage: "lightbulb.slash"
                )
            }
        }
        .background(Palette.pageBG)
        .confirmationDialog(
            "删除这个点子？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除点子", role: .destructive) {
                // 触感矩阵（规格 §2.3）：删除确认落锤
                // ＝impact heavy；删除成功后不再叠
                // success（同一因果链只震一次）
                Haptics.impact(.heavy)
                if let idea {
                    Task {
                        await store.delete(
                            appState: appState, idea: idea
                        )
                        // 删成（回读确认不在列表）才退页；
                        // 失败留在本页看 notes 的原因
                        if !store.ideas.contains(
                            where: { $0.id == idea.id }
                        ) {
                            dismiss()
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删点子本身；已经转成的任务不会受影响。")
        }
    }

    private func evidenceSection(_ idea: BridgeIdea) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text("依据")
                .font(.headline)
                .foregroundStyle(Palette.bodyInk)
            Text(idea.evidence)
                .font(.body)
                .foregroundStyle(Palette.bodyInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「包含哪些内容」（0.47.0 §117）：交付物行＝粗
    /// 体名＋灰副文＋右侧蓝色实心对勾圆；小节标题右
    /// 侧剪贴板图标与 Muse 同位
    private func deliverablesSection(
        _ idea: BridgeIdea
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            HStack {
                Text("包含哪些内容")
                    .font(.headline)
                    .foregroundStyle(Palette.bodyInk)
                Spacer()
                Image(systemName: "list.clipboard")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.inkSecondary)
            }
            ForEach(
                Array(idea.deliverables.enumerated()), id: \.offset
            ) { _, item in
                HStack(
                    alignment: .top, spacing: OneDayMetrics.spacingM
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.bodyInk)
                        if !item.summary.isEmpty {
                            Text(item.summary)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoGroup(_ idea: BridgeIdea) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("信息")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                FieldRow(label: "来源") {
                    Text(idea.source == .generated ? "生成" : "手记")
                }
                GroupDivider()
                FieldRow(label: idea.source == .generated ? "生成于" : "记于") {
                    Text(
                        DisplayDate.dateTime(
                            Date(timeIntervalSince1970: idea.createdAt)
                        )
                    )
                }
                if let expiresAt = idea.expiresAt {
                    GroupDivider()
                    FieldRow(label: "过期") {
                        Text(
                            DisplayDate.dateOnly(
                                Date(timeIntervalSince1970: expiresAt)
                            )
                        )
                    }
                }
                if let goalTitle = store.goalTitle(for: idea) {
                    GroupDivider()
                    FieldRow(label: "关联目标") {
                        Text(goalTitle)
                    }
                }
                if idea.isAdopted, idea.taskId != nil {
                    GroupDivider()
                    FieldRow(label: "任务状态") {
                        Text(
                            store.taskStatusText(
                                for: idea, kanban: kanban
                            ) ?? "已转任务"
                        )
                    }
                }
                // §177：详情不再摆点子自身的状态字
                // （待阅/已采纳/已忽略/已过期）——状态
                // 只决定卡进不进列表，不做呈现
            }
            .odGroup()
        }
    }

    /// 底部动作栏（0.47.0 §117）：「···」圆钮收次要
    /// 动作、蓝色胶囊主钮只做当前主动作
    private func actionBar(_ idea: BridgeIdea) -> some View {
        let acting = store.actingIDs.contains(idea.id)
        return HStack(spacing: OneDayMetrics.spacingM) {
            Menu {
                if idea.status == .pending {
                    Button("忽略") {
                        Task {
                            await store.dismiss(
                                appState: appState, idea: idea
                            )
                            dismiss()
                        }
                    }
                    if idea.source == .generated {
                        Button("太泛了，忽略") {
                            Task {
                                await store.dismiss(
                                    appState: appState, idea: idea,
                                    tooGeneric: true
                                )
                                dismiss()
                            }
                        }
                    }
                }
                Button("删除点子", role: .destructive) {
                    confirmDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(Palette.surface, in: Circle())
            }
            .disabled(acting)
            if idea.status == .pending {
                Button {
                    Task {
                        await store.convertToTask(
                            appState: appState, idea: idea,
                            kanban: kanban
                        )
                        // 采纳落定判据与 store 内回读确认
                        // 同口径：任务 id 已落字且无失败留
                        // 痕才开旁聊；未落定留在本页看原因
                        if let fresh = store.ideas.first(
                            where: { $0.id == idea.id }
                        ), fresh.taskId != nil,
                           store.notes[idea.id] == nil {
                            openIdeaChat(fresh)
                        }
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "sparkles")
                        Text(acting ? "处理中…" : "开始吧")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Palette.primary, in: Capsule())
                }
                // 手感 A 档：页面主动作补按下态（公用
                // 按压件）；采纳结果触感已由 IdeasStore
                // 按表 D 落 success，此处不叠震
                .buttonStyle(.odPressable)
                .disabled(acting)
            } else if idea.isAdopted, idea.taskId != nil {
                Button {
                    openIdeaChat(idea)
                } label: {
                    Text("打开对话")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Palette.primary, in: Capsule())
                }
                // 手感 A 档：与「开始吧」同式补按下态
                .buttonStyle(.odPressable)
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .background(Palette.pageBG)
    }

    /// 开旁聊（§122 立形；§219 引用化）：关联线程还
    /// 在就回那条；没有关联（存量已采纳点子）或线程
    /// 已被删，则现在补建一条并记关联——建线程走既
    /// 有旁聊创建链（DrawerView.createThread／动态
    /// 「讨论」同形：本地插入 ChatThread 即出生记
    /// 录，服务端会话由该线程首发时经 SideChatLink
    /// 铸 oneday-side- 会话）。点子上下文改走引用道
    /// （§219，与动态「讨论」§210 同型）：新建与回
    /// 既有两路都把引用直写目标线程的待发状态
    /// （AppState.pendingSourceQuotesByThread 按线程
    /// 寻址，落点决定与写入同动作），点子以引用卡
    /// 挂目标线程发送舱（IdeaQuote 值快照），输入框
    /// 恒空、亲笔才是草稿、不代发；§219 前只在新建
    /// 时经 setDraft 把 IdeaChatPrefill 预填直写草稿
    /// 账——与亲笔同形且被防丢稿保活，是通道选错
    /// （定性见 §208），本包堵死；回既有线程的旧
    /// 「不覆盖草稿」顾虑随之消解：引用与草稿分属
    /// 两道，挂引用不动该线程已有的亲笔草稿
    private func openIdeaChat(_ idea: BridgeIdea) {
        let thread: ChatThread
        if let linkedID = appState.sideChats.threadID(
            forIdeaID: idea.id
        ), let existing = fetchThread(linkedID) {
            thread = existing
        } else {
            let fresh = ChatThread()
            modelContext.insert(fresh)
            try? modelContext.save()
            appState.sideChats.linkThread(
                fresh.id, forIdeaID: idea.id
            )
            thread = fresh
        }
        // §219：引用直写目标线程的待发状态（落点决定
        // 与引用写入同动作完成），不再经种子消费
        appState.pendingSourceQuotesByThread[thread.id] =
            .idea(IdeaQuote(idea: idea))
        appState.drawerThreadSelection = thread.id
        appState.routes.mainTabSwitchRequest = .chat
        dismiss()
    }

    private func fetchThread(_ id: UUID) -> ChatThread? {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

/// 新建点子（sheet）：标题＋详情＋可挂目标（picker 只
/// 列现存目标——服务端对假 goalId 回 400，客户端不给
/// 选不存在的；目标列表是打开表单时 IdeasStore 已拉的
/// 一批，提交时服务端再校验、错误透人话）
struct IdeaCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: IdeasStore

    @State private var title = ""
    @State private var detail = ""
    @State private var goalId: String?
    /// 分类（§177）：必选——无分类的卡不进列表，入
    /// 口就不能产出无分类卡；选项与桥分类同表（Core
    /// IdeaCategory.pickerOptions），存键不存名
    @State private var categoryKey: String?

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && categoryKey != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("点子")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            FieldRow(label: "标题") {
                                TextField("一句话说清这个点子", text: $title)
                            }
                            GroupDivider()
                            FieldRow(label: "详情") {
                                TextField("可选", text: $detail, axis: .vertical)
                                    .lineLimit(2...6)
                            }
                            GroupDivider()
                            FieldRow(label: "分类") {
                                Picker("分类", selection: $categoryKey) {
                                    Text("请选择").tag(String?.none)
                                    ForEach(
                                        IdeaCategory.pickerOptions
                                    ) { option in
                                        Text(option.title)
                                            .tag(String?.some(option.key))
                                    }
                                }
                                .labelsHidden()
                            }
                            GroupDivider()
                            FieldRow(label: "关联目标") {
                                Picker("关联目标", selection: $goalId) {
                                    Text("不关联").tag(String?.none)
                                    ForEach(store.goals) { goal in
                                        Text(goal.title)
                                            .tag(String?.some(goal.id))
                                    }
                                }
                                .labelsHidden()
                            }
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
            .navigationTitle("新建点子")
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
                                detail: detail, goalId: goalId,
                                category: categoryKey
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
