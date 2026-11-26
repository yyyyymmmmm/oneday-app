import SwiftUI
import OneDayCore

/// 档案面（棒 4，对位 #44）：档案清单＋切换激活＋
/// Soul 文档查看/编辑（写回后回读，与 iOS 档案面
/// 同口径）
struct MacHubProfilesView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "档案", count: store.profiles.count
            )
            if store.profiles.isEmpty {
                HubEmptyText(text: "暂无档案。")
            }
            ForEach(
                Array(store.profiles.enumerated()), id: \.offset
            ) { _, profile in
                let name = profile.hubFirstStr(["name", "id"]) ?? ""
                let active = profile.hubBool("active")
                    ?? profile.hubBool("is_active") ?? false
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.callout.weight(.medium))
                        if let desc = profile.hubFirstStr(
                            ["description", "model"]
                        ) {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if active {
                        Text("当前")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    } else {
                        Button("设为当前") {
                            Task {
                                await store.activateProfile(
                                    session: session, name: name
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Soul") {
                        Task {
                            await store.loadSoul(
                                session: session, name: name
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            if let name = store.soulProfileName {
                HubSectionHeader(title: "Soul · \(name)")
                TextEditor(text: Binding(
                    get: { store.soulText },
                    set: { store.soulText = $0 }
                ))
                .font(.body)
                .frame(minHeight: 160)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }
                HStack {
                    Spacer()
                    Button("保存 Soul") {
                        Task { await store.saveSoul(session: session) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

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

/// 工具集面（棒 4，对位 #47）：/v1/toolsets 平台真
/// 值清单＋启停开关（回读为准）
struct MacHubToolsetsView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "工具集", count: store.toolsetRows.count
            )
            if store.toolsetRows.isEmpty {
                HubEmptyText(text: "工具集清单暂不可用。")
            }
            ForEach(
                Array(store.toolsetRows.enumerated()), id: \.offset
            ) { _, row in
                let name = row.hubFirstStr(["name", "id"]) ?? ""
                let enabled = row.hubBool("enabled") ?? false
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.callout.weight(.medium))
                        Text(row.hubFirstStr(
                            ["description", "platform"]
                        ) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            Task {
                                await store.setToolset(
                                    session: session, name: name,
                                    enabled: newValue
                                )
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                Divider()
            }
        }
    }
}

/// 委派面（棒 4，对位 #48）：路由全量呈现（当前后
/// 端/后端清单/模型路线/档案路线），切换与设默认
/// 都走先读后改＋回读对账（成败以 routing 回读为
/// 准，与 iOS 同口径）；呈现直接读原始路由文档，
/// 未知字段不丢
struct MacHubDelegationView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            if let raw = store.routingRaw {
                let configured = raw.hubFirstStr(
                    ["configured", "backend"]
                ) ?? ""
                HubSectionHeader(title: "当前后端")
                HubKVView(label: "后端", value: configured)
                if let reason = raw.hubFirstStr(["blocked_reason"]) {
                    Text("当前后端在本机跑不了：\(reason)")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                let backends = raw.hubFirstList(["backends"])
                HubSectionHeader(
                    title: "后端清单", count: backends.count
                )
                ForEach(
                    Array(backends.enumerated()), id: \.offset
                ) { _, backend in
                    let name = backend.hubFirstStr(["name"]) ?? ""
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backend.hubFirstStr(["label", "name"])
                                ?? name)
                                .font(.callout.weight(.medium))
                            Text(backend.hubFirstStr(
                                ["description", "reason"]
                            ) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if name == configured {
                            Text("当前")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else if backend.hubBool("available") ?? true {
                            Button("切换") {
                                Task {
                                    await store.setBackend(
                                        session: session, backend: name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text("不可用")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Divider()
                }
                let modelMap = raw.hubDict["model_map"] ?? .null
                let options = modelMap.hubFirstList(["options"])
                let modelDefault = modelMap.hubStr("default")
                HubSectionHeader(
                    title: "模型路线", count: options.count
                )
                ForEach(
                    Array(options.enumerated()), id: \.offset
                ) { _, option in
                    let name = option.hubFirstStr(["name", "id"]) ?? ""
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.callout.weight(.medium))
                            Text(option.hubFirstStr(
                                ["description", "model"]
                            ) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if name == modelDefault {
                            Text("默认")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Button("设为默认") {
                                Task {
                                    await store.setModelRouteDefault(
                                        session: session, name: name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Divider()
                }
                let profileRoutes = raw.hubDict["profile_routes"]
                    ?? .null
                let profiles = profileRoutes.hubFirstList(["profiles"])
                let profileDefault = profileRoutes.hubStr("default")
                HubSectionHeader(
                    title: "档案路由", count: profiles.count
                )
                ForEach(
                    Array(profiles.enumerated()), id: \.offset
                ) { _, route in
                    let name = route.hubFirstStr(
                        ["profile", "name", "id"]
                    ) ?? ""
                    HStack(spacing: 8) {
                        Text(name).font(.callout.weight(.medium))
                        Spacer()
                        if name == profileDefault {
                            Text("默认")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Button("设为默认") {
                                Task {
                                    await store.setProfileRouteDefault(
                                        session: session, name: name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "委派路由暂不可用。")
            }
        }
    }
}
