import OneDayCore
import OneDayDesign
import SwiftUI

/// 目标格（0.11.0 P4 转正）：oneday-bridge 目标仓真
/// 列表——卡＝标题＋里程碑进度 x/y＋进度条（设计标准
/// §7 P4 锚：目标卡＝§5.8 卡骨架，里程碑 CheckRow 在
/// 详情里）。桥未连接/未开通如实露、零假数据；写动作
/// 全部走 GoalsStore 的回读确认口径。
struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = GoalsStore()
    @State private var showCreate = false

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
            ScrollView {
                LazyVStack(spacing: OneDayMetrics.spacingSM) {
                    ForEach(store.goals) { goal in
                        NavigationLink {
                            GoalDetailView(store: store, goalID: goal.id)
                        } label: {
                            GoalCardView(goal: goal)
                        }
                        .buttonStyle(.plain)
                        if let note = store.notes[goal.id] {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .refreshable {
                await store.load(appState: appState)
            }
        }
    }
}

/// 目标卡（§5.8 卡骨架）：标题＋备注一行＋进度条＋
/// 「x/y 里程碑」；无里程碑时不画进度条（0/0 不冒充进度）
struct GoalCardView: View {
    let goal: BridgeGoal

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkMuted)
            }
            if !goal.note.isEmpty {
                Text(goal.note)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            if !goal.milestones.isEmpty {
                HStack(spacing: OneDayMetrics.spacingS) {
                    DataBar(fraction: GoalProgress.fraction(of: goal), height: 4)
                    Text("\(GoalProgress.text(of: goal)) 里程碑")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .tabularDigits()
                }
            }
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
                            .font(.system(size: 11, weight: .bold))
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
        .buttonStyle(.plain)
    }
}

/// 目标详情/编辑（0.11.0）：草稿全量编辑——标题/备注/
/// 里程碑勾选·改名·增删都在本地草稿里改，保存时一次
/// PATCH 全量替换（已有里程碑 id 原样带回）＋回读逐项
/// 对账确认（GoalsStore.saveEdits）。删除走破坏性确认，
/// 服务端确认消失后才关页
struct GoalDetailView: View {
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
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

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

    private var current: BridgeGoal? { store.goal(id: goalID) }
    private var acting: Bool {
        isSaving || isDeleting || store.actingIDs.contains(goalID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                fieldsGroup
                milestonesGroup
                if let saveError {
                    InlineError(saveError)
                }
                if let note = store.notes[goalID] {
                    InlineError(note)
                }
                deleteButton
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("目标详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : "保存") {
                    Task { await save() }
                }
                .disabled(acting || title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个目标？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除目标", role: .destructive) {
                Task { await deleteGoal() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("里程碑会一并删除。挂在这个目标上的点子会解除关联（点子本身保留）。")
        }
        // 服务端回读把目标换了新值（如别处改动）时不覆盖
        // 正在编辑的草稿——草稿以打开时快照为准，保存走全量
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
                        }
                        .buttonStyle(.plain)
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

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text(isDeleting ? "删除中…" : "删除目标")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(acting)
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
            // 回读已确认：以服务端现值重同步草稿基线
            if let fresh = current {
                title = fresh.title
                note = fresh.note
                milestones = fresh.milestones.map {
                    MilestoneDraftState(
                        id: $0.id, title: $0.title, done: $0.done
                    )
                }
                newMilestoneTitle = ""
            }
        } else {
            saveError = store.notes[goalID]
        }
    }

    private func deleteGoal() async {
        isDeleting = true
        defer { isDeleting = false }
        if await store.delete(appState: appState, goalID: goalID) {
            dismiss()
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
                                    }
                                    .buttonStyle(.plain)
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
