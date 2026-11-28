import OneDayCore
import OneDayDesign
import SwiftUI

/// 分身全能编辑表（Hermes v0.23.0 `profiles.py` 全契约闭环）：
/// - 重命名（`PATCH /api/profiles/{name}`，default 档案自动改写显示名）
/// - 职责简介编辑（`PUT /api/profiles/{name}/description`）+ AI 一键自动生成简介（`POST /api/profiles/{name}/describe-auto`）
/// - 分身专属模型绑定（`PUT /api/profiles/{name}/model`，独立于全局主模型）
struct ProfileDetailEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let profile: ProfileItem
    let isActive: Bool
    let existingNames: [String]
    let onSaved: (String) async -> Void

    @State private var editedName: String
    @State private var editedDescription: String
    @State private var editedProvider: String
    @State private var editedModel: String
    @State private var availableModels: [String] = []
    @State private var isAutoDescribing = false
    @State private var isSaving = false
    @State private var inlineError: String?

    init(
        profile: ProfileItem,
        isActive: Bool,
        existingNames: [String],
        onSaved: @escaping (String) async -> Void
    ) {
        self.profile = profile
        self.isActive = isActive
        self.existingNames = existingNames
        self.onSaved = onSaved
        let initialDisplay = (profile.isDefault == true && !(profile.displayName ?? "").isEmpty)
            ? (profile.displayName ?? profile.name)
            : profile.name
        _editedName = State(initialValue: initialDisplay)
        _editedDescription = State(initialValue: profile.description ?? "")
        _editedProvider = State(initialValue: profile.provider ?? "custom")
        _editedModel = State(initialValue: profile.model ?? "")
    }

    private var trimmedName: String {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedProvider: String {
        editedProvider.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedModel: String {
        editedModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameChanged: Bool {
        if profile.isDefault == true {
            let current = (profile.displayName?.isEmpty == false) ? profile.displayName! : profile.name
            return !trimmedName.isEmpty && trimmedName != current
        }
        return !trimmedName.isEmpty && trimmedName != profile.name
    }

    private var nameConflict: Bool {
        guard profile.isDefault != true, nameChanged else { return false }
        return existingNames.contains(trimmedName)
    }

    private var descriptionChanged: Bool {
        trimmedDescription != (profile.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var modelChanged: Bool {
        guard !trimmedProvider.isEmpty, !trimmedModel.isEmpty else { return false }
        return trimmedModel != (profile.model ?? "")
            || trimmedProvider != (profile.provider ?? "")
    }

    private var hasAnyChange: Bool {
        nameChanged || descriptionChanged || modelChanged
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: isActive ? "person.crop.circle.badge.checkmark" : "person.crop.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isActive ? Palette.tintSkyInk : Palette.tintLavenderInk)
                            .frame(width: 36, height: 36)
                            .background(
                                isActive ? Palette.tintSky : Palette.tintLavender,
                                in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Text(isActive ? "当前活跃分身 · 独立记忆与技能隔离" : "独立分身 · 可按任务委派或切换")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section(profile.isDefault == true ? "显示名称" : "分身名称") {
                    TextField("输入名称", text: $editedName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if nameConflict {
                        Text("已有同名分身，请换一个名称。")
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    } else if profile.isDefault == true {
                        Text("默认分身的底层标识保持为 default，修改此处仅更新展示名称。")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                Section {
                    TextEditor(text: $editedDescription)
                        .font(.subheadline)
                        .frame(minHeight: 78)
                    Button {
                        Task { await autoDescribe() }
                    } label: {
                        HStack {
                            Label("AI 根据人设与技能自动生成简介", systemImage: "sparkles")
                            Spacer()
                            if isAutoDescribing {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isAutoDescribing || isSaving)
                } header: {
                    Text("分身职责简介")
                } footer: {
                    Text("职责简介会作为多智能体委派与任务看板的路由信号，帮助主 Agent 决定何时把任务分派给该分身。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }

                Section {
                    TextField("Provider（如 custom / anthropic / openai）", text: $editedProvider)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Model ID（如 claude-sonnet-4-6）", text: $editedModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if !availableModels.isEmpty {
                        Picker("从服务器可用模型快选", selection: $editedModel) {
                            Text("保持当前输入").tag(editedModel)
                            ForEach(availableModels, id: \.self) { modelID in
                                Text(modelID).tag(modelID)
                            }
                        }
                    }
                } header: {
                    Text("分身专属模型")
                } footer: {
                    Text("绑定后该分身将使用独立的主模型配置，不影响全局或其他分身。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }

                if let inlineError {
                    Section {
                        InlineError(inlineError)
                    }
                }
            }
            .navigationTitle("编辑分身")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await saveAll() }
                    }
                    .disabled(!hasAnyChange || nameConflict || isSaving || isAutoDescribing)
                }
            }
            .task {
                if let options = try? await appState.performAdmin({ client, config in
                    try await client.modelOptions(config: config)
                }) {
                    availableModels = Array(options.prefix(40))
                }
            }
        }
        .fullscreenPopBridge()
    }

    private func autoDescribe() async {
        isAutoDescribing = true
        inlineError = nil
        defer { isAutoDescribing = false }
        do {
            let result = try await appState.performAdmin { client, config in
                try await client.autoDescribeProfile(
                    config: config, name: profile.name, overwrite: true
                )
            }
            if result.ok, let desc = result.description, !desc.isEmpty {
                editedDescription = desc
            } else {
                inlineError = result.reason ?? "自动生成简介未返回结果，请稍后重试或手动填写。"
            }
        } catch {
            inlineError = (error as? HermesError)?.userMessage ?? "自动生成简介失败。"
        }
    }

    private func saveAll() async {
        isSaving = true
        inlineError = nil
        defer { isSaving = false }

        var currentTargetName = profile.name
        var savedItems: [String] = []

        do {
            if nameChanged {
                try await appState.performAdmin { client, config in
                    try await client.renameProfile(
                        config: config, name: currentTargetName, newName: trimmedName
                    )
                }
                if profile.isDefault != true {
                    currentTargetName = trimmedName
                }
                savedItems.append("名称")
            }

            if descriptionChanged {
                try await appState.performAdmin { client, config in
                    try await client.updateProfileDescription(
                        config: config, name: currentTargetName, description: trimmedDescription
                    )
                }
                savedItems.append("简介")
            }

            if modelChanged {
                try await appState.performAdmin { client, config in
                    try await client.updateProfileModel(
                        config: config, name: currentTargetName,
                        provider: trimmedProvider, model: trimmedModel
                    )
                }
                savedItems.append("专属模型")
            }

            let summary = savedItems.isEmpty
                ? "分身配置已更新。"
                : "已更新分身「\(currentTargetName)」的\(savedItems.joined(separator: "、"))。"
            await onSaved(summary)
            dismiss()
        } catch {
            inlineError = (error as? HermesError)?.userMessage ?? "保存分身配置失败，请重试。"
        }
    }
}
