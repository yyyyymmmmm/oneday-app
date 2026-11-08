import OneDayDesign
import OneDayCore
import SwiftUI

/// 首次启动连接页：填服务器地址、面板账号密码、API 密钥，
/// 「测试并连接」跑三步探活，全过才进主界面（凭据落 Keychain
/// 在 AppState.connect 内、且只在全过后落）。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：字标裸排、字段走分组行式、
/// 探活是安静清单、主按钮是全屏唯一的蓝色时刻。
struct ConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var serverText = "https://hermes.didichou.site"
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""

    // 连接页演示态（-odDemoConnect）：预填值全是占位假串，
    // 账号只写 admin，不含任何真实凭据（赋值在 onAppear）。
    // 演示态两个安全行不用 SecureField 而用等长圆点文本占位：
    // 0.1.3 三轮截图实证——程序化给 SecureField 赋的值在模拟器
    // 里不渲染圆点且行高异常（init 预填 / onAppear 同帧 /
    // 延迟 400ms 三种赋值时机全中），而生产路径是用户手输、
    // 不经过程序化赋值，不受此缺陷影响（见 DESIGN-V2 §7.3）。

    private enum Field: Hashable {
        case server, username, password, apiKey
    }

    @FocusState private var focusedField: Field?
    @State private var appeared = false

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
            VStack(alignment: .leading, spacing: 0) {
                brandBlock
                    .padding(.top, OneDayMetrics.spacingXXL)                formGroup
                    .padding(.top, OneDayMetrics.spacingXL)
                if !stepStates.isEmpty {
                    probeGroup
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                Button("测试并连接") {
                    Task { await submit() }
                }
                .buttonStyle(.odPrimary)
                .disabled(!canSubmit)
                .padding(.top, OneDayMetrics.spacingXL)
                Text("凭据只存这台手机的钥匙串，不经过任何第三方。服务器需为 Hermes v0.23.0。")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, OneDayMetrics.spacingM)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.bottom, OneDayMetrics.spacingL)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.pageBG)
        .onAppear {
            if DemoMode.current == .connectPage {
                // 演示预填：值只供 canSubmit 与演示探活消费；
                // 安全行的可见形态是等长圆点占位（见文件头注释）
                username = "admin"
                password = "demo-password"
                apiKey = "demo-api-key"
            }
            withAnimation(MotionTokens.resolved(MotionTokens.entrance, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }

    // MARK: - 区块

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text("OneDay")
                .font(TypeScale.display)
                .foregroundStyle(Palette.ink)
            Text("连接你的 Hermes 服务器")
                .font(TypeScale.subhead)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var formGroup: some View {
        VStack(spacing: 0) {
            FieldRow(label: "服务器地址", isActive: focusedField == .server) {
                TextField("https://hermes.didichou.site", text: $serverText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .server)
            }
            GroupDivider(inset: OneDayMetrics.spacingM)
            FieldRow(label: "面板账号", isActive: focusedField == .username) {
                TextField("Dashboard 用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
            }
            GroupDivider(inset: OneDayMetrics.spacingM)
            FieldRow(label: "面板密码", isActive: focusedField == .password) {
                if DemoMode.current == .connectPage {
                    // 演示占位：与假串等长的圆点（理由见文件头注释）
                    Text(String(repeating: "•", count: 13))
                } else {
                    SecureField("Dashboard 密码", text: $password)
                        .focused($focusedField, equals: .password)
                }
            }
            GroupDivider(inset: OneDayMetrics.spacingM)
            FieldRow(label: "API 密钥", isActive: focusedField == .apiKey) {
                if DemoMode.current == .connectPage {
                    Text(String(repeating: "•", count: 12))
                } else {
                    SecureField("API Server 的密钥", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .apiKey)
                }
            }
        }
        .odGroup()
    }

    private var probeGroup: some View {
        VStack(spacing: 0) {
            ForEach(Array(ProbeStep.allCases.enumerated()), id: \.element.rawValue) { index, step in
                if index > 0 {
                    GroupDivider(inset: 42)
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    stepIcon(step)
                        .frame(width: 18, alignment: .center)
                    Text(step.label)
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if stepStates[step] == .done {
                        Text("通过")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.success)
                    } else if stepStates[step] == .failed {
                        Text("失败")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.minTapTarget)
            }
        }
        .odGroup()
    }

    @ViewBuilder
    private func stepIcon(_ step: ProbeStep) -> some View {
        switch stepStates[step] {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.danger)
        case .active:
            ProgressView()
                .frame(width: 18, height: 18)
        case nil:
            Image(systemName: "circle")
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkMuted)
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
