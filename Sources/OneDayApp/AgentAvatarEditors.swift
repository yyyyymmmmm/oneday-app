import OneDayCore
import OneDayDesign
import PhotosUI
import SwiftUI

/// 身份写穿失败的人话出口（§253 编辑器共用）：
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

/// 更换虚拟形象（参考 OpenBot AgentAppearancePicker）：
/// 顶部 132pt 大预览 + 环境光晕 + 弹簧动效；
/// 下方「灵动形象」4 列网格（支持随机换一个）+「经典图标」+「从相册选择」。
/// 选点即写穿头像仓，全端同值。
struct AgentAvatarEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorText: String?

    private var store: AgentProfileStore { appState.agentProfileStore }

    private var characterPresets: [AgentAvatarPreset] {
        AgentAvatarPreset.all.filter(\.isCharacter)
    }

    private var classicPresets: [AgentAvatarPreset] {
        AgentAvatarPreset.all.filter { !$0.isCharacter }
    }

    private var currentGlowColor: Color {
        if case .preset(let id) = store.currentAvatarSelection,
           AgentAvatarPreset.resolve(id: id).isCharacter {
            return BotCharacterSpec.resolve(id).glowColor
        }
        return Palette.primary
    }

    private var currentPresetTitle: String {
        switch store.currentAvatarSelection {
        case .preset(let id):
            return AgentAvatarPreset.resolve(id: id).displayName
        case .custom:
            return L10n.string("自定义照片")
        case nil:
            return AgentAvatarPreset.resolve(id: AgentAvatarPreset.defaultID).displayName
        }
    }

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: OneDayMetrics.spacingSM),
        count: 4
    )

    var body: some View {
        NavigationStack {
            List {
                previewSection
                characterGridSection
                classicGridSection
                photoPickerSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle("更换形象")
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
        .fullscreenPopBridge()
    }

    // MARK: - 顶部大预览（OpenBot 风格：120pt 头像 + 柔和环境光晕）

    private var previewSection: some View {
        Section {
            VStack(spacing: OneDayMetrics.spacingSM) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [currentGlowColor.opacity(0.28), .clear],
                                center: .center,
                                startRadius: 12,
                                endRadius: 88
                            )
                        )
                        .frame(width: 168, height: 168)

                    appState.agentAvatarImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.4), lineWidth: 1.5)
                        }
                        .shadow(color: currentGlowColor.opacity(0.25), radius: 16, y: 6)
                        .animation(
                            .spring(response: 0.36, dampingFraction: 0.66),
                            value: store.revision
                        )
                }

                VStack(spacing: 3) {
                    Text(currentPresetTitle)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(appState.agentDisplayName)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OneDayMetrics.spacingS)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 灵动形象网格（OpenBot 同构：4 列网格 + 随机切换）

    private var characterGridSection: some View {
        Section {
            LazyVGrid(columns: gridColumns, spacing: OneDayMetrics.spacingM) {
                ForEach(characterPresets) { preset in
                    presetGridCell(preset)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingXS)
        } header: {
            HStack {
                SettingsSectionHeader("灵动形象")
                Spacer()
                Button {
                    shuffleCharacter()
                } label: {
                    Label("随机", systemImage: "shuffle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.primary)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 经典图标与搭档

    private var classicGridSection: some View {
        Section {
            LazyVGrid(columns: gridColumns, spacing: OneDayMetrics.spacingM) {
                ForEach(classicPresets) { preset in
                    presetGridCell(preset)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingXS)
        } header: {
            SettingsSectionHeader("经典图标")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 相册选图

    private var photoPickerSection: some View {
        Section {
            PhotosPicker(
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(symbol: "photo.on.rectangle")
                    Text("从相册选择")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if store.currentAvatarSelection == .custom {
                        SettingsStatusPill(text: "使用中", tone: .healthy)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
            .disabled(isSaving)
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
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
            }
        } footer: {
            Text("头像保存在你的服务器上，改一次，所有地方看到的都是新头像。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    @ViewBuilder
    private func presetGridCell(_ preset: AgentAvatarPreset) -> some View {
        let selected = store.currentAvatarSelection == .preset(id: preset.id)
        Button {
            Haptics.selection()
            selectPreset(preset)
        } label: {
            VStack(spacing: 6) {
                presetPreview(preset, diameter: 56)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .padding(3)
                    .overlay {
                        if selected {
                            Circle()
                                .stroke(Palette.primary, lineWidth: 2.5)
                        }
                    }
                Text(preset.displayName)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.primary : Palette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(
            selected
                ? preset.displayName + "，" + L10n.string("已选")
                : preset.displayName
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func presetPreview(_ preset: AgentAvatarPreset, diameter: CGFloat) -> some View {
        if let assetName = preset.assetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
        } else if let symbolName = preset.symbolName {
            AgentAvatarPresetDisc(
                symbolName: symbolName,
                tint: AgentProfileStore.presetTint(id: preset.id),
                diameter: diameter
            )
        } else {
            BotCharacterAvatarView(
                presetID: preset.id,
                diameter: diameter
            )
        }
    }

    private func shuffleCharacter() {
        let currentID: String?
        if case .preset(let id) = store.currentAvatarSelection {
            currentID = id
        } else {
            currentID = nil
        }
        let candidates = characterPresets.filter { $0.id != currentID }
        guard let next = candidates.randomElement() ?? characterPresets.first else { return }
        Haptics.selection()
        selectPreset(next)
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

/// 编辑名称（0.36.22 立、§253 改写穿）：改的就是服
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
                                .foregroundStyle(Palette.inkSecondary)
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
        .fullscreenPopBridge()
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
