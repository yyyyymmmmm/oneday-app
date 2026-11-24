import OneDayCore
import OneDayDesign
import SwiftUI

/// 外部事件页（H11，DESIGN §390；自动化面）：GitHub 推送、
/// 监控告警、表单提交等外部事件，按订阅的地址打进来直达
/// 触发 Hermes。订阅真值在服务端（与 CLI 同一份存储）；
/// 密钥只在建订阅时回一次，本页展示一次后不再出现。
/// 入站实触发要外部系统真打进来，属联调门（§390 记账）。
struct WebhooksView: View {
    @Environment(AppState.self) private var appState
    @State private var store = WebhooksStore()
    @State private var showCreate = false
    @State private var pendingDelete: WebhookRoute?

    private var ops: WebhooksOperations {
        WebhooksOperations(
            load: {
                try await appState.performAdmin { client, config in
                    try await client.webhooksPage(config: config)
                }
            },
            create: { input in
                try await appState.performAdmin { client, config in
                    try await client.createWebhook(config: config, input: input)
                }
            },
            delete: { name in
                try await appState.performAdmin { client, config in
                    try await client.deleteWebhook(config: config, name: name)
                }
            },
            setEnabled: { name, enabled in
                try await appState.performAdmin { client, config in
                    try await client.setWebhookEnabled(
                        config: config, name: name, enabled: enabled
                    )
                }
            },
            enablePlatform: {
                try await appState.performAdmin { client, config in
                    try await client.enableWebhooks(config: config)
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                Text("外面的系统（GitHub、监控、表单）有事发生时，按订阅地址把事件打进来，Hermes 立刻被触发去处理——不用等它轮询。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)

            if let note = store.note {
                Section {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(
                            store.noteIsProblem
                                ? Palette.danger : Palette.inkSecondary
                        )
                }
                .listRowBackground(Palette.surface)
            }

            if let oneTime = store.oneTimeSecret {
                Section {
                    Text("订阅「\(oneTime.name)」的密钥只显示这一次，关掉就再也看不到（服务端之后只说有没有）。发事件时用它签名：")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Text(oneTime.secret)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("我已保存，关掉") { store.dismissOneTimeSecret() }
                } header: {
                    Text("新订阅的密钥")
                }
                .listRowBackground(Palette.surface)
            }

            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("外部事件")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(ops: ops) }
        .refreshable { await store.load(ops: ops) }
        .sheet(isPresented: $showCreate) {
            WebhookCreateForm { input in
                await store.create(ops: ops, input: input)
            }
        }
        .confirmationDialog(
            "删除订阅「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let route = pendingDelete {
                    Task { await store.delete(ops: ops, name: route.name) }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("删掉后这个地址立刻失效，外面的系统再打进来会被拒。")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取外部事件…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
        case .notLoggedIn:
            Section {
                Text("登录已失效，重新连接服务器后这里会显示外部事件订阅。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
        case .failed(let message):
            Section {
                InlineError(message)
                Button("重试") { Task { await store.load(ops: ops) } }
            }
            .listRowBackground(Palette.surface)
        case .ready(let page):
            platformSection(page)
            subscriptionsSection(page)
        }
    }

    private func platformSection(_ page: WebhooksPage) -> some View {
        Section {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text("接收外部事件")
                    .foregroundStyle(Palette.ink)
                Spacer()
                if page.platformEnabled {
                    Text("已开启")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } else if store.isEnablingPlatform {
                    ProgressView()
                } else {
                    Button("开启") {
                        Task { await store.enablePlatform(ops: ops) }
                    }
                }
            }
            if !page.baseURL.isEmpty {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("事件入口")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Text(page.baseURL)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.inkSecondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("平台")
        } footer: {
            Text(page.platformEnabled
                ? "订阅地址形如 入口/webhooks/订阅名。关平台要去服务器上改配置，这里只负责开。"
                : "平台没开时建不了订阅。开启会让网关重启一次。")
        }
    }

    private func subscriptionsSection(_ page: WebhooksPage) -> some View {
        Section {
            if page.subscriptions.isEmpty {
                Text("还没有订阅。建一个：给它起名、选它接收什么事件、写清 Hermes 收到后做什么。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            ForEach(page.subscriptions) { route in
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(route.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        if !route.enabled {
                            Text("已停用")
                                .font(.caption)
                                .foregroundStyle(Palette.danger)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { route.enabled },
                            set: { newValue in
                                Task {
                                    await store.setEnabled(
                                        ops: ops, name: route.name,
                                        enabled: newValue
                                    )
                                }
                            }
                        ))
                        .labelsHidden()
                        .disabled(store.actingNames.contains(route.name))
                    }
                    if !route.routeDescription.isEmpty {
                        Text(route.routeDescription)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text(route.events.isEmpty
                        ? "全部事件"
                        : "事件：" + route.events.joined(separator: "、"))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    if !route.prompt.isEmpty {
                        Text(route.prompt)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                    Text(route.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.inkMuted)
                        .textSelection(.enabled)
                    HStack(spacing: OneDayMetrics.spacingM) {
                        Text(route.secretSet ? "密钥已设" : "未设密钥")
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                        Spacer()
                        Button("删除", role: .destructive) {
                            pendingDelete = route
                        }
                        .font(.footnote)
                        .disabled(store.actingNames.contains(route.name))
                    }
                }
            }
            Button("新建订阅") { showCreate = true }
                .disabled(!page.platformEnabled)
        } header: {
            Text("订阅")
        } footer: {
            Text("启停立刻生效，不用重启。投递目标在建订阅时定：log 只记录处理结果，填平台名会把结果发到那个平台；直达投递则不经 Hermes 加工、原样送达。")
        }
    }
}

/// 建订阅表单：名字会被规范化（小写、空格转连字符）；
/// 预检与服务端同口径（名合法、deliver_only 不能配 log）
struct WebhookCreateForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var routeDescription = ""
    @State private var eventsText = ""
    @State private var prompt = ""
    @State private var deliver = "log"
    @State private var deliverChatID = ""
    @State private var deliverOnly = false
    @State private var problem: String?
    let onCreate: (WebhookCreateInput) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let problem {
                    Section {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                Section("订阅") {
                    TextField("名字（如 github-push）", text: $name)
                    TextField("说明（可选）", text: $routeDescription)
                    TextField("事件（逗号分隔，留空＝全部）", text: $eventsText)
                }
                Section("收到事件后") {
                    TextField("投递目标（log＝只记录，或平台名如 telegram）", text: $deliver)
                    TextField("投递聊天 ID（可选，配平台名时用）", text: $deliverChatID)
                    Toggle("只投递、不让 Hermes 再加工", isOn: $deliverOnly)
                    TextField("给 Hermes 的话（收到事件时照此处理）", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("新建订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("建订阅") {
                        var input = WebhookCreateInput(name: name)
                        input.routeDescription = routeDescription
                        input.events = eventsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        input.prompt = prompt
                        input.deliver = deliver.isEmpty ? "log" : deliver
                        input.deliverOnly = deliverOnly
                        input.deliverChatID = deliverChatID
                        if let first = input.problems.first {
                            problem = first
                            return
                        }
                        Task {
                            await onCreate(input)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
