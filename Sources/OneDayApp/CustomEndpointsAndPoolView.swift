import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 自定义模型供应商端点与多 Key 凭据池管理（Hermes v0.23.0）：
/// 统一收口 `/api/providers/custom-endpoints*` 与 `/api/credentials/pool*`，
/// 支持 OpenAI 兼容端点的一键连通性探测、设为默认、增删编辑，以及多 Key 轮询池管理。
struct CustomEndpointsAndPoolView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedSegment = 0
    @State private var endpoints: [CustomModelEndpoint] = []
    @State private var currentProvider: String?
    @State private var poolGroups: [CredentialPoolProviderGroup] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showAddEndpointSheet = false
    @State private var showAddPoolKeySheet = false

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "point.3.connected.trianglepath.dotted",
                tint: Palette.tintSkyInk,
                title: "自定义模型端点与凭据池",
                subtitle: "配置 OpenAI 兼容自建端点（vLLM / Ollama / OneAPI / 中转站）与多 Key 轮询凭据池，支持实时连通性校验。",
                statusText: selectedSegment == 0 ? "\(endpoints.count) 个端点" : "\(totalPoolKeys) 把密钥",
                statusTone: .healthy
            )

            Section {
                Picker("管理视图", selection: $selectedSegment) {
                    Text("自定义端点").tag(0)
                    Text("多 Key 凭据池").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Palette.surface)
            }

            if selectedSegment == 0 {
                endpointsContent
            } else {
                credentialPoolContent
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("端点与凭据池")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.selection()
                    if selectedSegment == 0 {
                        showAddEndpointSheet = true
                    } else {
                        showAddPoolKeySheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(selectedSegment == 0 ? "新增自定义端点" : "新增凭据池密钥")
            }
        }
        .refreshable {
            await loadAll()
        }
        .task {
            await loadAll()
        }
        .sheet(isPresented: $showAddEndpointSheet) {
            AddCustomEndpointSheet {
                await loadAll()
            }
        }
        .sheet(isPresented: $showAddPoolKeySheet) {
            AddCredentialPoolKeySheet {
                await loadAll()
            }
        }
    }

    private var totalPoolKeys: Int {
        poolGroups.reduce(0) { $0 + $1.entries.count }
    }

    @ViewBuilder
    private var endpointsContent: some View {
        Section {
            if loading && endpoints.isEmpty {
                HStack {
                    ProgressView()
                    Text("正在加载自定义端点…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if endpoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂未配置自定义模型端点")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text("点击右上角 + 添加 OpenAI 兼容接口地址，并一键测试 /models 连通性。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(endpoints) { endpoint in
                    endpointRow(endpoint)
                }
            }
        } header: {
            SettingsSectionHeader("已配置端点")
        }
        .listRowBackground(Palette.surface)
    }

    private func endpointRow(_ endpoint: CustomModelEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: OneDayMetrics.spacingS) {
                SettingsRowIcon(
                    symbol: endpoint.isCurrent ? "checkmark.seal.fill" : "server.rack",
                    color: endpoint.isCurrent ? Palette.tintGreenInk : Palette.tintSkyInk
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(endpoint.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        if endpoint.isCurrent {
                            SettingsStatusPill(text: "当前默认", tone: .healthy)
                        }
                    }
                    Text(endpoint.baseURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                if !endpoint.model.isEmpty {
                    Label(endpoint.model, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Label(endpoint.hasAPIKey ? "已设密钥" : "无密钥", systemImage: endpoint.hasAPIKey ? "key.fill" : "key")
                    .font(.caption)
                    .foregroundStyle(endpoint.hasAPIKey ? Palette.successText : Palette.inkMuted)
                Spacer()
                if !endpoint.isCurrent {
                    Button("设为默认") {
                        Task { await activate(endpoint) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await deleteEndpoint(endpoint) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var credentialPoolContent: some View {
        if loading && poolGroups.isEmpty {
            Section {
                HStack {
                    ProgressView()
                    Text("正在加载凭据池…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
        } else if poolGroups.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("凭据池为空")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text("为同一模型供应商添加多把 API Key，Hermes 将自动轮询与故障切换，降低限流风险。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Palette.surface)
        } else {
            ForEach(poolGroups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "key.radiowaves.forward.fill", color: Palette.tintLavenderInk)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(entry.label)
                                        .font(.rowTitleL)
                                        .foregroundStyle(Palette.ink)
                                    Text("#\(entry.index)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Text(entry.tokenPreview.isEmpty ? entry.authType : entry.tokenPreview)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.inkSecondary)
                                Text("已调用 \(entry.requestCount) 次 · 来源 \(entry.source)")
                                    .font(.caption2)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                            Spacer()
                            if let status = entry.lastStatus, !status.isEmpty {
                                SettingsStatusPill(
                                    text: status,
                                    tone: status.lowercased().contains("ok") ? .healthy : .warning
                                )
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await deletePoolEntry(provider: group.provider, index: entry.index) }
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader(group.provider.uppercased())
                }
                .listRowBackground(Palette.surface)
            }
        }
    }

    private func loadAll() async {
        loading = true
        errorText = nil
        defer { loading = false }

        do {
            let epResp = try await appState.performAdmin { config in
                try await appState.client.customEndpoints(config: config)
            }
            endpoints = epResp.endpoints
            currentProvider = epResp.currentProvider

            poolGroups = try await appState.performAdmin { config in
                try await appState.client.credentialPool(config: config)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func activate(_ endpoint: CustomModelEndpoint) async {
        do {
            try await appState.performAdmin { config in
                try await appState.client.activateCustomEndpoint(config: config, endpointID: endpoint.id)
            }
            Haptics.success()
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteEndpoint(_ endpoint: CustomModelEndpoint) async {
        do {
            try await appState.performAdmin { config in
                try await appState.client.deleteCustomEndpoint(config: config, endpointID: endpoint.id)
            }
            Haptics.success()
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deletePoolEntry(provider: String, index: Int) async {
        do {
            try await appState.performAdmin { config in
                try await appState.client.deleteCredentialPoolEntry(config: config, provider: provider, index: index)
            }
            Haptics.success()
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct AddCustomEndpointSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var makeDefault = false
    @State private var validating = false
    @State private var saving = false
    @State private var validationResult: CustomEndpointValidationResult?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("端点信息") {
                    TextField("名称（如 My vLLM / OneAPI）", text: $name)
                    TextField("Base URL（如 https://api.example.com/v1）", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API Key（可选）", text: $apiKey)
                    TextField("默认模型 ID（可点下方校验自动拉取）", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("保存后设为全局默认端点", isOn: $makeDefault)
                }

                Section {
                    Button {
                        Task { await validate() }
                    } label: {
                        HStack {
                            if validating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.shield")
                            }
                            Text(validating ? "正在探测 /models…" : "测试连通性并发现模型")
                        }
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validating)

                    if let result = validationResult {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                SettingsStatusPill(
                                    text: result.ok ? "连通正常" : (result.reachable ? "已触达但有告警" : "无法连接"),
                                    tone: result.ok ? .healthy : (result.reachable ? .warning : .error)
                                )
                                if !result.models.isEmpty {
                                    Text("发现 \(result.models.count) 个模型")
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            if !result.message.isEmpty {
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            if !result.models.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(result.models.prefix(8), id: \.self) { candidate in
                                            Button(candidate) {
                                                model = candidate
                                                Haptics.selection()
                                            }
                                            .font(.caption2.monospaced())
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("新增自定义端点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || saving
                    )
                }
            }
        }
    }

    private func validate() async {
        validating = true
        errorText = nil
        defer { validating = false }

        do {
            let result = try await appState.performAdmin { config in
                try await appState.client.validateCustomEndpoint(
                    config: config,
                    baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    model: model.isEmpty ? nil : model
                )
            }
            validationResult = result
            if model.isEmpty, let first = result.models.first {
                model = first
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }

        do {
            try await appState.performAdmin { config in
                try await appState.client.upsertCustomEndpoint(
                    config: config,
                    id: nil,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model.trimmingCharacters(in: .whitespacesAndNewlines),
                    makeDefault: makeDefault
                )
            }
            Haptics.success()
            await onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct AddCredentialPoolKeySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onSaved: () async -> Void

    @State private var provider = "openai"
    @State private var label = ""
    @State private var apiKey = ""
    @State private var saving = false
    @State private var errorText: String?

    private let commonProviders = ["openai", "anthropic", "openrouter", "deepseek", "google", "xai"]

    var body: some View {
        NavigationStack {
            Form {
                Section("供应商") {
                    TextField("供应商标识（如 openai / openrouter）", text: $provider)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(commonProviders, id: \.self) { slug in
                                Button(slug) {
                                    provider = slug
                                    Haptics.selection()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section("密钥详情") {
                    TextField("备注名（如 主账号 Key 2，可选）", text: $label)
                    SecureField("API Key", text: $apiKey)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("添加凭据池密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "添加中…" : "添加") {
                        Task { await save() }
                    }
                    .disabled(
                        provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || saving
                    )
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }

        do {
            try await appState.performAdmin { config in
                try await appState.client.addCredentialPoolEntry(
                    config: config,
                    provider: provider.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            Haptics.success()
            await onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
