import OneDayDesign
import OneDayCore
import SwiftUI

/// 连接详情（设置·服务器）：地址、面板账号、API 密钥
/// （本机 Keychain 里的值，点按才显示）、重测连接（三步探活）、
/// 切换服务器预留位（多服务器二期，IA §5.3 明记）。
struct ServerDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var showAPIKey = false
    @State private var isRetesting = false
    @State private var retestResult: String?
    @State private var retestFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("连接详情")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    infoRow("服务器地址", appState.config?.baseString ?? "—", mono: true)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("面板账号", appState.username ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    apiKeyRow
                }
                .odGroup()

                SectionLabel("连接测试")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    Button {
                        Task { await retest() }
                    } label: {
                        HStack {
                            Text("重新测试连接")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if isRetesting {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetesting)
                    if let retestResult {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                        Group {
                            if retestFailed {
                                InlineError(retestResult)
                            } else {
                                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Palette.success)
                                        .accessibilityHidden(true)
                                    Text(retestResult)
                                        .font(TypeScale.subhead)
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .odGroup()

                Text("多服务器切换为二期预留：当前版本只保存一台服务器，换服务器请断开后重新连接。")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, OneDayMetrics.spacingM)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("当前服务器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var apiKeyRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text("API 密钥")
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            if showAPIKey, let key = appState.apiKey {
                Text(key)
                    .font(TypeScale.monoCaption)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            } else {
                Text("••••••••••")
                    .font(TypeScale.monoCallout)
                    .foregroundStyle(Palette.inkMuted)
            }
            Button(showAPIKey ? "隐藏" : "显示") {
                showAPIKey.toggle()
            }
            .font(TypeScale.callout)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func retest() async {
        isRetesting = true
        retestResult = nil
        defer { isRetesting = false }
        do {
            try await appState.retestConnection()
            retestFailed = false
            retestResult = "连接正常：健康检查、登录、API 密钥三步全过。"
        } catch {
            retestFailed = true
            retestResult = (error as? HermesError)?.userMessage ?? "连接失败。"
        }
    }
}

/// 档案页（设置·服务器）：档案列表＋切换。
/// 切换走 POST /api/profiles/active {name}，切换后新对话
/// 使用该档案的模型/技能/记忆（已有数据不迁移）。
struct ProfilesView: View {
    @Environment(AppState.self) private var appState

    @State private var profiles: [ProfileItem] = []
    @State private var activeName: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var pendingSwitch: ProfileItem?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !profiles.isEmpty {
                    SectionLabel("全部档案")
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 {
                                GroupDivider(inset: OneDayMetrics.spacingM)
                            }
                            profileRow(profile)
                        }
                    }
                    .odGroup()
                    Text("档案是服务端的一套独立配置（模型、技能、记忆各一份）。切换后新的对话使用新档案。")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, OneDayMetrics.spacingM)
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取档案…")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice {
                    Text(notice)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("档案 Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "切换档案？",
            isPresented: Binding(
                get: { pendingSwitch != nil },
                set: { if !$0 { pendingSwitch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换到 \(pendingSwitch?.name ?? "")") {
                if let profile = pendingSwitch {
                    Task { await switchTo(profile) }
                }
                pendingSwitch = nil
            }
            Button("取消", role: .cancel) { pendingSwitch = nil }
        } message: {
            Text("切换后新的对话将使用该档案的模型、技能与记忆；当前对话不受影响。")
        }
    }

    private func profileRow(_ profile: ProfileItem) -> some View {
        let isActive = profile.name == activeName
        return Button {
            if !isActive {
                pendingSwitch = profile
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(profile.name)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.ink)
                        if profile.isDefault == true {
                            Text("默认")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    Text(subtitle(profile))
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if isActive {
                    Text("使用中")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.success)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ profile: ProfileItem) -> String {
        var parts: [String] = []
        if let model = profile.model, !model.isEmpty {
            parts.append(model)
        }
        if let count = profile.skillCount {
            parts.append("技能 \(count)")
        }
        if profile.gatewayRunning == true {
            parts.append("网关运行中")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let list = appState.performAdmin { client, config in
                try await client.profiles(config: config)
            }
            async let active = appState.performAdmin { client, config in
                try await client.activeProfileName(config: config)
            }
            profiles = try await list
            activeName = try await active
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "档案读取失败。"
        }
    }

    private func switchTo(_ profile: ProfileItem) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.setActiveProfile(config: config, name: profile.name)
            }
            activeName = profile.name
            notice = "已切换到档案 \(profile.name)。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }
}

/// 模型管理（设置·模型与密钥）：服务端默认模型切换＋
/// 提供商清单。读写走 /api/config 全量：先读全量 JSON、
/// 只改 model/providers 键、整包写回，未知字段原样保留
/// （JSONValue 载体保证不丢字段）。候选与聊天页选择器
/// 同源（0.2.4）：AppState 的上游管线——/api/model/options
/// 优先、用量回落、网关别名硬排除；写回前有候选集校验，
/// 非法值（网关别名等）拦截不写。对话调用网关时填的别名
/// （AppState.modelID）不在此改。
struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var rawConfig: [String: JSONValue] = [:]
    @State private var candidates: [String] = []
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var isLoading = false
    @State private var pendingModel: String?
    @State private var pendingDeleteProvider: String?

    private var currentModel: String? {
        rawConfig["model"]?.stringValue
    }

    /// 候选＝拉取并集去掉当前值（当前值在上方单独成组展示）
    private var switchableModels: [String] {
        candidates.filter { $0 != currentModel }
    }

    private var providers: [(name: String, baseURL: String?)] {
        guard case .object(let dict) = rawConfig["providers"] ?? .null else {
            return []
        }
        return dict.keys.sorted().map { name in
            var baseURL: String?
            if case .object(let fields) = dict[name] ?? .null {
                baseURL = fields["base_url"]?.stringValue
            }
            return (name, baseURL)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                currentGroup
                candidatesGroup
                providersGroup
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice {
                    Text(notice)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                Text("这里改的是服务端默认模型（新会话的起点）；正在进行的对话不切换。提供商的密钥在「密钥」页以环境变量形式管理。")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, OneDayMetrics.spacingM)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("对话模型")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "切换默认模型？",
            isPresented: Binding(
                get: { pendingModel != nil },
                set: { if !$0 { pendingModel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换到 \(pendingModel ?? "")") {
                if let model = pendingModel {
                    Task { await setModel(model) }
                }
                pendingModel = nil
            }
            Button("取消", role: .cancel) { pendingModel = nil }
        } message: {
            Text("新的会话将默认使用该模型；已有会话不受影响。")
        }
        .confirmationDialog(
            "删除提供商？",
            isPresented: Binding(
                get: { pendingDeleteProvider != nil },
                set: { if !$0 { pendingDeleteProvider = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let name = pendingDeleteProvider {
                    Task { await deleteProvider(name) }
                }
                pendingDeleteProvider = nil
            }
            Button("取消", role: .cancel) { pendingDeleteProvider = nil }
        } message: {
            Text("将从服务端配置里移除该提供商；使用它的会话可能受影响。")
        }
    }

    private var currentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("当前默认模型")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text(currentModel ?? "未配置")
                        .font(TypeScale.monoBody)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
            }
            .odGroup()
        }
    }

    private var candidatesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("可切换的模型（服务端拉取）")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if switchableModels.isEmpty {
                    Text("服务端没有返回上游模型列表（/api/model/options 与用量记录均为空）。")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(switchableModels.enumerated()), id: \.element) { index, model in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    Button {
                        if model != currentModel {
                            pendingModel = model
                        }
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model)
                                    .font(TypeScale.monoCallout)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if let runtime = ModelCatalog.aliasRuntime[model] {
                                    Text("别名 · 将按 \(runtime) 运行")
                                        .font(TypeScale.footnote)
                                        .foregroundStyle(Palette.inkMuted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            if model == currentModel {
                                Text("当前")
                                    .font(TypeScale.footnote)
                                    .foregroundStyle(Palette.success)
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .odGroup()
            if !appState.gatewayAliases.isEmpty {
                Text("网关模型名 \(appState.gatewayAliases.sorted().joined(separator: "、")) 是客户端调用别名，不是上游模型，不可设为默认。")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, OneDayMetrics.spacingS)
            }
        }
    }

    private var providersGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("提供商（服务端配置拉取）")
                .padding(.top, 28)
            .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if providers.isEmpty {
                    Text("服务端配置里暂无提供商条目（模型可能走环境变量直连）。新增提供商请在服务端配置里维护，此页只做拉取展示与删除。")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(providers.enumerated()), id: \.element.name) { index, provider in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.ink)
                            if let baseURL = provider.baseURL, !baseURL.isEmpty {
                                Text(baseURL)
                                    .font(TypeScale.monoCaption)
                                    .foregroundStyle(Palette.inkMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Button("删除", role: .destructive) {
                            pendingDeleteProvider = provider.name
                        }
                        .font(TypeScale.callout)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }

    // MARK: - 数据与写入（先读全量、只改目标键、整包写回）

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            rawConfig = try await appState.performAdmin { client, config in
                try await client.rawConfig(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "配置读取失败。"
        }
        // 0.2.4：候选与聊天页选择器共用 AppState 管线
        // （上游 options 优先、用量回落、网关别名硬排除），
        // 本页不再自拼并集——0.2.2 在这里拼的那份正是把
        // hermes-agent 送进候选的 bug 路径之一
        await appState.refreshModelCatalog()
        candidates = appState.availableModels
    }

    private func writeBack(_ mutate: (inout [String: JSONValue]) -> Void) async throws {
        var updated = rawConfig
        mutate(&updated)
        try await appState.performAdmin { client, config in
            try await client.updateConfig(config: config, newConfig: updated)
        }
        rawConfig = updated
    }

    private func setModel(_ model: String) async {
        // 写入校验（0.2.4）：与选择器同一道闸——不在候选
        // 集内（含网关别名）直接拦截，不发写请求
        guard ModelCatalog.isWritable(model, candidates: candidates) else {
            notice = HermesError.modelNotUpstream(model).userMessage
            return
        }
        do {
            try await writeBack { $0["model"] = .string(model) }
            appState.noteDefaultModel(model)
            notice = "默认模型已切换为 \(model)。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }

    private func deleteProvider(_ name: String) async {
        do {
            try await writeBack { config in
                if case .object(var providers) = config["providers"] ?? .null {
                    providers[name] = nil
                    config["providers"] = .object(providers)
                }
            }
            notice = "提供商 \(name) 已删除。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }
}

struct EnvVarsView: View {
    @Environment(AppState.self) private var appState

    @State private var entries: [EnvVarEntry] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !entries.isEmpty {
                    SectionLabel("环境变量（已设定在前）")
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                GroupDivider(inset: OneDayMetrics.spacingM)
                            }
                            NavigationLink {
                                EnvVarDetailView(entry: entry) {
                                    Task { await load() }
                                }
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .odGroup()
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取密钥…")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("密钥")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增环境变量")
            }
        }
        .sheet(isPresented: $showAdd) {
            EnvVarEditorView(existingKey: nil) {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func entryRow(_ entry: EnvVarEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.key)
                    .font(TypeScale.monoCallout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let description = entry.description, !description.isEmpty {
                    Text(description)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(entry.isSet ? (entry.redactedValue ?? "已设置") : "未设置")
                .font(TypeScale.monoCaption)
                .foregroundStyle(entry.isSet ? Palette.inkSecondary : Palette.inkMuted)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await appState.performAdmin { client, config in
                try await client.envVars(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "密钥读取失败。"
        }
    }
}

/// 密钥详情：说明、当前值（脱敏）、查看明文、改值、删除。
struct EnvVarDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entry: EnvVarEntry
    var onChange: () -> Void = {}

    @State private var revealed: String?
    @State private var isRevealing = false
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("变量")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    infoRow("键", entry.key, mono: true)
                    if let description = entry.description, !description.isEmpty {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                        Text(description)
                            .font(TypeScale.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .padding(.vertical, OneDayMetrics.spacingSM)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let category = entry.category, !category.isEmpty {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                        infoRow("类别", category)
                    }
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    valueRow
                }
                .odGroup()

                SectionLabel("操作")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    actionRow(title: entry.isSet ? "修改值" : "设置值", icon: "pencil.circle") {
                        showEditor = true
                    }
                    if entry.isSet {
                        GroupDivider(inset: 56)
                        actionRow(
                            title: isRevealing ? "拉取中…" : "查看明文",
                            icon: "eye.circle"
                        ) {
                            Task { await reveal() }
                        }
                        GroupDivider(inset: 56)
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                Image(systemName: "trash.circle")
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.danger)
                                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                                    .accessibilityHidden(true)
                                Text("删除")
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.danger)
                                Spacer()
                            }
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .frame(minHeight: OneDayMetrics.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .odGroup()
                if let notice {
                    Text(notice)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle(entry.key)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            EnvVarEditorView(existingKey: entry.key) {
                onChange()
                dismiss()
            }
        }
        .confirmationDialog(
            "删除这个环境变量？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await deleteVar() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("依赖它的功能会立即失效；变量目录条目仍在，可随时重新设置。")
        }
    }

    private var valueRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text("当前值")
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            if let revealed {
                Text(revealed)
                    .font(TypeScale.monoCaption)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else {
                Text(entry.isSet ? (entry.redactedValue ?? "已设置") : "未设置")
                    .font(TypeScale.monoCaption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func actionRow(
        title: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reveal() async {
        isRevealing = true
        defer { isRevealing = false }
        do {
            revealed = try await appState.performAdmin { client, config in
                try await client.revealEnvVar(config: config, key: entry.key)
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "明文拉取失败。"
        }
    }

    private func deleteVar() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteEnvVar(config: config, key: entry.key)
            }
            onChange()
            dismiss()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }
}

/// 环境变量编辑表单：新增（键＋值）与改值（键锁定）共用。
/// 值默认按密钥处理走 SecureField 不回显。
struct EnvVarEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingKey: String?
    var onSaved: () -> Void = {}

    @State private var key: String
    @State private var value: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(existingKey: String?, onSaved: @escaping () -> Void = {}) {
        self.existingKey = existingKey
        self.onSaved = onSaved
        _key = State(initialValue: existingKey ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        FieldRow(label: "键") {
                            TextField("如 DEEPSEEK_API_KEY", text: $key)
                                .font(TypeScale.monoBody)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .disabled(existingKey != nil)
                        }
                        GroupDivider(inset: OneDayMetrics.spacingM)
                        FieldRow(label: "值") {
                            SecureField("输入新值", text: $value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .odGroup()
                    if let errorMessage {
                        InlineError(errorMessage)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
            }
            .background(Palette.pageBG)
            .navigationTitle(existingKey == nil ? "新增环境变量" : "修改值")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(
                        key.trimmingCharacters(in: .whitespaces).isEmpty
                            || value.isEmpty || isSaving
                    )
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.setEnvVar(
                    config: config,
                    key: key.trimmingCharacters(in: .whitespaces),
                    value: value
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }
}

/// 用量详情（设置·模型与密钥，IA §5.3）：从总览降下来的
/// 趋势与分布住这里——近 7/30 天 Token 趋势（按日条）＋
/// 按模型分布＋周期汇总。数据 /api/analytics/usage 与
/// /api/analytics/models。
struct UsageDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var days: Int = 7
    @State private var usage: UsageAnalytics?
    @State private var models: ModelAnalytics?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("周期", selection: $days) {
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { _, _ in
                    Task { await load() }
                }
                if let usage {
                    totalsGroup(usage)
                    trendGroup(usage)
                }
                if let models, !models.models.isEmpty {
                    modelsGroup(models)
                }
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if usage == nil && errorMessage == nil {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取用量…")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("用量")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func totalsGroup(_ usage: UsageAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("周期汇总")
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                infoRow("Token（入＋出）", AdminFormat.count(usage.totals.tokens), mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow("请求数", AdminFormat.count(usage.totals.totalAPICalls ?? 0), mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow("会话数", AdminFormat.count(usage.totals.totalSessions ?? 0), mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow(
                    "估算费用",
                    AdminFormat.cost(usage.totals.totalEstimatedCost ?? 0),
                    mono: true
                )
            }
            .odGroup()
        }
    }

    private func trendGroup(_ usage: UsageAnalytics) -> some View {
        let maxTokens = max(usage.daily.map(\.tokens).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("按日趋势")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(usage.daily.enumerated()), id: \.element.id) { index, day in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text(AdminFormat.usageDay(day.day))
                            .font(TypeScale.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.primaryTint)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(index == usage.daily.count - 1
                                          ? Palette.primary : Palette.inkSecondary)
                                    .frame(
                                        width: max(
                                            geo.size.width * CGFloat(day.tokens / maxTokens),
                                            day.tokens > 0 ? 6 : 0
                                        ),
                                        height: 6
                                    )
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 20)
                        Text(AdminFormat.count(day.tokens))
                            .font(TypeScale.monoFootnote)
                            .foregroundStyle(Palette.ink)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }

    private func modelsGroup(_ models: ModelAnalytics) -> some View {
        let total = max(models.models.map(\.tokens).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("按模型分布")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(models.models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.model)
                                .font(TypeScale.monoCallout)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if let provider = model.provider, !provider.isEmpty {
                                Text(provider)
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(AdminFormat.count(model.tokens))
                                .font(TypeScale.monoCallout)
                                .foregroundStyle(Palette.ink)
                            Text(String(format: "%.0f%%", model.tokens / total * 100))
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            usage = try await appState.performAdmin { client, config in
                try await client.usageAnalytics(config: config, days: days)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "用量读取失败。"
        }
        models = try? await appState.performAdmin { client, config in
            try await client.modelAnalytics(config: config, days: days)
        }
    }
}

/// 网关页（设置·网关）：状态详情（/api/status 全字段呈现）＋
/// 启停控制。重启入口在设置首页与总览快捷动作也有，动作口径
/// 一致：二次确认后 POST，状态靠回读确认不靠回执猜。
struct GatewayView: View {
    @Environment(AppState.self) private var appState

    @State private var status: ServerStatus?
    @State private var errorMessage: String?
    @State private var pendingAction: String?
    @State private var notice: String?
    @State private var isActing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let status {
                    statusGroup(status)
                    platformsGroup(status)
                    actionsGroup(status)
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取网关状态…")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice {
                    Text(notice)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("网关")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(dialogButton, role: pendingAction == "stop" ? .destructive : nil) {
                // 0.3.2：确认点不再挂触觉，结果点在 perform()
                if let action = pendingAction {
                    Task { await perform(action) }
                }
                pendingAction = nil
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(dialogMessage)
        }
    }

    private var dialogTitle: String {
        switch pendingAction {
        case "restart": return "重启网关？"
        case "stop": return "停止网关？"
        default: return "启动网关？"
        }
    }

    private var dialogButton: String {
        switch pendingAction {
        case "restart": return "重启"
        case "stop": return "停止"
        default: return "启动"
        }
    }

    private var dialogMessage: String {
        switch pendingAction {
        case "stop":
            return "停止后 Agent 将无法收发消息，直到重新启动。"
        case "restart":
            return "重启期间对话会短暂中断，进行中的任务会被打断。"
        default:
            return "启动后 Agent 恢复收发消息。"
        }
    }

    private func statusGroup(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("状态")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    StatusDot(color: Palette.stateColor(status.gatewayState))
                    Text(stateWord(status))
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow("服务端版本", status.version.map { "v\($0)" } ?? "—", mono: true)
                if let date = status.releaseDate {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("发布日期", date, mono: true)
                }
                if let version = status.configVersion {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("配置版本", "\(version)", mono: true)
                }
            }
            .odGroup()
        }
    }

    private func platformsGroup(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("平台连接")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if status.platforms.isEmpty {
                    Text("暂无平台状态")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                }
                ForEach(
                    Array(status.platforms.keys.sorted().enumerated()),
                    id: \.element
                ) { index, name in
                    if index > 0 {
                        GroupDivider(inset: 36)
                    }
                    if let platform = status.platforms[name] {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            StatusDot(color: Palette.stateColor(platform.state))
                            Text(name)
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(platform.state ?? "未知")
                                .font(TypeScale.footnote)
                                .foregroundStyle(Palette.stateColor(platform.state))
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                    }
                }
            }
            .odGroup()
        }
    }

    private func actionsGroup(_ status: ServerStatus) -> some View {
        let running = status.gatewayRunning == true
            || status.gatewayState?.lowercased() == "running"
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("控制")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                actionRow(title: "重启网关", danger: false) {
                    pendingAction = "restart"
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                if running {
                    actionRow(title: "停止网关", danger: true) {
                        pendingAction = "stop"
                    }
                } else {
                    actionRow(title: "启动网关", danger: false) {
                        pendingAction = "start"
                    }
                }
            }
            .odGroup()
        }
    }

    private func actionRow(
        title: String, danger: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(danger ? Palette.danger : Palette.ink)
                Spacer()
                if isActing {
                    ProgressView()
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isActing)
    }

    private func stateWord(_ status: ServerStatus) -> String {
        switch status.gatewayState?.lowercased() {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "error", "failed": return "异常"
        default: return status.gatewayRunning == true ? "运行中" : "未运行"
        }
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func load() async {
        guard let config = appState.config else { return }
        do {
            status = try await appState.client.status(config: config)
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "网关状态读取失败。"
        }
    }

    private func perform(_ action: String) async {
        isActing = true
        defer { isActing = false }
        do {
            switch action {
            case "restart":
                try await appState.performAdmin { client, config in
                    try await client.gatewayRestart(config: config)
                }
                notice = "重启指令已发送。"
            case "stop":
                try await appState.performAdmin { client, config in
                    try await client.gatewayStop(config: config)
                }
                notice = "停止指令已发送。"
            default:
                try await appState.performAdmin { client, config in
                    try await client.gatewayStart(config: config)
                }
                notice = "启动指令已发送。"
            }
            // 结果触感（0.3.2 纪律）：指令发送成功 .success
            Haptics.success()
            // 给服务端几秒落地再回读，状态以回读为准
            try? await Task.sleep(for: .seconds(3))
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "操作失败，请稍后再试。"
            Haptics.warning()
        }
    }
}

/// 日志页（设置·网关）：/api/logs 只读查看，级别与关键词
/// 筛选都走服务端参数；行按最新在前呈现（文件本身正序）。
struct LogsView: View {
    @Environment(AppState.self) private var appState

    @State private var lines: [String] = []
    @State private var fileName: String?
    @State private var level: String = ""
    @State private var search: String = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let levels: [(value: String, label: String)] = [
        ("", "全部"), ("error", "错误"), ("warning", "警告"),
        ("info", "信息"), ("debug", "调试"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("级别", selection: $level) {
                    ForEach(levels, id: \.value) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: level) { _, _ in
                    Task { await load() }
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                    TextField("搜索日志", text: $search)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.ink)
                        .onSubmit { Task { await load() } }
                    if !search.isEmpty {
                        Button {
                            search = ""
                            Task { await load() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.inkMuted)
                        }
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .background(
                    Palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.fieldCorner)
                )
                .padding(.top, OneDayMetrics.spacingM)

                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                } else if lines.isEmpty && !isLoading {
                    Text("没有匹配的日志行。")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingL)
                } else {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(TypeScale.monoCaption)
                                .foregroundStyle(
                                    line.contains("ERROR")
                                        ? Palette.danger : Palette.inkSecondary
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
                if let fileName {
                    Text("文件 \(fileName) · 共 \(lines.count) 行（最新在前）")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await appState.performAdmin { client, config in
                try await client.logs(
                    config: config,
                    level: level.isEmpty ? nil : level,
                    search: search.isEmpty ? nil : search,
                    lines: 200
                )
            }
            lines = Array(response.lines.reversed())
            fileName = response.file
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "日志读取失败。"
        }
    }
}
