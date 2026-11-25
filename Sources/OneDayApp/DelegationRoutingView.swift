import OneDayCore
import OneDayDesign
import SwiftUI

/// 委派路由页（H8，DESIGN §390；设置·智能体）：Hermes 把
/// 子任务委派出去时走哪个后端、重活/杂活怎么分流、能以
/// 哪些档案身份跑——三块都在这一页看清、改完回读对账。
/// 落位口径：蓝图把 H8 归设置·智能体高级区；与工具集页
/// 同组并列（一个功能一个家，不进枢纽）。
struct DelegationRoutingView: View {
    @Environment(AppState.self) private var appState
    @State private var store = DelegationRoutingStore()
    @State private var showModelEditor = false
    @State private var showProfileEditor = false

    private var ops: DelegationRoutingOperations {
        DelegationRoutingOperations(
            load: {
                try await appState.performAdmin { client, config in
                    try await client.delegationRouting(config: config)
                }
            },
            setBackend: { backend in
                try await appState.performAdmin { client, config in
                    try await client.setDelegationBackend(
                        config: config, backend: backend
                    )
                }
            },
            setModelMap: { routes, defaultRoute in
                try await appState.performAdmin { client, config in
                    try await client.setDelegationModelMap(
                        config: config, routes: routes,
                        defaultRoute: defaultRoute
                    )
                }
            },
            setProfileRoutes: { routes, defaultRoute in
                try await appState.performAdmin { client, config in
                    try await client.setDelegationProfileRoutes(
                        config: config, routes: routes,
                        defaultRoute: defaultRoute
                    )
                }
            }
        )
    }

    var body: some View {
        List {
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

            content
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("子任务")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(ops: ops) }
        .refreshable { await store.load(ops: ops) }
        .sheet(isPresented: $showModelEditor) {
            if let routing = store.routing {
                DelegationModelRoutesEditor(
                    routes: routing.modelRoutes,
                    defaultRoute: routing.modelRouteDefault
                ) { routes, defaultRoute in
                    await store.saveModelMap(
                        ops: ops, routes: routes, defaultRoute: defaultRoute
                    )
                }
            }
        }
        .sheet(isPresented: $showProfileEditor) {
            if let routing = store.routing {
                DelegationProfileRoutesEditor(
                    routes: routing.profileRoutes,
                    defaultRoute: routing.profileRouteDefault,
                    profiles: routing.profiles
                ) { routes, defaultRoute in
                    await store.saveProfileRoutes(
                        ops: ops, routes: routes, defaultRoute: defaultRoute
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取委派路由…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
        case .notLoggedIn:
            Section {
                Text("登录已失效，重新连接服务器后这里会显示委派路由。")
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
        case .ready(let routing):
            backendSection(routing)
            modelRoutesSection(routing)
            profileRoutesSection(routing)
        }
    }

    private func backendSection(_ routing: DelegationRouting) -> some View {
        Section {
            if let blocked = routing.blockedReason, !blocked.isEmpty {
                Text("现行后端在这台机器上跑不了：\(blocked)子任务会被拒绝，先换一个能用的后端。")
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            ForEach(routing.backends) { backend in
                Button {
                    Task {
                        await store.selectBackend(ops: ops, backend: backend.name)
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(backend.displayLabel)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            if !backend.description.isEmpty {
                                Text(backend.description)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            if !backend.available, !backend.reason.isEmpty {
                                Text(backend.reason)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.danger)
                            }
                        }
                        Spacer()
                        if routing.configured == backend.name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isWriting || !backend.available)
            }
        } header: {
            Text("委派后端")
        } footer: {
            Text("子智能体实际干活的地方。标着跑不了的后端选不了——选了子任务也会被拒绝。")
        }
    }

    private func modelRoutesSection(_ routing: DelegationRouting) -> some View {
        Section {
            if routing.modelRoutes.isEmpty {
                Text("还没有模型路线——所有子任务都走默认模型。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            ForEach(routing.modelRoutes) { route in
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(route.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        if routing.modelRouteDefault == route.name {
                            Text("默认")
                                .font(.caption)
                                .foregroundStyle(Palette.primary)
                        }
                    }
                    if !route.routeDescription.isEmpty {
                        Text(route.routeDescription)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text(route.model.isEmpty ? "未选模型" : route.model)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Button("编辑模型路线") { showModelEditor = true }
                .disabled(store.isWriting)
        } header: {
            Text("模型路线")
        }
    }

    private func profileRoutesSection(_ routing: DelegationRouting) -> some View {
        Section {
            if routing.profileRoutes.isEmpty {
                Text("还没有档案路线——子智能体只以当前档案身份跑。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            ForEach(routing.profileRoutes) { route in
                HStack(spacing: OneDayMetrics.spacingS) {
                    Text(route.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if routing.profileRouteDefault == route.name {
                        Text("默认")
                            .font(.caption)
                            .foregroundStyle(Palette.primary)
                    }
                    Spacer()
                    if !route.routeDescription.isEmpty {
                        Text(route.routeDescription)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Button("编辑档案路线") { showProfileEditor = true }
                .disabled(store.isWriting)
        } header: {
            Text("档案路线")
        }
    }
}

/// 模型路由整块编辑（保存＝整块替换，与服务端写口同义）：
/// 草稿行带稳定 id（改名不丢焦点）；存量路线钉 originalName
/// （改名时服务端靠它把密钥预览对回真钥）；密钥只在新填
/// 时经手，已存的只显脱敏预览、不回显本体
struct DelegationModelRoutesEditor: View {
    private struct Draft: Identifiable {
        let id = UUID()
        var route: DelegationModelRoute
    }

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Draft]
    @State private var defaultRoute: String?
    @State private var problem: String?
    let onSave: ([DelegationModelRoute], String?) async -> Void

    init(
        routes: [DelegationModelRoute], defaultRoute: String?,
        onSave: @escaping ([DelegationModelRoute], String?) async -> Void
    ) {
        _drafts = State(initialValue: routes.map { route in
            var route = route
            if route.originalName == nil { route.originalName = route.name }
            return Draft(route: route)
        })
        _defaultRoute = State(initialValue: defaultRoute)
        self.onSave = onSave
    }

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
                ForEach($drafts) { $draft in
                    Section {
                        TextField("路线名（如 heavy / cheap）", text: $draft.route.name)
                        TextField("说明（智能体靠它选路）", text: $draft.route.routeDescription)
                        TextField("服务商（如 custom 或已配的服务商名）", text: $draft.route.provider)
                        TextField("模型", text: $draft.route.model)
                        TextField("自定义地址（可选）", text: $draft.route.baseURL)
                        SecureField(
                            draft.route.apiKeyPreview.isEmpty
                                ? "密钥（可选）" : "密钥（已存，留空不改）",
                            text: Binding(
                                get: { draft.route.pendingAPIKey ?? "" },
                                set: {
                                    draft.route.pendingAPIKey = $0.isEmpty ? nil : $0
                                }
                            )
                        )
                        Toggle("设为默认路线", isOn: Binding(
                            get: {
                                !draft.route.name.isEmpty
                                    && defaultRoute == draft.route.name
                            },
                            set: { on in
                                defaultRoute = on ? draft.route.name : nil
                            }
                        ))
                        Button("删掉这条路线", role: .destructive) {
                            let removedID = draft.id
                            let removedName = draft.route.name
                            drafts.removeAll { $0.id == removedID }
                            if defaultRoute == removedName { defaultRoute = nil }
                        }
                    }
                }
                Section {
                    Button("加一条路线") {
                        drafts.append(Draft(route: DelegationModelRoute(name: "")))
                    }
                }
            }
            .navigationTitle("模型路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let routes = drafts.map(\.route)
                        let problems = DelegationValidation.modelRouteProblems(
                            routes: routes, defaultRoute: defaultRoute
                        )
                        if let first = problems.first {
                            problem = first
                            return
                        }
                        Task {
                            await onSave(routes, defaultRoute)
                            dismiss()
                        }
                    }
                }
            }
        }
        .fullscreenPopBridge()
    }
}

/// 档案路由整块编辑：只能从已存在档案里选（服务端硬校验）
struct DelegationProfileRoutesEditor: View {
    private struct Draft: Identifiable {
        let id = UUID()
        var route: DelegationProfileRoute
    }

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Draft]
    @State private var defaultRoute: String?
    @State private var problem: String?
    let profiles: [String]
    let onSave: ([DelegationProfileRoute], String?) async -> Void

    init(
        routes: [DelegationProfileRoute], defaultRoute: String?,
        profiles: [String],
        onSave: @escaping ([DelegationProfileRoute], String?) async -> Void
    ) {
        _drafts = State(initialValue: routes.map { Draft(route: $0) })
        _defaultRoute = State(initialValue: defaultRoute)
        self.profiles = profiles
        self.onSave = onSave
    }

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
                ForEach($drafts) { $draft in
                    Section {
                        Picker("档案", selection: $draft.route.name) {
                            Text("请选择").tag("")
                            ForEach(profiles, id: \.self) { profile in
                                Text(profile).tag(profile)
                            }
                        }
                        TextField("说明（可选）", text: $draft.route.routeDescription)
                        Toggle("设为默认档案", isOn: Binding(
                            get: {
                                !draft.route.name.isEmpty
                                    && defaultRoute == draft.route.name
                            },
                            set: { on in
                                defaultRoute = on ? draft.route.name : nil
                            }
                        ))
                        Button("删掉这条", role: .destructive) {
                            let removedID = draft.id
                            let removedName = draft.route.name
                            drafts.removeAll { $0.id == removedID }
                            if defaultRoute == removedName { defaultRoute = nil }
                        }
                    }
                }
                Section {
                    Button("加一条档案路线") {
                        drafts.append(Draft(route: DelegationProfileRoute(name: "")))
                    }
                }
            }
            .navigationTitle("档案路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let routes = drafts.map(\.route)
                        let problems = DelegationValidation.profileRouteProblems(
                            routes: routes, defaultRoute: defaultRoute,
                            knownProfiles: profiles
                        )
                        if let first = problems.first {
                            problem = first
                            return
                        }
                        Task {
                            await onSave(routes, defaultRoute)
                            dismiss()
                        }
                    }
                }
            }
        }
        .fullscreenPopBridge()
    }
}
