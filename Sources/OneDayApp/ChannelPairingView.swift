import OneDayCore
import OneDayDesign
import SwiftUI

/// 平台频道入口（频道扩展一期）：抽屉平台行点开先
/// 到这里——回读伴生状态，已连上（connected）直达
/// 频道页，其余状态（未配对/等待生效/连接失败）落
/// 配对引导页。状态没回来之前只显等待，不猜。
struct ChannelEntryView: View {
    let channel: ChannelDescriptor
    var onOpenSession: (String) -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var store = ChannelStatusStore()
    @State private var showList = false

    private var connected: Bool {
        store.status(for: channel.id)?.connected == true
    }

    var body: some View {
        Group {
            if showList || connected {
                PlatformChannelView(
                    channel: channel,
                    onOpenSession: onOpenSession,
                    onClose: onClose
                )
            } else if Self.usesTokenBatchPairing(channel.id) {
                TokenChannelPairingView(
                    channel: channel, store: store,
                    onShowList: { showList = true },
                    onClose: onClose
                )
            } else {
                ChannelPairingView(
                    channel: channel, store: store,
                    onShowList: { showList = true },
                    onClose: onClose
                )
            }
        }
        .task { await store.load(appState: appState) }
    }

    /// 二期令牌四家走通用引导页（字段逐家不同，不
    /// 进 Telegram 打样页的硬编码面）；Telegram 与
    /// 冻结行仍走一期页
    private static func usesTokenBatchPairing(
        _ channelID: String
    ) -> Bool {
        switch channelID {
        case "dingtalk", "qqbot", "discord", "slack":
            return true
        default:
            return false
        }
    }
}

/// 配对引导页（规格 §6）：全屏页、与设置页同语言
/// （浅色 insetGrouped、系统件、一屏一主角）。结构
/// ＝页头（官方图标＋平台名＋一句人话）→状态带→步
/// 骤区（每步至多一个动作）→页脚小字。步骤内容按
/// 平台分型：Telegram 是拿钥匙三步；飞书按其官方
/// 建应用流程走四步（建应用拿凭证／贴凭证／只认你
/// 一个人／打开消息通道），不照 TG 平移。微信冻结
/// 变体已随二期微信行下架退役（2026-11-13）。
struct ChannelPairingView: View {
    let channel: ChannelDescriptor
    var store: ChannelStatusStore
    var onShowList: () -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var token = ""
    @State private var userID = ""
    @State private var appID = ""
    @State private var appSecret = ""
    @State private var openID = ""
    @State private var submitting = false
    @State private var submitError: String?
    /// 最近一次保存回执：生效相位只认它＋当前
    /// status（判定在 Core ChannelApplyPhase）
    @State private var lastReceipt: ChannelCredentialsReceipt?

    private var status: ChannelPlatformStatus? {
        store.status(for: channel.id)
    }

    private var applyPhase: ChannelApplyPhase {
        ChannelApplyPhase.resolve(
            applyTriggered: lastReceipt?.applyTriggered,
            applyError: lastReceipt?.applyError,
            statusState: status?.state
        )
    }

    private var pairingKind: ChannelPairingKind {
        ChannelRegistry.pairingKind(for: channel.id)
    }

    private var isFeishu: Bool { channel.id == "feishu" }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                statusSection
                if showsSteps {
                    if isFeishu {
                        feishuStepOneSection
                        feishuStepTwoSection
                        feishuStepThreeSection
                    } else {
                        stepOneSection
                        stepTwoSection
                        stepThreeSection
                    }
                    connectSection
                }
                if isFeishu {
                    feishuStepFourSection
                }
                footerSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { onClose() }
                }
            }
            .refreshable { await store.load(appState: appState) }
            .task(id: applyPhase == .applying) {
                await pollWhileApplying()
            }
        }
    }

    /// 正在生效期间自动刷新状态：每 3 秒回读一次、
    /// 最多约两分钟；status 翻 connected/error 后
    /// applyPhase 退场、循环收口，页面消失自动取消
    private func pollWhileApplying() async {
        guard applyPhase == .applying else { return }
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            await store.load(appState: appState)
            if applyPhase != .applying { return }
        }
    }

    // MARK: - 页头

    private var headerSection: some View {
        Section {
            VStack(spacing: OneDayMetrics.spacingS) {
                if let asset = channel.iconAssetName {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                }
                Text(channel.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .listRowBackground(Palette.surface)
        }
    }

    private var headerSubtitle: String {
        switch channel.id {
        case "telegram":
            return L10n.string("连上之后，你在 Telegram 里给机器人发消息，"
                + "就能和你的智能体聊天；对话会回到这里的频道里。")
        case "feishu":
            return L10n.string("连上之后，你在飞书里给机器人发消息，"
                + "就能和你的智能体聊天；对话会回到这里的频道里。")
        default:
            return channel.pageSubtitle
        }
    }

    // MARK: - 状态带

    private var showsSteps: Bool {
        guard pairingKind == .token else { return false }
        guard let status else { return store.loadError == nil }
        return status.state == "not_configured"
            || status.state == "error"
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if store.isLoading, status == nil {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取状态…")
                        .font(.bodyText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
            } else if status == nil, let error = store.loadError {
                VStack(alignment: .leading,
                       spacing: OneDayMetrics.spacingS) {
                    Text("暂时读不到状态")
                        .font(.rowTitle)
                        .foregroundStyle(Palette.ink)
                    Text(error)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                    Button("重试") {
                        Task { await store.load(appState: appState) }
                    }
                }
                .listRowBackground(Palette.surface)
            } else if let status {
                statusBand(status)
                    .listRowBackground(Palette.surface)
            }
        }
    }

    @ViewBuilder
    private func statusBand(
        _ status: ChannelPlatformStatus
    ) -> some View {
        switch applyPhase {
        case .applying:
            applyingBand
        case .applyFailed(let reason):
            applyFailedBand(reason)
        case .none, .awaitingRestart:
            // 未触发即时生效时 status 的等待态就是如
            // 实口径；无流程态时呈现完全归 status
            statusStateBand(status)
        }
    }

    @ViewBuilder
    private func statusStateBand(
        _ status: ChannelPlatformStatus
    ) -> some View {
        switch status.state {
        case "connected":
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("已配对")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text("这个频道已经连上了。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                Button("去频道看看") { onShowList() }
            }
        case "pending_restart":
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("钥匙已保存，等待生效")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("服务器下一次重启后就会自动连上，这期间"
                    + "不用你再做什么。连上之后，抽屉里这一行"
                    + "会变成已配对的样子。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                if isFeishu {
                    Text(L10n.string("飞书还差一步：按下面第四步把消息"
                        + "通道打开，机器人才会开始收消息。"))
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Button("刷新状态") {
                    Task { await store.load(appState: appState) }
                }
            }
        case "error":
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("连接失败")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.danger)
                if let message = status.message {
                    Text(message)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text("检查一下钥匙，按下面三步重新连接。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        default:
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("还没配对")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text("按下面三步连上，几分钟就好。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 正在生效带（回执 applyTriggered=true）：网关
    /// 重启的空窗里给明确的进行时，不许显成笼统的
    /// 连接中/等待；status 翻 connected 后由状态带
    /// 正常收口（ChannelEntryView 会直接进频道页）
    private var applyingBand: some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在生效")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
            }
            Text(L10n.string("钥匙已保存，服务器正在让它生效，通常"
                + "几秒钟就好。连上之后这里会自动变成已配对"
                + "的样子，你不用再做什么。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            if isFeishu {
                Text(L10n.string("生效之后，别忘了按下面第四步把飞书"
                    + "那边的消息通道打开。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 即时生效没触发成功的回退带：口径仍是等待生
    /// 效，原因用桥回的人话原样摆出来——不许包装
    /// 成已经在生效
    private func applyFailedBand(_ reason: String) -> some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            Text("钥匙已保存，等待生效")
                .font(.rowTitle)
                .foregroundStyle(Palette.ink)
            Text(reason)
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Text(L10n.string("服务器下一次重启后就会自动连上，这期间"
                + "不用你再做什么。连上之后，抽屉里这一行"
                + "会变成已配对的样子。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Button("刷新状态") {
                Task { await store.load(appState: appState) }
            }
        }
    }

    // MARK: - 步骤（令牌型，每步至多一个动作）

    private var stepOneSection: some View {
        Section {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text(L10n.string("在 Telegram 里打开 @BotFather，按它的提示"
                    + "建一个机器人。建好后它会给你一串连接"
                    + "钥匙——那是这个机器人的钥匙，不是你的"
                    + "账号密码。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Link("打开 @BotFather",
                     destination: URL(string: "https://t.me/BotFather")!)
                    .font(.bodyText)
            }
            .listRowBackground(Palette.surface)
        } header: {
            Text("第一步 · 拿连接钥匙")
        }
    }

    private var stepTwoSection: some View {
        Section {
            SecureField("把连接钥匙贴在这里", text: $token)
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Text(L10n.string("钥匙会直接发到你自己的服务器保存，这个 "
                + "App 不留存。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第二步 · 贴钥匙")
        }
    }

    private var stepThreeSection: some View {
        Section {
            TextField("你的 Telegram 数字 ID（可不填）",
                      text: $userID)
                .font(.bodyText)
                .keyboardType(.numberPad)
            Text(L10n.string("填了 ID，就只有你能跟这个机器人说话。"
                + "在 Telegram 里给 @userinfobot 发任意一句话，"
                + "它就会回你的 ID。不填也能先连上，之后再补。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第三步 · 只认你一个人（可跳过）")
        }
    }

    // MARK: - 步骤（飞书，按官方建应用流程）

    private var feishuStepOneSection: some View {
        Section {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text(L10n.string("打开飞书开放平台，创建一个「企业自建"
                    + "应用」；在应用里添加「机器人」能力、开通"
                    + "发送消息的权限；再到「凭证与基础信息」页"
                    + "复制 App ID 和 App Secret——那是这个应用"
                    + "的凭证，不是你的账号密码。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Link("打开飞书开放平台",
                     destination: URL(
                        string: "https://open.feishu.cn/app")!)
                    .font(.bodyText)
            }
            .listRowBackground(Palette.surface)
        } header: {
            Text("第一步 · 建应用拿凭证")
        }
    }

    private var feishuStepTwoSection: some View {
        Section {
            TextField("App ID（cli_ 开头）", text: $appID)
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            SecureField("App Secret", text: $appSecret)
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Text(L10n.string("凭证会直接发到你自己的服务器保存，这个 "
                + "App 不留存。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第二步 · 贴凭证")
        }
    }

    private var feishuStepThreeSection: some View {
        Section {
            TextField("你的 open_id（ou_ 开头，可不填）",
                      text: $openID)
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Text(L10n.string("填了，就只有名单里的人能跟机器人说话。"
                + "不填也能先连上：陌生人私聊机器人时，要先"
                + "经过你的批准才会放行。open_id 在你给机器人"
                + "发过消息之后，能从服务器的会话里查到。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第三步 · 只认你一个人（可跳过）")
        }
    }

    /// 第四步是飞书特有的一段：事件订阅选长连接必
    /// 须等网关先连上才能在飞书后台保存成功（先存
    /// 会报没有在线连接），且改完要发布版本才生效
    /// ——顺序写死在文案里，不当隐知识
    private var feishuStepFourSection: some View {
        Section {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text(L10n.string("等这里显示连上之后，再回飞书开放平台："
                    + "进这个应用的「事件与回调」，把订阅方式选成"
                    + "「使用长连接接收事件」，添加「接收消息」事件"
                    + "并保存；最后到「版本管理与发布」发布一个"
                    + "版本，配置才会生效。顺序别反——先在这里"
                    + "连上，那边才存得上。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Link("打开飞书开放平台",
                     destination: URL(
                        string: "https://open.feishu.cn/app")!)
                    .font(.bodyText)
            }
            .listRowBackground(Palette.surface)
        } header: {
            Text("第四步 · 打开消息通道（连上之后做）")
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                Text(submitting ? "正在连接…" : "连接")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canSubmit || submitting)
            if let submitError {
                Text(submitError)
                    .font(.captionText)
                    .foregroundStyle(Palette.danger)
                    .listRowBackground(Palette.surface)
            }
        }
    }

    private var canSubmit: Bool {
        if isFeishu {
            return !appID.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty
                && !appSecret.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty
        }
        return !token.trimmingCharacters(
            in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 页脚

    private var footerSection: some View {
        Section {
            Text("钥匙只存在你自己的服务器上，这个 App 不保存。")
                .font(.captionText)
                .foregroundStyle(Palette.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - 提交

    private func submit() async {
        submitting = true
        submitError = nil
        lastReceipt = nil
        do {
            if isFeishu {
                let trimmedID = appID.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let trimmedSecret = appSecret.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let trimmedOpenID = openID.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                lastReceipt = try await store.submitFeishu(
                    appState: appState, appID: trimmedID,
                    appSecret: trimmedSecret,
                    allowedUserIds: trimmedOpenID.isEmpty
                        ? nil : [trimmedOpenID]
                )
                // 提交即清空：凭证不留在页面状态里过夜
                appID = ""
                appSecret = ""
                openID = ""
            } else {
                let trimmedToken = token.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let trimmedID = userID.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                lastReceipt = try await store.submitTelegram(
                    appState: appState, token: trimmedToken,
                    allowedUserIds: trimmedID.isEmpty ? nil : [trimmedID]
                )
                token = ""
                userID = ""
            }
        } catch let error as ChannelsBridgeError {
            submitError = ChannelStatusStore.message(for: error)
        } catch {
            submitError = L10n.string("连接失败，请稍后再试")
        }
        submitting = false
    }
}
