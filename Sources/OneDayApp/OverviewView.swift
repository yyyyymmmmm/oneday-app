import OneDayDesign
import OneDayCore
import SwiftUI

/// 状态总览：/api/status（免登录）＋ /api/config 摘要（登录后）。
/// 两路分开报错：状态接口挂了是服务器不可达；配置接口挂了
/// 多半是会话问题（AppState 已自动重登兜底）。
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
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                    if let statusError, status == nil {
                        errorCard(statusError)
                    }
                    if let status {
                        serverCard(status)
                        platformsCard(status)
                    }
                    if let summary {
                        configCard(summary)
                    } else if let summaryError {
                        errorCard(summaryError)
                    }
                    if status == nil && statusError == nil {
                        ProgressView("正在读取服务器状态…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, OneDayMetrics.spacingXL)
                    }
                }
                .padding(OneDayMetrics.spacingM)
            }
            .background(Palette.pageBG)
            .navigationTitle("总览")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    // MARK: - 卡片

    private func serverCard(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                SectionHeader("服务器")
                Spacer()
                StatusPill(
                    text: status.gatewayRunning == true ? "网关运行中" : "网关未运行",
                    color: Palette.stateColor(status.gatewayState)
                )
            }
            row(label: "地址", value: appState.config?.host ?? "—")
            row(label: "Hermes 版本", value: status.version ?? "未知")
            if let date = status.releaseDate {
                row(label: "发布日期", value: date)
            }
            if let state = status.gatewayState {
                row(label: "网关状态", value: state)
            }
        }
        .odCard()
    }

    private func platformsCard(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            SectionHeader("平台连接")
            if status.platforms.isEmpty {
                Text("暂无平台状态")
                    .font(.callout)
                    .foregroundStyle(Palette.sub)
            }
            ForEach(status.platforms.keys.sorted(), id: \.self) { name in
                if let platform = status.platforms[name] {
                    HStack {
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        StatusPill(
                            text: platform.state ?? "未知",
                            color: Palette.stateColor(platform.state)
                        )
                    }
                    if let message = platform.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
        }
        .odCard()
    }

    private func configCard(_ summary: ServerConfigSummary) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            SectionHeader("当前配置")
            row(label: "模型", value: summary.model ?? "未配置")
            row(
                label: "提供商",
                value: summary.providerNames.isEmpty
                    ? "未配置" : summary.providerNames.joined(separator: "、")
            )
            row(
                label: "工具集",
                value: summary.toolsets.isEmpty
                    ? "—" : summary.toolsets.joined(separator: "、")
            )
        }
        .odCard()
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Palette.danger)
            Button("重试") {
                Task { await load() }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Palette.primary)
        }
        .odCard()
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Palette.sub)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
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
