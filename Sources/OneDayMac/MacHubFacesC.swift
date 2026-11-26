import SwiftUI
import OneDayCore

/// 定时任务面（棒 4，对位 #49，兼全局搜索定时段
/// #10 的数据源）：任务清单（系统任务按 is_system
/// 如实标注）＋暂停/恢复/立即跑/删除＋新建表单＋蓝
/// 图目录，全走 /api/cron/jobs 系（与 iOS 同口）
struct MacHubCronView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newPrompt = ""
    @State private var newSchedule = ""
    @State private var confirmDelete: CronJob?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "定时任务", count: store.cronJobs.count
            )
            if store.cronJobs.isEmpty {
                HubEmptyText(text: "暂无定时任务。")
            }
            ForEach(store.cronJobs) { job in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(job.name ?? "（未命名）")
                                .font(.callout.weight(.medium))
                            if job.isSystem == true {
                                Text("系统任务")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: 4
                                        )
                                        .stroke(
                                            Color.secondary.opacity(0.4)
                                        )
                                    }
                            }
                        }
                        Text([
                            job.scheduleDisplay,
                            job.state,
                            job.nextRunAt.map { "下次 \($0)" },
                            job.lastError.map { "末错：\($0)" },
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(job.enabled ? "暂停" : "恢复") {
                        Task {
                            await store.cronAction(
                                session: session, id: job.id,
                                action: job.enabled
                                    ? "pause" : "resume"
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Button("立即跑") {
                        Task {
                            await store.cronAction(
                                session: session, id: job.id,
                                action: "trigger"
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Button("删除") { confirmDelete = job }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Divider()
            }
            HubSectionHeader(title: "新建定时任务")
            TextField("名称（可空）", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("提示词", text: $newPrompt)
                .textFieldStyle(.roundedBorder)
            TextField(
                "计划（如 every 1h / 0 9 * * *）",
                text: $newSchedule
            )
            .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("新建") {
                    Task {
                        await store.createCron(
                            session: session, name: newName,
                            prompt: newPrompt, schedule: newSchedule
                        )
                        newName = ""
                        newPrompt = ""
                        newSchedule = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPrompt.isEmpty || newSchedule.isEmpty)
            }
            if !store.blueprints.isEmpty {
                HubSectionHeader(
                    title: "蓝图目录", count: store.blueprints.count
                )
                ForEach(
                    Array(store.blueprints.enumerated()), id: \.offset
                ) { _, blueprint in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blueprint.hubFirstStr(["name", "id"])
                            ?? "（未命名蓝图）")
                            .font(.callout.weight(.medium))
                        Text(blueprint.hubFirstStr(["description"])
                            ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .confirmationDialog(
            "删除这个定时任务？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let job = confirmDelete {
                    Task {
                        await store.deleteCron(
                            session: session, id: job.id
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}

/// MCP 面（棒 4，对位 #50）：服务器清单（启停/测
/// 试）＋可安装目录；插件预置条目服务端不许端侧改
/// 开关（网页端实测 409 口径），开关置灰并明示
struct MacHubMCPView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "MCP 服务器", count: store.mcpServers.count
            )
            if store.mcpServers.isEmpty {
                HubEmptyText(text: "暂无 MCP 服务器。")
            }
            ForEach(store.mcpServers) { server in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.callout.weight(.medium))
                        Text([
                            server.originLabel,
                            server.endpointLine,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("测试") {
                        Task {
                            await store.testMCP(
                                session: session, name: server.name
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Toggle("", isOn: Binding(
                        get: { server.enabled },
                        set: { newValue in
                            Task {
                                await store.setMCPEnabled(
                                    session: session,
                                    name: server.name,
                                    enabled: newValue
                                )
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(server.isPluginProvided)
                }
                Divider()
            }
            if store.mcpServers.contains(where: \.isPluginProvided) {
                Text("插件预置的服务器开关在服务端锁定，本面只呈现状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !store.mcpCatalog.isEmpty {
                HubSectionHeader(
                    title: "可安装目录", count: store.mcpCatalog.count
                )
                ForEach(
                    Array(store.mcpCatalog.enumerated()), id: \.offset
                ) { _, entry in
                    let name = entry.hubFirstStr(["name", "id"]) ?? ""
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.callout.weight(.medium))
                            Text(entry.hubFirstStr(["description"])
                                ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("安装") {
                            Task { await install(entry) }
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
            }
        }
    }

    private func install(_ entry: JSONValue) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        var body = entry.hubDict
        if body.isEmpty {
            body = ["name": entry]
        }
        do {
            try await session.chatClient.hubMCPInstall(
                config: config, apiKey: key, body: body
            )
            store.actionNote = "MCP 已安装（已回读清单）"
            await store.load(.mcp, session: session, force: true)
        } catch let error as HermesError {
            store.actionNote = error.userMessage
        } catch {
            store.actionNote = "安装 MCP 失败"
        }
    }
}

/// 连接器面（棒 4，对位 #51）：目录走 Core 静态目
/// 录单源（八家＋接入说明如实标注）；已连接＝端点
/// 读到的 MCP 服务器（Core ConnectedConnector 同
/// 口径：端点读到的才算已连接）
struct MacHubConnectorsView: View {
    let store: MacHubStore

    private var catalog: [ConnectorCatalogEntry] {
        ConnectorDirectory.catalog
    }

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "已连接（服务端在册）",
                count: store.mcpServers.count
            )
            if store.mcpServers.isEmpty {
                HubEmptyText(text: "服务端暂无在册连接。")
            }
            ForEach(store.mcpServers) { server in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ConnectedConnector(server: server)
                            .displayName)
                            .font(.callout.weight(.medium))
                        Text(server.originLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(server.enabled ? "启用中" : "已停用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
            HubSectionHeader(title: "可连接目录", count: catalog.count)
            ForEach(catalog) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.callout.weight(.medium))
                        Text(entry.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(entry.accessDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Divider()
            }
        }
    }
}

/// 频道面（棒 4，对位 #52）：消息平台全量＋网关频
/// 道两段状态呈现（配置在服务端/各平台侧，本面只
/// 读，与 iOS 频道面同口径）
struct MacHubChannelsView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "消息平台")
            if let platforms = store.platforms {
                let rows = platforms.hubFirstList(
                    ["platforms", "items"]
                )
                if rows.isEmpty {
                    HubJSONSummaryView(value: platforms)
                } else {
                    ForEach(
                        Array(rows.enumerated()), id: \.offset
                    ) { _, platform in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.hubFirstStr(
                                    ["name", "platform", "id"]
                                ) ?? "（未命名平台）")
                                    .font(.callout.weight(.medium))
                                Text(platform.hubFirstStr(
                                    ["status", "state"]
                                ) ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let enabled = platform.hubBool(
                                "enabled"
                            ) {
                                Text(enabled ? "启用中" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                    }
                }
            } else {
                HubEmptyText(text: "消息平台暂不可用。")
            }
            HubSectionHeader(title: "网关频道")
            if let channels = store.channels {
                HubJSONSummaryView(value: channels)
            } else {
                HubEmptyText(text: "网关频道暂不可用。")
            }
        }
    }
}

/// 设备与主会话面（棒 4，对位 #53/#61，兼 #60 服
/// 务器会话）：设备会话/同步/主会话停泊态/登录会
/// 话四段状态呈现，全走 device-bridge 与 /v1/auth
/// 既有口（与 iOS MainSessionView 同源）
struct MacHubDevicesView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "主会话（停泊态）")
            if let park = store.parkState {
                HubJSONSummaryView(value: park)
            } else {
                HubEmptyText(text: "主会话状态暂不可用。")
            }
            HubSectionHeader(title: "设备会话")
            if let device = store.deviceSession {
                HubJSONSummaryView(value: device)
            } else {
                HubEmptyText(text: "设备会话暂不可用。")
            }
            HubSectionHeader(title: "同步状态")
            if let sync = store.deviceSync {
                HubJSONSummaryView(value: sync)
            } else {
                HubEmptyText(text: "同步状态暂不可用。")
            }
            HubSectionHeader(title: "登录会话")
            if let sessions = store.authSessions {
                let rows = sessions.hubFirstList(
                    ["sessions", "items"]
                )
                if rows.isEmpty {
                    HubJSONSummaryView(value: sessions)
                } else {
                    ForEach(
                        Array(rows.enumerated()), id: \.offset
                    ) { _, row in
                        HubKVView(
                            label: row.hubFirstStr(
                                ["client", "name", "id"]
                            ) ?? "会话",
                            value: row.hubFirstStr(
                                ["created_at", "last_seen", "status"]
                            ) ?? ""
                        )
                    }
                }
            } else {
                HubEmptyText(text: "登录会话暂不可用。")
            }
        }
    }
}
