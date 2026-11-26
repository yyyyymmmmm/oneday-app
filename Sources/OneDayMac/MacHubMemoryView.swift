import SwiftUI
import OneDayCore

/// 记忆面（棒 4，对位 #45）：记忆状态（provider/
/// 内置文件）＋分层摘要＋学习图谱节点（全文可编辑/
/// 删除，与 iOS 记忆面同三口）
struct MacHubMemoryView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var confirmDeleteNode: String?

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "记忆状态")
            if let status = store.memoryStatus {
                HubKVView(
                    label: "当前 provider",
                    value: status.active?.isEmpty == false
                        ? (status.active ?? "")
                        : "内置记忆"
                )
                ForEach(status.providers) { provider in
                    HStack(spacing: 8) {
                        Text(provider.name)
                            .font(.callout.weight(.medium))
                        Text(provider.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(provider.configured == true
                            ? "已配置" : "未配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(
                    status.builtinFiles.keys.sorted(), id: \.self
                ) { file in
                    HubKVView(
                        label: "内置文件 \(file)",
                        value: "\(Int(status.builtinFiles[file] ?? 0)) 字节"
                    )
                }
            } else {
                HubEmptyText(text: "记忆状态暂不可用。")
            }
            if let layers = store.memoryLayers {
                HubSectionHeader(title: "分层记忆")
                HubJSONSummaryView(value: layers)
            }
            HubSectionHeader(
                title: "学习图谱节点", count: store.graphNodes.count
            )
            ForEach(
                Array(store.graphNodes.enumerated()), id: \.offset
            ) { _, node in
                let id = node.hubFirstStr(["id", "node_id"]) ?? ""
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.hubFirstStr(
                            ["title", "name", "id"]
                        ) ?? "（无标题）")
                            .font(.callout.weight(.medium))
                        Text(node.hubFirstStr(["kind", "type"]) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("编辑") {
                        Task {
                            await store.loadNode(
                                session: session, id: id
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Button("删除") { confirmDeleteNode = id }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Divider()
            }
            if store.nodeID != nil {
                HubSectionHeader(title: "节点全文")
                TextEditor(text: Binding(
                    get: { store.nodeText },
                    set: { store.nodeText = $0 }
                ))
                .font(.body)
                .frame(minHeight: 160)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }
                HStack {
                    Spacer()
                    Button("保存节点") {
                        Task { await store.saveNode(session: session) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .confirmationDialog(
            "删除这个图谱节点？",
            isPresented: Binding(
                get: { confirmDeleteNode != nil },
                set: { if !$0 { confirmDeleteNode = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let id = confirmDeleteNode {
                    Task {
                        await store.deleteNode(
                            session: session, id: id
                        )
                    }
                }
                confirmDeleteNode = nil
            }
            Button("取消", role: .cancel) { confirmDeleteNode = nil }
        } message: {
            Text("技能节点是归档（可恢复），记忆节点是删除（不可恢复），以服务端语义为准。")
        }
    }
}
