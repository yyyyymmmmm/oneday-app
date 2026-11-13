import OneDayCore
import OneDayDesign
import SwiftUI

/// 平台频道入口（频道扩展一期）：抽屉平台行点开先
/// 到这里——回读伴生状态，已连上（connected）直达
/// 频道页，其余状态（未配对/等待生效/连接失败/冻
/// 结）落配对引导页。状态没回来之前只显等待，不猜。
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
/// 骤区（每步至多一个动作）→页脚小字。冻结平台
/// （微信）换成说明三行、无配对按钮。
struct ChannelPairingView: View {
    let channel: ChannelDescriptor
    var store: ChannelStatusStore
    var onShowList: () -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var token = ""
    @State private var userID = ""
    @State private var submitting = false
    @State private var submitError: String?

    private var status: ChannelPlatformStatus? {
        store.status(for: channel.id)
    }

    private var pairingKind: ChannelPairingKind {
        ChannelRegistry.pairingKind(for: channel.id)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if pairingKind == .frozen {
                    frozenSection
                } else {
                    statusSection
                    if showsSteps {
                        stepOneSection
                        stepTwoSection
                        stepThreeSection
                        connectSection
                    }
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
        case "weixin":
            return L10n.string("微信个人号")
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

    private var connectSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                Text(submitting ? "正在连接…" : "连接")
                    .frame(maxWidth: .infinity)
            }
            .disabled(token.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty || submitting)
            if let submitError {
                Text(submitError)
                    .font(.captionText)
                    .foregroundStyle(Palette.danger)
                    .listRowBackground(Palette.surface)
            }
        }
    }

    // MARK: - 冻结说明（微信）

    private var frozenSection: some View {
        Section {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("微信个人号现在还接不进来。")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("我们试过微信官方的机器人通道——就是之前"
                    + "试过的 ClawBot 同一套。它连进来的是一个"
                    + "机器人账号，不是你自己的微信号，连接也"
                    + "不稳定。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("所以这一行先停在这里。等微信那边有正式"
                    + "的个人号通道，我们再把它打开。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
            }
            .listRowBackground(Palette.surface)
        }
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
        let trimmedToken = token.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let trimmedID = userID.trimmingCharacters(
            in: .whitespacesAndNewlines)
        submitting = true
        submitError = nil
        do {
            _ = try await store.submitTelegram(
                appState: appState, token: trimmedToken,
                allowedUserIds: trimmedID.isEmpty ? nil : [trimmedID]
            )
            // 提交即清空：钥匙不留在页面状态里过夜
            token = ""
            userID = ""
        } catch let error as ChannelsBridgeError {
            submitError = ChannelStatusStore.message(for: error)
        } catch {
            submitError = L10n.string("连接失败，请稍后再试")
        }
        submitting = false
    }
}
