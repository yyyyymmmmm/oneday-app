import SwiftUI
import OneDayDesign

/// 连接页（对位表第 12 件的 Mac 落点）：地址＋面板密
/// 码一步制，与 iOS 连接页同口径——只问这两样，凭据
/// 进 Keychain，不落任何文件。地基棒只做连接本身，
/// 扫码配对（第 76/94 件等价路）不在本棒。
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var address = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            header
            form
            if let error = session.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(40)
        .frame(width: 460)
        .frame(minHeight: 520)
        .background(Palette.pageBG)
        .onAppear {
            if address.isEmpty,
               let saved = MacKeychain.read(
                   account: MacCredentialKey.baseURL
               ) {
                address = saved
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(Palette.inkSecondary)
            Text("OneDay")
                .font(.largeTitle.bold())
            Text("连接你的 Hermes 服务器，开始在 Mac 上用 OneDay。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("服务器地址")
                    .font(.headline)
                TextField("如 hermes.example.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(session.isConnecting)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("面板密码")
                    .font(.headline)
                SecureField("服务器面板的登录密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(session.isConnecting)
                    .onSubmit(connect)
            }
            Button(action: connect) {
                HStack(spacing: 8) {
                    if session.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(connectButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(
                session.isConnecting
                    || address.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    || password.isEmpty
            )
        }
    }

    private var footer: some View {
        Text("密码只用于向你的服务器验证身份，换回的登录密钥保存在本机钥匙串里。")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private var connectButtonTitle: String {
        if case .connecting(let step) = session.phase {
            return step
        }
        return "连接"
    }

    private func connect() {
        guard !session.isConnecting else { return }
        Task {
            await session.connectWithPassword(
                address: address, password: password
            )
        }
    }
}
