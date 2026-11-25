import CoreImage
import OneDayDesign
import OneDayCore
import SwiftUI
import UIKit

/// 添加设备（配对一期，台账 153/160）：设置 → 服务
/// 与工作区 →「添加设备」。已登录侧出码面——向网关
/// 领一次性认领码（5 分钟、只能用一次、待领上限
/// 3），组二维码给新设备在连接页「扫码」认领。状
/// 态呈现按台账 156 口径：阶段＋人话原因，不甩状
/// 态码。凭据口径：码只活在本面内存与二维码里这一
/// 会儿，落盘的仍只有 Keychain 里既有的登录密钥一
/// 份——出码不新增任何凭据账
struct AddDeviceView: View {
    @Environment(AppState.self) private var appState

    private enum Phase {
        case idle
        case issuing
        case issued(EnrollmentIssue)
        case failed(String)
    }

    @State private var phase: Phase = .idle

    var body: some View {
        List {
            Section {
                Text("在新设备上装好 OneDay、打开连接页选「扫码」，对准这里的二维码就能连上这台服务器，不用手填地址和密钥。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
            )

            Section {
                content
            } header: {
                sectionHeader("认领二维码")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("添加设备")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Button {
                issue()
            } label: {
                Text("生成认领二维码")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.primary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
        case .issuing:
            HStack(spacing: OneDayMetrics.spacingSM) {
                ProgressView()
                Text("正在向服务器领码…")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        case .issued(let issued):
            if let config = appState.config {
                IssuedCodeView(
                    issue: issued,
                    payloadText: EnrollmentPayload(
                        config: config,
                        code: issued.code,
                        fingerprint: issued.fingerprint
                    ).qrString(),
                    onRegenerate: { issue() }
                )
            } else {
                failureRow("这台手机还没连上服务器，先完成连接再添加设备。")
            }
        case .failed(let message):
            failureRow(message)
        }
    }

    private func failureRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text(message)
                .font(.rowSubtitle)
                .foregroundStyle(Palette.danger)
            Button {
                issue()
            } label: {
                Text("再试一次")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.primary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
        }
    }

    /// 领码：凭据只读既有真源（当前连接配置＋
    /// Keychain 里的登录密钥），不落任何新账
    private func issue() {
        guard let config = appState.config,
              let key = appState.apiKey else {
            phase = .failed("这台手机还没连上服务器，先完成连接再添加设备。")
            return
        }
        phase = .issuing
        Task {
            do {
                let issued = try await appState.client
                    .issueEnrollmentCode(config: config, apiKey: key)
                phase = .issued(issued)
            } catch let error as HermesError {
                phase = .failed(error.userMessage)
            } catch {
                phase = .failed("领码没成功，请稍后再试。")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        SettingsSectionHeader(title)
    }

    private var settingsRowInsets: EdgeInsets {
        OneDayMetrics.settingsRowInsets
    }
}

/// 已出码呈现：二维码＋码文（给人眼对码）＋倒计时；
/// 到期就地翻「已过期」并给重新生成（阶段＋人话，
/// 台账 156 口径）
private struct IssuedCodeView: View {
    let issue: EnrollmentIssue
    let payloadText: String
    let onRegenerate: () -> Void

    @State private var now = Date()

    private var remaining: Int {
        max(0, Int(issue.expiresAt - now.timeIntervalSince1970))
    }

    private var expired: Bool { remaining <= 0 }

    var body: some View {
        VStack(alignment: .center, spacing: OneDayMetrics.spacingM) {
            if let image = Self.qrImage(payloadText) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .opacity(expired ? 0.25 : 1)
                    .accessibilityLabel("认领二维码")
            }
            Text(groupedCode)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("认领码 \(issue.code)")
            if expired {
                Text("这个码已经过期了，扫了也连不上。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.danger)
                Button {
                    onRegenerate()
                } label: {
                    Text("重新生成")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.primary)
                        .frame(minHeight: OneDayMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            } else {
                Text("还剩 \(remaining / 60) 分 \(remaining % 60) 秒可用，只能用一次；用完或过期后要重新生成。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OneDayMetrics.spacingM)
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { tick in
            now = tick
        }
    }

    /// 码文四字一组，便于两台设备之间人眼对码
    private var groupedCode: String {
        stride(from: 0, to: issue.code.count, by: 4).map { start in
            let from = issue.code.index(
                issue.code.startIndex, offsetBy: start
            )
            let to = issue.code.index(
                from, offsetBy: min(4, issue.code.count - start)
            )
            return String(issue.code[from..<to])
        }.joined(separator: " ")
    }

    /// 二维码渲染：CoreImage 生成后最近邻放大（扫码
    /// 识别要边缘锐利，不许插值糊边）
    private static func qrImage(_ text: String) -> UIImage? {
        guard !text.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        )
        guard let cgImage = CIContext().createCGImage(
            scaled, from: scaled.extent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 设备会话与短时票据管理页（#1 短时票据）

/// 设置 → 模型与连接 →「登录会话与票据」：
/// 展示当前设备的短时票据状态（支持一键启用/刷新）、列出服务端已签发的所有设备会话并支持按设备撤销。
struct AuthSessionsView: View {
    @Environment(AppState.self) private var appState

    @State private var sessions: [AuthSessionSummary] = []
    @State private var isLoading = false
    @State private var isExchanging = false
    @State private var errorMessage: String?
    @State private var statusBanner: String?

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "key.radiowaves.forward",
                tint: .indigo,
                title: "登录会话与短时票据",
                subtitle: "用 24 小时短时票据替代长期密钥直传，支持多设备独立撤销与重放自动吊销。",
                statusText: appState.shortLivedTokenActive ? "短时票据已启用" : "仅长期密钥",
                statusTone: appState.shortLivedTokenActive ? .healthy : .neutral
            )

            Section {
                if let pair = appState.shortLivedTokenPair {
                    SettingsValueRow(
                        symbol: "person.badge.shield.checkmark",
                        tint: .green,
                        title: "当前会话",
                        value: pair.sessionID,
                        monospaced: true,
                        copyable: true
                    )
                    SettingsValueRow(
                        symbol: "clock",
                        tint: .blue,
                        title: "访问票据有效期至",
                        value: Self.formatTimestamp(pair.accessExpiresAt)
                    )
                    SettingsValueRow(
                        symbol: "arrow.triangle.2.circlepath",
                        tint: .teal,
                        title: "换票凭据有效期至",
                        value: Self.formatTimestamp(pair.refreshExpiresAt)
                    )
                }

                Button {
                    enableOrRotate()
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(
                            symbol: appState.shortLivedTokenActive ? "arrow.clockwise" : "bolt.shield",
                            color: Palette.primary
                        )
                        Text(appState.shortLivedTokenActive ? "重新签发短时票据" : "启用短时票据")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.primary)
                        Spacer()
                        if isExchanging {
                            ProgressView()
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .disabled(isExchanging)
            } header: {
                SettingsSectionHeader("本机票据状态")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            if let statusBanner {
                Section {
                    Text(statusBanner)
                        .font(.footnote)
                        .foregroundStyle(Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                if isLoading && sessions.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        ProgressView()
                        Text("正在加载已登录设备…")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                } else if sessions.isEmpty {
                    Text("服务端暂无短时票据会话记录（若服务端尚未升级到短时票据版本，此列表为空）。")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingS)
                } else {
                    ForEach(sessions) { item in
                        sessionRow(item)
                    }
                }
            } header: {
                SettingsSectionHeader("已签发设备会话")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("登录会话与票据")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadSessions()
        }
        .task {
            await loadSessions()
        }
    }

    private func sessionRow(_ item: AuthSessionSummary) -> some View {
        let isCurrent = item.sessionID == appState.shortLivedTokenPair?.sessionID
        return HStack(spacing: OneDayMetrics.spacingSM) {
            SettingsRowIcon(
                symbol: item.revoked ? "xmark.shield" : "iphone",
                color: item.revoked ? Palette.inkMuted : (isCurrent ? Palette.successText : nil)
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.deviceName)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if isCurrent {
                        SettingsStatusPill(text: "本机", tone: .healthy)
                    } else if item.revoked {
                        SettingsStatusPill(text: "已撤销", tone: .error)
                    }
                }
                Text("最近活跃：\(Self.formatTimestamp(item.lastUsedAt))")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !item.revoked {
                Button("撤销", role: .destructive) {
                    revoke(sessionID: item.sessionID)
                }
                .font(.footnote.weight(.medium))
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadSessions() async {
        guard let config = appState.config,
              let token = await appState.effectiveBearerToken() else {
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            sessions = try await appState.client.listAuthSessions(config: config, apiKey: token)
        } catch let error as HermesError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "读取会话列表失败，请稍后重试。"
        }
    }

    private func enableOrRotate() {
        isExchanging = true
        errorMessage = nil
        statusBanner = nil
        Task {
            defer { isExchanging = false }
            do {
                _ = try await appState.enableShortLivedToken()
                statusBanner = "已成功签发 24 小时短时票据并安全存入钥匙串。"
                await loadSessions()
            } catch let error as HermesError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = "签发短时票据失败，请确认服务端已部署最新补丁。"
            }
        }
    }

    private func revoke(sessionID: String) {
        errorMessage = nil
        statusBanner = nil
        Task {
            guard let config = appState.config,
                  let token = await appState.effectiveBearerToken() else { return }
            do {
                _ = try await appState.client.revokeAuthSession(
                    config: config, apiKey: token, sessionID: sessionID
                )
                if sessionID == appState.shortLivedTokenPair?.sessionID {
                    appState.clearShortLivedToken()
                }
                statusBanner = "已立即撤销会话 \(sessionID)。"
                await loadSessions()
            } catch let error as HermesError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = "撤销会话失败，请稍后再试。"
            }
        }
    }

    private static func formatTimestamp(_ epoch: Double) -> String {
        let date = Date(timeIntervalSince1970: epoch)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
