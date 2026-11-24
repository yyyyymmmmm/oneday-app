import Charts
import OneDayCore
import OneDayDesign
import SwiftUI

/// 用量详情（设置·模型与密钥，IA §5.3）：对标 OpenBot / OpenAI / Claude 用量页——
/// 今日 / 近 7 天 / 近 30 天分段 + 三格核心 KPI 卡 + 原生 Swift Charts 柱状趋势图 + 按模型占比分布。
struct UsageDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var days: Int = 7
    @State private var usage: UsageAnalytics?
    @State private var loadedDays: Int = 7
    @State private var models: ModelAnalytics?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                Picker("周期", selection: $days) {
                    Text("今日").tag(1)
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { _, _ in
                    Task { await load() }
                }

                if let usage {
                    kpiSummaryGrid(usage)
                    dailyTrendChart(usage)
                }
                if let models, !models.models.isEmpty {
                    modelsGroup(models)
                }
                if let errorMessage {
                    InlineError(errorMessage)
                }
                if usage == nil && errorMessage == nil {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取用量…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, OneDayMetrics.spacingXL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("用量")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - 核心 KPI 汇总卡

    private func kpiSummaryGrid(_ usage: UsageAnalytics) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(loadedDays == 1 ? "今日 Token 总消耗" : "近 \(loadedDays) 天 Token 总消耗")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                RollingNumberText(
                    key: "usage.\(appState.config?.baseString ?? "").\(loadedDays).tokens",
                    value: usage.totals.tokens,
                    font: .largeTitle.weight(.bold),
                    format: { AdminFormat.count($0) }
                )
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingM)

            GroupDivider()

            HStack(spacing: 0) {
                kpiCell(
                    title: "估算费用",
                    value: AdminFormat.cost(usage.totals.totalEstimatedCost ?? 0)
                )
                Divider().frame(height: 36)
                kpiCell(
                    title: "请求次数",
                    value: AdminFormat.count(usage.totals.totalAPICalls ?? 0)
                )
                Divider().frame(height: 36)
                kpiCell(
                    title: "会话数",
                    value: AdminFormat.count(usage.totals.totalSessions ?? 0)
                )
            }
            .padding(.vertical, OneDayMetrics.spacingSM)
        }
        .odGroup()
    }

    private func kpiCell(title: String, value: String) -> some View {
        VStack(spacing: OneDayMetrics.spacingMicro) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 按日趋势图（Swift Charts）

    private func dailyTrendChart(_ usage: UsageAnalytics) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            SectionLabel("按日趋势")
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                if usage.daily.isEmpty {
                    Text("当前周期暂无用量记录")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
                } else {
                    Chart(usage.daily) { day in
                        BarMark(
                            x: .value("日期", AdminFormat.usageDay(day.day)),
                            y: .value("Token", day.tokens)
                        )
                        .foregroundStyle(Palette.primary.gradient)
                        .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Palette.hairline)
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(AdminFormat.count(v))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                    .padding(.top, OneDayMetrics.spacingS)
                }
            }
            .padding(OneDayMetrics.spacingM)
            .odGroup()
        }
    }

    // MARK: - 按模型分布（横向占比条）

    private func modelsGroup(_ models: ModelAnalytics) -> some View {
        let total = max(models.models.map(\.tokens).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            SectionLabel("按模型分布")
            VStack(spacing: 0) {
                ForEach(Array(models.models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        GroupDivider()
                    }
                    let ratio = min(max(model.tokens / total, 0), 1)
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                        HStack(alignment: .firstTextBaseline, spacing: OneDayMetrics.spacingS) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.model)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if let provider = model.provider, !provider.isEmpty {
                                    Text(provider)
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AdminFormat.count(model.tokens))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(Palette.ink)
                                Text(String(format: "%.0f%%", ratio * 100))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        ProgressView(value: ratio)
                            .tint(Palette.primary)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
            }
            .odGroup()
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let requestedDays = days
        do {
            usage = try await appState.performAdmin { client, config in
                try await client.usageAnalytics(config: config, days: requestedDays)
            }
            loadedDays = requestedDays
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "用量没读出来，可能是网络或服务暂时没响应"
        }
        models = try? await appState.performAdmin { client, config in
            try await client.modelAnalytics(config: config, days: days)
        }
    }
}
