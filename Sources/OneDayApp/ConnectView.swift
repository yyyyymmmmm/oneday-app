import OneDayDesign
import OneDayCore
import SwiftUI

/// 首次启动连接页：填服务器地址、面板账号密码、API 密钥，
/// 「测试并连接」跑三步探活，全过才进主界面（凭据落 Keychain
/// 在 AppState.connect 内、且只在全过后落）。
struct ConnectView: View {
    @Environment(AppState.self) private var appState

    @State private var serverText = "https://hermes.didichou.site"
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""

    private enum StepState {
        case active
        case done
        case failed
    }

    @State private var stepStates: [ProbeStep: StepState] = [:]
    @State private var currentStep: ProbeStep?
    @State private var isProbing = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isProbing
            && !serverText.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.isEmpty
            && !password.isEmpty
            && !apiKey.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                brandBlock
                formCard
                if !stepStates.isEmpty {
                    probeCard
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(Palette.danger)
                }
                Button("测试并连接") {
                    Task { await submit() }
                }
                .buttonStyle(.odPrimary)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
                Text("凭据只存这台手机的钥匙串，不经过任何第三方。服务器需为 Hermes v0.23.0。")
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)
            }
            .padding(OneDayMetrics.spacingL)
        }
        .background(Palette.pageBG)
    }

    // MARK: - 区块

    private var brandBlock: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Palette.primaryFill)
                .frame(width: 52, height: 52)
                .overlay(
                    Text("1")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("OneDay")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text("连接你的 Hermes 服务器")
                    .font(.subheadline)
                    .foregroundStyle(Palette.sub)
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            field(label: "服务器地址") {
                TextField("https://hermes.didichou.site", text: $serverText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field(label: "面板账号") {
                TextField("Dashboard 用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field(label: "面板密码") {
                SecureField("Dashboard 密码", text: $password)
            }
            field(label: "API 密钥") {
                SecureField("API Server 的密钥", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .odCard()
    }

    private func field<Content: View>(
        label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.sub)
            content()
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .background(
                    Palette.pageBG,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.controlCorner)
                )
        }
    }

    private var probeCard: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            ForEach(ProbeStep.allCases, id: \.rawValue) { step in
                HStack(spacing: OneDayMetrics.spacingS) {
                    stepIcon(step)
                    Text(step.label)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if stepStates[step] == .done {
                        Text("通过")
                            .font(.caption)
                            .foregroundStyle(Palette.success)
                    } else if stepStates[step] == .failed {
                        Text("失败")
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
        }
        .odCard()
    }

    @ViewBuilder
    private func stepIcon(_ step: ProbeStep) -> some View {
        switch stepStates[step] {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Palette.danger)
        case .active:
            ProgressView()
                .frame(width: 18, height: 18)
        case nil:
            Image(systemName: "circle")
                .foregroundStyle(Palette.sub)
        }
    }

    // MARK: - 提交

    private func submit() async {
        errorMessage = nil
        stepStates = [:]
        currentStep = nil
        guard let config = ServerConfig(rawInput: serverText) else {
            errorMessage = HermesError.invalidServerAddress.userMessage
            return
        }
        isProbing = true
        defer { isProbing = false }
        do {
            try await appState.connect(
                config: config,
                username: username,
                password: password,
                apiKey: apiKey
            ) { step in
                if let current = currentStep {
                    stepStates[current] = .done
                }
                currentStep = step
                stepStates[step] = .active
            }
            for step in ProbeStep.allCases {
                stepStates[step] = .done
            }
        } catch {
            if let current = currentStep {
                stepStates[current] = .failed
            }
            errorMessage = (error as? HermesError)?.userMessage ?? "连接失败，请稍后再试。"
        }
    }
}
