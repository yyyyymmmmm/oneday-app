import SwiftUI
import OneDayCore

/// 看板面（棒 4，对位 #58，兼想法采纳 #35 的建卡
/// 口）：板切换＋按列分组的卡清单＋建卡/改状态/
/// 删卡/催派，全走 kanban 插件口（与 iOS 同口）
struct MacHubKanbanView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newTitle = ""
    @State private var newBody = ""
    @State private var confirmDelete: KanbanTask?

    private static let columnOrder = [
        "triage", "todo", "scheduled", "ready",
        "running", "blocked", "review", "done",
    ]

    private var grouped: [(String, [KanbanTask])] {
        guard let tasks = store.kanbanSnapshot?.tasks else {
            return []
        }
        let byStatus = Dictionary(grouping: tasks) { $0.status }
        var result = Self.columnOrder.compactMap { status in
            byStatus[status].map { (status, $0) }
        }
        for status in byStatus.keys.sorted()
        where !Self.columnOrder.contains(status) {
            if let tasks = byStatus[status] {
                result.append((status, tasks))
            }
        }
        return result
    }

    var body: some View {
        HubScroll {
            HStack(spacing: 8) {
                HubSectionHeader(title: "看板")
                if !store.kanbanBoards.isEmpty {
                    Picker("", selection: Binding(
                        get: { store.kanbanBoard },
                        set: { board in
                            Task {
                                await store.selectBoard(
                                    session: session, board: board
                                )
                            }
                        }
                    )) {
                        ForEach(store.kanbanBoards, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                Spacer()
                Button("催派") {
                    Task { await store.kanbanDispatch(session: session) }
                }
                .buttonStyle(.borderless)
            }
            if grouped.isEmpty {
                HubEmptyText(text: "本板暂无卡片。")
            }
            ForEach(grouped, id: \.0) { status, tasks in
                HubSectionHeader(title: status, count: tasks.count)
                ForEach(tasks) { task in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.callout.weight(.medium))
                            Text([
                                task.displayAssignee.map {
                                    "执行：\($0)"
                                },
                                task.latestSummary,
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Menu("改状态") {
                            ForEach(Self.columnOrder, id: \.self) {
                                target in
                                Button(target) {
                                    Task {
                                        await store.kanbanSetStatus(
                                            session: session,
                                            id: task.id,
                                            status: target
                                        )
                                    }
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        Button("删除") { confirmDelete = task }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    Divider()
                }
            }
            HubSectionHeader(title: "新建卡片")
            TextField("标题", text: $newTitle)
                .textFieldStyle(.roundedBorder)
            TextField("正文（可空）", text: $newBody)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("建卡") {
                    Task {
                        await store.kanbanCreate(
                            session: session, title: newTitle,
                            body: newBody
                        )
                        newTitle = ""
                        newBody = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这张卡片？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let task = confirmDelete {
                    Task {
                        await store.kanbanDelete(
                            session: session, id: task.id
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}
