import OneDayDesign
import OneDayCore
import SwiftUI

/// 添加提供商（0.37.0 接入层）：表单四件套（名／址／
/// 钥／模型，设计 §6.2）＋连通性检查（§6.4：验证就是
/// 调对方 /models；拉不到列表降级手填）。密钥只在
/// 提交时经服务端通道落 /api/env，本页不留存（保存
/// 后字段随 sheet 关闭销毁，本地零持久化）。
struct ProviderEditorView: View {
    var store: ModelManagementStore
    /// 保存成功回调（父页据此重拉）
    var onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    /// 拉到的模型全集（勾选制）；手填的并入 selected
    @State private var fetchedModels: [String] = []
    @State private var selectedModels: [String] = []
    @State private var manualModel = ""
    @State private var isProbing = false
    @State private var probeMessage: String?
    @State private var isSaving = false
    @State private var formProblem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名字（如：某某直连）", text: $name)
                    TextField("接口地址（以 /v1 结尾）", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("密钥", text: $apiKey)
                } header: {
                    Text("提供商")
                } footer: {
                    Text("密钥只在保存时发给你的服务端保存，App 不留存。")
                }

                Section {
                    Button {
                        Task { await probe() }
                    } label: {
                        HStack {
                            Text("拉取模型列表")
                            Spacer()
                            if isProbing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isProbing || baseURL.isEmpty || apiKey.isEmpty)
                    if let probeMessage {
                        Text(probeMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
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
                } header: {
                    Text("模型")
                } footer: {
                    Text("先填好地址与密钥，再拉取列表勾选；拉不到也可以手动填。")
                }

                if let formProblem {
                    Section {
                        Text(formProblem)
                            .font(.callout)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("添加提供商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
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

    private func probe() async {
        isProbing = true
        defer { isProbing = false }
        do {
            let models = try await store.probeProviderModels(
                baseURL: baseURL, apiKey: apiKey
            )
            fetchedModels = models
            // 拉到的默认全选（用户可逐个取消）
            selectedModels = models
            probeMessage = "连上了，共 \(models.count) 个模型，已全部勾选，不用的可以取消。"
        } catch let error as ProviderProbeClient.ProbeFailure {
            probeMessage = error.message
        } catch {
            probeMessage = "拉取没能完成，可以手动填模型名。"
        }
    }

    private func save() async {
        if let problem = ProviderRegistry.validateDraft(
            name: name, baseURL: baseURL, apiKey: apiKey,
            models: selectedModels,
            existingNames: store.providers.map(\.name),
            existingEnvKeys: store.providers.compactMap(\.keyEnv)
        ) {
            formProblem = problem.message
            return
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
}
