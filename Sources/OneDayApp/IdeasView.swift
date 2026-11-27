import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 点子格（0.11.0 P5 转正；0.47.0 §117 对标重做；
/// §177 分类对标改判）：形态照 Muse 点子页——行＝
/// 内容 emoji 大字（无底砖）＋semibold 标题＋次色宽
/// 松正文，行面不摆元信息；点行开底部 sheet 详情
/// （「包含哪些内容」交付物清单＋底部动作栏「开始
/// 吧」）。列表结构只有领域小节（标题＋其下卡片；
/// §459 起分节键＝桥下发 domain、App 不自判，旧
/// category 只作存量折算兜底、恒有落点不丢卡），
/// 页面不出现「待阅/已采纳」分区、
/// 状态字与角标（§123 M3 底栏角标随本包退役，用
/// 户 2026-11-12 亲定）。数据口径：生成卡由桥端管
/// 道每日晨间产出（source=generated、evidence 必
/// 填、14 天过期），手记保留；已转任务以桥 taskId
/// 为真源。桥未连接/未开通与目标格同口径、零假数据。
/// 点子详情 sheet 档位（§470，2026-11-24 用户裁）：
/// 默认半屏（.medium）打开、可上拖到大档（.large）。
/// 档位集与默认档单源于此——呈现层只引本表，钉测
/// 直断本表（IdeaDetailSheetDetentsTests）；此前为
/// [.large] 单档（§459 对位时量测冲突未擅改、维持
/// 现行，裁决回后按本节落码）
enum IdeaDetailSheet {
    static let detents: Set<PresentationDetent> = [.medium, .large]
    static let defaultDetent: PresentationDetent = .medium
}

struct IdeasView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    /// 台账 199：点子店走 AppState 共享单例（§259
    /// 先例补齐），与动态格／目标详情同一份，不再
    /// 私建
    private var store: IdeasStore {
        appState.sharedIdeasStore()
    }
    /// §259 三店合一：任务店走 AppState 共享单例，
    /// 与枢纽/目标/动态各面同一份，不再私建
    private var kanban: KanbanStore {
        appState.sharedKanbanStore()
    }
    @State private var deleteCandidate: BridgeIdea?
    /// 页头身份簇开中枢（§486：与动态页同件接入，
    /// 落点本栈推 AgentHubView）
    @State private var showHub = false
    /// 详情 sheet 的当前点子（0.47.0：点行不再推页）
    @State private var selectedIdeaID: String?
    /// 详情 sheet 当前档位（§470）：每次打开回默认
    /// 档 .medium（onChange 于 selectedIdeaID 落定），
    /// 用户上拖到 .large 只管本次呈现
    @State private var detailDetent: PresentationDetent =
        IdeaDetailSheet.defaultDetent
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaBar(edge: .top, spacing: 0) {
                ideasTopHeader
            }
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            // §486.5：页头整簇改页内自持（ContentPage-
            // Header＋大标题，见 ideasPageHead）——本
            // 页此前整簇缺失（状态栏下 87.7pt 空白直
            // 达标题，审计 §2.2），系统导航栏在根隐藏
            .toolbar(.hidden, for: .navigationBar)
            // H2 收编：中枢改 cover 呈现（与聊天页
            // 同一宿主），原 push 入中枢退役
            .hubCover(isPresented: $showHub)
            .task {
                await store.loadIfNeeded(appState: appState)
                // §177：底栏角标退役后进页不再推进
                // 「已见」水位（水位制整套随角标下线）
                if !store.adoptedIdeas.isEmpty {
                    await kanban.load(appState: appState)
                }
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
                    .presentationDetents(
                        IdeaDetailSheet.detents,
                        selection: $detailDetent
                    )
                    // §489（HIG 批 A／P1-02）：可调 sheet
                    // 补抓手（HIG Sheets：Include a grabber
                    // in a resizable sheet）
                    .presentationDragIndicator(.visible)
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
            // §470：详情每次打开回默认档（上一回拖到
            // 大档不带进下一回，默认半屏是裁定口径）
            .onChange(of: selectedIdeaID) { _, newValue in
                if newValue != nil {
                    detailDetent = IdeaDetailSheet.defaultDetent
                }
            }
            // §219：聊天里点点子引用块的回跳——请求在
            // 此消费（清零先行防重入），落点判定走
            // resolveIdeaOpen（在名单开详情、名单就绪
            // 而查无给诚实提示、未就绪挂起等名单）
            .onChange(of: appState.router.ideaOpenRequest) { _, id in
                if let id {
                    appState.router.ideaOpenRequest = nil
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
        .fullscreenPopBridge()
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

    /// 顶部固定身份簇：只固定圆钮、头像与身份胶囊
    private var ideasTopHeader: some View {
        ContentPageHeader(
            onOpenHub: {
                HubCoverPresenter.present(
                    $showHub, reduceMotion: reduceMotion
                )
            }
        ) {
            EmptyView()
        }
    }

    /// 随列表滑动的大标题
    private var ideasTitleBlock: some View {
        Text("点子")
            .font(.pageTitle)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
            .padding(.bottom, OneDayMetrics.spacingM)
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
            VStack(spacing: 0) {
                ideasTitleBlock
                Group {
                    switch store.emptyKind {
                    case .neverProduced:
                        ODEmptyState(
                            "还没有点子",
                            systemImage: "lightbulb",
                            description: "点子都由我来想——每天早上我会想一轮，想到新的就会出现在这里"
                        )
                    case .cleared:
                        ODEmptyState(
                            "这一轮的点子都处理完了",
                            systemImage: "checkmark.circle",
                            description: "明早会再想一轮，想到新的就会出现在这里"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ideasTitleBlock
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(store.domainSections) { section in
                    groupHeader(section.domain.title)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ForEach(section.ideas) { idea in
                        ideaRow(idea)
                    }
                }
                Text(generationFootnote)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .listSectionSpacing(OneDayMetrics.spacingL)
            .contentMargins(.bottom, OneDayMetrics.spacingL, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable {
                await store.load(appState: appState)
                if !store.adoptedIdeas.isEmpty {
                    await kanban.load(appState: appState)
                }
            }
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
        .listRowBackground(Color.clear)
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
/// 行）＋正文（次色、行距放宽、至多四行）。行面不
/// 摆元信息：生成时间/到期/目标/任务状态全收进详
/// 情 sheet。行内不摆按钮：动作在详情与左滑/长按
/// 里。§486.6：依据行与 category 灰片已撤出卡面
/// （依据进详情 sheet、分类只剩 domain 分组一处）
struct IdeaRowView: View {
    let idea: BridgeIdea
    let note: String?

    private var kickerSymbol: String {
        IdeaKicker.symbolName(for: idea.category)
    }

    private var kickerColor: Color {
        IdeaKicker.color(for: idea.category)
    }

    private var kickerForeground: Color {
        IdeaKicker.foregroundColor(for: idea.category)
    }

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Image(systemName: kickerSymbol)
                .font(.system(size: FrameworkIcon.cardGlyphSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kickerForeground)
                .frame(width: 34, height: 34)
                .background(kickerColor)
                .clipShape(RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusTile,
                    style: .continuous
                ))
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingS
            ) {
                Text(idea.title)
                    // §364（台账 23）：行题升内容行题
                    // 例外角色 contentListTitle
                    // （Title3 semibold）——§117.5 例
                    // 外升档，用户 2026-11-22 裁定三
                    // 面同例
                    .font(.contentListTitle)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                if !idea.detail.isEmpty {
                    Text(idea.detail)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(4)
                }
                // §486.6：卡面分类呈现收口——「依据」行
                // 与 categoryLabel 灰片整行撤出卡面：分
                // 类在卡面只剩 domain 分组一处（分组与
                // 卡面同源，不再双源打架——帧实证「个
                // 人效率」组下卡片自称「服务器运维」）；
                // 依据收进详情 sheet（见 IdeaDetail-
                // View），category 数据层口径不变（§459
                // 生成侧在管，本节只收呈现层）
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
        .padding(.vertical, OneDayMetrics.spacingM)
    }
}

/// 点子详情（0.47.0 §117 对标形态；§453 用户
/// 2026-11-24 亲裁收构成）：底部 sheet 呈现——只
/// 留标题→摘要正文→「包含哪些内容」交付物清单
/// （蓝勾圆）；依据小节与信息组（来源/生成于罗
/// 列）整形态退役、不许搬进 sheet；底部固定动作
/// 栏＝左侧浅灰圆形「···」菜单（太泛了/忽略/删除，
/// 沿用既有 store 动作）＋通栏蓝色胶囊主钮。
/// §486.6 口径变更（同日、后令覆盖 §453 此点）：
/// 「依据」随卡面收口收进本 sheet——只收依据一
/// 件（生成卡且 evidence 非空才出），§453 退役的
/// 信息组（来源/生成于罗列）不复活。
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
    /// §459 kind=routine：例行创建表单（既有 cron 面）
    /// 的呈现开关
    @State private var routineFormShown = false

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
                            }
                        }
                        if IdeaDeliverablesSection.isVisible(
                            idea.deliverables
                        ) {
                            GroupDivider()
                            deliverablesSection(idea)
                        }
                        // §486.6：依据收进 sheet（卡面已
                        // 撤）——生成卡且 evidence 非空才
                        // 出，全文呈现不截断
                        if idea.source == .generated,
                           !idea.evidence.isEmpty {
                            GroupDivider()
                            VStack(
                                alignment: .leading,
                                spacing: OneDayMetrics.spacingS
                            ) {
                                Text("依据")
                                    .font(.headline)
                                    .foregroundStyle(Palette.bodyInk)
                                Text(idea.evidence)
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        Palette.inkSecondary
                                    )
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
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
        // §367.5：refs 落点自带门控懒拉——从动态点引
        // 用进入时本店可能从未加载，落点自己保底（已
        // 载/新鲜＝0 请求），不再靠动态面预热全量联动
        .task {
            await store.loadIfNeeded(appState: appState)
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
        // §459：建为例行走既有 cron 创建面（预填点子
        // 标题/正文，用户在面里定计划）；建成回执带
        // 新 job 本体，回读共享 CronStore 名单确认在
        // 列后才回写点子状态（回读判据）
        .sheet(isPresented: $routineFormShown) {
            if let idea {
                CronJobFormView(
                    job: nil,
                    prefillName: idea.title,
                    prefillPrompt: idea.detail.isEmpty
                        ? idea.title : idea.detail,
                    onCreated: { created in
                        Task {
                            await confirmRoutine(
                                created, idea: idea
                            )
                        }
                    }
                )
            }
        }
    }

    /// 例行建成确认：刷新共享 CronStore 名单，新
    /// job id 在列才算建成（§459 回读判据）；回写
    /// 落定后退页，未落定留在本页看 notes 原因
    private func confirmRoutine(
        _ created: CronJob, idea: BridgeIdea
    ) async {
        let cron = appState.sharedCronStore()
        await cron.refresh()
        let confirmed = cron.jobs.contains {
            $0.id == created.id
        }
        await store.markAdoptedForRoutine(
            appState: appState, idea: idea,
            routineConfirmed: confirmed
        )
        if confirmed,
           let fresh = store.ideas.first(
               where: { $0.id == idea.id }
           ), fresh.status == .adopted,
           store.notes[idea.id] == nil {
            dismiss()
        }
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
                    .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                        .font(.system(size: FrameworkIcon.tabGlyphSize))
                        .foregroundStyle(Palette.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: FrameworkIcon.moreGlyphSize, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(Palette.surface, in: Circle())
                    // §459 对位 Muse 参照：白底轻描边——
                    // 参照像素实测钮面纯白 (255,255,255)、
                    // 靠细边与浅灰页底分界；OneDay 截图
                    // 实测为灰填充 (229,229,229)。白面
                    // （surface 浅档 #FFF）＋separator
                    // 1pt 描边把分界写实，不靠面色对比
                    .overlay {
                        Circle()
                            .stroke(
                                Palette.separator, lineWidth: 1
                            )
                    }
            }
            .disabled(acting)
            if idea.status == .pending {
                // §459：主钮按 kind 分形——chat 开始吧
                // （现行落点不变）／goal 立为目标／
                // routine 建为例行；三态建成判据都是回
                // 读（口径在 IdeasStore 与 confirmRoutine）
                pendingPrimaryButton(idea, acting: acting)
            } else if idea.isAdopted, idea.taskId != nil {
                Button {
                    openIdeaChat(idea)
                } label: {
                    Text("打开对话")
                        .font(.headline)
                        // 主按钮统一口径（2026-11-24 主线
                        // 裁决，§453 改判后续）：与「开始吧」
                        // 同栏同槽同为主钮——饱和蓝底＋白
                        // 字（primarySaturated），不再走第
                        // 85 条 BC-1 的 primaryPale 配对
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Palette.primarySaturated, in: Capsule())
                }
                // 手感 A 档：与「开始吧」同式补按下态
                .buttonStyle(.odPressable)
            } else if idea.isAdopted {
                // §459：goal/routine 落地后无任务关联，
                // 主钮位如实标已落地形态，不给假动作
                Text(adoptedKindText(idea))
                    .font(.headline)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .background(Palette.pageBG)
    }

    /// 待阅主钮（§459 kind 分形）：三钮同几何同配色
    /// （饱和蓝底白字，Palette.primarySaturated，对
    /// 位 Muse 样张 #0064D4——2026-11-24 用户亲裁，
    /// §453 改判追记；「打开对话」未跟改、待主线裁）
    @ViewBuilder
    private func pendingPrimaryButton(
        _ idea: BridgeIdea, acting: Bool
    ) -> some View {
        switch idea.kind {
        case .chat:
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
                primaryButtonLabel(
                    icon: "sparkles",
                    title: acting ? "处理中…" : "开始吧"
                )
            }
            // 手感 A 档：页面主动作补按下态（公用
            // 按压件）；采纳结果触感已由 IdeasStore
            // 按表 D 落 success，此处不叠震
            .buttonStyle(.odPressable)
            .disabled(acting)
        case .goal:
            Button {
                Task {
                    await store.convertToGoal(
                        appState: appState, idea: idea
                    )
                    // 回读确认落字（目标在列＋点子 adop-
                    // ted）才退页；未落定留在本页看原因
                    if let fresh = store.ideas.first(
                        where: { $0.id == idea.id }
                    ), fresh.status == .adopted,
                       store.notes[idea.id] == nil {
                        dismiss()
                    }
                }
            } label: {
                primaryButtonLabel(
                    icon: "target",
                    title: acting ? "处理中…" : "立为目标"
                )
            }
            .buttonStyle(.odPressable)
            .disabled(acting)
        case .routine:
            Button {
                routineFormShown = true
            } label: {
                primaryButtonLabel(
                    icon: "repeat",
                    title: "建为例行"
                )
            }
            .buttonStyle(.odPressable)
            .disabled(acting)
        }
    }

    /// 主钮标签（三态共用）：图标＋标题、饱和蓝胶囊
    /// （开始吧图标＝sparkles 星簇，与 Muse 参照同
    /// 名符号——大四角星＋两小星，像素比对坐实；用
    /// 户 05:52 截图中 107 构建呈现魔杖形，与本分支
    /// 代码不符、疑发货构建树差异，真机以新构建复
    /// 核为准，见 §459 交卷对位表）
    private func primaryButtonLabel(
        icon: String, title: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Palette.primarySaturated, in: Capsule())
    }

    /// 已落地（无任务关联）的主钮位文案：按 kind 如
    /// 实回显落地形态
    private func adoptedKindText(_ idea: BridgeIdea) -> String {
        switch idea.kind {
        case .goal: return "已立为目标"
        case .routine: return "已建为例行"
        case .chat: return "已开始"
        }
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
        if let linkedID = appState.sessionLedger.threadID(
            forIdeaID: idea.id
        ), let existing = fetchThread(linkedID) {
            thread = existing
        } else {
            let fresh = ChatThread()
            modelContext.insert(fresh)
            try? modelContext.save()
            appState.sessionLedger.linkThread(
                fresh.id, forIdeaID: idea.id
            )
            thread = fresh
        }
        // §219：引用直写目标线程的待发状态（落点决定
        // 与引用写入同动作完成），不再经种子消费
        appState.pendingQuotes.sourceQuotesByThread[thread.id] =
            .idea(IdeaQuote(idea: idea))
        appState.router.drawerThreadSelection = thread.id
        appState.router.mainTabSwitchRequest = .chat
        dismiss()
    }

    private func fetchThread(_ id: UUID) -> ChatThread? {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Kicker 字形块映射（§462）

enum IdeaKicker {
    /// 点子 kicker 字形名：统一轻盈分层符号体系，与全 App 图标重量一致
    static func symbolName(for category: String?) -> String {
        guard let category = category?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !category.isEmpty else {
            return "lightbulb"
        }
        switch category {
        case "health", "健康":
            return "heart"
        case "relationships", "人际关系":
            return "person.2"
        case "finance", "财务":
            return "dollarsign.circle"
        case "career", "事业":
            return "briefcase"
        case "interest", "兴趣":
            return "star"
        case "efficiency", "效率提升":
            return "bolt"
        case "other", "其他":
            return "lightbulb"
        default:
            return "lightbulb"
        }
    }

    /// 点子 kicker 低饱和语义圆角底色（统一柔和浅底，消除纯色块突兀感）
    static func color(for category: String?) -> Color {
        guard let category = category?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !category.isEmpty else {
            return Palette.fillSecondary
        }
        switch category {
        case "health", "健康":
            return Palette.tintGreen
        case "relationships", "人际关系":
            return Palette.tintLavender
        case "finance", "财务":
            return Palette.tintOrange
        case "career", "事业":
            return Palette.tintSky
        case "interest", "兴趣":
            return Palette.tintSky
        case "efficiency", "效率提升":
            return Palette.primaryTint
        case "other", "其他":
            return Palette.fillSecondary
        default:
            return Palette.fillSecondary
        }
    }

    /// 与柔和底色配套的同色系符号前景色
    static func foregroundColor(for category: String?) -> Color {
        guard let category = category?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !category.isEmpty else {
            return Palette.inkSecondary
        }
        switch category {
        case "health", "健康":
            return Palette.successText
        case "relationships", "人际关系":
            return .purple
        case "finance", "财务":
            return Palette.warningText
        case "career", "事业", "interest", "兴趣", "efficiency", "效率提升":
            return Palette.primary
        default:
            return Palette.inkSecondary
        }
    }
}
