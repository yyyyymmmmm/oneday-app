import OneDayDesign
import OneDayCore
import SwiftUI

/// 连接详情（设置·服务器）：地址、面板账号、API 密钥
/// （本机 Keychain 里的值，点按才显示）、重测连接（三步探活）、
/// 切换服务器预留位（多服务器二期，IA §5.3 明记）。
struct ServerDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var showAPIKey = false
    @State private var isRetesting = false
    @State private var retestResult: String?
    @State private var retestFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 0.3.7 卡 6：摘要卡置顶——地址＋连接状态一句话
                SectionLabel("这台服务器")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        StatusDot(color: retestFailed ? Palette.danger : Palette.success)
                        Text(retestFailed ? "连接异常" : "连接正常")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("服务器地址") {
                        Text(appState.config?.baseString ?? "—")
                            .font(.system(.callout, design: .monospaced))
                    }
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    LabeledContent("面板账号", value: appState.username ?? "—")
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    apiKeyRow
                }
                .odGroup()

                SectionLabel("连接测试")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    Button {
                        Task { await retest() }
                    } label: {
                        HStack {
                            Text("重新测试连接")
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if isRetesting {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetesting)
                    if let retestResult {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                        Group {
                            if retestFailed {
                                InlineError(retestResult)
                            } else {
                                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Palette.success)
                                        .accessibilityHidden(true)
                                    Text(retestResult)
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .odGroup()

            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("当前服务器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var apiKeyRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text("API 密钥")
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            if showAPIKey, let key = appState.apiKey {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            } else {
                Text("••••••••••")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.inkMuted)
            }
            Button(showAPIKey ? "隐藏" : "显示") {
                showAPIKey.toggle()
            }
            .font(.callout)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    // （infoRow 已于 0.4.0 删除，审计 §3.1：键值行统一 LabeledContent）

    private func retest() async {
        isRetesting = true
        retestResult = nil
        defer { isRetesting = false }
        do {
            try await appState.retestConnection()
            retestFailed = false
            retestResult = "连接正常：健康检查、登录、API 密钥三步全过。"
        } catch {
            retestFailed = true
            retestResult = (error as? HermesError)?.userMessage ?? "连接失败。"
        }
    }
}
