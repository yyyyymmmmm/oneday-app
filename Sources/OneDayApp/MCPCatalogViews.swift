import OneDayDesign
import OneDayCore
import SwiftUI

/// MCP 目录面（§388 H7，总表 167）：服务端批准目录单源
/// ——GET /api/mcp/catalog 浏览、详情摊全信任信息（命令/
/// 地址/自举步骤，服务端信任模型原文要求）、POST install
/// 点按安装，落定靠门面回读对账。已配置服务的启停/测试
/// 仍在连接器面原位，本面不重复造管理面；入口在连接器
/// 面「可连接」段，与技能 hub 凑成能力商店双面。
struct MCPCatalogView: View {
    @Environment(AppState.self) private var appState

    let facade: ConnectorsFacade

    @State private var detailEntry: MCPCatalogEntry?

    private var installable: [MCPCatalogEntry] {
        facade.catalogEntries.filter { !$0.installed }
    }

    private var installed: [MCPCatalogEntry] {
        facade.catalogEntries.filter(\.installed)
    }

    var body: some View {
        List {
            if let notice = facade.catalogNotice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            }
            if facade.isLoadingCatalog, facade.catalogEntries.isEmpty {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取目录…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Color.clear)
            } else if let catalogError = facade.catalogError,
                      facade.catalogEntries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                        Text(catalogError)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Button("重试") {
                            Task { await facade.loadCatalog(appState: appState) }
                        }
                        .buttonStyle(.odSecondary)
                    }
                }
                .listRowBackground(Color.clear)
            } else if facade.catalogEntries.isEmpty {
                Section {
                    Text("服务器目录是空的。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            } else {
                if !installable.isEmpty {
                    Section {
                        ForEach(installable) { entry in
                            catalogRow(entry)
                        }
                    } header: {
                        headerText("可安装")
                    }
                    .listRowBackground(Palette.surface)
                }
                if !installed.isEmpty {
                    Section {
                        ForEach(installed) { entry in
                            catalogRow(entry)
                        }
                    } header: {
                        headerText("已安装")
                    }
                    .listRowBackground(Palette.surface)
                }
                if !facade.catalogDiagnostics.isEmpty {
                    Section {
                        ForEach(
                            Array(facade.catalogDiagnostics.enumerated()),
                            id: \.offset
                        ) { _, diagnostic in
                            Text(diagnostic.message.isEmpty
                                ? diagnostic.kind : diagnostic.message)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    } header: {
                        headerText("目录诊断")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("MCP 目录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await facade.loadCatalog(appState: appState) }
        .refreshable { await facade.loadCatalog(appState: appState) }
        .sheet(item: $detailEntry) { entry in
            MCPCatalogDetailView(entry: entry, facade: facade)
        }
    }

    private func headerText(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    private func catalogRow(_ entry: MCPCatalogEntry) -> some View {
        Button {
            detailEntry = entry
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(entry.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Text(entry.stateLabel)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }
}

// MARK: - 详情/安装面

struct MCPCatalogDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entry: MCPCatalogEntry
    let facade: ConnectorsFacade

    @State private var envValues: [String: String] = [:]
    @State private var enableOnInstall = true

    /// 实时条目：安装回读后以门面最新名单为准，不看打开
    /// 时的旧快照
    private var liveEntry: MCPCatalogEntry {
        facade.catalogEntries.first { $0.name == entry.name } ?? entry
    }

    private var isInstalling: Bool {
        facade.installingCatalog.contains(entry.name)
    }

    private var requiredEnvMissing: Bool {
        liveEntry.requiredEnv.contains { spec in
            spec.required
                && (envValues[spec.name] ?? "")
                    .trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !liveEntry.description.isEmpty {
                        Text(liveEntry.description)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .padding(.bottom, OneDayMetrics.spacingM)
                    }
                    SectionLabel("状态")
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        FieldRow(label: "安装状态") {
                            Text(liveEntry.stateLabel)
                        }
                        if let transport = liveEntry.transport, !transport.isEmpty {
                            GroupDivider()
                            FieldRow(label: "传输") {
                                Text(transport)
                            }
                        }
                        if let authType = liveEntry.authType, !authType.isEmpty {
                            GroupDivider()
                            FieldRow(label: "鉴权") {
                                Text(authType)
                            }
                        }
                    }
                    .odGroup()

                    trustSection

                    if !liveEntry.postInstall.isEmpty {
                        Text(liveEntry.postInstall)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, OneDayMetrics.spacingM)
                    }

                    if liveEntry.installed {
                        Text("已安装。在连接器「已连接」里可以启停和测试它。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, OneDayMetrics.spacingL)
                    } else {
                        installSection
                    }

                    if let notice = facade.catalogNotice {
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
            .navigationTitle(liveEntry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .fullscreenPopBridge()
    }

    /// 信任信息：命令/地址/自举步骤全量摊开（服务端信任
    /// 模型要求用户装前能查实际要跑什么）
    @ViewBuilder
    private var trustSection: some View {
        let commandLine = liveEntry.commandLine
        let url = liveEntry.url
        let installUrl = liveEntry.installUrl
        if commandLine != nil || url != nil || installUrl != nil
            || !liveEntry.bootstrap.isEmpty {
            SectionLabel("将要运行")
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if let commandLine {
                    FieldRow(label: "命令") {
                        Text(commandLine)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if let url, !url.isEmpty {
                    if commandLine != nil { GroupDivider() }
                    FieldRow(label: "地址") {
                        Text(url)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if let installUrl, !installUrl.isEmpty {
                    if commandLine != nil || url != nil { GroupDivider() }
                    FieldRow(label: "自举来源") {
                        Text(installLine(installUrl))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if !liveEntry.bootstrap.isEmpty {
                    if commandLine != nil || url != nil || installUrl != nil {
                        GroupDivider()
                    }
                    FieldRow(label: "自举步骤") {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            ForEach(
                                Array(liveEntry.bootstrap.enumerated()),
                                id: \.offset
                            ) { _, step in
                                Text(step)
                                    .font(.system(.footnote, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .odGroup()
        }
    }

    private func installLine(_ url: String) -> String {
        if let ref = liveEntry.installRef, !ref.isEmpty {
            return "\(url) @ \(ref)"
        }
        return url
    }

    @ViewBuilder
    private var installSection: some View {
        if !liveEntry.requiredEnv.isEmpty {
            SectionLabel("安装参数")
                .padding(.top, OneDayMetrics.spacingL)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(
                    Array(liveEntry.requiredEnv.enumerated()),
                    id: \.element.id
                ) { index, spec in
                    if index > 0 { GroupDivider() }
                    FieldRow(label: envLabel(spec)) {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            if spec.looksSecret {
                                SecureField(spec.name, text: envBinding(spec))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                TextField(spec.name, text: envBinding(spec))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            if !spec.prompt.isEmpty {
                                Text(spec.prompt)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                }
            }
            .odGroup()
        }
        Toggle("安装后启用", isOn: $enableOnInstall)
            .padding(.top, OneDayMetrics.spacingL)
        Button {
            Task { await install() }
        } label: {
            if isInstalling {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("安装中…")
                }
            } else {
                Text(liveEntry.needsInstall ? "安装（后台自举）" : "安装")
            }
        }
        .buttonStyle(.odPrimary)
        .disabled(isInstalling || requiredEnvMissing)
        .padding(.top, OneDayMetrics.spacingM)
        if requiredEnvMissing {
            Text("标了「必填」的参数还没填。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
        }
    }

    private func envLabel(_ spec: MCPCatalogEnvSpec) -> String {
        spec.required ? "\(spec.name)（必填）" : spec.name
    }

    private func envBinding(_ spec: MCPCatalogEnvSpec) -> Binding<String> {
        Binding(
            get: { envValues[spec.name] ?? "" },
            set: { envValues[spec.name] = $0 }
        )
    }

    /// 只带填了值的声明键（服务端对未声明键 400、本面
    /// 只从声明清单取值，天然合规）
    private func install() async {
        var env: [String: String] = [:]
        for spec in liveEntry.requiredEnv {
            let value = (envValues[spec.name] ?? "")
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { env[spec.name] = value }
        }
        await facade.installCatalogEntry(
            liveEntry, env: env, enable: enableOnInstall, appState: appState
        )
        if liveEntry.installed {
            dismiss()
        }
    }
}
