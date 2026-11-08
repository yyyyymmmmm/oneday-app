import OneDayDesign
import OneDayCore
import SwiftUI

/// 记忆页（智能体格，IA v3 §5.2）：提供方清单＋当前值，
/// 点入 provider 配置页切换/改配置；内置记忆文件计数与重置
/// 在本页（重置口径据服务端源码：target ∈ all/memory/user，
/// 删的是内置记忆文件，destructive＋二次确认沿定版纪律）。
struct MemoryView: View {
    @Environment(AppState.self) private var appState

    @State private var status: MemoryStatus?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var resetTarget: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let status {
                    providersGroup(status)
                    builtinGroup(status)
                    resetGroup
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    loadingRow
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
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "重置记忆？",
            isPresented: Binding(
                get: { resetTarget != nil },
                set: { if !$0 { resetTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认重置", role: .destructive) {
                if let target = resetTarget {
                    Task { await reset(target) }
                }
                resetTarget = nil
            }
            Button("取消", role: .cancel) { resetTarget = nil }
        } message: {
            Text(resetDescription)
        }
    }

    private var resetDescription: String {
        switch resetTarget {
        case "memory":
            return "将删除内置记忆文件（MEMORY），用户档案文件保留。此操作不可恢复。"
        case "user":
            return "将删除内置用户文件（USER），记忆文件保留。此操作不可恢复。"
        default:
            return "将删除全部内置记忆文件（MEMORY 与 USER）。此操作不可恢复。"
        }
    }

    private var loadingRow: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            ProgressView()
            Text("正在读取记忆状态…")
                .font(TypeScale.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.top, OneDayMetrics.spacingL)
    }

    // MARK: - 提供方

    private func providersGroup(_ status: MemoryStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("记忆提供方")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                builtinRow(status)
                ForEach(status.providers) { provider in
                    GroupDivider(inset: 56)
                    NavigationLink {
                        MemoryProviderConfigView(provider: provider, isActive: isActive(provider, in: status))
                    } label: {
                        providerRow(provider, status: status)
                    }
                    .buttonStyle(.plain)
                }
            }
            .odGroup()
        }
    }

    /// 内置记忆行：active 为空串即内置当值（实测口径）
    private func builtinRow(_ status: MemoryStatus) -> some View {
        let active = (status.active ?? "").isEmpty
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "internaldrive")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("内置记忆")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Text("Hermes 自带的文件记忆，零配置")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if active {
                Text("使用中")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.success)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func isActive(
        _ provider: MemoryStatus.MemoryProvider, in status: MemoryStatus
    ) -> Bool {
        status.active == provider.name
    }

    private func providerRow(
        _ provider: MemoryStatus.MemoryProvider, status: MemoryStatus
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "brain")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                if let description = provider.description, !description.isEmpty {
                    Text(description)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            VStack(alignment: .trailing, spacing: 2) {
                if isActive(provider, in: status) {
                    Text("使用中")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.success)
                } else if let state = provider.status, !state.isEmpty {
                    Text(state)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    // MARK: - 内置文件与重置

    private func builtinGroup(_ status: MemoryStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("内置记忆文件")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                fileRow(label: "MEMORY（长期记忆）", value: status.builtinFiles["memory"])
                GroupDivider(inset: OneDayMetrics.spacingM)
                fileRow(label: "USER（用户档案）", value: status.builtinFiles["user"])
            }
            .odGroup()
        }
    }

    private func fileRow(label: String, value: Double?) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value.map { AdminFormat.count($0) } ?? "—")
                .font(TypeScale.monoCallout)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private var resetGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("重置")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                resetRow(title: "重置全部记忆", target: "all")
                GroupDivider(inset: OneDayMetrics.spacingM)
                resetRow(title: "只重置 MEMORY", target: "memory")
                GroupDivider(inset: OneDayMetrics.spacingM)
                resetRow(title: "只重置 USER", target: "user")
            }
            .odGroup()
        }
    }

    private func resetRow(title: String, target: String) -> some View {
        Button(role: .destructive) {
            resetTarget = target
        } label: {
            HStack {
                Text(title)
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

    // MARK: - 数据

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await appState.performAdmin { client, config in
                try await client.memoryStatus(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "记忆状态读取失败。"
        }
    }

    private func reset(_ target: String) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.resetMemory(config: config, target: target)
            }
            notice = "已重置。新的记忆会从下一次对话重新积累。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "重置失败，请稍后再试。"
        }
    }
}

/// 记忆提供方配置页：字段表单（GET …/config 的 fields 驱动）＋
/// 切换当前提供方。字段按 kind 呈现：secret 走 SecureField、
/// 其余走 TextField；保存走 PUT {"values": {…}}（只回写改动项）。
struct MemoryProviderConfigView: View {
    @Environment(AppState.self) private var appState
    let provider: MemoryStatus.MemoryProvider
    let isActive: Bool

    @State private var config: MemoryProviderConfig?
    @State private var values: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isSwitching = false
    @State private var showSwitchConfirm = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusGroup
                if let config, !config.fields.isEmpty {
                    fieldsGroup(config)
                } else if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                } else if config != nil {
                    Text("该提供方没有可配置项。")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, OneDayMetrics.spacingL)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取配置…")
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
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            "切换记忆提供方？",
            isPresented: $showSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("切换到 \(provider.name)") {
                Task { await switchProvider() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("切换后新的对话将使用 \(provider.name) 读写长期记忆；已有记忆文件不删除。")
        }
    }

    private var statusGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("状态")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                infoRow("可用", provider.available == true ? "是" : "否")
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow("已配置", provider.configured == true ? "是" : "否")
                if let state = provider.status, !state.isEmpty {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    infoRow("状态", state)
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                if isActive {
                    HStack {
                        Text("当前提供方")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("使用中")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.success)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                } else {
                    Button {
                        showSwitchConfirm = true
                    } label: {
                        HStack {
                            Text("切换为当前提供方")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.primary)
                            Spacer()
                            if isSwitching {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSwitching)
                }
            }
            .odGroup()
        }
    }

    private func fieldsGroup(_ config: MemoryProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("配置")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(config.fields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    fieldRow(field)
                }
            }
            .odGroup()
            Button(isSaving ? "保存中…" : "保存配置") {
                Task { await save(config) }
            }
            .buttonStyle(.odPrimary)
            .disabled(isSaving)
            .padding(.top, OneDayMetrics.spacingL)
        }
    }

    private func fieldRow(_ field: MemoryProviderConfig.Field) -> some View {
        FieldRow(label: field.label ?? field.key) {
            Group {
                if field.kind == "secret" || field.kind == "password" {
                    SecureField(
                        field.isSet == true ? "已设置（输入新值替换）" : (field.placeholder ?? ""),
                        text: binding(for: field)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } else {
                    TextField(
                        field.placeholder ?? "",
                        text: binding(for: field)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
        }
    }

    private func binding(for field: MemoryProviderConfig.Field) -> Binding<String> {
        Binding(
            get: { values[field.key] ?? field.value?.stringValue ?? "" },
            set: { values[field.key] = $0 }
        )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func load() async {
        do {
            let loaded = try await appState.performAdmin { client, config in
                try await client.memoryProviderConfig(config: config, name: provider.name)
            }
            config = loaded
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "配置读取失败。"
        }
    }

    private func save(_ config: MemoryProviderConfig) async {
        isSaving = true
        defer { isSaving = false }
        var changed: [String: JSONValue] = [:]
        for field in config.fields {
            if let value = values[field.key],
               value != (field.value?.stringValue ?? "") {
                changed[field.key] = .string(value)
            }
        }
        guard !changed.isEmpty else {
            notice = "没有改动。"
            return
        }
        do {
            try await appState.performAdmin { client, config in
                try await client.updateMemoryProviderConfig(
                    config: config, name: provider.name, values: changed
                )
            }
            values = [:]
            notice = "已保存。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }

    private func switchProvider() async {
        isSwitching = true
        defer { isSwitching = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.setMemoryProvider(config: config, name: provider.name)
            }
            notice = "已切换。返回上一页可看到新的当前提供方。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }
}
