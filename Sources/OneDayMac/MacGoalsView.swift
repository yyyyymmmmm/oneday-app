import SwiftUI
import OneDayCore

/// 目标列表（棒 3，对位 #4/#36）：进行中/已完成两
/// 段；行呈活动状态一行（桥派生 label）；工具栏新建。
struct MacGoalsView: View {
    @Environment(SessionStore.self) private var session
    var store: MacGoalsStore
    @Binding var selection: String?
    @State private var showCreate = false

    var body: some View {
        Group {
            if let error = store.loadError, store.goals.isEmpty {
                ContentUnavailableView {
                    Label("目标加载失败", systemImage: "target")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await store.refresh(session: session) }
                    }
                }
            } else if store.loaded && store.goals.isEmpty {
                ContentUnavailableView(
                    "暂无目标",
                    systemImage: "target",
                    description: Text("新建一个目标开始跟踪。")
                )
            } else {
                List(selection: $selection) {
                    if !store.activeGoals.isEmpty {
                        Section("进行中") {
                            ForEach(store.activeGoals) { goal in
                                row(goal).tag(goal.id)
                            }
                        }
                    }
                    if !store.completedGoals.isEmpty {
                        Section("已完成") {
                            ForEach(store.completedGoals) { goal in
                                row(goal).tag(goal.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { showCreate = true } label: {
                    Label("新建目标", systemImage: "plus")
                }
                Button {
                    Task { await store.refresh(session: session) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            MacGoalFormView(store: store, goal: nil, parentId: nil) {
                showCreate = false
            }
        }
        .task {
            if !store.loaded {
                await store.refresh(session: session)
            }
        }
    }

    private func row(_ goal: BridgeGoal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if goal.parentId != nil {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(goal.title)
                    .font(.body)
                    .lineLimit(2)
                if goal.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if let label = goal.activity?.label, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let entry = goal.latestEntry {
                Text(entry.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
