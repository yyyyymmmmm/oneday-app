import OneDayDesign
import OneDayCore
import SwiftUI

/// 引导线（欢迎／登录／连接中／成功／帮助五面，蓝本＝
/// 用户 2026-11-11 亲递原型 oneday-prototype.html；本版
/// 覆盖 0.6.0 直登单卡面貌）。与原型的口径差（定版优
/// 先）：①登录一步制——原型密码登录是「面板验证→再填
/// 密钥」两步，与「用户只持一把凭据」定版冲突，已改：
/// 密码（Hermes 面板账号＋密码）验证通过后由服务端
/// /api/env/reveal 下发登录密钥，App 一步连上（链路见
/// AppState.connectWithPassword）；密钥登录保留作后门
/// 单步。②连接中四步全部真检查、状态来自真实请求
/// （原型是定时演示动画）。③成功面数据全取本次实测、
/// 取不到不显示。
///
/// 出现时机：根层只在 phase == .needsConnection 呈现
/// 本面（首启未连接／断开后），已连接直进主界面，与
/// 现行连接态判定同口径。连接全过先落 Keychain 并停
/// 在成功面，「开始聊天」才 activatePreparedConnection
/// 进主界面。
struct ConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Page {
        case welcome, login, connecting, success, help
    }

    private enum LoginMode: String, CaseIterable {
        case password, key
    }

    private enum Field: Hashable {
        case server, username, password, apiKey
    }

    private enum StepState {
        case waiting, active, done, failed
    }

    @State private var page: Page = .welcome
    /// 帮助面的返回落点（欢迎/登录/失败面三处都能进帮助，
    /// 回去要回原处，不许一律弹回登录）
    @State private var helpReturn: Page = .login
    @State private var mode: LoginMode = .password
    @State private var serverText = "https://hermes.didichou.site"
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var revealSecret = false
    @State private var formError: String?
    @State private var stepStates: [OnboardingStep: StepState] = [:]
    @State private var failure: OnboardingFailure?
    @State private var serviceInfo: ConnectionServiceInfo?
    @State private var isConnecting = false
    @State private var appeared = false
    @FocusState private var focusedField: Field?

    private var canSubmit: Bool {
        guard !isConnecting,
              !serverText.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        switch mode {
        case .password: return !username.isEmpty && !password.isEmpty
        case .key: return !apiKey.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            Group {
                switch page {
                case .welcome: welcomePage
                case .login: loginPage
                case .connecting: connectingPage
                case .success: successPage
                case .help: helpPage
                }
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
                // 演示态预填全是占位假串、不含真实凭据
                username = "demo"
                password = "demo-password"
                apiKey = "demo-api-key"
            }
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.entrance, reduceMotion: reduceMotion
                )
            ) {
                appeared = true
            }
        }
    }

    // MARK: - 欢迎面

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                Text("你的智能体，随身继续。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                // 三层分工句：与命名包连接页同词条同文案
                Text("OneDay 是客户端，连接你自己部署的 Hermes 服务；智能体的名字以服务器上的人设为准。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, OneDayMetrics.spacingXXL)

            demoPreviewCard
                .padding(.top, OneDayMetrics.spacingXL)

            Button("开始连接") { page = .login }
                .buttonStyle(.odPrimary)
                .padding(.top, OneDayMetrics.spacingXL)
            Button("还没有服务器？先看看怎么部署") { helpReturn = .welcome; page = .help }
                .font(.callout)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text("凭据只保存在本机钥匙串")
                    .font(.caption)
            }
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity)
        }
    }

    /// 演示对话预览卡：明确标「对话预览」，内容是示例
    /// 文案、不冒充真实对话（原型 demo-card 同口径）。
    private var demoPreviewCard: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image("SangouPartner")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text(appState.agentDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("对话预览")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            GroupDivider()
            VStack(alignment: .trailing, spacing: OneDayMetrics.spacingS) {
                Text("帮我把这周的会议整理成一页纪要。")
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .background(
                        Palette.primaryPale,
                        in: RoundedRectangle(
                            cornerRadius: OneDayMetrics.fieldCorner,
                            style: .continuous
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                HStack(spacing: OneDayMetrics.spacingXS) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text(appState.agentDisplayName)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.primary)
                Text("已整理 6 场会议，冲突的周四已单独标出。")
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.fieldCorner,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.fieldCorner,
                    style: .continuous
                )
                .stroke(Palette.hairline, lineWidth: 0.5)
            }
            GroupDivider()
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(systemName: "clock")
                    .font(.caption)
                Text("任务在服务器上继续运行，锁屏也不中断")
                    .font(.caption)
            }
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(OneDayMetrics.spacingM)
        .odGroup()
    }

    // MARK: - 登录面

    private var loginPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton("欢迎") { page = .welcome }
            Text("连接你的服务器")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, OneDayMetrics.spacingS)
            Text("OneDay 不提供账号体系，你的数据只在你的服务器上。")
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)

            Picker("登录方式", selection: $mode) {
                Text("密码登录").tag(LoginMode.password)
                Text("密钥登录").tag(LoginMode.key)
            }
            .pickerStyle(.segmented)
            .padding(.top, OneDayMetrics.spacingL)
            .onChange(of: mode) { _, _ in formError = nil }

            Group {
                if mode == .password {
                    passwordFields
                } else {
                    keyFields
                }
            }
            .padding(.top, OneDayMetrics.spacingL)

            if mode == .password {
                noticeRow(
                    "密码只用来验证你的身份。验证通过后，服务器会把登录密钥交给 App 保管，你不用再填第二遍。"
                )
                .padding(.top, OneDayMetrics.spacingM)
            }

            if let formError {
                InlineError(formError)
                    .padding(.top, OneDayMetrics.spacingM)
            }

            Button(mode == .password ? "验证并连接" : "测试并连接") {
                submit()
            }
            .buttonStyle(.odPrimary)
            .disabled(!canSubmit)
            .padding(.top, OneDayMetrics.spacingXL)

            Button("需要帮助？") { helpReturn = .login; page = .help }
                .font(.callout)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
        }
    }

    private var passwordFields: some View {
        VStack(spacing: 0) {
            FieldRow(label: "服务器地址", isActive: focusedField == .server) {
                TextField("https://hermes.didichou.site", text: $serverText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .server)
            }
            GroupDivider()
            FieldRow(label: "账号", isActive: focusedField == .username) {
                TextField("你的面板账号", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
            }
            GroupDivider()
            FieldRow(label: "密码", isActive: focusedField == .password) {
                secretField(
                    placeholder: "输入面板密码", text: $password,
                    field: .password
                )
            }
        }
        .odGroup()
    }

    private var keyFields: some View {
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
                    // 演示占位：与假串等长的圆点（0.1.3 截图
                    // 实证：程序化给 SecureField 赋的值在模
                    // 拟器里不渲染圆点且行高异常；生产路径
                    // 是用户手输、不受此缺陷影响）
                    Text(String(repeating: "•", count: 12))
                } else {
                    secretField(
                        placeholder: "Hermes 的登录密钥", text: $apiKey,
                        field: .apiKey
                    )
                }
            }
        }
        .odGroup()
    }

    /// 密钥/密码输入行：SecureField＋显隐切换（原型
    /// secret 行同形态）
    private func secretField(
        placeholder: String, text: Binding<String>, field: Field
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Group {
                if revealSecret {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            Button {
                revealSecret.toggle()
            } label: {
                Image(systemName: revealSecret ? "eye.slash" : "eye")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
            }
            .accessibilityLabel(revealSecret ? "隐藏" : "显示")
        }
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(Palette.primary)
            Text(L10n.string(text))
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.fieldCorner, style: .continuous
            )
        )
    }

    private func backButton(_ label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingMicro) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.string(label))
                    .font(.callout)
            }
            .foregroundStyle(Palette.primary)
            .frame(minHeight: OneDayMetrics.minTapTarget)
        }
    }

    // MARK: - 连接中面（四步真检查＋失败分面）

    private var connectingPage: some View {
        Group {
            if let failure {
                failureFace(failure)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    orb(systemImage: "server.rack")
                    Text("正在连接")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text("正在确认这台服务器可以安全使用。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingS)
                    stepsList
                        .padding(.top, OneDayMetrics.spacingXL)
                    Text("每一步都以服务器的真实回应为准，通常几秒内完成。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                .padding(.top, OneDayMetrics.spacingXXL)
            }
        }
    }

    private var stepsList: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(OnboardingStep.allCases.enumerated()),
                id: \.element.rawValue
            ) { index, step in
                if index > 0 {
                    GroupDivider()
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    stepIcon(stepStates[step] ?? .waiting)
                        .frame(width: 18, alignment: .center)
                    Text(step.label())
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    switch stepStates[step] ?? .waiting {
                    case .done:
                        Text("通过")
                            .font(.footnote)
                            .foregroundStyle(Palette.success)
                    case .failed:
                        Text("失败")
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    case .active:
                        Text(mode == .password && step == .serviceInfo
                            ? "换取登录密钥"
                            : "检查中")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    case .waiting:
                        EmptyView()
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.minTapTarget)
            }
        }
        .odGroup()
    }

    @ViewBuilder
    private func stepIcon(_ state: StepState) -> some View {
        switch state {
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
        case .waiting:
            Image(systemName: "circle")
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkMuted)
        }
    }

    /// 失败面（按型分面）：三出口恒在——重新连接／修改
    /// 连接信息／查看连接帮助
    private func failureFace(_ failure: OnboardingFailure) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            orb(systemImage: "exclamationmark.triangle", isDanger: true)
            Text(failure.headline())
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text("可能的原因")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.danger)
                .padding(.top, OneDayMetrics.spacingL)
            Text(failure.advice())
                .font(.callout)
                .foregroundStyle(Palette.danger)
                .padding(.top, OneDayMetrics.spacingXS)
            Button("重新连接") { submit() }
                .buttonStyle(.odPrimary)
                .padding(.top, OneDayMetrics.spacingXL)
            Button("修改连接信息") { page = .login }
                .font(.callout.weight(.medium))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
            Button("查看连接帮助") { helpReturn = .connecting; page = .help }
                .font(.callout)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
        }
        .padding(.top, OneDayMetrics.spacingXXL)
    }

    private func orb(systemImage: String, isDanger: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 28))
            .foregroundStyle(isDanger ? Palette.danger : Palette.primary)
            .frame(width: 70, height: 70)
            .background(
                isDanger ? Palette.errorSurface : Palette.primaryPale,
                in: RoundedRectangle(
                    cornerRadius: 21, style: .continuous
                )
            )
            .padding(.bottom, OneDayMetrics.spacingXL)
            .accessibilityHidden(true)
    }

    // MARK: - 成功面（数据全取本次实测）

    private var successPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            orb(systemImage: "checkmark")
            Text("已连接")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text(L10n.format(
                "%@ 已就绪，可以开始对话了。", appState.agentDisplayName
            ))
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
            if let serviceInfo {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.primary)
                        Text(serviceInfo.host)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    let line = serviceInfo.summaryLine()
                    if !line.isEmpty {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .padding(OneDayMetrics.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .odGroup()
                .padding(.top, OneDayMetrics.spacingXL)
            }
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                nextItem(
                    systemImage: "person.crop.circle",
                    title: "形象与名称",
                    detail: "稍后可在设置里修改，只影响这台手机"
                )
                nextItem(
                    systemImage: "shield",
                    title: "设备权限",
                    detail: "默认关闭，需要时逐项开启"
                )
            }
            .padding(.top, OneDayMetrics.spacingXL)
            Button("开始聊天") {
                appState.activatePreparedConnection()
            }
            .buttonStyle(.odPrimary)
            .padding(.top, OneDayMetrics.spacingXL)
        }
        .padding(.top, OneDayMetrics.spacingXXL)
    }

    private func nextItem(
        systemImage: String, title: String, detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(L10n.string(title))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(L10n.string(detail))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    // MARK: - 帮助面（真实部署路径，不编造步骤）

    private var helpPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton("返回") { page = helpReturn }
            Text("帮助与反馈")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, OneDayMetrics.spacingS)
            Text("连接不上，或者想提一个建议？")
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)

            helpGroupTitle("连接帮助")
            VStack(spacing: 0) {
                helpRow(
                    systemImage: "server.rack", title: "服务器地址",
                    detail: "形如 https://hermes.example.com，不要带结尾斜杠。手机需要能直接访问这个地址，不能用 localhost。"
                )
                GroupDivider()
                helpRow(
                    systemImage: "person.crop.circle", title: "密码登录",
                    detail: "用你部署 Hermes 时设的面板账号和密码。验证通过后，App 会向你的服务器换取登录密钥并保存在本机钥匙串，之后不用再填。"
                )
                GroupDivider()
                helpRow(
                    systemImage: "key", title: "密钥登录",
                    detail: "密钥是这台 Hermes 的登录密钥，在服务器配置中生成。只保存在本机钥匙串，不会上传到别处。"
                )
            }
            .odGroup()

            helpGroupTitle("还没有服务器？")
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                Text("Hermes 是开源项目，部署在你自己的服务器上。按官方仓库的说明装好，再回来用上面的方式连接。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                Link(destination: URL(string: "https://github.com/NousResearch/hermes-agent")!) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text("Hermes 官方仓库")
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.primary)
                }
            }
            .padding(OneDayMetrics.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .odGroup()

            helpGroupTitle("反馈")
            VStack(spacing: 0) {
                Link(destination: URL(string: "https://github.com/yyyyymmmmm/oneday-app/issues")!) {
                    HStack(spacing: OneDayMetrics.spacingM) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.inkSecondary)
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text("在 GitHub 提交问题")
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                            Text("附上复现步骤与系统版本")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.minTapTarget)
                }
            }
            .odGroup()
            Text("请勿在公开议题中粘贴密钥、服务器地址或个人数据。")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
        }
    }

    private func helpGroupTitle(_ title: String) -> some View {
        Text(L10n.string(title))
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.top, OneDayMetrics.spacingXL)
            .padding(.bottom, OneDayMetrics.spacingS)
    }

    private func helpRow(
        systemImage: String, title: String, detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(Palette.inkSecondary)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(L10n.string(title))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(L10n.string(detail))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 提交（四步真检查）

    private func submit() {
        formError = nil
        failure = nil
        // 第一步：地址格式——本地归一化，未过不发请求、
        // 不进连接中面（表单层报错，与旧口径一致）
        guard let config = ServerConfig(rawInput: serverText) else {
            formError = OnboardingFailure(
                step: .addressFormat, kind: .invalidAddress
            ).advice()
            Haptics.error()
            return
        }
        stepStates = [.addressFormat: .done]
        page = .connecting
        isConnecting = true
        Task {
            defer { isConnecting = false }
            var current: OnboardingStep?
            let onStep: (OnboardingStep) -> Void = { step in
                if let previous = current {
                    stepStates[previous] = .done
                }
                current = step
                stepStates[step] = .active
            }
            do {
                let info: ConnectionServiceInfo
                switch mode {
                case .password:
                    info = try await appState.connectWithPassword(
                        config: config, username: username,
                        password: password, onStep: onStep
                    )
                case .key:
                    info = try await appState.connectWithKey(
                        config: config, apiKey: apiKey, onStep: onStep
                    )
                }
                for step in OnboardingStep.allCases {
                    stepStates[step] = .done
                }
                serviceInfo = info
                page = .success
                Haptics.success()
            } catch let failureError as OnboardingFailure {
                if let current {
                    stepStates[current] = .failed
                }
                failure = failureError
                Haptics.error()
            } catch {
                if let current {
                    stepStates[current] = .failed
                }
                failure = OnboardingFailure(
                    step: current ?? .serviceInfo, kind: .other
                )
                Haptics.error()
            }
        }
    }
}
