import OneDayDesign
import OneDayCore
import SwiftUI

/// 用量详情（设置·模型与密钥，IA §5.3）：从总览降下来的
/// 趋势与分布住这里——近 7/30 天 Token 趋势（按日条）＋
/// 按模型分布＋周期汇总。数据 /api/analytics/usage 与
/// /api/analytics/models。
struct UsageDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var days: Int = 7
    @State private var usage: UsageAnalytics?
    @State private var models: ModelAnalytics?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("周期", selection: $days) {
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { _, _ in
                    Task { await load() }
                }
                if let usage {
                    totalsGroup(usage)
                    trendGroup(usage)
                }
                if let models, !models.models.isEmpty {
                    modelsGroup(models)
                }
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if usage == nil && errorMessage == nil {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取用量…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
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

    private func totalsGroup(_ usage: UsageAnalytics) -> some View {
        // 0.3.7 卡 10：周期汇总升摘要卡——总数大数字主位，
        // 请求/会话/费用作卡内次级读数
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                Text(AdminFormat.count(usage.totals.tokens))
                    .font(.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .tabularDigits()
                    .contentTransition(.numericText())
                Text("Token 总数（近 \(days) 天）")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingS)
            GroupDivider(inset: OneDayMetrics.spacingM)
            VStack(spacing: 0) {
                LabeledContent("请求数") {
                    Text(AdminFormat.count(usage.totals.totalAPICalls ?? 0))
                        .font(.system(.callout, design: .monospaced))
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                LabeledContent("会话数") {
                    Text(AdminFormat.count(usage.totals.totalSessions ?? 0))
                        .font(.system(.callout, design: .monospaced))
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                LabeledContent("估算费用") {
                    Text(AdminFormat.cost(usage.totals.totalEstimatedCost ?? 0))
                        .font(.system(.callout, design: .monospaced))
                }
            }
        }
        .odGroup()
        .padding(.top, OneDayMetrics.spacingL)
    }

    private func trendGroup(_ usage: UsageAnalytics) -> some View {
        let maxTokens = max(usage.daily.map(\.tokens).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("按日趋势")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(usage.daily.enumerated()), id: \.element.id) { index, day in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text(AdminFormat.usageDay(day.day))
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // 0.3.7 卡 10/17：趋势条中性口径
                                // （轨道 fieldFill、填充恒墨，蓝退出）
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.fieldFill)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.ink)
                                    .frame(
                                        width: max(
                                            geo.size.width * CGFloat(day.tokens / maxTokens),
                                            day.tokens > 0 ? 6 : 0
                                        ),
                                        height: 6
                                    )
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 20)
                        Text(AdminFormat.count(day.tokens))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }

    private func modelsGroup(_ models: ModelAnalytics) -> some View {
        let total = max(models.models.map(\.tokens).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("按模型分布")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(models.models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
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
                            Text(String(format: "%.0f%%", model.tokens / total * 100))
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }


    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            usage = try await appState.performAdmin { client, config in
                try await client.usageAnalytics(config: config, days: days)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "用量读取失败。"
        }
        models = try? await appState.performAdmin { client, config in
            try await client.modelAnalytics(config: config, days: days)
        }
    }
}
