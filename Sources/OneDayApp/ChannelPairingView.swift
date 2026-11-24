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
                ChannelPairingHeaderSection(
                    channel: channel, subtitle: headerSubtitle
                )
                ChannelPairingStatusSection(
                    channel: channel, store: store,
                    phase: applyPhase,
                    pendingNote: isFeishu ? feishuPendingNote : nil,
                    applyingNote: isFeishu ? feishuApplyingNote : nil,
                    onShowList: onShowList
                )
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
                ChannelPairingFooterSection()
            }
            .channelPairingListChrome(
                title: channel.name, onClose: onClose
            ) {
                await store.load(appState: appState)
            }
        }
        .fullscreenPopBridge()
    }

    // MARK: - 页头（骨架走 ChannelPairingScaffold 共用件）

    /// 飞书专属补注（注入共用状态带）：等待生效时
    /// 提醒第四步要在连上之后做
    private var feishuPendingNote: String {
        L10n.string("飞书还差一步：按下面第四步把消息"
            + "通道打开，机器人才会开始收消息。")
    }

    /// 飞书专属补注（注入共用状态带）：正在生效时
    /// 同样提醒第四步
    private var feishuApplyingNote: String {
        L10n.string("生效之后，别忘了按下面第四步把飞书"
            + "那边的消息通道打开。")
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

    // MARK: - 步骤显隐门（状态带本体走共用件）

    private var showsSteps: Bool {
        guard pairingKind == .token else { return false }
        guard let status else { return store.loadError == nil }
        return status.state == "not_configured"
            || status.state == "error"
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
