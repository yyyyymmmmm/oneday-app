import SwiftUI
import OneDayCore

/// 想法详情（棒 3，对位 #35）：全文＋依据＋交付物清
/// 单；动作＝忽略/删除＋采纳（棒 4 看板 #58 落地后
/// 接通：建卡→回写 taskId，见 MacIdeasStore.adopt）。
struct MacIdeaDetailView: View {
    @Environment(SessionStore.self) private var session
    var store: MacIdeasStore
    let ideaID: String?
    @Binding var selection: String?
    @State private var confirmDelete = false

    private var idea: BridgeIdea? {
        guard let ideaID else { return nil }
        return store.ideas.first { $0.id == ideaID }
    }

    var body: some View {
        Group {
            if let idea {
                ScrollView {
                    VStack(
                        alignment: .leading, spacing: 14
                    ) {
                        header(idea)
                        if !idea.detail.isEmpty {
                            Text(idea.detail)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        if !idea.deliverables.isEmpty {
                            deliverables(idea)
                        }
                        if !idea.evidence.isEmpty {
                            VStack(
                                alignment: .leading, spacing: 4
                            ) {
                                Text("依据")
                                    .font(.headline)
                                Text(idea.evidence)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        actions(idea)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "选择一个想法",
                    systemImage: "lightbulb",
                    description: Text("在中间列表点开一个，这里看详情。")
                )
            }
        }
        .confirmationDialog(
            "删除这个想法？", isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let idea else { return }
                selection = nil
                Task { await store.delete(session: session, idea: idea) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func header(_ idea: BridgeIdea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(IdeaEmoji.resolve(emoji: idea.emoji))
                    .font(.title2)
                Text(idea.title)
                    .font(.title3.weight(.bold))
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Text(MacIdeasView.statusLabel(idea.status))
                if let label = MacIdeasView.domainLabel(idea) {
                    Text(label)
                }
                Text(
                    idea.source == .generated ? "自动生成" : "手动记录"
                )
                Text(MacTimeText.full(idea.createdAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func deliverables(_ idea: BridgeIdea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("包含哪些内容")
                .font(.headline)
            ForEach(
                Array(idea.deliverables.enumerated()), id: \.offset
            ) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func actions(_ idea: BridgeIdea) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 10) {
                if idea.status == .pending {
                    Button {
                        Task {
                            await store.adopt(
                                session: session, idea: idea
                            )
                        }
                    } label: {
                        Label(
                            "采纳（建任务推进）",
                            systemImage: "hammer"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Task {
                            await store.dismiss(
                                session: session, idea: idea
                            )
                        }
                    } label: {
                        Label("忽略", systemImage: "eye.slash")
                    }
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            if let taskID = idea.taskId {
                Text("已转任务：\(taskID)（在枢纽看板面跟进）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = store.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
