import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 目标编辑与委派表单：统一为原生 iOS 26 Form，告别手绘 ScrollView + .odGroup()。

/// 目标编辑（sheet）：草稿编辑——标题/备注/类别在本地草稿里改，
/// 保存时一次 PATCH＋回读对账确认（GoalsStore.saveEdits）。
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
            Form {
                Section {
                    LabeledContent("标题") {
                        TextField("目标标题", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("备注") {
                        TextField("可选", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .multilineTextAlignment(.trailing)
                    }
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
                } header: {
                    SettingsSectionHeader("目标")
                } footer: {
                    if let error = saveError ?? store.notes[goalID] {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
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

/// 委派表单（sheet）：一件事的标题；提交走 GoalsStore.delegateTask，
/// 确认落定才关表单，失败原因留表单内。
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
            Form {
                Section {
                    TextField(
                        "如：把发言稿打印两份",
                        text: $title, axis: .vertical
                    )
                    .lineLimit(2...4)
                } header: {
                    SettingsSectionHeader("要办的事")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提交后会在任务板上建一张卡，并和目标《\(goal.title)》关联起来；开始、办完或失败，都会记进这个目标的进展对话。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        if let submitError {
                            Text(submitError)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
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
