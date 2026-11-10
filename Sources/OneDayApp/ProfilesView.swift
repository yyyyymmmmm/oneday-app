import OneDayDesign
import OneDayCore
import SwiftUI

/// 档案页（设置·服务器）：档案列表＋切换。
/// 切换走 POST /api/profiles/active {name}，切换后新对话
/// 使用该档案的模型/技能/记忆（已有数据不迁移）。
/// P10 补齐增删与导入导出：新建（可复制来源）/删除
/// （当前与默认档案不给删）/导出（包生成在服务器、
/// 回执路径展示）/导入（收服务器路径——导出产物同机
/// 导回的正道；本机文件无上传通道，不假装能传文件）。
/// 全部写动作回读列表对账，没在列表里确认到不报成功。
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !profiles.isEmpty {
                    // 0.3.7 卡 7：摘要卡——当前档案名＋「使用中」
                    if let activeName {
                        SectionLabel("现在用的")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Text(activeName)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("使用中")
                                .font(.footnote)
                                .foregroundStyle(Palette.success)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .odGroup()
                    }
                    SectionLabel("全部档案")
                        .padding(.top, 28)
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
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取档案…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
                // 新建/导入动作行（P10）
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
                .padding(.top, 28)
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("档案")
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
            ImportProfileSheet { archive, name in
                await importProfile(archive: archive, name: name)
            }
        }
        .sheet(item: $exportingProfile) { profile in
            ProfileExportSheet(profile: profile)
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(profile.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        if profile.isDefault == true {
                            Text("默认")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
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
                        .font(.footnote)
                        .foregroundStyle(Palette.success)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .contextMenu {
            if !isActive {
                Button("切换到此档案") {
                    pendingSwitch = profile
                }
            }
            Button("导出档案") {
                exportingProfile = profile
            }
            // 当前档案与默认档案不给删：删当前会让服务端
            // 无档案可用，删默认没有退路
            if !isActive && profile.isDefault != true {
                Button("删除档案", role: .destructive) {
                    deleteTarget = profile
                }
            }
        }
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

/// 导入档案表单（P10）：收服务器上的档案包路径。
/// 定案：导出产物就在服务器上，同机导回是真用例；
/// 手机本地文件没有已定义的上传通道，不猜编码、
/// 不假装能从手机传文件
struct ImportProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 返回 true = 已提交/已确认，表单才关闭
    let onImport: (String, String?) async -> Bool

    @State private var archive = ""
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var failed = false

    private var trimmedArchive: String {
        archive.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var canSubmit: Bool {
        !trimmedArchive.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("档案包路径") {
                    TextField("服务器上的档案包路径", text: $archive)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("填导出时服务端回的那串路径。档案包生成在服务器上、导回同一台服务器是正道；手机本地文件目前没有上传通道。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Section("导入为（可选）") {
                    TextField("新档案名，留空用包内原名", text: $name)
                        .autocorrectionDisabled()
                }
                if failed {
                    Section {
                        InlineError("导入失败，请核对路径后重试。")
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
                    Button("导入") { Task { await submit() } }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await onImport(
            trimmedArchive, trimmedName.isEmpty ? nil : trimmedName
        )
        if ok {
            dismiss()
        } else {
            failed = true
        }
    }
}

/// 导出结果（P10）：打开即调导出端点；回执带路径就
/// 展示路径（可选中复制），没带就如实说没回路径——
/// 不编造下载链接
struct ProfileExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let profile: ProfileItem

    @State private var result: ProfileExportResult?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                if let result {
                    if let reference = result.archiveReference {
                        Text("档案包已生成在服务器上：")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(reference)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                        Text("需要恢复时，在「导入档案」里填这个路径即可导回。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    } else {
                        Text("导出已完成，但服务端没有回档案包路径。")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                    }
                } else if failed {
                    InlineError("导出失败，请稍后重试。")
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
            .navigationTitle("导出档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
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
    }
}
