import OneDayDesign
import OneDayCore
import SwiftUI

/// 装包链本地失败口径（§393）：上传后回读对账
/// 不过——字节没在服务器上落到预期形态，不进
/// 导入段、如实报，不冒充服务端错误
enum PackageInstallError: Error {
    case readbackMismatch

    var message: String {
        switch self {
        case .readbackMismatch:
            return "包已上传，但核对没对上（服务器上的包大小和手机里的不一致），已停下、没有继续导入。"
        }
    }
}

/// 配置档案页（设置·智能体）：档案列表＋切换＋当前
/// 档案的人设入口（台账 198 收敛 S12）。页题与设置
/// 目录题对齐「配置档案」（S9，此前页题只写「档案」）。
/// 切换走 POST /api/profiles/active {name}，切换后新对话
/// 使用该档案的模型/技能/记忆（已有数据不迁移）。
/// P10 补齐增删与导入导出：新建（可复制来源）/删除
/// （当前与默认档案不给删）/导出（包生成在服务器、
/// 回执路径展示）/导入（收服务器路径——导出产物同机
/// 导回的正道；本机文件无上传通道，不假装能传文件）。
/// 全部写动作回读列表对账，没在列表里确认到不报成功。
///
/// §393（台账 165 智能体成包）：P10「本机文件无上
/// 传通道」的前提已被文件面组合证伪——文件面下载
/// /上传端点实存（托管根锁 HERMES_HOME、导出落点
/// profile-exports 在根内），成包三件就此补齐：导
/// 出包可下载到手机并分享、手机里的包可装到当前连
/// 着的任意服务器（上传→回读→导入→回读四段对
/// 账）、装前有真解包清单预览。服务端零新增端点。
struct ProfilesView: View {
    @Environment(AppState.self) private var appState

    @State private var profiles: [ProfileItem] = []
    @State private var activeName: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var pendingSwitch: ProfileItem?
    @State private var notice: String?
    @State private var showCreateSheet = false
    @State private var showImportSheet = false
    @State private var deleteTarget: ProfileItem?
    @State private var exportingProfile: ProfileItem?
    @State private var editingProfile: ProfileItem?

    var body: some View {
        List {
            if !profiles.isEmpty {
                // 0.3.7 卡 7：摘要卡——当前档案名＋「使用中」
                if let activeName {
                    Section {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Text(activeName)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("使用中")
                                .font(.footnote)
                                .foregroundStyle(Palette.successText)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                    } header: {
                        SettingsSectionHeader("现在用的")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }
                Section {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                } header: {
                    SettingsSectionHeader("全部分身与档案")
                } footer: {
                    Text("每个分身拥有独立的 SOUL.md 人设、模型、技能与记忆库；长按可导出分身包跨机分发，或通过新建快速克隆出专业分身。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
                // 人设组（台账 198 收敛 S12）：当前档
                // 案的人设在设置内的正式入口——行本
                // 体是就绪闸门（PersonaEntryRow），
                // 点达既有 SoulEditorView、不新建编辑器
                Section {
                    PersonaEntryRow()
                } header: {
                    SettingsSectionHeader("人设")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            } else if let errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        InlineError(errorMessage)
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.odSecondary)
                            .padding(.top, OneDayMetrics.spacingSM)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取档案…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
            // 新建/导入动作行（P10）
            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("新建档案", systemImage: "plus")
                    }
                    .buttonStyle(.odSecondary)
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("导入档案", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.odSecondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("配置档案")
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
        .sheet(isPresented: $showCreateSheet) {
            CreateProfileSheet(existingNames: profiles.map(\.name)) { name, cloneFrom in
                await createProfile(name: name, cloneFrom: cloneFrom)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportProfileSheet(
                existingNames: profiles.map(\.name),
                onImportPath: { archive, name in
                    await importProfile(archive: archive, name: name)
                },
                onInstallLocal: { data, fileName, name in
                    await installLocalPackage(
                        data: data, fileName: fileName, name: name
                    )
                }
            )
        }
        .sheet(item: $exportingProfile) { profile in
            ProfileExportSheet(profile: profile)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileDetailEditSheet(
                profile: profile,
                isActive: profile.name == activeName,
                existingNames: profiles.map(\.name),
                onSaved: { message in
                    notice = message
                    await load()
                }
            )
        }
        .confirmationDialog(
            "删除档案？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { profile in
            Button("删除", role: .destructive) {
                Task { await deleteProfile(profile) }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { profile in
            Text("将删除档案「\(profile.name)」的配置与记忆，此操作不可恢复。")
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
                Image(systemName: isActive ? "person.crop.circle.badge.checkmark" : "person.crop.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? Palette.tintSkyInk : Palette.tintLavenderInk)
                    .frame(width: 36, height: 36)
                    .background(
                        isActive ? Palette.tintSky : Palette.tintLavender,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(profile.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        if profile.isDefault == true {
                            Text("默认")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Palette.inkSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.fillTertiary, in: Capsule())
                        }
                    }
                    Text(subtitle(profile))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if isActive {
                    Text("使用中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.successText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.tintGreen, in: Capsule())
                }
                Button {
                    editingProfile = profile
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑分身 \(profile.name)")
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .contextMenu {
            Button("编辑分身配置与专属模型") {
                editingProfile = profile
            }
            if !isActive {
                Button("切换到此分身") {
                    pendingSwitch = profile
                }
            }
            Button("导出分身包") {
                exportingProfile = profile
            }
            // 当前档案与默认档案不给删：删当前会让服务端
            // 无档案可用，删默认没有退路
            if !isActive && profile.isDefault != true {
                Button("删除分身", role: .destructive) {
                    deleteTarget = profile
                }
            }
        }
    }

    private func subtitle(_ profile: ProfileItem) -> String {
        var parts: [String] = []
        if let desc = profile.description, !desc.isEmpty {
            parts.append(desc)
        }
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
            errorMessage = (error as? HermesError)?.userMessage ?? "档案没读出来，可能是网络或服务暂时没响应"
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

    /// 新建：POST 后回读列表，名字出现才算建成（返回给
    /// 表单决定是否关闭）
    private func createProfile(name: String, cloneFrom: String?) async -> Bool {
        do {
            try await appState.performAdmin { client, config in
                try await client.createProfile(
                    config: config, name: name, cloneFrom: cloneFrom
                )
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "档案创建失败。"
            return false
        }
        await load()
        let confirmed = profiles.contains { $0.name == name }
        notice = confirmed
            ? "已新建档案 \(name)。"
            : "已提交创建，但列表里还没出现，请下拉刷新核对。"
        return confirmed
    }

    /// 导入：填了新名按新名对账；没填名无法预知包内
    /// 名字，只报已提交、请用户在列表核对
    private func importProfile(archive: String, name: String?) async -> Bool {
        do {
            try await appState.performAdmin { client, config in
                try await client.importProfile(
                    config: config, archive: archive, name: name
                )
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "档案导入失败。"
            return false
        }
        await load()
        if let name, !name.isEmpty {
            let confirmed = profiles.contains { $0.name == name }
            notice = confirmed
                ? "已导入档案 \(name)。"
                : "已提交导入，但列表里还没出现目标档案，请下拉刷新核对。"
            return confirmed
        }
        notice = "已提交导入，请在列表里核对新档案是否出现。"
        return true
    }

    /// 装包（§393）：手机里的包字节装到当前服务
    /// 器——四段对账，缺一不报成：①上传到托管根
    /// profile-exports/（相对路径，文件面既有上
    /// 传端点）②回读该目录列表，同名条目在且字
    /// 节数一致、取其绝对路径 ③以该路径调导入
    /// ④回读档案列表，目标名出现才算装成。根路
    /// 径取文件面列表回执的 root/lockedRoot，不
    /// 猜服务器目录结构。
    private func installLocalPackage(
        data: Data, fileName: String, name: String
    ) async -> Bool {
        let relative = ProfilePackage.uploadRelativePath(
            fileName: fileName
        )
        let baseName = (relative as NSString).lastPathComponent
        do {
            let archivePath = try await appState
                .performAdmin { client, config in
                    let rootListing = try await client.files(
                        config: config, path: nil
                    )
                    let root = rootListing.lockedRoot
                        ?? rootListing.root
                        ?? rootListing.path
                    try await client.uploadFile(
                        config: config, path: relative,
                        dataURL: FileBrowserLogic.makeDataURL(
                            data: data, fileName: baseName
                        ),
                        overwrite: false
                    )
                    let dirListing = try await client.files(
                        config: config,
                        path: "\(root)/\(ProfilePackage.exportsDirectory)"
                    )
                    guard let entry = dirListing.entries
                        .first(where: {
                            $0.name == baseName && !$0.isDirectory
                        }),
                        entry.size == Int64(data.count)
                    else {
                        throw PackageInstallError.readbackMismatch
                    }
                    try await client.importProfile(
                        config: config, archive: entry.path,
                        name: name
                    )
                    return entry.path
                }
            _ = archivePath
        } catch let error as PackageInstallError {
            notice = error.message
            return false
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "装包失败，请稍后再试。"
            return false
        }
        await load()
        let confirmed = profiles.contains { $0.name == name }
        notice = confirmed
            ? "已装入档案 \(name)。"
            : "已提交装包，但列表里还没出现目标档案，请下拉刷新核对。"
        return confirmed
    }

    /// 删除：回读确认从列表消失才报已删
    private func deleteProfile(_ profile: ProfileItem) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteProfile(config: config, name: profile.name)
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "档案删除失败。"
            return
        }
        await load()
        notice = profiles.contains { $0.name == profile.name }
            ? "已提交删除，但列表里仍有这个档案，请下拉刷新核对。"
            : "已删除档案 \(profile.name)。"
    }
}

/// 新建档案表单（P10）：名称＋可选复制来源；同名在
/// 表单内先拦（服务端也会拒，客户端先拦少一次往返）
struct CreateProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingNames: [String]
    /// 返回 true = 已在列表确认建成，表单才关闭
    let onCreate: (String, String?) async -> Bool

    @State private var name = ""
    /// "" = 不复制
    @State private var cloneFrom = ""
    @State private var isSubmitting = false
    @State private var failed = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameTaken: Bool {
        !trimmedName.isEmpty && existingNames.contains(trimmedName)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !nameTaken && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("新档案名称", text: $name)
                        .autocorrectionDisabled()
                    if nameTaken {
                        Text("已有同名档案")
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                Section("复制来源") {
                    Picker("从现有档案复制", selection: $cloneFrom) {
                        Text("不复制（空白新建）").tag("")
                        ForEach(existingNames, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    Text("复制带上来源档案的模型与技能配置；对话与记忆不迁移。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if failed {
                    Section {
                        InlineError("创建没有确认成功，请关闭后在列表里核对，或稍后重试。")
                    }
                }
            }
            .navigationTitle("新建档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("创建") { Task { await submit() } }
                        .disabled(!canSubmit)
                }
            }
        }
        .fullscreenPopBridge()
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await onCreate(
            trimmedName, cloneFrom.isEmpty ? nil : cloneFrom
        )
        if ok {
            dismiss()
        } else {
            failed = true
        }
    }
}

/// 导入档案表单（P10＋§393 成包）：双模式——
/// 「手机里的包」是成包正道（在一台服务器导出
/// 下载到手机、切到另一台在这里装）；「服务器
/// 路径」保留 P10 同机导回形态。手机模式选中包
/// 先出真解包清单（Core ProfilePackage），解不
/// 开降级文件名推断并如实标注；装包走上传→回
/// 读→导入→回读四段（宿主 installLocalPackage）
struct ImportProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingNames: [String]
    /// 服务器路径模式：返回 true = 已确认，关表
    let onImportPath: (String, String?) async -> Bool
    /// 手机包模式：（包字节, 包文件名, 导入名）
    let onInstallLocal: (Data, String, String) async -> Bool

    private enum Mode: String, CaseIterable {
        case localPackage = "手机里的包"
        case serverPath = "服务器路径"
    }

    @State private var mode: Mode = .localPackage
    // 服务器路径模式（P10 原形态）
    @State private var archive = ""
    @State private var pathName = ""
    // 手机包模式
    @State private var localPackages:
        [AgentPackageLibrary.LocalPackage] = []
    @State private var selectedFileName: String?
    @State private var selectedData: Data?
    @State private var manifest:
        ProfilePackage.Manifest?
    @State private var importName = ""
    @State private var showPicker = false
    @State private var pickFailed = false
    // 共用
    @State private var isSubmitting = false
    @State private var failed = false

    private var trimmedArchive: String {
        archive.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedPathName: String {
        pathName.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedImportName: String {
        importName.trimmingCharacters(in: .whitespaces)
    }

    private var nameVerdict:
        ProfilePackage.ImportNameVerdict {
        ProfilePackage.importNameVerdict(
            trimmedImportName, existingNames: existingNames
        )
    }

    private var localSizeAllowed: Bool {
        guard let selectedData else { return false }
        return FileBrowserLogic.isUploadSizeAllowed(
            byteCount: selectedData.count
        )
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        switch mode {
        case .serverPath:
            return !trimmedArchive.isEmpty
        case .localPackage:
            return selectedData != nil
                && nameVerdict == .ok
                && localSizeAllowed
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("来源", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if mode == .serverPath {
                    serverPathSections
                } else {
                    localPackageSections
                }
                if failed {
                    Section {
                        InlineError(
                            mode == .serverPath
                                ? "导入失败，请核对路径后重试。"
                                : "装包失败，请关闭后在列表里核对，或稍后重试。"
                        )
                    }
                }
            }
            .navigationTitle("导入档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .task { refreshLocalPackages() }
            // 选包走 DocumentPickerView 状态旗路
            // （.fileImporter 已退役，见其文件头）
            .fullScreenCover(isPresented: $showPicker) {
                DocumentPickerView(
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        showPicker = false
                        handlePicked(urls)
                    },
                    onCancel: { showPicker = false }
                )
            }
        }
        .fullscreenPopBridge()
    }

    // MARK: 服务器路径模式（P10 原形态）

    @ViewBuilder
    private var serverPathSections: some View {
        Section("档案包路径") {
            TextField("服务器上的档案包路径", text: $archive)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Text("填导出时服务端回的那串路径，导回同一台服务器用。包在手机里（从别的服务器下载的）切到「手机里的包」。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        Section("导入为（可选）") {
            TextField("新档案名，留空用包内原名", text: $pathName)
                .autocorrectionDisabled()
        }
    }

    // MARK: 手机包模式（§393）

    @ViewBuilder
    private var localPackageSections: some View {
        Section("手机里的档案包") {
            if localPackages.isEmpty {
                Text("手机里还没有档案包。在任意一台服务器的档案行选「导出档案→下载到手机」，包就会出现在这里；也可以从文件里选一个包。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            ForEach(localPackages) { item in
                Button {
                    selectLocalPackage(item.fileName)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Text(item.fileName)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(byteText(item.byteCount))
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                        }
                        Spacer()
                        if selectedFileName == item.fileName {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .swipeActions {
                    Button("删除本地副本", role: .destructive) {
                        AgentPackageLibrary.delete(
                            fileName: item.fileName
                        )
                        if selectedFileName == item.fileName {
                            selectedFileName = nil
                            selectedData = nil
                            manifest = nil
                        }
                        refreshLocalPackages()
                    }
                }
            }
            Button {
                showPicker = true
            } label: {
                Label("从文件选择档案包", systemImage: "folder")
            }
            if pickFailed {
                InlineError("这个文件读不出来，换一个包再试。")
            }
        }
        if selectedData != nil {
            Section("包里是什么") {
                if let manifest {
                    LabeledContent(
                        "包内档案",
                        value: manifest.profileName
                    )
                    LabeledContent(
                        "文件",
                        value: "\(manifest.fileCount) 个 · \(byteText(manifest.totalFileBytes))"
                    )
                    LabeledContent(
                        "内容",
                        value: [
                            manifest.hasSoul ? "有人设" : nil,
                            manifest.hasConfig ? "有配置" : nil,
                        ].compactMap { $0 }
                            .joined(separator: " · ")
                            .ifEmpty("—")
                    )
                } else {
                    Text("这个包的清单读不出来（可能不是档案导出包，或包已损坏）。仍可试装——服务端导入时会校验，坏包会被拒绝。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if !localSizeAllowed {
                    InlineError("包超过 25MB，手机上传通道装不了（与文件上传同一上限）。")
                }
            }
            Section("装到这台服务器") {
                TextField("档案名", text: $importName)
                    .autocorrectionDisabled()
                switch nameVerdict {
                case .ok:
                    EmptyView()
                case .empty:
                    Text("给装好的档案起个名字（默认用包内原名）。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                case .reservedDefault:
                    Text("「default」是内置档案，不能作为导入名，换一个。")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                case .alreadyExists:
                    Text("这台服务器上已有同名档案，换一个名字再装。")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                Text("装到当前连着的这台服务器；换一台装，先在服务器列表切换，再回这里选同一个包。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes, countStyle: .file
        )
    }

    private func refreshLocalPackages() {
        localPackages = AgentPackageLibrary.list()
        if selectedFileName == nil,
           let first = localPackages.first {
            selectLocalPackage(first.fileName)
        }
    }

    /// 选中包即真解包读清单（装前预览口），读
    /// 不出清单不拦——导入名退回文件名推断
    private func selectLocalPackage(_ fileName: String) {
        selectedFileName = fileName
        pickFailed = false
        guard let data = try? AgentPackageLibrary.read(
            fileName: fileName
        ) else {
            selectedData = nil
            manifest = nil
            return
        }
        selectedData = data
        manifest = ProfilePackage.manifest(tarGz: data)
        importName = manifest?.profileName
            ?? ProfilePackage.inferredName(
                fromFileName: fileName
            )
            ?? ""
    }

    /// 选到的文件先落本地库再选中（与下载到手
    /// 机的包同位管理，之后换服务器还能再装）
    private func handlePicked(_ urls: [URL]) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url)
        else {
            pickFailed = true
            return
        }
        let fileName = url.lastPathComponent
        do {
            try AgentPackageLibrary.save(
                data: data, fileName: fileName
            )
        } catch {
            pickFailed = true
            return
        }
        refreshLocalPackages()
        selectLocalPackage(fileName)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let ok: Bool
        switch mode {
        case .serverPath:
            ok = await onImportPath(
                trimmedArchive,
                trimmedPathName.isEmpty ? nil : trimmedPathName
            )
        case .localPackage:
            guard let data = selectedData,
                  let fileName = selectedFileName
            else { return }
            ok = await onInstallLocal(
                data, fileName, trimmedImportName
            )
        }
        if ok {
            dismiss()
        } else {
            failed = true
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

/// 导出结果（P10＋§393 成包）：打开即调导出端
/// 点；回执带路径就展示路径（可选中复制），没带
/// 就如实说没回路径——不编造下载链接。§393 补
/// 「下载到手机」：经文件面 download 端点取回字
/// 节、存本地包库（AgentPackageLibrary），之后
/// 可分享/存到文件，也可在导入面装到别的服务器
struct ProfileExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let profile: ProfileItem

    @State private var result: ProfileExportResult?
    @State private var failed = false
    @State private var downloadedURL: URL?
    @State private var isDownloading = false
    @State private var downloadFailed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                if let result {
                    if let reference = result.archiveReference {
                        Text("档案包已生成在服务器上：")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(reference)
                            .font(.metaMonospaced)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                        Text("需要恢复时，在「导入档案」里填这个路径即可导回。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        // §393 成包：包离机——下载到
                        // 手机后可分享、也可装到别的
                        // 服务器（导入面「手机里的包」）
                        if let downloadedURL {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                ShareLink(item: downloadedURL) {
                                    Label(
                                        "分享 / 存到文件",
                                        systemImage: "square.and.arrow.up"
                                    )
                                }
                                .buttonStyle(.odPrimary)
                            }
                            Text("已存到手机的档案包库：在另一台服务器上打开「导入档案→手机里的包」就能装上。")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        } else {
                            Button {
                                Task {
                                    await downloadPackage(
                                        reference: reference
                                    )
                                }
                            } label: {
                                if isDownloading {
                                    HStack(
                                        spacing: OneDayMetrics.spacingS
                                    ) {
                                        ProgressView()
                                        Text("正在下载…")
                                    }
                                } else {
                                    Label(
                                        "下载到手机",
                                        systemImage: "square.and.arrow.down"
                                    )
                                }
                            }
                            .buttonStyle(.odPrimary)
                            .disabled(isDownloading)
                            if downloadFailed {
                                InlineError("下载没成功，包还在服务器上（路径见上），稍后再试。")
                            }
                        }
                    } else {
                        Text("导出已完成，但服务端没有回档案包路径。")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                    }
                } else if failed {
                    InlineError("导出失败，请稍后再试。")
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在导出…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OneDayMetrics.pageGutter)
            // 0.36.0（宪法 §5／审计 C9 同族）：撤居中
            // 标题与手写关闭——导出状态内容领头、关
            // 闭走系统下拉手势
            .task {
                do {
                    result = try await appState.performAdmin { client, config in
                        try await client.exportProfile(
                            config: config, name: profile.name
                        )
                    }
                } catch {
                    failed = true
                }
            }
        }
        .fullscreenPopBridge()
    }

    /// 下载到手机（§393）：文件面 download 端点
    /// 取原始字节（导出回执的绝对路径与文件面条
    /// 目路径同形态、直传），落本地包库；字节数
    /// 为零判失败，不存空包冒充成功
    private func downloadPackage(reference: String) async {
        isDownloading = true
        downloadFailed = false
        defer { isDownloading = false }
        do {
            let data = try await appState
                .performAdmin { client, config in
                    try await client.fileData(
                        config: config, path: reference
                    )
                }
            guard !data.isEmpty else {
                downloadFailed = true
                return
            }
            downloadedURL = try AgentPackageLibrary.save(
                data: data,
                fileName: (reference as NSString)
                    .lastPathComponent
            )
        } catch {
            downloadFailed = true
        }
    }
}

/// 人设入口行（台账 198 收敛 S12）：就绪闸门——共
/// 享枢纽 store 的 soul 已读到才给编辑入口（直达既
/// 有 SoulEditorView，编辑器本体与枢纽身份段共用一
/// 份）；未读到先经 store 补拉（loadIdentityIfNeeded
/// 自带在飞守卫），失败如实显行内错＋重试、不空开
/// 编辑器（空开会让用户对着空白草稿改、保存必失败）。
/// 已知边界：枢纽 store 的冻结档案名与本页刚切换的
/// 档案可能短暂不一致——编辑器保存侧有档案已切换
/// 的拒存兜底（saveSoul 的 .profileChanged），不会
/// 写错档案；真机时序列待验清单。
private struct PersonaEntryRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.sharedHubStore()
        Group {
            if store.soulDocument != nil {
                NavigationLink {
                    SoulEditorView(store: store)
                } label: {
                    rowLabel
                }
                .buttonStyle(.odPressable)
            } else if store.identityFailed {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("人设没读出来，检查连接后再试。")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Button("重试") {
                        Task { await store.loadIdentityIfNeeded() }
                    }
                    .font(.rowTitleL)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取人设…")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .task { await store.loadIdentityIfNeeded() }
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text("编辑人设")
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            DisclosureChevron(font: .system(size: FrameworkIcon.smallGlyphSize, weight: .regular))
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}
