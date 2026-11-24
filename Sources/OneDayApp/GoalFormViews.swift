import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// A-11 结构拆分（2026-11-16）：自 GoalsView.swift 按职责拆出（编辑/新建/委派三表单），内容逐字未改、零行为变更（DESIGN §311）。

/// 目标编辑（sheet，0.33.0 自详情拆出）：草稿编辑
/// ——标题/备注在本地草稿里改，保存时一次 PATCH＋
/// 回读对账确认（GoalsStore.saveEdits）；G-6 后里程
/// 碑已随概念移除，编辑面只剩标题/备注/类别
struct GoalEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: GoalsStore
    let goalID: String

    @State private var title: String
    @State private var note: String
    @State private var category: GoalCategory?
    @State private var isSaving = false
    @State private var saveError: String?

    init(store: GoalsStore, goalID: String) {
        self.store = store
        self.goalID = goalID
        let goal = store.goal(id: goalID)
        _title = State(initialValue: goal?.title ?? "")
        _note = State(initialValue: goal?.note ?? "")
        _category = State(initialValue: goal?.category)
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
        .fullscreenPopBridge()
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

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let ok = await store.saveEdits(
            appState: appState, goalID: goalID, title: title,
            note: note
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

/// 委派表单（sheet，0.40.0）：一件事的标题；提交走
/// GoalsStore.delegateTask（桥一次调用建卡＋写 goalId
/// 字段→回读确认，§308 单轨），确认落定才关表单，
/// 失败原因留表单内——与新建目标同一纪律
struct GoalDelegateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let store: GoalsStore
    let goal: BridgeGoal

    @State private var title = ""
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
        .fullscreenPopBridge()
    }

    /// 进展对话绑定（§123 H1）：委派确认落定后给目标绑
    /// 一个旁聊（没有才建、已有复用），绑定落盘在
    /// SideChatStore.goalThreadIDs。线程以目标名为题并
    /// 钉住标题（titleIsManual）——它在抽屉里的身份就
    /// 是这个目标，不让服务端 AI 标题改掉；回响条目本
    /// 身由目标详情的物化点按真源补落（GoalEcho），这
    /// 里只立绑定，不预写任何状态
    private func ensureGoalThread() {
        if appState.sessionLedger.threadID(forGoalID: goal.id) != nil {
            return
        }
        let thread = ChatThread(title: goal.title)
        thread.titleIsManual = true
        modelContext.insert(thread)
        try? modelContext.save()
        appState.sessionLedger.linkThread(thread.id, forGoalID: goal.id)
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        let ok = await store.delegateTask(
            appState: appState, goalID: goal.id, title: title
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
