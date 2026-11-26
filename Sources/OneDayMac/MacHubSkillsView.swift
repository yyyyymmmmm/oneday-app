import SwiftUI
import OneDayCore

/// 技能面（棒 4，对位 #46）：技能清单（启停/锁定）
/// ＋全文编辑＋市集搜索安装，与 iOS 技能面同口
struct MacHubSkillsView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var searchText = ""
    @State private var searchResults: [JSONValue] = []
    @State private var searching = false

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "技能", count: store.skills.count
            )
            ForEach(store.skills) { skill in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.callout.weight(.medium))
                        Text([
                            skill.category,
                            skill.description,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(skill.locked == true ? "已锁定" : "锁定") {
                        Task {
                            await store.lockSkill(
                                session: session, name: skill.name,
                                locked: !(skill.locked ?? false)
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Toggle("", isOn: Binding(
                        get: { skill.isEnabled },
                        set: { newValue in
                            Task {
                                await store.toggleSkill(
                                    session: session, name: skill.name,
                                    enabled: newValue
                                )
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    Button("全文") {
                        Task {
                            await store.loadSkill(
                                session: session, name: skill.name
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            if store.skillName != nil {
                HubSectionHeader(
                    title: "技能全文 · \(store.skillName ?? "")"
                )
                TextEditor(text: Binding(
                    get: { store.skillText },
                    set: { store.skillText = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }
                HStack {
                    Spacer()
                    Button("保存技能") {
                        Task { await store.saveSkill(session: session) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            HubSectionHeader(title: "技能市集")
            HStack(spacing: 8) {
                TextField("搜索市集技能", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button("搜索") { Task { await runSearch() } }
                    .disabled(searchText.isEmpty || searching)
            }
            ForEach(
                Array(searchResults.enumerated()), id: \.offset
            ) { _, hit in
                let identifier = hit.hubFirstStr(
                    ["identifier", "id", "name"]
                ) ?? ""
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.hubFirstStr(["name", "identifier"])
                            ?? identifier)
                            .font(.callout.weight(.medium))
                        Text(hit.hubFirstStr(["description"]) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("安装") {
                        Task { await install(identifier) }
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
        }
    }

    private func runSearch() async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        searching = true
        defer { searching = false }
        if let raw = try? await session.chatClient.hubSkillSearch(
            config: config, apiKey: key, query: searchText
        ) {
            searchResults = raw.hubFirstList(
                ["results", "skills", "items"]
            )
            if searchResults.isEmpty {
                searchResults = raw.hubList
            }
        }
    }

    private func install(_ identifier: String) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            try await session.chatClient.hubSkillInstall(
                config: config, apiKey: key, identifier: identifier
            )
            store.actionNote = "技能已安装（已回读清单）"
            await store.load(.skills, session: session, force: true)
        } catch let error as HermesError {
            store.actionNote = error.userMessage
        } catch {
            store.actionNote = "安装技能失败"
        }
    }
}
