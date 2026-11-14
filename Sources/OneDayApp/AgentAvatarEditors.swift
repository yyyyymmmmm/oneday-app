import OneDayCore
import OneDayDesign
import PhotosUI
import SwiftUI

/// 身份写穿失败的人话出口（§245 编辑器共用）：
/// IdentityBridgeError 的 failed 文案已过 §232 安全
/// 门、原样呈现；无钥/未授权/未知错误落编辑器侧通
/// 用人话，不露任何内部细节
private func identityWriteErrorText(_ error: Error) -> String {
    switch error as? IdentityBridgeError {
    case .noKey:
        return L10n.string("还没连上服务器，先完成连接再试。")
    case .unauthorized:
        return L10n.string("登录已失效，重新登录后再试。")
    case .failed(let message):
        return message
    case nil:
        return L10n.string("保存失败，再试一次。")
    }
}

/// 更换虚拟形象（0.36.22 立、§245 改写穿）：预置目
/// 录（OneDayCore.AgentAvatarPreset）逐款预览选点即
/// 换＋相册选图（PhotosPicker，与聊天附件同一
/// loadTransferable 口径）。§245 起头像是服务端单
/// 真值：选点＝写穿头像仓，成功后缓存以仓指针整份
/// 替换、全端同值；写穿失败留在本页报错、不先斩后
/// 奏地改呈现。页内注明头像存服务器。
struct AgentAvatarEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorText: String?

    private var store: AgentProfileStore { appState.agentProfileStore }

    var body: some View {
        NavigationStack {
            List {
                Section("预置形象") {
                    ForEach(AgentAvatarPreset.all) { preset in
                        Button {
                            selectPreset(preset)
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                presetPreview(preset)
                                    .frame(
                                        width: OneDayMetrics.avatarListRow,
                                        height: OneDayMetrics.avatarListRow
                                    )
                                    .clipShape(Circle())
                                Text(preset.displayName)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if store.currentAvatarSelection
                                    == .preset(id: preset.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                        .disabled(isSaving)
                        // 0.43.0（A11Y-V5）：选中态只有勾
                        // 形——补「已选」播报＋特征（与外
                        // 观页/连接器页房内先例同式）
                        .accessibilityLabel(
                            store.currentAvatarSelection
                                == .preset(id: preset.id)
                                ? preset.displayName + "，"
                                    + L10n.string("已选")
                                : preset.displayName
                        )
                        .accessibilityAddTraits(
                            store.currentAvatarSelection
                                == .preset(id: preset.id)
                                ? [.isSelected] : []
                        )
                    }
                }

                Section {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            if store.currentAvatarSelection == .custom {
                                appState.agentAvatarImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: OneDayMetrics.avatarListRow,
                                        height: OneDayMetrics.avatarListRow
                                    )
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "photo")
                                    .frame(
                                        width: OneDayMetrics.avatarListRow,
                                        height: OneDayMetrics.avatarListRow
                                    )
                            }
                            Text("从相册选择")
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if store.currentAvatarSelection == .custom {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.primary)
                            }
                        }
                    }
                    .disabled(isSaving)
                    // 0.43.0（A11Y-V5）：同预置行——自定
                    // 义头像在用时补「已选」播报＋特征
                    .accessibilityLabel(
                        store.currentAvatarSelection == .custom
                            ? L10n.string("从相册选择") + "，"
                                + L10n.string("已选")
                            : L10n.string("从相册选择")
                    )
                    .accessibilityAddTraits(
                        store.currentAvatarSelection == .custom
                            ? [.isSelected] : []
                    )
                    if isSaving {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            ProgressView()
                            Text("正在保存…")
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                } footer: {
                    Text("头像保存在你的服务器上，改一次，所有地方看到的都是新头像。")
                }
            }
            .navigationTitle("更换虚拟形象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPickedPhoto(item) }
            }
        }
    }

    @ViewBuilder
    private func presetPreview(_ preset: AgentAvatarPreset) -> some View {
        if let assetName = preset.assetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
        } else if let symbolName = preset.symbolName {
            AgentAvatarPresetDisc(
                symbolName: symbolName,
                tint: AgentProfileStore.presetTint(id: preset.id),
                diameter: OneDayMetrics.avatarListRow
            )
        }
    }

    private func selectPreset(_ preset: AgentAvatarPreset) {
        guard store.currentAvatarSelection
                != .preset(id: preset.id) else { return }
        isSaving = true
        errorText = nil
        Task {
            do {
                try await appState.selectAvatarPreset(id: preset.id)
            } catch {
                errorText = identityWriteErrorText(error)
            }
            isSaving = false
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        errorText = nil
        guard let data = try? await item.loadTransferable(
            type: Data.self
        ) else {
            errorText = L10n.string("这张图读不出来，换一张试试。")
            photoItem = nil
            return
        }
        isSaving = true
        do {
            try await appState.setCustomAvatar(imageData: data)
        } catch {
            errorText = identityWriteErrorText(error)
        }
        isSaving = false
        photoItem = nil
    }
}

/// 编辑名称（0.36.22 立、§245 改写穿）：改的就是服
/// 务器上的身份名本身——经桥写口写穿（服务端复校、
/// 带备份与留痕），成功后全 App 以回读刷新。旧「本
/// 机显示名覆盖＋恢复自动」整套退役：名字只有一份、
/// 没有第二层。校验与服务端同口径（Core AgentName-
/// Edit：≤20 字、无句读、非结构词），不合口径不许
/// 保存并明示原因，不静默截断用户输入。
struct AgentNameEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String
    @State private var isSaving = false
    @State private var errorText: String?

    init(initialName: String) {
        _draft = State(initialValue: initialName)
    }

    /// 净化后的可存名（与服务端校验同口径）；nil＝
    /// 不合口径（空/超长/带句读/结构词），不许保存
    private var sanitizedName: String? {
        AgentNameEdit.sanitizedRename(draft)
    }

    /// 与现行名相同：保存即关闭、不发无谓写穿
    private var isUnchanged: Bool {
        sanitizedName != nil
            && sanitizedName == appState.identityName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $draft)
                        .autocorrectionDisabled()
                        .disabled(isSaving)
                } footer: {
                    if sanitizedName == nil {
                        Text("名字不能为空，最多 20 个字，且不能带标点。")
                            .foregroundStyle(Palette.danger)
                    } else {
                        Text("改名会直接改服务器上的身份名，所有地方看到的都会跟着变。")
                    }
                }
                if isSaving {
                    Section {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            ProgressView()
                            Text("正在保存…")
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("编辑名称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(
                            sanitizedName == nil || isSaving
                        )
                }
            }
        }
    }

    private func save() {
        guard let name = sanitizedName else { return }
        if isUnchanged {
            dismiss()
            return
        }
        isSaving = true
        errorText = nil
        Task {
            do {
                try await appState.renameAgent(to: name)
                dismiss()
            } catch {
                errorText = identityWriteErrorText(error)
            }
            isSaving = false
        }
    }
}
