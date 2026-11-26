import SwiftUI
import OneDayCore

/// 预设面（棒 4，对位 #56）：模型组合文档（桥
/// meta/model-combos）清单＋增删；写回走先读后改
/// 整档 PUT（未知字段原样保留，与 iOS 同口径）
struct MacHubPresetsView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newModel = ""

    private var combos: [JSONValue] {
        store.combosRaw?.hubFirstList(["combos", "presets"]) ?? []
    }

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "模型组合", count: combos.count)
            if combos.isEmpty {
                HubEmptyText(text: "暂无模型组合。")
            }
            ForEach(Array(combos.enumerated()), id: \.offset) { _, combo in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(combo.hubFirstStr(["name", "id"])
                            ?? "（未命名组合）")
                            .font(.callout.weight(.medium))
                        Text(comboModels(combo).joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("删除") {
                        Task { await deleteCombo(combo) }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Divider()
            }
            HubSectionHeader(title: "新建组合")
            TextField("组合名", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("模型 id", text: $newModel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("新建") { Task { await addCombo() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty || newModel.isEmpty)
            }
        }
    }

    private func comboModels(_ combo: JSONValue) -> [String] {
        combo.hubFirstList(["models", "model_ids"]).compactMap {
            $0.stringValue ?? $0.hubFirstStr(["id", "model", "name"])
        }
    }

    /// 先读后改：以本面已回读的文档为底，只动 combos
    /// 数组，整档写回（其余键原样保留）
    private func saveCombos(_ updated: [JSONValue]) async {
        guard let config = session.config, let key = session.apiKey,
              var document = store.combosRaw?.hubDict
        else { return }
        document["combos"] = .array(updated)
        do {
            try await session.chatClient.hubSaveModelCombos(
                config: config, apiKey: key, document: document
            )
            store.actionNote = "模型组合已保存（已回读）"
            await store.load(.presets, session: session, force: true)
        } catch let error as HermesError {
            store.actionNote = error.userMessage
        } catch {
            store.actionNote = "保存模型组合失败"
        }
    }

    private func addCombo() async {
        var updated = combos
        updated.append(.object([
            "name": .string(newName),
            "models": .array([.string(newModel)]),
        ]))
        await saveCombos(updated)
        newName = ""
        newModel = ""
    }

    private func deleteCombo(_ combo: JSONValue) async {
        let name = combo.hubFirstStr(["name", "id"])
        await saveCombos(combos.filter {
            $0.hubFirstStr(["name", "id"]) != name
        })
    }
}
