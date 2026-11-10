import OneDayCore
import OneDayDesign
import SwiftUI

/// 点子格（0.11.0 P5 转正；0.32.0 P1 升级）：形态按设
/// 计档 §1.4 向 Muse 点子页收——描边卡改扁平行（左
/// 来源瓷砖＋标题＋说明＋依据行＋信息行）、动作收进
/// 详情页、卡面只留左滑忽略；分区＝待阅（生成在前）
/// 与已采纳（近 30 天、行尾任务状态派生文案）。数据
/// 口径：生成卡由桥端管道每日晨间产出（source=
/// generated、evidence 必填、14 天过期），手记保留；
/// 已转任务以桥 taskId 为真源。桥未连接/未开通与目
/// 标格同口径、零假数据。
struct IdeasView: View {
    @Environment(AppState.self) private var appState
    @State private var store = IdeasStore()
    @State private var kanban = KanbanStore()
    @State private var showCreate = false
    @State private var deleteCandidate: BridgeIdea?

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
                        Label("点子读取失败", systemImage: "exclamationmark.triangle")
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
                if !store.adoptedIdeas.isEmpty {
                    await kanban.load(appState: appState)
                }
            }
            .sheet(isPresented: $showCreate) {
                IdeaCreateView(store: store)
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
                    Task { await store.delete(appState: appState, idea: idea) }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("只删点子本身；已经转成的任务不会受影响。")
            }
        }
    }

    @ViewBuilder
    private var readyContent: some View {
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
                if !store.pendingIdeas.isEmpty {
                    Section("待阅") {
                        ForEach(store.pendingIdeas) { idea in
                            rowLink(for: idea)
                                .swipeActions(
                                    edge: .trailing,
                                    allowsFullSwipe: true
                                ) {
                                    Button("忽略") {
                                        Task {
                                            await store.dismiss(
                                                appState: appState,
                                                idea: idea
                                            )
                                        }
                                    }
                                    .tint(Palette.inkSecondary)
                                }
                        }
                    }
                }
                if !store.adoptedIdeas.isEmpty {
                    Section("已采纳") {
                        ForEach(store.adoptedIdeas) { idea in
                            rowLink(for: idea)
                        }
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
        }
    }

    private func rowLink(for idea: BridgeIdea) -> some View {
        NavigationLink {
            IdeaDetailView(
                store: store, kanban: kanban, ideaID: idea.id
            )
        } label: {
            IdeaRowView(
                idea: idea,
                goalTitle: store.goalTitle(for: idea),
                taskStatusText: store.taskStatusText(
                    for: idea, kanban: kanban
                ),
                note: store.notes[idea.id]
            )
        }
        .listRowBackground(Palette.pageBG)
        .contextMenu {
            if idea.status == .pending {
                Button("忽略") {
                    Task {
                        await store.dismiss(
                            appState: appState, idea: idea
                        )
                    }
                }
                if idea.source == .generated {
                    Button("太泛了，忽略") {
                        Task {
                            await store.dismiss(
                                appState: appState, idea: idea,
                                tooGeneric: true
                            )
                        }
                    }
                }
            }
            Button("删除", role: .destructive) {
                deleteCandidate = idea
            }
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

/// 点子扁平行（设计档 §1.4 落点）：34pt 来源瓷砖＋
/// 标题（Headline semibold、提案标题属语义位）＋说明
/// ＋依据行（生成卡）＋信息行（目标 chip/相对时间/
/// 过期倒数/任务状态）。行内不摆按钮：动作在详情页
/// 与左滑/长按里
struct IdeaRowView: View {
    let idea: BridgeIdea
    let goalTitle: String?
    let taskStatusText: String?
    let note: String?

    private var tileSymbol: String {
        guard idea.source == .generated else { return "pencil" }
        // 锚点模型（0.39.0）：S/G/M 映射与旧 switch 逐一
        // 对齐，K（任务）/R（记忆）新增各自瓷砖
        let kind = IdeaAnchor(evidenceRef: idea.evidenceRef)?.kind
            ?? .unknown
        return kind.tileSymbol
    }

    private var infoText: String {
        var parts = [IdeasView.dayTimeText(idea.createdAt)]
        if idea.source == .generated,
           let days = IdeaBoard.expiryDaysLeft(
               idea, now: Date().timeIntervalSince1970
           ) {
            parts.append(days == 0 ? "今天到期" : "\(days) 天后过期")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusTile,
                style: .continuous
            )
            .fill(Palette.primaryPale)
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: tileSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.primary)
            }
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingXS
            ) {
                Text(idea.title)
                    // 0.41.0（收口批 C14）：行题回收角色
                    // 表 .rowTitle（Body regular），与动态
                    // 帖行同轨
                    .font(.rowTitle)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                if !idea.detail.isEmpty {
                    Text(idea.detail)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(3)
                }
                if idea.source == .generated, !idea.evidence.isEmpty {
                    Text("依据 · \(idea.evidence)")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    if let goalTitle {
                        Label(goalTitle, systemImage: "target")
                            .font(.footnote)
                            .foregroundStyle(Palette.primary)
                            .padding(
                                .horizontal, OneDayMetrics.spacingS
                            )
                            .padding(
                                .vertical, OneDayMetrics.spacingXS
                            )
                            .background(
                                Palette.primaryPale, in: Capsule()
                            )
                            .lineLimit(1)
                    }
                    Text(infoText)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer(minLength: 0)
                    if let taskStatusText {
                        Text(taskStatusText)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    } else if idea.isAdopted {
                        Label("已转任务", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }
}

/// 点子详情（设计档 §1.4 动作全集）：全文＋依据＋
/// 信息＋任务关联；底部动作＝转成任务（主）/忽略
/// （次）/删除。采纳后本页就地变已采纳态、给出打开
/// 任务的入口；忽略/删除后自动返回列表
struct IdeaDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: IdeasStore
    let kanban: KanbanStore
    let ideaID: String

    @State private var showTask = false
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
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.bodyInk)
                            if !idea.detail.isEmpty {
                                Text(idea.detail)
                                    .font(.body)
                                    .foregroundStyle(Palette.bodyInk)
                            }
                        }
                        if idea.source == .generated,
                           !idea.evidence.isEmpty {
                            VStack(
                                alignment: .leading, spacing: 0
                            ) {
                                SectionLabel("依据")
                                    .padding(
                                        .bottom, OneDayMetrics.spacingS
                                    )
                                VStack(
                                    alignment: .leading,
                                    spacing: OneDayMetrics.spacingXS
                                ) {
                                    Text(idea.evidence)
                                        .font(.body)
                                        .foregroundStyle(Palette.bodyInk)
                                    if let ref = idea.evidenceRef {
                                        Text("素材编号 \(ref)")
                                            .font(.footnote)
                                            .foregroundStyle(
                                                Palette.inkSecondary
                                            )
                                    }
                                }
                                .padding(OneDayMetrics.cardPadding)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .background(
                                    Palette.surface,
                                    in: RoundedRectangle(
                                        cornerRadius:
                                            OneDayMetrics.containerCorner,
                                        style: .continuous
                                    )
                                )
                            }
                        }
                        infoGroup(idea)
                        if idea.isAdopted, idea.taskId != nil {
                            taskGroup(idea)
                        }
                        actionsGroup(idea)
                        if let note = store.notes[idea.id] {
                            InlineError(note)
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.top, OneDayMetrics.spacingM)
                    .padding(.bottom, OneDayMetrics.spacingXL)
                }
            } else {
                ContentUnavailableView(
                    "这个点子已不在列表里",
                    systemImage: "lightbulb.slash"
                )
            }
        }
        .background(Palette.pageBG)
        .navigationTitle("点子详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTask) {
            if let taskId = idea?.taskId {
                KanbanTaskDetailView(store: kanban, taskID: taskId)
            }
        }
        .confirmationDialog(
            "删除这个点子？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除点子", role: .destructive) {
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
                GroupDivider()
                FieldRow(label: "状态") {
                    Text(statusText(idea))
                }
            }
            .odGroup()
        }
    }

    private func statusText(_ idea: BridgeIdea) -> String {
        switch idea.status {
        case .pending: return "待阅"
        case .adopted: return "已采纳"
        case .dismissed: return "已忽略"
        case .expired: return "已过期"
        }
    }

    private func taskGroup(_ idea: BridgeIdea) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("任务")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                FieldRow(label: "状态") {
                    Text(
                        store.taskStatusText(
                            for: idea, kanban: kanban
                        ) ?? "已转任务"
                    )
                }
                GroupDivider()
                FieldRow(label: "任务") {
                    Button("打开任务详情") { showTask = true }
                }
            }
            .odGroup()
        }
    }

    private func actionsGroup(_ idea: BridgeIdea) -> some View {
        let acting = store.actingIDs.contains(idea.id)
        return VStack(spacing: OneDayMetrics.spacingS) {
            if idea.status == .pending {
                Button {
                    Task {
                        await store.convertToTask(
                            appState: appState, idea: idea,
                            kanban: kanban
                        )
                    }
                } label: {
                    Label(
                        acting ? "处理中…" : "转成任务",
                        systemImage: "arrow.right.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(acting)
                Button {
                    Task {
                        await store.dismiss(
                            appState: appState, idea: idea
                        )
                        dismiss()
                    }
                } label: {
                    Label("忽略", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(acting)
                if idea.source == .generated {
                    Button {
                        Task {
                            await store.dismiss(
                                appState: appState, idea: idea,
                                tooGeneric: true
                            )
                            dismiss()
                        }
                    } label: {
                        Label(
                            "太泛了，忽略",
                            systemImage: "hand.thumbsdown"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(acting)
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("删除点子", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(acting)
        }
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

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                                detail: detail, goalId: goalId
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
