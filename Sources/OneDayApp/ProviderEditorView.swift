import OneDayDesign
import OneDayCore
import SwiftUI

/// 服务商编辑（0.37.0 添加形态；§119 扩编辑既有）：
/// 表单四件套（名／址／钥／模型）＋测连接三态（连通
/// 报发现数／通但无目录教手填／失败给「仍然保存」出
/// 路）。编辑态名字锁定（名字是条目键）、密钥留空＝
/// 不改。密钥只在提交时经服务端通道保存，App 不留
/// 存（保存后字段随 sheet 关闭销毁，本地零持久化）。
struct ProviderEditorView: View {
    var store: ModelManagementStore
    /// 非 nil＝编辑这家既有服务商；nil＝添加新服务商
    var editing: ProviderRegistry.Entry?
    /// 保存成功回调（父页据此重拉）
    var onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey = ""
    /// 拉到的模型全集（勾选制）；手填的并入 selected
    @State private var fetchedModels: [String]
    @State private var selectedModels: [String]
    @State private var manualModel = ""
    @State private var isProbing = false
    @State private var probeOutcome: ProviderConnectionOutcome?
    @State private var isSaving = false
    @State private var formProblem: String?

    init(
        store: ModelManagementStore,
        editing: ProviderRegistry.Entry? = nil,
        onDone: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.editing = editing
        self.onDone = onDone
        _name = State(initialValue: editing?.name ?? "")
        _baseURL = State(initialValue: editing?.baseURL ?? "")
        _fetchedModels = State(initialValue: editing?.models ?? [])
        _selectedModels = State(initialValue: editing?.models ?? [])
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名字（如：某某直连）", text: $name)
                        .disabled(isEditing)
                    TextField("接口地址（以 /v1 结尾）", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField(
                        isEditing ? "新密钥（留空表示不改）" : "密钥",
                        text: $apiKey
                    )
                } header: {
                    Text("服务商")
                } footer: {
                    Text(isEditing
                        ? "名字是这家服务商的标识，不能改名；要换名字请删掉重新添加。密钥只在保存时发给你的服务端保存，App 不留存。"
                        : "密钥只在保存时发给你的服务端保存，App 不留存。")
                }

                Section {
                    Button {
                        Task { await probe() }
                    } label: {
                        HStack {
                            Text("测连接并拉取模型列表")
                            Spacer()
                            if isProbing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isProbing || baseURL.isEmpty
                        || (!isEditing && apiKey.isEmpty))
                    if let probeOutcome {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(probeOutcome.headline())
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                            if let advice = probeOutcome.advice() {
                                Text(advice)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                    ForEach(fetchedModels, id: \.self) { model in
                        Button {
                            toggle(model)
                        } label: {
                            HStack {
                                Text(model)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if selectedModels.contains(model) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                    HStack {
                        TextField("手动填模型名", text: $manualModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("添加") { addManual() }
                            .disabled(manualModel.trimmingCharacters(
                                in: .whitespaces).isEmpty)
                    }
                    if !selectedModels.isEmpty {
                        Text("已选 \(selectedModels.count) 个：\(selectedModels.joined(separator: "、"))")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if probeOutcome?.canSaveAnyway == true {
                        Button("仍然保存") {
                            Task { await save(anyway: true) }
                        }
                        .disabled(isSaving)
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text("先填好地址与密钥，再测连接拉列表勾选；拉不到也可以手动填。")
                }

                if let formProblem {
                    Section {
                        Text(formProblem)
                            .font(.callout)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑服务商" : "添加服务商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save(anyway: false) }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func toggle(_ model: String) {
        if let index = selectedModels.firstIndex(of: model) {
            selectedModels.remove(at: index)
        } else {
            selectedModels.append(model)
        }
    }

    private func addManual() {
        let model = manualModel.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { return }
        if !selectedModels.contains(model) {
            selectedModels.append(model)
        }
        manualModel = ""
    }

    /// 测连接：填了新密钥就用新密钥直连；编辑态没填
    /// 新密钥则用服务端已存的那把（经 reveal 只过手）
    private func probe() async {
        isProbing = true
        defer { isProbing = false }
        if isEditing, apiKey.isEmpty, let editing {
            let result = await store.fetchRefreshedModels(
                entry: editing, appState: appState
            )
            probeOutcome = result.outcome
            if let models = result.models {
                fetchedModels = models
                selectedModels = models
            }
            return
        }
        do {
            let models = try await store.probeProviderModels(
                baseURL: baseURL, apiKey: apiKey
            )
            fetchedModels = models
            // 拉到的默认全选（用户可逐个取消）
            selectedModels = models
            probeOutcome = .connected(modelCount: models.count)
        } catch let error as ProviderProbeClient.ProbeFailure {
            probeOutcome = error.connectionOutcome
        } catch HermesError.demoLimitReached {
            probeOutcome = .failed(message: HermesError.demoLimitReached.userMessage)
        } catch {
            probeOutcome = .failed(message: L10n.string("拉取没能完成，可以手动填模型名。"))
        }
    }

    private func save(anyway: Bool) async {
        if isEditing {
            await saveEdit(anyway: anyway)
            return
        }
        if let problem = ProviderRegistry.validateDraft(
            name: name, baseURL: baseURL, apiKey: apiKey,
            models: selectedModels,
            existingNames: store.providers.map(\.name),
            existingEnvKeys: store.providers.compactMap(\.keyEnv)
        ) {
            // 「仍然保存」只绕过模型为空一闸，其余照拦
            guard anyway, problem == .noModels,
                  probeOutcome?.canSaveAnyway == true
            else {
                formProblem = problem.message
                return
            }
        }
        formProblem = nil
        isSaving = true
        defer { isSaving = false }
        let ok = await store.addProvider(
            name: name.trimmingCharacters(in: .whitespaces),
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            apiKey: apiKey,
            models: selectedModels,
            appState: appState
        )
        if ok {
            onDone(true)
            dismiss()
        } else {
            formProblem = store.notice ?? "保存没完成，请稍后再试。"
        }
    }

    private func saveEdit(anyway: Bool) async {
        guard let editing else { return }
        let allowNoModels = anyway
            && probeOutcome?.canSaveAnyway == true
        if let problem = ProviderRegistry.validateEditDraft(
            baseURL: baseURL, apiKey: apiKey,
            models: selectedModels,
            allowNoModels: allowNoModels
        ) {
            formProblem = problem.message
            return
        }
        formProblem = nil
        isSaving = true
        defer { isSaving = false }
        let ok = await store.updateProvider(
            entry: editing,
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            newKey: apiKey,
            models: selectedModels,
            appState: appState
        )
        if ok {
            onDone(true)
            dismiss()
        } else {
            formProblem = store.notice ?? "保存没完成，请稍后再试。"
        }
    }
}
