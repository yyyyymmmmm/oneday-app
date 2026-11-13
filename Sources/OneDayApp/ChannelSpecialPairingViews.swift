import CoreImage
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 特殊两家配对区（频道补齐·特殊批）：WhatsApp 扫码
/// 区与邮箱表单区，由 ChannelPairingView 按配对形态
/// 分发进来，与一期引导页同一套版式（页头/状态带在
/// 主视图，这里只管形态自己的段落）。

// MARK: - WhatsApp 扫码

/// WhatsApp 配对区：第一屏先风险明示（规格 §2.1/
/// §8 口径，不弱化），看完才出码；码面永远只渲染
/// 伴生回传的最新一张（约 20 秒轮换，Baileys 通行
/// 做法）；扫码成功由伴生自动启用，本区只转述。
struct WhatsAppPairingSections: View {
    var store: ChannelStatusStore

    @Environment(AppState.self) private var appState
    @State private var starting = false

    private var session: ChannelQRSession? { store.qrSession }

    var body: some View {
        Group {
            riskSection
            qrSection
        }
        .task(id: session?.pairingId) {
            guard session != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                let latest = await store.pollQR(appState: appState)
                switch latest?.status {
                case "connected", "expired", "error", "cancelled":
                    return
                default:
                    continue
                }
            }
        }
        .onDisappear {
            // 离开页面时收掉还没扫完的会话，不留悬空
            // 配对在服务器上占位（已连上的不动）
            if let session, session.status != "connected" {
                Task { await store.cancelQR(appState: appState) }
            }
        }
    }

    // MARK: 风险明示（第一屏，出码之前）

    private var riskSection: some View {
        Section {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text(L10n.string("这条通道不是 WhatsApp 官方的接口。"
                    + "它模拟 WhatsApp 网页版连进来，官方没有"
                    + "认可这种用法。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("账号有被限制甚至封禁的可能。这个风险"
                    + "是真的存在，是否接受由你决定——不接受"
                    + "就不要扫下面的码。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("扫的是你自己的 WhatsApp 账号。连上后，"
                    + "你在这个号里和智能体的对话会回到这里。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("连接断开的话，重新扫一次码就能接回来。"))
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
            }
            .listRowBackground(Palette.surface)
        } header: {
            Text("先说清风险")
        }
    }

    // MARK: 码面区

    @ViewBuilder
    private var qrSection: some View {
        Section {
            qrContent
                .listRowBackground(Palette.surface)
        } header: {
            Text("扫码连接")
        }
    }

    @ViewBuilder
    private var qrContent: some View {
        if let session {
            switch session.status {
            case "connected":
                connectedContent(session)
            case "expired":
                expiredContent
            case "error", "cancelled":
                failedContent(
                    session.error
                        ?? L10n.string("配对没能完成"))
            default:
                waitingContent(session)
            }
        } else if starting {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在准备二维码…")
                    .font(.bodyText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                if let error = store.qrError {
                    Text(error)
                        .font(.bodyText)
                        .foregroundStyle(Palette.danger)
                }
                Button("显示二维码") {
                    Task { await start() }
                }
                .font(.bodyText)
            }
        }
    }

    @ViewBuilder
    private func waitingContent(
        _ session: ChannelQRSession
    ) -> some View {
        if let payload = session.qrPayload,
           let image = Self.qrImage(from: payload) {
            VStack(spacing: OneDayMetrics.spacingS) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 216, height: 216)
                    .accessibilityLabel("WhatsApp 配对二维码")
                Text(L10n.string("打开手机上的 WhatsApp，进「设置 → "
                    + "已关联的设备 → 关联设备」，对着这个码扫一下。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                Text(L10n.string("码每 20 秒左右换一张新的，这个页面会"
                    + "自己刷新，扫屏幕上最新的一张就行。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在连接 WhatsApp，出码中…")
                        .font(.bodyText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(L10n.string("第一次准备会久一点。如果几分钟还没有"
                    + "二维码，多半是服务器网络到不了 WhatsApp，"
                    + "需要先让服务器能访问它。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func connectedContent(
        _ session: ChannelQRSession
    ) -> some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            Text("扫好了，已经连上")
                .font(.rowTitle)
                .foregroundStyle(Palette.ink)
            if let name = session.accountName {
                Text(L10n.format("连上的是 %@", name))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if let applyError = session.applyError {
                Text(applyError)
                    .font(.captionText)
                    .foregroundStyle(Palette.danger)
            } else {
                Text("正在生效，马上就能在 WhatsApp 里和智能体聊天了。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private var expiredContent: some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            Text("二维码已过期")
                .font(.rowTitle)
                .foregroundStyle(Palette.ink)
            Text("码放太久会作废，重新出一张新的就行。")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Button("重新显示二维码") {
                Task {
                    await store.cancelQR(appState: appState)
                    await start()
                }
            }
            .font(.bodyText)
        }
    }

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            Text("连接失败")
                .font(.rowTitle)
                .foregroundStyle(Palette.danger)
            Text(message)
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Button("再试一次") {
                Task {
                    await store.cancelQR(appState: appState)
                    await start()
                }
            }
            .font(.bodyText)
        }
    }

    private func start() async {
        starting = true
        await store.startQR(appState: appState)
        starting = false
    }

    /// 二维码载荷 → 图面：系统 CoreImage 生成（扫码
    /// 内容是伴生回传的字符串载荷，与 WhatsApp 官方
    /// 关联设备同机制）
    static func qrImage(from payload: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(
            Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(
            scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 邮箱表单

/// 邮箱配对区：服务商预置（选谁带出谁的服务器，
/// 主流客户端同形态）＋表单（地址/授权码/收发服
/// 务器/允许发信名单）。验钥在伴生侧（收发各真
/// 登录一次），失败原因原样显示；授权码提交即清。
struct EmailPairingSections: View {
    var store: ChannelStatusStore

    @Environment(AppState.self) private var appState
    @State private var presetID = EmailProviderPresets.qq.id
    @State private var address = ""
    @State private var code = ""
    @State private var imapHost = EmailProviderPresets.qq.imapHost
    @State private var imapPort = String(EmailProviderPresets.qq.imapPort)
    @State private var smtpHost = EmailProviderPresets.qq.smtpHost
    @State private var smtpPort = String(EmailProviderPresets.qq.smtpPort)
    @State private var hostsTouched = false
    @State private var allowed = ""
    @State private var submitting = false
    @State private var submitError: String?

    private var preset: EmailProviderPreset {
        EmailProviderPresets.preset(id: presetID)
    }

    private var canSubmit: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && address.contains("@")
            && !code.isEmpty
            && !imapHost.trimmingCharacters(
                in: .whitespaces).isEmpty
            && !smtpHost.trimmingCharacters(
                in: .whitespaces).isEmpty
            && !allowed.trimmingCharacters(
                in: .whitespaces).isEmpty
            && !submitting
    }

    var body: some View {
        Group {
            providerSection
            accountSection
            serverSection
            allowedSection
            connectSection
        }
    }

    // MARK: 服务商

    private var providerSection: some View {
        Section {
            Picker("邮箱服务商", selection: $presetID) {
                ForEach(EmailProviderPresets.all) { item in
                    Text(item.name).tag(item.id)
                }
                Text(EmailProviderPresets.custom.name)
                    .tag(EmailProviderPresets.custom.id)
            }
            .font(.bodyText)
            .onChange(of: presetID) { _, newValue in
                applyPreset(
                    EmailProviderPresets.preset(id: newValue))
            }
            Text(preset.credentialHint)
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第一步 · 选邮箱服务商")
        }
    }

    // MARK: 账号

    private var accountSection: some View {
        Section {
            TextField("邮箱地址", text: $address)
                .font(.bodyText)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onChange(of: address) { _, newValue in
                    autoMatchPreset(for: newValue)
                }
            SecureField("授权码", text: $code)
                .font(.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Text(L10n.string("授权码会直接发到你自己的服务器保存，"
                + "这个 App 不留存。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第二步 · 填邮箱和授权码")
        }
    }

    // MARK: 服务器

    private var serverSection: some View {
        Section {
            serverRow("收信服务器", host: $imapHost, port: $imapPort)
            serverRow("发信服务器", host: $smtpHost, port: $smtpPort)
        } header: {
            Text("第三步 · 服务器（已按服务商填好，可改）")
        }
    }

    private func serverRow(
        _ label: String, host: Binding<String>,
        port: Binding<String>
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Text(label)
                .font(.bodyText)
                .foregroundStyle(Palette.ink)
            TextField("服务器地址", text: host)
                .font(.bodyText)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onChange(of: host.wrappedValue) { _, _ in
                    hostsTouched = true
                }
            TextField("端口", text: port)
                .font(.bodyText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: 允许发信名单

    private var allowedSection: some View {
        Section {
            TextField("你常用的发信邮箱", text: $allowed)
                .font(.bodyText)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Text(L10n.string("你打算用哪个邮箱给它写信，就填那个邮箱。"
                + "只有名单里的地址发来的信会被处理，别人发的"
                + "不会。可以填多个，用逗号隔开。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } header: {
            Text("第四步 · 谁能给它发信")
        }
    }

    // MARK: 提交

    private var connectSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                Text(submitting ? "正在验证…" : "连接")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canSubmit)
            if submitting {
                Text(L10n.string("正在用这个授权码登录收信和发信服务器"
                    + "各一次，验证通过才会保存。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                    .listRowBackground(Palette.surface)
            }
            if let submitError {
                Text(submitError)
                    .font(.captionText)
                    .foregroundStyle(Palette.danger)
                    .listRowBackground(Palette.surface)
            }
        }
    }

    // MARK: 行为

    private func applyPreset(_ item: EmailProviderPreset) {
        imapHost = item.imapHost
        imapPort = String(item.imapPort)
        smtpHost = item.smtpHost
        smtpPort = String(item.smtpPort)
        hostsTouched = false
    }

    /// 地址域名命中预置且服务器还没被手改过时，自动
    /// 对位服务商（主流客户端同行为：输完地址参数
    /// 自己出来）
    private func autoMatchPreset(for address: String) {
        guard !hostsTouched,
              let match = EmailProviderPresets.matching(
                  address: address),
              match.id != presetID else { return }
        presetID = match.id
        applyPreset(match)
    }

    private func submit() async {
        let trimmedAddress = address.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let senders = allowed
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        submitting = true
        submitError = nil
        do {
            _ = try await store.submitEmail(
                appState: appState,
                fields: [
                    "address": trimmedAddress,
                    "password": code,
                    "imapHost": imapHost.trimmingCharacters(
                        in: .whitespacesAndNewlines),
                    "imapPort": imapPort.trimmingCharacters(
                        in: .whitespacesAndNewlines),
                    "smtpHost": smtpHost.trimmingCharacters(
                        in: .whitespacesAndNewlines),
                    "smtpPort": smtpPort.trimmingCharacters(
                        in: .whitespacesAndNewlines),
                ],
                preset: presetID,
                allowedUserIds: senders
            )
            // 提交即清空：授权码不留在页面状态里过夜
            code = ""
        } catch let error as ChannelsBridgeError {
            submitError = ChannelStatusStore.message(for: error)
        } catch {
            submitError = L10n.string("连接失败，请稍后再试")
        }
        submitting = false
    }
}
