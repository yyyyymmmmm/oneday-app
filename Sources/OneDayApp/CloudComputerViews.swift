import OneDayDesign
import OneDayCore
import SwiftUI

/// 云电脑详情（0.37.0 接入层，cloud-computer 规格
/// §6.2 的连接面部分）：状态与验活记录如实呈现、凭
/// 据只报「已配置/未配置」、更换凭据与断开在此办。
/// 能力面（画面/终端/文件）是另一层：托管 Box 的电
/// 脑页已存在，VPS 的能力面随服务端电脑通用面落
/// 地，本页不假装有入口。
struct CloudComputerDetailView: View {
    var store: ConnectionsStore
    let connectionID: String

    @Environment(AppState.self) private var appState
    @State private var showCredentialForm = false
    @State private var pendingDisconnect = false

    private var connection: CompanionConnection? {
        store.connections.first { $0.id == connectionID }
    }

    var body: some View {
        List {
            if let connection {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.name)
                            .font(.title3)
                            .foregroundStyle(Palette.ink)
                        Text(connection.providerWording)
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, OneDayMetrics.spacingS)
                }
                Section {
                    let status = ConnectionStatusWording.evaluate(connection)
                    HStack {
                        Text("状态")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(status.text)
                            .foregroundStyle(
                                status.tone == .ok ? Palette.success
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
                    Button {
                        Task { await store.verify(id: connectionID, appState: appState) }
                    } label: {
                        Text("测试连接")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.odPrimary)
                } header: {
                    Text("连接")
                }
                Section {
                    HStack {
                        Text("凭据")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(connection.configured == true ? "已配置" : "未配置")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Button(showCredentialForm ? "收起" : "填写 / 更换凭据") {
                        showCredentialForm.toggle()
                    }
                    if showCredentialForm {
                        CredentialFormView(
                            store: store, connection: connection
                        ) {
                            showCredentialForm = false
                        }
                    }
                } header: {
                    Text("凭据")
                } footer: {
                    Text("凭据只发给你的服务端保存，App 不留存；这里也读不出已保存的值。")
                }
                Section {
                    Button("断开这台电脑", role: .destructive) {
                        pendingDisconnect = true
                    }
                } footer: {
                    Text(connection.provider == "vps_agent"
                        ? "断开只摘掉这边的登记与凭据；VPS 上的代理程序要用它自带的卸载命令才算全清。"
                        : "断开只摘掉这边的凭据；厂商那边的密钥请到厂商处吊销。")
                }
            } else {
                Section {
                    Text("这台电脑的记录已经不在了。")
                        .foregroundStyle(Palette.inkSecondary)
                }
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
        .background(Palette.settingsBG)
        .navigationTitle("云电脑")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "断开这台电脑？",
            isPresented: $pendingDisconnect,
            titleVisibility: .visible
        ) {
            Button("断开", role: .destructive) {
                Task { await store.disconnect(id: connectionID, appState: appState) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("智能体将不能再用这台电脑，直到重新填写凭据。")
        }
    }
}

/// 凭据表单（添加流与详情更换共用）：按 provider 分
/// 型——托管类只有密钥一格（端点是已知常量，不让用
/// 户填，规格 §3.1）；VPS 类地址＋令牌，另支持整串
/// 粘贴自动拆分（§3.2）。提交后验活结果由 store 的
/// 状态机回显（成/败都带服务端人话，失败含回滚说明）。
struct CredentialFormView: View {
    var store: ConnectionsStore
    let connection: CompanionConnection
    var onVerified: () -> Void

    @Environment(AppState.self) private var appState
    @State private var apiKey = ""
    @State private var endpointUrl = ""
    @State private var token = ""
    @State private var configString = ""

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            if connection.provider == "vps_agent" {
                TextField("配置串（可整串粘贴，自动拆分）", text: $configString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: configString) { _, newValue in
                        if let parsed = ConnectionPayloads.parseConfigString(newValue) {
                            endpointUrl = parsed.endpointUrl
                            token = parsed.token
                        }
                    }
                TextField("电脑地址（如 https://…/mcp）", text: $endpointUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("令牌", text: $token)
                if endpointUrl.hasPrefix("http://"),
                   !endpointUrl.hasPrefix("http://127."),
                   !endpointUrl.contains("100.") {
                    Text("提醒：这是公网明文地址，令牌等于这台电脑的钥匙，明文传输有被截获的风险；建议用私网地址或带 https 的地址。")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            } else {
                SecureField("API 密钥", text: $apiKey)
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Text("保存并测试连接")
                    Spacer()
                    if store.credentialPhase.isBusy {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.odPrimary)
            .disabled(store.credentialPhase.isBusy || !inputReady)
            switch store.credentialPhase {
            case .verified(let detail):
                Text("已连上：\(detail)")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            case .failed(let detail):
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            case .idle, .submitting:
                EmptyView()
            }
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    private var inputReady: Bool {
        if connection.provider == "vps_agent" {
            return ConnectionPayloads.isPlausibleEndpoint(endpointUrl)
                && !token.isEmpty
        }
        return apiKey.count >= 10
    }

    private func submit() async {
        let body: [String: JSONValue] = connection.provider == "vps_agent"
            ? ConnectionPayloads.vpsCredential(
                endpointUrl: endpointUrl.trimmingCharacters(in: .whitespaces),
                token: token
            )
            : ConnectionPayloads.simularCredential(apiKey: apiKey)
        await store.submitCredential(
            id: connection.id, body: body, appState: appState
        )
        if case .verified = store.credentialPhase {
            onVerified()
        }
    }
}

/// 添加电脑（0.37.0，规格 §6.4）：一屏选类型→名字
/// →建记录→就地填凭据验活→成功落详情。失败停在表
/// 单给人话，不产生半截记录之外的假象（记录是「未
/// 配置」态，如实可见、可继续填或断开删除）。
struct AddComputerView: View {
    var store: ConnectionsStore

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var provider = "simular_box"
    @State private var name = ""
    @State private var created: CompanionConnection?
    @State private var isCreating = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                if created == nil {
                    Section {
                        providerRow(
                            value: "simular_box", title: "托管云电脑",
                            detail: "Simular Box 这类自带服务的云端电脑，填密钥就能用"
                        )
                        providerRow(
                            value: "vps_agent", title: "我的 VPS",
                            detail: "自己的服务器，装好电脑代理后填地址与令牌"
                        )
                    } header: {
                        Text("类型")
                    }
                    Section {
                        TextField("电脑名字（如：我的 Box）", text: $name)
                    } header: {
                        Text("名字")
                    } footer: {
                        Text("跟智能体提这台电脑时，就用这个名字。")
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
                                Text("下一步：填凭据")
                                Spacer()
                                if isCreating { ProgressView() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.odPrimary)
                        .disabled(isCreating
                            || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else if let created {
                    Section {
                        Text("「\(created.name)」已建好，把凭据填上并测试连接就完成。")
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
                        Text("凭据")
                    }
                    Section {
                        Button("稍后再填") { dismiss() }
                    }
                }
            }
            .navigationTitle("添加电脑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
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
        let created = await store.createComputer(
            provider: provider,
            name: name.trimmingCharacters(in: .whitespaces),
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
