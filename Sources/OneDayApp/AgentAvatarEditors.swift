import OneDayCore
import OneDayDesign
import PhotosUI
import SwiftUI

/// 更换虚拟形象（0.36.22，枢纽头像角标菜单第一项）：
/// 预置目录（OneDayCore.AgentAvatarPreset）逐款预览
/// 选点即换＋相册选图（PhotosPicker，与聊天附件同一
/// loadTransferable 口径）。头像只存本机档案，页内
/// 注明、不上传服务器。
struct AgentAvatarEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var loadFailed = false

    private var store: AgentProfileStore { appState.agentProfileStore }

    var body: some View {
        NavigationStack {
            List {
                Section("预置形象") {
                    ForEach(AgentAvatarPreset.all) { preset in
                        Button {
                            store.selectPreset(id: preset.id)
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                presetPreview(preset)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                Text(preset.displayName)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if store.profile.avatar
                                    == .preset(id: preset.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                }

                Section {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            if store.profile.avatar == .custom {
                                appState.agentAvatarImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "photo")
                                    .frame(width: 44, height: 44)
                            }
                            Text("从相册选择")
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if store.profile.avatar == .custom {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.primary)
                            }
                        }
                    }
                    if loadFailed {
                        Text("这张图读不出来，换一张试试。")
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                } footer: {
                    Text("头像只保存在这台手机上，换头像不会改动服务器上的智能体身份。")
                }
            }
            .navigationTitle("更换虚拟形象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
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
                tint: AgentProfileStore.presetTint(id: preset.id)
            )
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        loadFailed = false
        guard let data = try? await item.loadTransferable(
            type: Data.self
        ), store.setCustomAvatar(data: data) else {
            loadFailed = true
            return
        }
        photoItem = nil
    }
}

/// 编辑名称（0.36.22，枢纽头像角标菜单第二项）：改
/// 的是本地档案显示名覆盖——留空保存＝清覆盖、恢复
/// 跟随服务器身份名；超 20 字（Core 净化口径）不许
/// 保存并明示原因，不静默截断用户输入。
struct AgentNameEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String

    init(initialOverride: String?) {
        _draft = State(initialValue: initialOverride ?? "")
    }

    private var store: AgentProfileStore { appState.agentProfileStore }

    /// 草稿三态：留空（清覆盖）／合法（可存）／超长（拒存）
    private enum DraftState {
        case blank
        case valid
        case overlong
    }

    private var draftState: DraftState {
        let trimmed = draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty { return .blank }
        return AgentDisplayName.sanitizedOverride(draft) == nil
            ? .overlong : .valid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("显示名", text: $draft)
                        .autocorrectionDisabled()
                } footer: {
                    switch draftState {
                    case .blank:
                        Text("留空保存将恢复自动：跟随服务器上的身份名。")
                    case .valid:
                        Text("只改这台手机上的称呼，不改动服务器上的智能体身份。")
                    case .overlong:
                        Text("名字最多 20 个字。")
                            .foregroundStyle(Palette.danger)
                    }
                }
                if store.profile.displayNameOverride != nil {
                    Section {
                        Button("恢复自动（跟随服务器身份名）", role: .destructive) {
                            store.setDisplayNameOverride(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("编辑名称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        switch draftState {
                        case .blank:
                            store.setDisplayNameOverride(nil)
                        case .valid:
                            store.setDisplayNameOverride(draft)
                        case .overlong:
                            break
                        }
                        dismiss()
                    }
                    .disabled(draftState == .overlong)
                }
            }
        }
    }
}
