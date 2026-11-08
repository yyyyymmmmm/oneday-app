import OneDayDesign
import OneDayCore
import SwiftUI

/// 设置：服务器信息、重测连接、断开连接、关于。
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var isRetesting = false
    @State private var retestResult: String?
    @State private var retestFailed = false
    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("服务器") {
                    infoRow(label: "地址", value: appState.config?.baseString ?? "—")
                    infoRow(label: "面板账号", value: appState.username ?? "—")
                    infoRow(label: "对话模型", value: appState.modelID)
                }
                Section("连接") {
                    Button {
                        Task { await retest() }
                    } label: {
                        HStack {
                            Text("重新测试连接")
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if isRetesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRetesting)
                    if let retestResult {
                        Text(retestResult)
                            .font(.footnote)
                            .foregroundStyle(retestFailed ? Palette.danger : Palette.success)
                    }
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Text("断开连接")
                    }
                }
                Section("关于") {
                    infoRow(label: "OneDay 版本", value: "0.1.0（里程碑 1）")
                    infoRow(label: "服务端要求", value: "Hermes v0.23.0")
                    Text("OneDay 只与你自己的服务器通信；凭据存本机钥匙串，聊天记录存本机。")
                        .font(.footnote)
                        .foregroundStyle(Palette.sub)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG)
            .navigationTitle("设置")
            .confirmationDialog(
                "断开连接？",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("断开连接", role: .destructive) {
                    appState.disconnect()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除这台手机上保存的服务器凭据与登录会话。本地聊天记录保留。")
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value)
                .foregroundStyle(Palette.sub)
                .textSelection(.enabled)
        }
    }

    private func retest() async {
        isRetesting = true
        retestResult = nil
        defer { isRetesting = false }
        do {
            try await appState.retestConnection()
            retestFailed = false
            retestResult = "连接正常：健康检查、登录、API 密钥三步全过。"
        } catch {
            retestFailed = true
            retestResult = (error as? HermesError)?.userMessage ?? "连接失败。"
        }
    }
}
