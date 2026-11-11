import OneDayDesign
import OneDayCore
import SwiftUI

/// 欢迎/连接页（0.6.0 直登版，用户拍板学 OpenMuse 欢迎
/// 页版式）：三狗吉祥物＋中文一句话＋一张卡（服务器地址
/// 框＋密钥框）＋一个大连接钮。地址预填
/// https://hermes.didichou.site 可改；密钥＝Hermes 的
/// Bearer（API 密钥）。校验走 AppState.connectDirect 两
/// 步（健康检查→验证密钥），全过才进五格、才落
/// Keychain。面板账号/密码自此退出连接页（存量四件套
/// 仍可被恢复与重测兼容，见 AppState.restore）；改址/
/// 换钥在设置页「当前服务器」走同一 connectDirect。
/// write-gate 钥匙不在本页（维持 0.5.0 设置页粘贴字段）。
struct ConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var serverText = "https://hermes.didichou.site"
    @State private var apiKey = ""

    // 连接页演示态（-odDemoConnect）：预填值全是占位假串，
    // 不含任何真实凭据（赋值在 onAppear）。演示态安全行
    // 不用 SecureField 而用等长圆点文本占位：0.1.3 三轮
    // 截图实证——程序化给 SecureField 赋的值在模拟器里
    // 不渲染圆点且行高异常，生产路径是用户手输、不经
    // 过程化赋值，不受此缺陷影响（见 DESIGN-V2 §7.3）。

    private enum Field: Hashable {
        case server, apiKey
    }

    @FocusState private var focusedField: Field?
    @State private var appeared = false

    private enum StepState {
        case active
        case done
        case failed
    }

    /// 直登只两步：健康检查、验证密钥（面板登录步随四
    /// 件套退出本页）
    private static let steps: [ProbeStep] = [.health, .apiKey]

    @State private var stepStates: [ProbeStep: StepState] = [:]
    @State private var currentStep: ProbeStep?
    @State private var isProbing = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isProbing
            && !serverText.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandBlock
                    .frame(maxWidth: .infinity)
                    .padding(.top, OneDayMetrics.spacingXXL)
                formGroup
                    .padding(.top, OneDayMetrics.spacingXL)
                if !stepStates.isEmpty {
                    probeGroup
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                Button("连接") {
                    Task { await submit() }
                }
                .buttonStyle(.odPrimary)
                .disabled(!canSubmit)
                .padding(.top, OneDayMetrics.spacingXL)
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
                apiKey = "demo-api-key"
            }
            withAnimation(MotionTokens.resolved(MotionTokens.entrance, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }

    // MARK: - 区块

    private var brandBlock: some View {
        // 版式对照 OpenMuse 欢迎页：吉祥物居中大图＋标题
        // ＋一句话；吉祥物换三狗搭档款定版图（SangouPartner
        // 资产，源 ip-design/STYLE-partner.webp 裁头）
        VStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
            Image("SangouPartner")
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                }
                .accessibilityHidden(true)
            Text("欢迎来到 OneDay")
                .font(.title)
                .foregroundStyle(Palette.ink)
                .padding(.top, OneDayMetrics.spacingS)
            Text("你的 Hermes，随时在身边。")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            // §155 三层命名定案：连接页当场把分工讲清
            // ——OneDay 是客户端、Hermes 是你部署的服
            // 务端、智能体的名字跟服务器人设走，免得
            // 连上后屏上名一变用户以为换了产品
            Text("OneDay 是客户端，连接你自己部署的 Hermes 服务；智能体的名字以服务器上的人设为准。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, OneDayMetrics.spacingS)
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
            GroupDivider()
            FieldRow(label: "密钥", isActive: focusedField == .apiKey) {
                if DemoMode.current == .connectPage {
                    // 演示占位：与假串等长的圆点（理由见文件头注释）
                    Text(String(repeating: "•", count: 12))
                } else {
                    SecureField("Hermes 的 Bearer 密钥", text: $apiKey)
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
            ForEach(Array(Self.steps.enumerated()), id: \.element.rawValue) { index, step in
                if index > 0 {
                    GroupDivider()
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    stepIcon(step)
                        .frame(width: 18, alignment: .center)
                    Text(step.label)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if stepStates[step] == .done {
                        Text("通过")
                            .font(.footnote)
                            .foregroundStyle(Palette.success)
                    } else if stepStates[step] == .failed {
                        Text("失败")
                            .font(.footnote)
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
            // 结果触感：失败 .error（0.36.2 表 D 归位）
            Haptics.error()
            return
        }
        isProbing = true
        defer { isProbing = false }
        do {
            try await appState.connectDirect(
                config: config,
                apiKey: apiKey
            ) { step in
                if let current = currentStep {
                    stepStates[current] = .done
                }
                currentStep = step
                stepStates[step] = .active
            }
            for step in Self.steps {
                stepStates[step] = .done
            }
            // 结果触感（0.3.2 纪律）：连接成功 .success
            Haptics.success()
        } catch {
            if let current = currentStep {
                stepStates[current] = .failed
            }
            errorMessage = (error as? HermesError)?.userMessage ?? "连接失败，请稍后再试。"
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
        }
    }
}
