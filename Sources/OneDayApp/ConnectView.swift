import AVFoundation
import OneDayDesign
import OneDayCore
import SwiftUI

/// 引导线（欢迎／登录／连接中／成功／通知／帮助六面，
/// 蓝本＝用户 2026-11-11 亲递原型 oneday-prototype.html；
/// 本版覆盖 0.6.0 直登单卡面貌）。2026-11-21 引导小包
/// （nanoMuse 引导线学习，§335）：欢迎面改分叉版式
/// （连接已有服务器／部署新服务器两路＋细字讲清关
/// 系）、成功与聊天之间插入通知权限段（模板在 Core
/// NotificationGuideSegment，按 needed() 判定出现、
/// 已决定自动跳过）。与原型的口径差（定版优
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
    @Environment(\.scenePhase) private var scenePhase

    private enum Page {
        case welcome, login, connecting, success, notifications, help
    }

    private enum LoginMode: String, CaseIterable {
        case password, key, scan
    }

    /// 扫码认领阶段（配对一期）：idle 待扫／claiming
    /// 认领请求在飞／denied 相机权限已拒绝（降级文案）
    private enum ScanPhase {
        case idle, claiming, denied
    }

    private enum StepState {
        case waiting, active, done, failed
    }

    @State private var page: Page = .welcome
    /// 帮助面的返回落点（欢迎/登录/失败面三处都能进帮助，
    /// 回去要回原处，不许一律弹回登录）
    @State private var helpReturn: Page = .login
    @State private var mode: LoginMode = .password
    @State private var serverText = "https://your-hermes.example.com"
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var formError: String?
    @State private var stepStates: [OnboardingStep: StepState] = [:]
    @State private var failure: OnboardingFailure?
    @State private var serviceInfo: ConnectionServiceInfo?
    @State private var scanPhase: ScanPhase = .idle
    /// 通知授权真状态（成功面出现时现读；nil＝还没
    /// 读到，按「段不需要」呈现，读到后自动改判——
    /// needed() 判定走 Core OnboardingGuide 单源）
    @State private var notificationState: DevicePermissionState?
    @State private var showScanner = false
    /// 连接自检深链（H13，DESIGN §357）：失败面出口
    /// ——对着刚填的候选地址（＋密钥模式下已填的密钥）
    /// 跑一轮只读自检，逐项看卡在哪一层
    @State private var showSelfCheck = false
    @State private var isConnecting = false
    @State private var appeared = false

    private var canSubmit: Bool {
        guard !isConnecting,
              !serverText.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        switch mode {
        case .password: return !username.isEmpty && !password.isEmpty
        case .key: return !apiKey.isEmpty
        case .scan: return false  // 扫码走认领流、不经底部提交钮
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
                case .notifications: notificationsPage
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
                password = "demo-password"
                apiKey = "demo-api-key"
            }
            // 回显已存账号：优先从 config 读（restore 已恢复）；
            // 未连接时直接读 Keychain 存量（用户断开后重登）
            if let stored = appState.config?.username
                ?? KeychainStore.read(account: CredentialKey.username),
               !stored.isEmpty {
                username = stored
            }
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.entrance, reduceMotion: reduceMotion
                )
            ) {
                appeared = true
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRScannerView(
                    onCode: { raw in
                        showScanner = false
                        handleScanned(raw)
                    },
                    onUnavailable: {
                        showScanner = false
                        formError = "这台设备上用不了相机。可以改用密码或密钥登录。"
                    }
                )
                .ignoresSafeArea()
                .navigationTitle("扫码连接")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showScanner = false }
                    }
                }
            }
            .fullscreenPopBridge()
        }
        .sheet(isPresented: $showSelfCheck) {
            NavigationStack {
                ConnectionSelfCheckView(target: selfCheckTarget)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showSelfCheck = false }
                        }
                    }
            }
            .fullscreenPopBridge()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 通知段里去系统设置开完回来：现读真状态
            // 刷新段面（已开启即翻成确认态，不重走请求）
            guard newPhase == .active, page == .notifications else {
                return
            }
            Task {
                notificationState =
                    await NotificationPermissionGate.currentState()
            }
        }
    }

    // MARK: - 欢迎面（大厂标准：品牌主视觉 + 三条核心价值 + 底部主次操作区）

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .center, spacing: OneDayMetrics.spacingM) {
                welcomeBrandMark

                VStack(spacing: OneDayMetrics.spacingXS) {
                    Text("欢迎使用 OneDay")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text("连接你自己的 Hermes 服务，随时随地协作。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, OneDayMetrics.spacingXXL + 8)

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                welcomePillar(
                    symbol: "lock.shield",
                    title: "数据完全归你所有",
                    detail: "直连自部署服务端，凭据仅存本机钥匙串，不经任何第三方。"
                )
                welcomePillar(
                    symbol: "bolt.horizontal.circle",
                    title: "后台持续执行",
                    detail: "复杂任务在服务端跑完，锁屏或切换对话也不会中断。"
                )
                welcomePillar(
                    symbol: "checkmark.seal",
                    title: "关键写入先经你批准",
                    detail: "外部访问与重要修改都会先弹出确认，掌控权始终在你手里。"
                )
            }
            .padding(.vertical, OneDayMetrics.spacingL)
            .padding(.horizontal, OneDayMetrics.spacingM)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.containerCorner,
                    style: .continuous
                )
            )
            .padding(.top, OneDayMetrics.spacingXL)

            VStack(spacing: OneDayMetrics.spacingS) {
                Button("连接我的服务器") { page = .login }
                    .buttonStyle(.odPrimary)

                Button {
                    helpReturn = .welcome
                    page = .help
                } label: {
                    Text("还没有服务器？了解部署")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Palette.primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: OneDayMetrics.minTapTarget)
                }
                .buttonStyle(.odPressable)
            }
            .padding(.top, OneDayMetrics.spacingXL + 8)
        }
    }

    /// 大厂标准欢迎页品牌标识：优先使用真实桌面 App 图标（圆角矩形 + 轻阴影），
    /// 图标不可用时回落极简几何品牌徽标，不使用具体宠物/角色照片。
    @ViewBuilder
    private var welcomeBrandMark: some View {
        if AppIconBitmap.image != nil {
            AppIconView(size: 80, cornerRadius: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.primary.gradient)
                    .frame(width: 80, height: 80)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Palette.primary.opacity(0.24), radius: 16, y: 6)
            .accessibilityHidden(true)
        }
    }

    private func welcomePillar(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Palette.primary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                Text("扫码").tag(LoginMode.scan)
            }
            .pickerStyle(.segmented)
            .padding(.top, OneDayMetrics.spacingL)
            .onChange(of: mode) { _, _ in formError = nil }

            Group {
                if mode == .password {
                    passwordFields
                } else if mode == .key {
                    keyFields
                } else {
                    scanFields
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

            if mode != .scan {
                Button(mode == .password ? "验证并连接" : "测试并连接") {
                    submit()
                }
                .buttonStyle(.odPrimary)
                .disabled(!canSubmit)
                .padding(.top, OneDayMetrics.spacingXL)
            }

            Button("需要帮助？") { helpReturn = .login; page = .help }
                .font(.callout)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
        }
    }

    // 地址/秘密字段走共用件（台账 198 收敛 S3：
    // ServerCredentialForm，与服务器详情页同一份）
    private var passwordFields: some View {
        VStack(spacing: 0) {
            ServerAddressFieldRow(text: $serverText)
            GroupDivider()
            ServerSecretFieldRow(
                label: "账号", text: $username,
                placeholder: "输入账号"
            )
            GroupDivider()
            ServerSecretFieldRow(
                label: "密码", text: $password,
                placeholder: "输入密码"
            )
        }
        .odGroup()
    }

    private var keyFields: some View {
        VStack(spacing: 0) {
            ServerAddressFieldRow(text: $serverText)
            GroupDivider()
            ServerSecretFieldRow(
                label: "密钥", text: $apiKey,
                placeholder: "Hermes 的登录密钥",
                demoObscured: DemoMode.current == .connectPage
            )
        }
        .odGroup()
    }

    /// 扫码字段区（配对一期）：说明＋扫码主按钮＋权
    /// 限降级文案。认领成功后回填地址/密钥、转密钥
    /// 模式走 submit() 既有四步流水线——连接状态不
    /// 在本面另立账
    private var scanFields: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            noticeRow(
                "在已经连好的手机或电脑上打开 OneDay，进「设置 → 添加设备」生成认领二维码，对准扫一下就连上，不用手填地址和密钥。二维码 5 分钟内有效、只能用一次。"
            )
            if scanPhase == .denied {
                InlineError(
                    "相机权限没开。去系统「设置 → OneDay」里打开相机，再回来扫码；也可以改用密码或密钥登录。"
                )
            }
            Button {
                beginScan()
            } label: {
                if scanPhase == .claiming {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在认领…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("打开相机扫码")
                }
            }
            .buttonStyle(.odPrimary)
            .disabled(scanPhase == .claiming)
        }
    }

    /// 扫码入口（授权铁律）：先同步读相机授权状态
    /// ——已授权直达取景、已拒绝只给降级文案，只有
    /// 未决定才发那一次请求（承接见 CameraPermissionGate）
    private func beginScan() {
        formError = nil
        scanPhase = .idle
        switch CameraPermissionGate.currentStatus() {
        case .authorized:
            showScanner = true
        case .notDetermined:
            Task {
                if await CameraPermissionGate.requestAccess() {
                    showScanner = true
                } else {
                    scanPhase = .denied
                }
            }
        case .denied, .restricted:
            scanPhase = .denied
        @unknown default:
            scanPhase = .denied
        }
    }

    /// 扫码认领：载荷先在 Core 验形，认领走网关公
    /// 开端点（码即凭据）；回执指纹必须与二维码所
    /// 带指纹对上，才把地址＋密钥回填表单、转密钥
    /// 模式走既有四步流水线（submit 单路）
    private func handleScanned(_ raw: String) {
        guard let payload = EnrollmentPayload.parse(raw) else {
            formError = "这不是 OneDay 的连接二维码。在已登录的设备上打开「设置 → 添加设备」生成一个，再扫一次。"
            Haptics.error()
            return
        }
        scanPhase = .claiming
        Task {
            do {
                let claim = try await appState.client.claimEnrollment(
                    config: payload.config, code: payload.code
                )
                guard claim.fingerprint == payload.fingerprint else {
                    scanPhase = .idle
                    formError = "二维码和服务器对不上：认领回来的不是出码的那台服务器。这次连接没有继续。"
                    Haptics.error()
                    return
                }
                serverText = payload.config.baseString
                apiKey = claim.apiKey
                mode = .key
                scanPhase = .idle
                submit()
            } catch let error as HermesError {
                scanPhase = .idle
                formError = error.userMessage
                Haptics.error()
            } catch {
                scanPhase = .idle
                formError = OnboardingFailure(
                    step: .serviceInfo, kind: .other
                ).advice()
                Haptics.error()
            }
        }
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "info.circle")
                .font(.system(size: FrameworkIcon.composerGlyphSize))
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
                    .font(.system(size: FrameworkIcon.composerGlyphSize, weight: .semibold))
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
                            .foregroundStyle(Palette.successText)
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
                .font(.system(size: FrameworkIcon.composerGlyphSize))
                .foregroundStyle(Palette.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: FrameworkIcon.composerGlyphSize))
                .foregroundStyle(Palette.danger)
        case .active:
            ProgressView()
                .frame(width: 18, height: 18)
        case .waiting:
            Image(systemName: "circle")
                .font(.system(size: FrameworkIcon.composerGlyphSize))
                .foregroundStyle(Palette.inkMuted)
        }
    }

    /// 失败面（按型分面）：四出口恒在——重新连接／修改
    /// 连接信息／查看连接帮助／查看连接自检（H13 深链，
    /// DESIGN §357：对候选地址跑一轮只读探活逐项定位）
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
            Button("查看连接自检") { showSelfCheck = true }
                .font(.callout)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
        }
        .padding(.top, OneDayMetrics.spacingXXL)
    }

    /// 自检深链的探针目标：候选地址按表单原文归一化
    /// （与提交时同式）；密钥只在密钥模式且已填时带
    /// 上——密码模式此阶段还没有 API 密钥，带鉴权面
    /// 在自检里如实显未探
    private var selfCheckTarget: ConnectionSelfCheckView.Target? {
        guard let config = ServerConfig(rawInput: serverText) else {
            return nil
        }
        let key = mode == .key && !apiKey.isEmpty ? apiKey : nil
        return ConnectionSelfCheckView.Target(
            config: config, apiKey: key
        )
    }

    private func orb(systemImage: String, isDanger: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: FrameworkIcon.largeGlyphSize))
            .foregroundStyle(isDanger ? Palette.danger : Palette.primary)
            .frame(width: 70, height: 70)
            .background(
                isDanger ? Palette.errorSurface : Palette.primaryPale,
                in: RoundedRectangle(
                    // 美化标尺 V1（§247.3）：手算散值
                    // 21 收编容器圆角令牌——本球是独立
                    // 容器面（非嵌套面、无从同心推导；
                    // 比例 ×0.3 亦非在册图标比例 0.25），
                    // 取 containerCorner 同族口径
                    cornerRadius: OneDayMetrics.containerCorner,
                    style: .continuous
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
                            .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                    detail: notificationsSegmentNeeded
                        ? "通知接下来会单独询问，其余需要时逐项开启"
                        : "默认关闭，需要时逐项开启"
                )
            }
            .padding(.top, OneDayMetrics.spacingXL)
            // needed() 路由：通知段还缺（未决定）才先
            // 过通知段，已决定直达聊天——判定走 Core
            // OnboardingGuide 单源，本面不自立第二套
            if notificationsSegmentNeeded {
                Button("继续") { page = .notifications }
                    .buttonStyle(.odPrimary)
                    .padding(.top, OneDayMetrics.spacingXL)
            } else {
                Button("开始聊天") {
                    appState.activatePreparedConnection()
                }
                .buttonStyle(.odPrimary)
                .padding(.top, OneDayMetrics.spacingXL)
            }
        }
        .padding(.top, OneDayMetrics.spacingXXL)
        .task {
            // 成功面出现即现读通知真状态（只读不请求），
            // 供上面的 needed() 路由与权限行文案改判
            if notificationState == nil {
                notificationState =
                    await NotificationPermissionGate.currentState()
            }
        }
    }

    /// 通知段是否还缺（连接已在本面内完成，hasCon-
    /// nection 恒真；状态没读到时按不需要呈现，读到
    /// 后自动改判）
    private var notificationsSegmentNeeded: Bool {
        guard let notificationState else { return false }
        return OnboardingGuide.neededSegments(
            hasConnection: true,
            notificationState: notificationState
        ).contains(.notifications)
    }

    // MARK: - 通知权限段（引导末段，模板见 Core）

    /// 通知段：连接成功后、进主界面前的最后一课。
    /// 呈现与文案全走 NotificationGuideView＋Core
    /// 模板；本面只接线三件事——请求（过授权门）、
    /// 去设置、前进（激活已备好的连接进主界面）。
    /// 跳过同样走前进：段是邀请不是关卡。
    private var notificationsPage: some View {
        NotificationGuideView(
            state: notificationState ?? .notDetermined,
            advanceTitle: L10n.string("开始聊天"),
            onRequest: {
                Task {
                    notificationState = await NotificationPermissionGate
                        .requestAccess()
                }
            },
            onOpenSettings: {
                NotificationPermissionGate.openSystemSettings()
            },
            onAdvance: {
                appState.activatePreparedConnection()
            }
        )
        .padding(.top, OneDayMetrics.spacingXXL)
    }

    private func nextItem(
        systemImage: String, title: String, detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Image(systemName: systemImage)
                .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                    detail: "用伴生面板的那把密码（和网页端同一把，没有账号）。验证通过后，App 会向你的服务器换取登录密钥并保存在本机钥匙串，之后不用再填。"
                )
                GroupDivider()
                helpRow(
                    systemImage: "key", title: "密钥登录",
                    detail: "密钥是这台 Hermes 的登录密钥，在服务器配置中生成。只保存在本机钥匙串，不会上传到别处。"
                )
                GroupDivider()
                helpRow(
                    systemImage: "qrcode.viewfinder", title: "扫码连接",
                    detail: "新设备最快的连法：在已经连好的设备上打开「设置 → 添加设备」生成认领二维码，新设备在这里选「扫码」对准即可。二维码 5 分钟内有效、只能用一次。"
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
                            .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                        config: config,
                        username: username,
                        password: password, onStep: onStep
                    )
                case .key, .scan:
                    // 扫码认领成功后先回填密钥并转 .key
                    // 才进 submit；.scan 在此只是穷尽兜
                    // 底，与密钥同路（同一条四步流水线）
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
