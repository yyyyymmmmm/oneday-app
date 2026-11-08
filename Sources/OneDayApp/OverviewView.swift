import OneDayDesign
import OneDayCore
import SwiftUI

/// 状态总览：/api/status（免登录）＋ /api/config 摘要（登录后）。
/// 两路分开报错：状态接口挂了是服务器不可达；配置接口挂了
/// 多半是会话问题（AppState 已自动重登兜底）。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：状态做成排版头——先读状态、
/// 再读等宽读数；其余信息进分组容器，零卡片零徽章。
struct OverviewView: View {
    @Environment(AppState.self) private var appState

    @State private var status: ServerStatus?
    @State private var summary: ServerConfigSummary?
    @State private var statusError: String?
    @State private var summaryError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let status {
                        statusHead(status)
                    } else if let statusError {
                        errorSection(statusError)
                    }
                    if let status {
                        platformsGroup(status)
                    }
                    if let summary {
                        configGroup(summary)
                    } else if let summaryError {
                        errorSection(summaryError)
                            .padding(.top, OneDayMetrics.spacingXL)
                    }
                    if status == nil && statusError == nil {
                        VStack(spacing: OneDayMetrics.spacingS) {
                            ProgressView()
                            Text("正在读取服务器状态…")
                                .font(TypeScale.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, OneDayMetrics.spacingXXL)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("总览")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    // MARK: - 状态头（签名排版：状态即排版，数字即读数）

    private func statusHead(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务器")
            HStack(spacing: OneDayMetrics.spacingSM) {
                StatusDot(color: Palette.stateColor(status.gatewayState))
                Text(stateWord(status))
                    .font(TypeScale.display)
                    .foregroundStyle(isAbnormal(status) ? Palette.danger : Palette.ink)
            }
            .padding(.top, OneDayMetrics.spacingS)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(appState.config?.host ?? "—")
                    .font(TypeScale.monoFootnote)
                    .foregroundStyle(Palette.inkSecondary)
                Text(versionLine(status))
                    .font(TypeScale.monoFootnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.top, OneDayMetrics.spacingSM)
        }
    }

    private func stateWord(_ status: ServerStatus) -> String {
        switch status.gatewayState?.lowercased() {
        case "running":
            return "运行中"
        case "stopped":
            return "已停止"
        case "error", "failed":
            return "异常"
        default:
            return status.gatewayRunning == true ? "运行中" : "未运行"
        }
    }

    private func isAbnormal(_ status: ServerStatus) -> Bool {
        switch status.gatewayState?.lowercased() {
        case "error", "failed", "disconnected", "stopped":
            return true
        default:
            return false
        }
    }

    private func versionLine(_ status: ServerStatus) -> String {
        let version = status.version.map { "v\($0)" } ?? "版本未知"
        guard let date = status.releaseDate else { return version }
        return "\(version) · 发布于 \(date)"
    }

    // MARK: - 分组

    private func platformsGroup(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("平台连接")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if status.platforms.isEmpty {
                    Text("暂无平台状态")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                }
                ForEach(
                    Array(status.platforms.keys.sorted().enumerated()),
                    id: \.element
                ) { index, name in
                    if index > 0 {
                        GroupDivider(inset: 36)
                    }
                    if let platform = status.platforms[name] {
                        platformRow(name: name, platform: platform)
                    }
                }
            }
            .odGroup()
        }
    }

    private func platformRow(name: String, platform: ServerStatus.PlatformState) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                StatusDot(color: Palette.stateColor(platform.state))
                Text(name)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(platform.state ?? "未知")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.stateColor(platform.state))
            }
            if let message = platform.errorMessage, !message.isEmpty {
                Text(message)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.leading, OneDayMetrics.spacingM + OneDayMetrics.spacingSM)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func configGroup(_ summary: ServerConfigSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("当前配置")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                configRow(label: "模型", value: summary.model ?? "未配置", mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                configRow(
                    label: "提供商",
                    value: summary.providerNames.isEmpty
                        ? "未配置" : summary.providerNames.joined(separator: "、")
                )
                GroupDivider(inset: OneDayMetrics.spacingM)
                configRow(
                    label: "工具集",
                    value: summary.toolsets.isEmpty
                        ? "—" : summary.toolsets.joined(separator: "、")
                )
            }
            .odGroup()
        }
    }

    private func configRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            InlineError(message)
            Button("重试") {
                Task { await load() }
            }
            .buttonStyle(.odSecondary)
        }
    }

    // MARK: - 加载

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let config = appState.config else { return }
        do {
            status = try await appState.client.status(config: config)
            statusError = nil
        } catch {
            statusError = (error as? HermesError)?.userMessage ?? "状态读取失败。"
        }
        do {
            summary = try await appState.configSummary()
            summaryError = nil
        } catch {
            summaryError = (error as? HermesError)?.userMessage ?? "配置读取失败。"
        }
    }
}
