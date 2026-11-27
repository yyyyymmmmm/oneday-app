import OneDayCore
import OneDayDesign
import SwiftUI

/// 设置页一级入口：云电脑与远程主机管理（大厂统一管理面）
/// 支持三类接入：
/// 1. 托管云电脑（Simular Box 等，API 密钥 + 可选自定义 MCP 地址）
/// 2. 自建 VPS / NAT 主机（Linux & Windows，自定义端口，SSH 密钥/一键生成 Ed25519 公私钥 或 密码）
/// 3. 内网穿透节点（纯内网 NAT 机/家用电脑，一次性配对命令反向回连）
struct CloudComputerListView: View {
    @Environment(AppState.self) private var appState
    @State private var store = ConnectionsStore()
    @State private var showAddSheet = false
    @State private var activeTakeoverTarget: CloudComputerTarget?

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "desktopcomputer",
                tint: .blue,
                title: "云电脑与远程主机",
                subtitle: "统一管理托管云电脑、Linux / Windows VPS、NAT 映射主机与内网穿透节点。",
                statusText: configuredCount > 0 ? "\(configuredCount) 台就绪" : "未配置",
                statusTone: configuredCount > 0 ? .healthy : .neutral
            )

            if let error = store.loadError, store.cloudComputers.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Palette.danger)
                        Button("重试") {
                            Task { await store.load(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, OneDayMetrics.spacingXS)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            Section {
                if store.isLoading && store.cloudComputers.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取远程主机列表…")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                } else if store.cloudComputers.isEmpty {
                    VStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 36))
                            .foregroundStyle(Palette.inkMuted)
                        Text("还没有添加云电脑或远程主机")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                        Button("添加一台主机") {
                            showAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OneDayMetrics.spacingM)
                } else {
                    ForEach(store.cloudComputers) { connection in
                        NavigationLink {
                            CloudComputerDetailView(
                                store: store,
                                connectionID: connection.id,
                                onOpenTakeover: { target in
                                    activeTakeoverTarget = target
                                }
                            )
                        } label: {
                            computerListRow(connection)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader("已登记主机")
            } footer: {
                Text("托管云电脑支持实时桌面接管；VPS / NAT 主机支持自定义端口与 SSH 密钥认证。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Palette.primary)
                        Text("添加云电脑 / VPS / NAT 机")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .buttonStyle(.odPressable)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("云电脑与远程主机")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加远程主机")
            }
        }
        .refreshable {
            await store.load(appState: appState)
        }
        .task {
            await store.load(appState: appState)
        }
        .sheet(isPresented: $showAddSheet) {
            AddComputerView(store: store)
        }
        .fullScreenCover(item: $activeTakeoverTarget) { target in
            CloudComputerTakeoverSheet(
                target: target,
                onHandBackToAI: nil
            )
        }
    }

    private var configuredCount: Int {
        store.cloudComputers.filter { $0.configured == true }.count
    }

    private func computerListRow(_ connection: CompanionConnection) -> some View {
        let status = ConnectionStatusWording.evaluate(connection)
        let iconName: String = {
            switch connection.provider {
            case "simular_box": return "desktopcomputer"
            case "reverse_node": return "point.3.connected.trianglepath.dotted"
            default:
                return connection.meta?.osType == "windows" ? "pc" : "terminal"
            }
        }()
        return HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.primary)
                .frame(width: 34, height: 34)
                .background(Palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(connection.name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Text(connection.providerWording)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    if let host = connection.meta?.host, !host.isEmpty {
                        let port = connection.meta?.port.map { ":\($0)" } ?? ""
                        Text("· \(host)\(port)")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            SettingsStatusPill(
                text: status.text,
                tone: status.tone == .ok ? .healthy
                    : status.tone == .bad ? .error
                    : status.tone == .pending ? .warning : .neutral
            )
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }
}

/// 云电脑 / 远程主机详情页
struct CloudComputerDetailView: View {
    var store: ConnectionsStore
    let connectionID: String
    var onOpenTakeover: ((CloudComputerTarget) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showCredentialForm = false
    @State private var pendingDisconnect = false
    @State private var pendingDelete = false
    @State private var copiedCommand = false
    /// 接管取数（盒子桥）：连接记录本身没有桌面地址，
    /// 打开接管前先经盒子桥现拉状态取真实地址
    @State private var boxStore = BoxBridgeStore()
    @State private var openingTakeover = false

    private var connection: CompanionConnection? {
        store.connections.first { $0.id == connectionID }
    }

    private var canDelete: Bool {
        connectionID != "box"
    }

    var body: some View {
        List {
            if let connection {
                Section {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                        Text(connection.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text(connection.providerWording)
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, OneDayMetrics.spacingS)

                    if let meta = connection.meta {
                        if let host = meta.host, !host.isEmpty {
                            let portText = meta.port.map { ":\($0)" } ?? ""
                            LabeledContent("主机地址", value: "\(host)\(portText)")
                        }
                        if let user = meta.username, !user.isEmpty {
                            LabeledContent("用户名", value: user)
                        }
                        if let os = meta.osType, !os.isEmpty {
                            LabeledContent("系统", value: os == "windows" ? "Windows" : "Linux")
                        }
                        if let auth = meta.authType, !auth.isEmpty {
                            LabeledContent("认证方式", value: authLabel(auth))
                        }
                        if let mcp = meta.mcpUrl, !mcp.isEmpty {
                            LabeledContent("MCP 地址", value: mcp)
                        }
                    }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                if connection.provider == "simular_box", connection.configured == true {
                    Section {
                        desktopPreviewCard(connection: connection)
                    } header: {
                        SettingsSectionHeader("实时桌面预览")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                Section {
                    let status = ConnectionStatusWording.evaluate(connection)
                    HStack {
                        Text("状态")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(status.text)
                            .foregroundStyle(
                                status.tone == .ok ? Palette.successText
                                    : status.tone == .bad ? Palette.danger
                                    : Palette.inkSecondary
                            )
                    }
                    if let verify = connection.lastVerify {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(verify.ok ? "最近一次测试：连上了" : "最近一次测试：没连上")
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                            Text(verify.detail)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.vertical, OneDayMetrics.spacingMicro)
                    }
                    if let note = connection.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if connection.provider == "simular_box", connection.configured == true,
                       let onOpenTakeover {
                        Button {
                            Task {
                                await openTakeover(
                                    connection: connection,
                                    onOpenTakeover: onOpenTakeover
                                )
                            }
                        } label: {
                            if openingTakeover {
                                HStack(spacing: OneDayMetrics.spacingS) {
                                    ProgressView()
                                    Text("正在读取桌面地址…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Label("打开全屏桌面接管", systemImage: "hand.tap.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.odPrimary)
                        .disabled(openingTakeover)
                    }
                    Button {
                        Task { await store.verify(id: connectionID, appState: appState) }
                    } label: {
                        Text("测试连接")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } header: {
                    SettingsSectionHeader("连接与控制")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                if connection.provider == "reverse_node",
                   let pairing = store.latestPairings[connectionID] {
                    Section {
                        Text(pairing.recommendedCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = pairing.recommendedCommand
                            Haptics.success()
                            copiedCommand = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copiedCommand = false
                            }
                        } label: {
                            Label(copiedCommand ? "已复制配对命令" : "复制一键配对命令", systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.odPrimary)
                    } header: {
                        SettingsSectionHeader("内网穿透配对命令")
                    } footer: {
                        Text("在 NAT 机或内网电脑终端运行此命令，无需公网 IP 或开放端口即可反向回连。")
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                }

                Section {
                    HStack {
                        Text("凭据")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(connection.configured == true ? "已配置" : "未配置")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Button {
                        store.resetCredentialPhase()
                        showCredentialForm = true
                    } label: {
                        HStack {
                            Text(connection.configured == true ? "更换凭据" : "配置凭据")
                                .foregroundStyle(Palette.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                } header: {
                    SettingsSectionHeader("凭据与密钥")
                } footer: {
                    Text("密钥与密码仅加密保存于你的服务端，App 端永不回传明文。")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)

                Section {
                    Button("断开这台主机", role: .destructive) {
                        pendingDisconnect = true
                    }
                    if canDelete {
                        Button("删除这台主机", role: .destructive) {
                            pendingDelete = true
                        }
                    }
                } footer: {
                    Text(connection.provider == "simular_box"
                        ? "断开会清除本服务端保存的密钥；厂商侧密钥请到厂商控制台吊销。"
                        : "断开或删除会立即清除服务端保存的登录凭据与私钥。")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            } else {
                Section {
                    Text("这台主机的记录已经不在了。")
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            if let notice = store.notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("主机详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: connection?.id) {
            guard connection?.provider == "simular_box",
                  connection?.configured == true else { return }
            await boxStore.refreshStatus(appState: appState)
            if boxStore.status?.isRunning == true {
                await boxStore.refreshScreenshot(appState: appState)
            }
        }
        .sheet(isPresented: $showCredentialForm) {
            if let connection {
                NavigationStack {
                    Form {
                        Section {
                            CredentialFormView(
                                store: store, connection: connection
                            ) {
                                showCredentialForm = false
                            }
                        } footer: {
                            Text("密钥与密码仅加密保存于你的服务端，App 端永不回传明文。")
                        }
                    }
                    .navigationTitle("凭据与密钥")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showCredentialForm = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(
            "断开这台主机？",
            isPresented: $pendingDisconnect,
            titleVisibility: .visible
        ) {
            Button("断开", role: .destructive) {
                Task { await store.disconnect(id: connectionID, appState: appState) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("智能体将不能再使用这台主机，直到重新填写凭据。")
        }
        .confirmationDialog(
            "删除这台主机？",
            isPresented: $pendingDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    if await store.deleteComputer(id: connectionID, appState: appState) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除该主机记录及其保存的密钥或密码。")
        }
    }

    /// 打开接管前先经盒子桥现拉一次状态取真实桌面
    /// 地址：连接记录与服务端载荷都没有 view 地址
    /// 与 box 标识，真实地址只在 box_status 里。
    /// 「box」连接与盒子桥同钥同盒——提交凭据时服务
    /// 端把密钥写入 MCP_BOX_API_KEY、客户端同步写
    /// 入 Keychain box.mcp.key，box_status 无参返回
    /// 的正是这台盒子的 box_id / view_url（与电脑面
    /// 状态头同一条取数路）。取到才打开；取不到就
    /// 不打开，把人话原因留在本页提示行，不许再传
    /// 空地址进去静默卡在连接中。盒子未运行时
    /// view_url 可能为空，此时 boxID 已是真值、
    /// 地址如实为空，接管页会按既有通路切直控面
    /// 唤醒出画面（与电脑面状态头的接管口径一致）。
    @ViewBuilder
    private func desktopPreviewCard(connection: CompanionConnection) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            if let shot = boxStore.screenshot,
               let data = shot.imageData,
               let uiImage = UIImage(data: data) {
                Button {
                    if let onOpenTakeover {
                        Task {
                            await openTakeover(
                                connection: connection,
                                onOpenTakeover: onOpenTakeover
                            )
                        }
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(shot.aspect, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                                    .stroke(Palette.separator.opacity(0.4), lineWidth: 0.5)
                            )
                        if let onOpenTakeover {
                            let _ = onOpenTakeover
                            Label("全屏接管", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Palette.primary)
                        .frame(width: 40, height: 40)
                        .background(Palette.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boxStore.hubState.statusLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        if let status = boxStore.status {
                            Text(status.pageTitleText)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if boxStore.screenshotLoading {
                        ProgressView()
                    } else {
                        Button("刷新画面") {
                            Task { await boxStore.refreshScreenshot(appState: appState) }
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
            }
        }
    }

    private func openTakeover(
        connection: CompanionConnection,
        onOpenTakeover: (CloudComputerTarget) -> Void
    ) async {
        openingTakeover = true
        defer { openingTakeover = false }
        await boxStore.refreshStatus(appState: appState)
        switch boxStore.hubState {
        case .ready(let status):
            onOpenTakeover(CloudComputerTarget(
                id: status.boxId ?? connection.id,
                boxID: status.boxId,
                liveURL: status.viewUrl ?? ""
            ))
        case .bridgeUnavailable:
            store.notice = L10n.string(
                "这台手机上还没存云电脑密钥，请在本页重新填写一次凭据再接管。"
            )
        case .failed, .loading:
            store.notice = L10n.string("云电脑状态没读出来，请稍后再试。")
        }
    }

    private func authLabel(_ auth: String) -> String {
        switch auth {
        case "ssh_key": return "SSH 密钥"
        case "password": return "密码"
        case "reverse_token": return "反向节点令牌"
        default: return auth
        }
    }
}

/// 凭据表单（托管云电脑 / Linux & Windows VPS / NAT 机 / 内网穿透节点）
struct CredentialFormView: View {
    var store: ConnectionsStore
    let connection: CompanionConnection
    var onVerified: () -> Void

    @Environment(AppState.self) private var appState
    // Simular Box
    @State private var apiKey = ""
    @State private var mcpUrl = ""
    // VPS / NAT
    @State private var osType = "linux"
    @State private var host = ""
    @State private var portText = "22"
    @State private var username = "root"
    @State private var authType = "ssh_key"
    @State private var privateKey = ""
    @State private var password = ""
    // SSH Keygen
    @State private var keygenReceipt: SSHKeygenReceipt?
    @State private var generatingKey = false
    @State private var copiedKeyCmd = false

    private var isVPS: Bool {
        connection.provider == "vps_ssh" || connection.provider == "vps_agent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            if connection.configured == true {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.successText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已保存加密凭据（••••••••）")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        Text("出于安全考虑不回显明文；下方填写新值并保存即可替换。")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(OneDayMetrics.spacingSM)
                .background(Palette.tintGreen.opacity(0.6), in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous))
            }

            if connection.provider == "reverse_node" {
                Picker("目标系统", selection: $osType) {
                    Text("Linux / macOS").tag("linux")
                    Text("Windows").tag("windows")
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await resetReversePairing() }
                } label: {
                    HStack {
                        Text("重新生成配对命令")
                        Spacer()
                        if store.credentialPhase.isBusy { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.odPrimary)
                .disabled(store.credentialPhase.isBusy)
            } else if isVPS {
                Picker("系统类型", selection: $osType) {
                    Text("Linux").tag("linux")
                    Text("Windows").tag("windows")
                }
                .pickerStyle(.segmented)
                .onChange(of: osType) { _, newOS in
                    if newOS == "windows" {
                        if username == "root" { username = "Administrator" }
                        if portText == "22" && authType == "password" { portText = "5985" }
                    } else {
                        if username == "Administrator" { username = "root" }
                        if portText == "5985" || portText == "3389" { portText = "22" }
                    }
                }

                TextField("主机 / IP（支持 NAT 域名）", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                HStack(spacing: OneDayMetrics.spacingS) {
                    TextField("端口（NAT 填映射端口）", text: $portText)
                        .keyboardType(.numberPad)
                        .frame(width: 140)
                    TextField(osType == "windows" ? "用户名（Administrator）" : "用户名（root）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Picker("认证方式", selection: $authType) {
                    Text("SSH 密钥（推荐）").tag("ssh_key")
                    Text("密码").tag("password")
                }
                .pickerStyle(.segmented)
                .onChange(of: authType) { _, newAuth in
                    if newAuth == "ssh_key", portText == "5985" || portText == "3389" {
                        portText = "22"
                    } else if newAuth == "password", osType == "windows", portText == "22" {
                        portText = "5985"
                    }
                }

                if authType == "ssh_key" {
                    Button {
                        Task { await generateKeypair() }
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                            Text(keygenReceipt == nil ? "一键生成 Ed25519 密钥对（推荐）" : "重新生成密钥对")
                            Spacer()
                            if generatingKey { ProgressView() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(generatingKey)

                    if let receipt = keygenReceipt {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("已生成私钥并安全保存在服务端。在你的 VPS/NAT 机执行以下命令写入公钥，再点下方保存测试：")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                            Text(receipt.installCommand)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 8))
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = receipt.installCommand
                                Haptics.success()
                                copiedKeyCmd = true
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    copiedKeyCmd = false
                                }
                            } label: {
                                Label(copiedKeyCmd ? "已复制公钥写入命令" : "复制公钥写入命令", systemImage: copiedKeyCmd ? "checkmark" : "doc.on.doc")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text("或直接粘贴已有 SSH 私钥（可选，留空则使用上面生成的私钥）：")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                    TextEditor(text: $privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 84, maxHeight: 130)
                        .padding(6)
                        .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("登录密码", text: $password)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Text("保存并测试连接")
                        Spacer()
                        if store.credentialPhase.isBusy { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.odPrimary)
                .disabled(store.credentialPhase.isBusy || !inputReady)
            } else {
                SecureField("API 密钥（Simular Box Key）", text: $apiKey)
                TextField("自定义 MCP 地址（可选，默认官方）", text: $mcpUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Text("保存并测试连接")
                        Spacer()
                        if store.credentialPhase.isBusy { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.odPrimary)
                .disabled(store.credentialPhase.isBusy || !inputReady)
            }

            switch store.credentialPhase {
            case .verified(let detail):
                Text("已连上：\(detail)")
                    .font(.footnote)
                    .foregroundStyle(Palette.successText)
            case .failed(let detail):
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            case .idle, .submitting:
                EmptyView()
            }
        }
        .padding(.vertical, OneDayMetrics.spacingS)
        .onAppear {
            prefillFromMeta()
        }
    }

    private func prefillFromMeta() {
        if let meta = connection.meta {
            if let h = meta.host, host.isEmpty { host = h }
            if let p = meta.port { portText = "\(p)" }
            if let u = meta.username, !u.isEmpty { username = u }
            if let os = meta.osType, !os.isEmpty { osType = os }
            if let auth = meta.authType, auth == "ssh_key" || auth == "password" { authType = auth }
            if let mcp = meta.mcpUrl, mcpUrl.isEmpty { mcpUrl = mcp }
        }
    }

    private var parsedPort: Int? {
        guard let p = Int(portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(p) else {
            return nil
        }
        return p
    }

    private var inputReady: Bool {
        if isVPS {
            guard WindowsLoginInput.isValidHost(host),
                  parsedPort != nil,
                  !username.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            if authType == "ssh_key" {
                return !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || keygenReceipt != nil
                    || connection.meta?.publicKey != nil
            }
            return !password.isEmpty
        }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    private func generateKeypair() async {
        generatingKey = true
        defer { generatingKey = false }
        if let receipt = await store.generateSSHKeypair(id: connection.id, appState: appState) {
            keygenReceipt = receipt
            Haptics.success()
        }
    }

    private func resetReversePairing() async {
        await store.submitCredential(
            id: connection.id,
            body: ["osType": .string(osType)],
            appState: appState
        )
        if case .verified = store.credentialPhase {
            onVerified()
        }
    }

    private func submit() async {
        let body: [String: JSONValue]
        if isVPS {
            let port = parsedPort ?? (osType == "windows" && authType == "password" ? 5985 : 22)
            body = ConnectionPayloads.vpsHostCredential(
                host: host.trimmingCharacters(in: .whitespaces),
                port: port,
                username: username.trimmingCharacters(in: .whitespaces),
                osType: osType,
                authType: authType,
                privateKey: authType == "ssh_key" ? privateKey.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                password: authType == "password" ? password : nil
            )
        } else {
            body = ConnectionPayloads.simularCredential(
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                mcpUrl: mcpUrl
            )
        }
        await store.submitCredential(
            id: connection.id, body: body, appState: appState
        )
        if case .verified = store.credentialPhase {
            if connection.provider == "simular_box" {
                KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "box.mcp.key")
                BoxMCPClientFactory.reset()
            }
            onVerified()
        }
    }
}

/// 添加云电脑 / VPS / NAT 机 / 内网穿透节点向导
struct AddComputerView: View {
    var store: ConnectionsStore

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var provider = "simular_box"
    @State private var osType = "linux"
    @State private var name = ""
    @State private var created: CompanionConnection?
    @State private var isCreating = false
    @State private var problem: String?
    @State private var copiedPairing = false

    var body: some View {
        NavigationStack {
            Form {
                if created == nil {
                    Section {
                        providerRow(
                            value: "simular_box",
                            title: "托管云电脑（Simular Box）",
                            detail: "自带图形桌面与浏览器，填 API 密钥即可在聊天内实时接管"
                        )
                        providerRow(
                            value: "vps_ssh",
                            title: "VPS / NAT 主机（Linux & Windows）",
                            detail: "支持公网 IP、NAT 端口映射，支持 SSH 密钥（推荐）或密码"
                        )
                        providerRow(
                            value: "reverse_node",
                            title: "内网穿透节点（无公网端口 NAT / 家用电脑）",
                            detail: "生成一条配对命令在目标机器运行，主动反向回连、免开端口"
                        )
                    } header: {
                        Text("接入方式")
                    }

                    if provider == "vps_ssh" || provider == "reverse_node" {
                        Section {
                            Picker("操作系统", selection: $osType) {
                                Text("Linux").tag("linux")
                                Text("Windows").tag("windows")
                            }
                            .pickerStyle(.segmented)
                        } header: {
                            Text("系统")
                        }
                    }

                    Section {
                        TextField(namePlaceholder, text: $name)
                    } header: {
                        Text("主机名称")
                    }

                    if let problem {
                        Section {
                            Text(problem)
                                .font(.callout)
                                .foregroundStyle(Palette.danger)
                        }
                    }

                    Section {
                        Button {
                            Task { await create() }
                        } label: {
                            HStack {
                                Text(provider == "reverse_node" ? "生成配对命令" : "下一步：配置凭据")
                                Spacer()
                                if isCreating { ProgressView() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.odPrimary)
                        .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else if let created {
                    if created.provider == "reverse_node",
                       let pairing = store.latestPairings[created.id] {
                        Section {
                            Text("「\(created.name)」已创建。复制下方命令到目标机器终端运行即可自动上线：")
                                .font(.callout)
                                .foregroundStyle(Palette.inkSecondary)
                            Text(pairing.recommendedCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = pairing.recommendedCommand
                                Haptics.success()
                                copiedPairing = true
                            } label: {
                                Label(copiedPairing ? "已复制命令" : "复制一键配对命令", systemImage: copiedPairing ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.odPrimary)
                        } header: {
                            Text("配对命令")
                        }
                        Section {
                            Button("完成") { dismiss() }
                        }
                    } else {
                        Section {
                            Text("「\(created.name)」已建好，填写连接凭据并测试连通后即生效。")
                                .font(.callout)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Section {
                            CredentialFormView(
                                store: store, connection: created
                            ) {
                                dismiss()
                            }
                        } header: {
                            Text("凭据与验活")
                        }
                        Section {
                            Button("稍后再填") { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("添加远程主机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fullscreenPopBridge()
    }

    private var namePlaceholder: String {
        switch provider {
        case "simular_box": return "主机名（如：我的云电脑）"
        case "reverse_node": return "节点名（如：家里电脑 / 内网 NAT）"
        default: return osType == "windows" ? "主机名（如：香港 Windows VPS）" : "主机名（如：香港 NAT Linux）"
        }
    }

    private func providerRow(
        value: String, title: String, detail: String
    ) -> some View {
        Button {
            provider = value
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                if provider == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        store.resetCredentialPhase()
        let selectedOS: String? = (provider == "vps_ssh" || provider == "reverse_node") ? osType : nil
        let created = await store.createComputer(
            provider: provider,
            name: name.trimmingCharacters(in: .whitespaces),
            osType: selectedOS,
            appState: appState
        )
        if let created {
            self.created = created
            problem = nil
        } else {
            problem = store.notice ?? "没能加上，请稍后再试。"
        }
    }
}
