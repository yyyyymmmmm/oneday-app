import SwiftUI
import OneDayCore

/// 目标详情（棒 3，对位 #36）：标题/备注＋状态流转
/// ＋进展时间线（手记追加/删条纠错）＋简报信件（点
/// 开记打开时刻）。编辑与子目标创建走 Sheet。
struct MacGoalDetailView: View {
    @Environment(SessionStore.self) private var session
    var store: MacGoalsStore
    let goalID: String?
    @Binding var selection: String?
    @State private var showEdit = false
    @State private var showSubgoal = false
    @State private var confirmDelete = false
    @State private var entryDraft = ""
    @State private var openBriefingID: String?

    private var goal: BridgeGoal? {
        guard let goalID else { return nil }
        return store.goals.first { $0.id == goalID }
    }

    var body: some View {
        Group {
            if let goal {
                ScrollView {
                    VStack(
                        alignment: .leading, spacing: 16
                    ) {
                        header(goal)
                        if !goal.note.isEmpty {
                            Text(goal.note)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        entriesSection(goal)
                        briefingsSection(goal)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .task(id: goal.id) {
                    await store.loadDetail(
                        session: session, goalID: goal.id
                    )
                }
            } else {
                ContentUnavailableView(
                    "选择一个目标",
                    systemImage: "target",
                    description: Text("在中间列表点开一个，这里看详情。")
                )
            }
        }
        .sheet(isPresented: $showEdit) {
            if let goal {
                MacGoalFormView(store: store, goal: goal, parentId: nil) {
                    showEdit = false
                }
            }
        }
        .sheet(isPresented: $showSubgoal) {
            if let goal {
                MacGoalFormView(
                    store: store, goal: nil, parentId: goal.id
                ) {
                    showSubgoal = false
                }
            }
        }
        .confirmationDialog(
            "删除这个目标？", isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let goal else { return }
                selection = nil
                Task { await store.delete(session: session, goal: goal) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func header(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(goal.title)
                    .font(.title3.weight(.bold))
                    .textSelection(.enabled)
                Spacer()
                Menu {
                    Button("编辑") { showEdit = true }
                    Button("新建子目标") { showSubgoal = true }
                    if goal.status == .active {
                        Button("标记完成") {
                            Task {
                                await store.setStatus(
                                    session: session, goal: goal,
                                    status: .completed
                                )
                            }
                        }
                    } else {
                        Button("重新打开") {
                            Task {
                                await store.setStatus(
                                    session: session, goal: goal,
                                    status: .active
                                )
                            }
                        }
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            HStack(spacing: 8) {
                Text(goal.status == .completed ? "已完成" : "进行中")
                if let label = goal.activity?.label, !label.isEmpty {
                    Text(label)
                }
                Text("建于 \(MacTimeText.full(goal.createdAt))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let note = store.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func entriesSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("进展")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("记一条进展…", text: $entryDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitEntry(goal) }
                Button("记录") { submitEntry(goal) }
                    .disabled(
                        entryDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
            }
            if store.entries.isEmpty {
                Text("还没有进展记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.callout.weight(.semibold))
                    }
                    Text(entry.body)
                        .font(.callout)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text(
                            entry.source == .user ? "手记" : "智能体记账"
                        )
                        Text(MacTimeText.full(entry.createdAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("删除这条", role: .destructive) {
                        Task {
                            await store.deleteEntry(
                                session: session, goalID: goal.id,
                                entry: entry
                            )
                        }
                    }
                }
            }
        }
    }

    private func briefingsSection(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目标简报")
                .font(.headline)
            if store.briefings.isEmpty {
                Text("还没有简报信件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.briefings) { briefing in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        let opening = openBriefingID != briefing.id
                        openBriefingID = opening ? briefing.id : nil
                        if opening {
                            Task {
                                await store.openBriefing(
                                    session: session,
                                    briefing: briefing
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName: briefing.lastOpenedAt == nil
                                    ? "envelope.badge"
                                    : "envelope.open"
                            )
                            Text(briefing.title)
                                .font(.callout.weight(.medium))
                            Text(briefing.period)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(MacTimeText.short(briefing.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if openBriefingID == briefing.id {
                        MacMarkdownView(text: briefing.body)
                        if let note = briefing.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func submitEntry(_ goal: BridgeGoal) {
        let text = entryDraft
        entryDraft = ""
        Task {
            await store.addEntry(
                session: session, goalID: goal.id, text: text
            )
        }
    }
}
