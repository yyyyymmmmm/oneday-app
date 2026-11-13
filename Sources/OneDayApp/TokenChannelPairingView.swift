import OneDayCore
import OneDayDesign
import SwiftUI

/// 令牌型频道通用配对引导页（频道二期·令牌批）：
/// 钉钉/QQ 机器人/Discord/Slack 四家共用一副骨架
/// ——页头（官方图标＋平台名＋一句人话）→状态带→
/// 三步（每步至多一个动作）→连接。与 Telegram 打
/// 样页（ChannelPairingView）同语言同结构，差异只
/// 在各家的拿钥路径与字段：字段逐家按官方口径出
/// （钉钉/QQ 是 ID＋Secret 双字段、Discord 是单令
/// 牌、Slack 是 Socket Mode 双令牌），不许照
/// Telegram 的单钥匙框平移（令牌批报告 §1）。
///
/// 状态带含「正在生效」语义：保存回执带
/// applyTriggered 时先行显正在生效并自动刷新状态
/// 直到网关记录翻终态；触发失败如实显原因＋等待
/// 生效，绝不包装成正在生效（与频道文案包的
/// ChannelApplyPhase 同语义，本文件内本地实现，
/// 回执字段同名，装配时两面口径一致）。
struct TokenChannelPairingView: View {
    let channel: ChannelDescriptor
    var store: ChannelStatusStore
    var onShowList: () -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var fieldValues: [String: String] = [:]
    @State private var allowedUsers = ""
    @State private var submitting = false
    @State private var submitError: String?
    @State private var lastReceipt: ChannelCredentialsReceipt?

    private var spec: TokenChannelPairingSpec {
        TokenChannelPairingSpec.spec(for: channel.id)
    }

    private var status: ChannelPlatformStatus? {
        store.status(for: channel.id)
    }

    private var applyPhase: TokenPairingApplyPhase {
        guard let lastReceipt else { return .none }
        return TokenPairingApplyPhase.resolve(
            applyTriggered: lastReceipt.applyTriggered,
            applyError: lastReceipt.applyError,
            statusState: status?.state
        )
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                statusSection
                if showsSteps {
                    stepOneSection
                    stepTwoSection
                    stepThreeSection
                    connectSection
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
                Text(spec.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .listRowBackground(Palette.surface)
        }
    }

    // MARK: - 状态带

    private var showsSteps: Bool {
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
    /// 正在换上新配置，自动刷新陪跑到状态翻终态
    private var applyingBand: some View {
        HStack(alignment: .top,
               spacing: OneDayMetrics.spacingS) {
            ProgressView()
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("正在生效")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("钥匙已保存，服务器正在换上新配置，"
                    + "几秒钟就好。连上之后这里会自动变成"
                    + "已配对的样子。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 生效触发失败带：钥匙已保存是事实、自动生效
    /// 没成也是事实，原因用桥回的人话原样摆出来
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

    /// 正在生效期间自动刷新状态：每 3 秒读一次、
    /// 最多约两分钟；状态翻终态后相位退场、循环
    /// 收口，页面消失自动取消（与文案包同口径）
    private func pollWhileApplying() async {
        guard applyPhase == .applying else { return }
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            await store.load(appState: appState)
            if applyPhase != .applying { return }
        }
    }

    // MARK: - 步骤（令牌型，每步至多一个动作）

    private var stepOneSection: some View {
        Section {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text(spec.stepOneText)
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                if let note = spec.stepOneNote {
                    Text(note)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Link(destination: URL(string: spec.stepOneURL)!) {
                    Text(spec.stepOneLinkTitle)
                        .font(.bodyText)
                }
            }
            .listRowBackground(Palette.surface)
        } header: {
            Text("第一步 · 拿连接钥匙")
        }
    }

    private var stepTwoSection: some View {
        Section {
            ForEach(spec.fields) { field in
                fieldRow(field)
            }
            Text(L10n.string("钥匙会直接发到你自己的服务器保存，这个 "
                + "App 不留存。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第二步 · 贴钥匙")
        }
    }

    @ViewBuilder
    private func fieldRow(
        _ field: TokenChannelFieldSpec
    ) -> some View {
        if field.isSecret {
            SecureField(field.title, text: binding(for: field.key))
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        } else {
            TextField(field.title, text: binding(for: field.key))
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
    }

    private var stepThreeSection: some View {
        Section {
            TextField(spec.allowedPlaceholder, text: $allowedUsers)
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Text(spec.allowedHelp)
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
            .disabled(!requiredFieldsFilled || submitting)
            if let submitError {
                Text(submitError)
                    .font(.captionText)
                    .foregroundStyle(Palette.danger)
                    .listRowBackground(Palette.surface)
            }
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

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fieldValues[key] ?? "" },
            set: { fieldValues[key] = $0 }
        )
    }

    private var requiredFieldsFilled: Bool {
        spec.fields.allSatisfy { field in
            !(fieldValues[field.key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    private func submit() async {
        var fields: [String: String] = [:]
        for field in spec.fields {
            fields[field.key] = (fieldValues[field.key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let allowed = allowedUsers
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowed.isEmpty {
            fields["allowedUsers"] = allowed
        }
        submitting = true
        submitError = nil
        do {
            let receipt = try await store.submitCredentials(
                appState: appState, platform: channel.id,
                fields: fields
            )
            lastReceipt = receipt
            // 提交即清空：钥匙不留在页面状态里过夜
            fieldValues = [:]
            allowedUsers = ""
        } catch let error as ChannelsBridgeError {
            submitError = ChannelStatusStore.message(for: error)
        } catch {
            submitError = L10n.string("连接失败，请稍后再试")
        }
        submitting = false
    }
}

/// 保存后生效相位（本地实现，语义与频道文案包的
/// ChannelApplyPhase 逐条一致）：status 已翻终态
/// （connected/error）时相位退场、呈现完全归
/// status；回执字段缺失（旧版伴生）回落 .none
private enum TokenPairingApplyPhase: Equatable {
    case none
    case applying
    case applyFailed(reason: String)
    case awaitingRestart

    static func resolve(
        applyTriggered: Bool?,
        applyError: String?,
        statusState: String?
    ) -> TokenPairingApplyPhase {
        if statusState == "connected" || statusState == "error" {
            return .none
        }
        guard let applyTriggered else { return .none }
        if let applyError, !applyError.isEmpty {
            return .applyFailed(reason: applyError)
        }
        return applyTriggered ? .applying : .awaitingRestart
    }
}

/// 单个凭据字段（第二步表单行）
private struct TokenChannelFieldSpec: Identifiable {
    let key: String
    let title: String
    let isSecret: Bool

    var id: String { key }
}

/// 一家的引导页文案与字段表：逐家按官方拿钥路径
/// 与 Hermes 适配器实际配置项写（令牌批报告 §1），
/// 文案全走 L10n 目录键（三语）
private struct TokenChannelPairingSpec {
    let subtitle: String
    let stepOneText: String
    let stepOneNote: String?
    let stepOneLinkTitle: String
    let stepOneURL: String
    let fields: [TokenChannelFieldSpec]
    let allowedPlaceholder: String
    let allowedHelp: String

    static func spec(for platform: String) -> TokenChannelPairingSpec {
        switch platform {
        case "dingtalk": return .dingtalk
        case "qqbot": return .qqbot
        case "discord": return .discord
        case "slack": return .slack
        default: return .dingtalk
        }
    }

    static let dingtalk = TokenChannelPairingSpec(
        subtitle: L10n.string("连上之后，你在钉钉里给机器人发消息，"
            + "就能和你的智能体聊天；对话会回到这里的频道里。"),
        stepOneText: L10n.string("打开钉钉开放平台，新建一个企业内部"
            + "应用，在应用里开启机器人。然后到「凭证与"
            + "基础信息」页，记下 Client ID 和 Client "
            + "Secret 两串钥匙——那是这个应用的钥匙，"
            + "不是你的账号密码。"),
        stepOneNote: nil,
        stepOneLinkTitle: L10n.string("打开钉钉开放平台"),
        stepOneURL: "https://open-dev.dingtalk.com",
        fields: [
            TokenChannelFieldSpec(
                key: "clientId", title: "Client ID", isSecret: false),
            TokenChannelFieldSpec(
                key: "clientSecret", title: "Client Secret",
                isSecret: true),
        ],
        allowedPlaceholder: L10n.string("你的钉钉员工 ID（可不填）"),
        allowedHelp: L10n.string("填了，就只有名单里的人能跟这个机器人"
            + "说话。员工 ID 可以在钉钉管理后台的通讯录"
            + "里查到。不填也能先连上，之后再补。")
    )

    static let qqbot = TokenChannelPairingSpec(
        subtitle: L10n.string("连上之后，你在 QQ 里给机器人发消息，"
            + "就能和你的智能体聊天；对话会回到这里的频道里。"),
        stepOneText: L10n.string("打开 QQ 机器人开放平台，用你的 QQ "
            + "登录，创建一个机器人。然后到「开发设置」"
            + "页，记下 AppID 和 Client Secret 两串"
            + "钥匙——那是这个机器人的钥匙，不是你的"
            + "账号密码。"),
        stepOneNote: L10n.string("新机器人要先在沙箱环境里调试，正式"
            + "上线要过平台审核；先连上、能在沙箱里说话，"
            + "就是接通了。"),
        stepOneLinkTitle: L10n.string("打开 QQ 机器人开放平台"),
        stepOneURL: "https://q.qq.com",
        fields: [
            TokenChannelFieldSpec(
                key: "appId", title: "AppID", isSecret: false),
            TokenChannelFieldSpec(
                key: "clientSecret", title: "Client Secret",
                isSecret: true),
        ],
        allowedPlaceholder: L10n.string("你的 QQ OpenID（可不填）"),
        allowedHelp: L10n.string("填了，就只有名单里的人能跟这个机器人"
            + "说话。OpenID 是平台给每个用户的一串编号，"
            + "在开放平台的沙箱配置里能看到。不填也能先"
            + "连上，之后再补。")
    )

    static let discord = TokenChannelPairingSpec(
        subtitle: L10n.string("连上之后，你在 Discord 里给机器人发"
            + "消息，就能和你的智能体聊天；对话会回到"
            + "这里的频道里。"),
        stepOneText: L10n.string("打开 Discord 开发者门户，新建一个"
            + "应用，进 Bot 页点 Reset Token 拿到机器人"
            + "令牌。在同一页打开 Message Content Intent "
            + "开关——不开这个开关，机器人收不到消息"
            + "内容。再用 OAuth2 页给出的链接把机器人"
            + "邀进你的服务器。"),
        stepOneNote: nil,
        stepOneLinkTitle: L10n.string("打开 Discord 开发者门户"),
        stepOneURL: "https://discord.com/developers/applications",
        fields: [
            TokenChannelFieldSpec(
                key: "botToken",
                title: L10n.string("机器人令牌（Bot Token）"),
                isSecret: true),
        ],
        allowedPlaceholder: L10n.string("你的 Discord 用户 ID（可不填）"),
        allowedHelp: L10n.string("填了，就只有名单里的人能跟这个机器人"
            + "说话。用户 ID 在 Discord 设置里打开「开发"
            + "者模式」后，点自己的头像就能复制。不填"
            + "也能先连上，之后再补。")
    )

    static let slack = TokenChannelPairingSpec(
        subtitle: L10n.string("连上之后，你在 Slack 里给机器人发"
            + "消息，就能和你的智能体聊天；对话会回到"
            + "这里的频道里。"),
        stepOneText: L10n.string("打开 Slack 应用后台，新建一个 App。"
            + "先在 Socket Mode 页打开开关、生成一把 "
            + "App Token；再到 OAuth & Permissions 页把 "
            + "App 装进你的工作区，拿到 Bot Token。两把"
            + "钥匙都要，一把都不能少。"),
        stepOneNote: nil,
        stepOneLinkTitle: L10n.string("打开 Slack 应用后台"),
        stepOneURL: "https://api.slack.com/apps",
        fields: [
            TokenChannelFieldSpec(
                key: "botToken",
                title: L10n.string("Bot Token（xoxb- 开头）"),
                isSecret: true),
            TokenChannelFieldSpec(
                key: "appToken",
                title: L10n.string("App Token（xapp- 开头）"),
                isSecret: true),
        ],
        allowedPlaceholder: L10n.string("你的 Slack 成员 ID（可不填）"),
        allowedHelp: L10n.string("填了，就只有名单里的人能跟这个机器人"
            + "说话。成员 ID 在 Slack 里点自己的头像、"
            + "选「查看完整资料」，在菜单里复制，形如 "
            + "U 开头的一串。不填也能先连上，之后再补。")
    )
}
