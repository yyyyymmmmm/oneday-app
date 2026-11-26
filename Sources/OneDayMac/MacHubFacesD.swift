import SwiftUI
import OneDayCore

/// 监控面（棒 4，对位 #54）：监控清单＋变化记录＋
/// 新建/删除，全走桥 /monitors 系（与 iOS 监控面
/// 同口；变化以桥回执为准）
struct MacHubMonitorsView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newTarget = ""
    @State private var expandedID: String?
    @State private var confirmDelete: BridgeMonitor?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "监控", count: store.monitors.count
            )
            if store.monitors.isEmpty {
                HubEmptyText(text: "暂无监控。")
            }
            ForEach(store.monitors) { monitor in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(monitor.name)
                                    .font(.callout.weight(.medium))
                                if monitor.unreadChanges > 0 {
                                    Text("\(monitor.unreadChanges) 条新变化")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Color.orange, in: Capsule()
                                        )
                                }
                            }
                            Text([
                                monitor.target,
                                monitor.scheduleText,
                                monitor.lastResult.map {
                                    "最近检查：\($0)"
                                },
                                monitor.lastError,
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(expandedID == monitor.id
                            ? "收起" : "变化") {
                            expandedID = expandedID == monitor.id
                                ? nil : monitor.id
                            if expandedID == monitor.id {
                                Task {
                                    await store.loadMonitorChanges(
                                        session: session,
                                        id: monitor.id
                                    )
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        Button("删除") { confirmDelete = monitor }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    if expandedID == monitor.id,
                       let changes = store.monitorChanges[monitor.id] {
                        if changes.isEmpty {
                            Text("暂无变化记录。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(changes) { change in
                            HStack(spacing: 8) {
                                Text(MacTimeText.short(
                                    change.detectedAt
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(change.summary)
                                    .font(.caption)
                            }
                        }
                    }
                }
                Divider()
            }
            HubSectionHeader(title: "新建监控")
            TextField("名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("目标（URL 或对象）", text: $newTarget)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("新建") {
                    Task {
                        await store.createMonitor(
                            session: session, name: newName,
                            target: newTarget
                        )
                        newName = ""
                        newTarget = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || newTarget.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个监控？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let monitor = confirmDelete {
                    Task {
                        await store.deleteMonitor(
                            session: session, id: monitor.id
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}

/// Webhooks 面（棒 4，对位 #55）：平台开关＋订阅清
/// 单（摘要无密钥）＋启停/删除＋新建（回执一次性密
/// 钥只在当次呈现、不落盘，与 iOS 同口径）
struct MacHubWebhooksView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newEvents = ""
    @State private var oneTimeSecret: String?
    @State private var confirmDelete: String?

    var body: some View {
        HubScroll {
            if let page = store.webhooksPage {
                HStack(spacing: 8) {
                    Text(page.platformEnabled ? "平台已开启" : "平台未开启")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(
                            page.platformEnabled ? .green : .orange
                        )
                    if !page.platformEnabled {
                        Button("开启平台") {
                            Task {
                                await store.enableWebhookPlatform(
                                    session: session
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    if !page.baseURL.isEmpty {
                        Text(page.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HubSectionHeader(
                    title: "订阅", count: page.subscriptions.count
                )
                ForEach(page.subscriptions) { route in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name)
                                .font(.callout.weight(.medium))
                            Text([
                                route.url,
                                route.events.joined(separator: ", "),
                                route.secretSet ? "密钥已设" : "无密钥",
                            ].joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { route.enabled },
                            set: { newValue in
                                Task {
                                    await store.setWebhookEnabled(
                                        session: session,
                                        name: route.name,
                                        enabled: newValue
                                    )
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        Button("删除") { confirmDelete = route.name }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "Webhooks 暂不可用。")
            }
            HubSectionHeader(title: "新建订阅")
            TextField("名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("URL", text: $newURL)
                .textFieldStyle(.roundedBorder)
            TextField("事件（逗号分隔，可空）", text: $newEvents)
                .textFieldStyle(.roundedBorder)
            if let secret = oneTimeSecret {
                Text("一次性密钥（只显示这一次，请立即保存）：\(secret)")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("新建") { Task { await create() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty || newURL.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个 Webhook 订阅？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let name = confirmDelete {
                    Task {
                        await store.deleteWebhook(
                            session: session, name: name
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }

    private func create() async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        var body: [String: JSONValue] = [
            "name": .string(newName),
            "url": .string(newURL),
        ]
        let events = newEvents
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !events.isEmpty {
            body["events"] = .array(events.map { .string($0) })
        }
        do {
            let receipt = try await session.chatClient
                .hubCreateWebhook(
                    config: config, apiKey: key, body: body
                )
            oneTimeSecret = receipt.hubFirstStr(
                ["secret", "webhook_secret", "token"]
            )
            store.actionNote = "订阅已新建（已回读）"
            newName = ""
            newURL = ""
            newEvents = ""
            await store.load(.webhooks, session: session, force: true)
        } catch let error as HermesError {
            store.actionNote = error.userMessage
        } catch {
            store.actionNote = "新建 Webhook 失败"
        }
    }
}

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

/// 环境变量面（棒 4，对位 #57）：清单只显遮蔽值与
/// 是否已设；明文只在点「查看」时经 reveal 口当次
/// 取回呈现、不落盘；设值/删除后回读
struct MacHubEnvView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var revealed: [String: String] = [:]
    @State private var confirmDelete: String?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "环境变量", count: store.envRows.count
            )
            ForEach(store.envRows) { row in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.key)
                            .font(.callout.weight(.medium))
                        Text([
                            row.isSet ? "已设置" : "未设置",
                            revealed[row.key] ?? row.redacted,
                            row.note,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if row.isSet && revealed[row.key] == nil {
                        Button("查看") {
                            Task {
                                if let value = await store.revealEnv(
                                    session: session, key: row.key
                                ) {
                                    revealed[row.key] = value
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("删除") { confirmDelete = row.key }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Divider()
            }
            HubSectionHeader(title: "设置变量")
            TextField("键名", text: $newKey)
                .textFieldStyle(.roundedBorder)
            SecureField("值", text: $newValue)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("保存") {
                    Task {
                        await store.setEnv(
                            session: session, key: newKey,
                            value: newValue
                        )
                        newKey = ""
                        newValue = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newKey.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个环境变量？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let key = confirmDelete {
                    Task {
                        await store.deleteEnv(
                            session: session, key: key
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}

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
