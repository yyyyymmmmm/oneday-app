import Charts
import OneDayCore
import OneDayDesign
import SwiftUI

/// 用量详情（P1-1 重构：原生 iOS 26 List(.insetGrouped) + 核心 KPI + Swift Charts + 预算预警 + 分模型占比）
struct UsageDetailView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("usage.monthlyBudgetUSD") private var monthlyBudgetUSD: Double = 0
    @State private var showBudgetEditor = false
    @State private var budgetDraft = ""
    @State private var days: Int = 7
    @State private var usage: UsageAnalytics?
    @State private var loadedDays: Int = 7
    @State private var models: ModelAnalytics?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Picker("周期", selection: $days) {
                    Text("今日").tag(1)
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { _, _ in
                    Task { await load() }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if let usage {
                kpiSummarySection(usage)
                budgetAlertSection(usage)
                dailyTrendSection(usage)
            }

            if let models, !models.models.isEmpty {
                modelsSection(models)
            }

            if let errorMessage {
                Section {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .foregroundStyle(Palette.primary)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            if usage == nil && errorMessage == nil {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取用量…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, OneDayMetrics.spacingM)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("用量统计")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .alert("设置月度预算（美元）", isPresented: $showBudgetEditor) {
            TextField("例如 50（填 0 关闭预警）", text: $budgetDraft)
                .keyboardType(.decimalPad)
            Button("保存") {
                let trimmed = budgetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Double(trimmed), val >= 0 {
                    monthlyBudgetUSD = val
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当所选周期估算费用达到预算 80% 时显示预警提示。")
        }
    }

    // MARK: - 核心 KPI 汇总卡

    private func kpiSummarySection(_ usage: UsageAnalytics) -> some View {
        Section {
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
            .padding(.vertical, OneDayMetrics.spacingS)

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
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    private func budgetAlertSection(_ usage: UsageAnalytics) -> some View {
        let spent = usage.totals.totalEstimatedCost ?? 0
        let budget = monthlyBudgetUSD
        let ratio = budget > 0 ? spent / budget : 0
        let isOver = budget > 0 && ratio >= 1.0
        let isWarn = budget > 0 && ratio >= 0.8 && !isOver
        let tintColor: Color = isOver ? Palette.danger : (isWarn ? Palette.warning : Palette.primary)

        return Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(
                        symbol: isOver ? "exclamationmark.triangle" : "gauge.with.dots.needle.33percent",
                        color: isOver ? .red : (isWarn ? .orange : nil)
                    )
                    Text("月度费用预算")
                        .font(.rowTitleL)
                        .foregroundStyle(isOver ? Palette.danger : Palette.ink)
                    Spacer()
                    Button(budget > 0 ? "调整" : "设置预算") {
                        budgetDraft = budget > 0 ? String(format: "%.0f", budget) : ""
                        showBudgetEditor = true
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.primary)
                }

                if budget > 0 {
                    ProgressView(value: min(max(ratio, 0), 1))
                        .tint(tintColor)
                    HStack {
                        Text("已用 \(AdminFormat.cost(spent)) / \(AdminFormat.cost(budget))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer()
                        Text(
                            isOver
                                ? "已超出预算"
                                : (isWarn ? "接近上限（\(Int(ratio * 100))%）" : "\(Int(ratio * 100))%")
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isOver || isWarn ? tintColor : Palette.inkSecondary)
                    }
                } else {
                    Text("设置后将自动跟踪当前周期费用，达到 80% 时预警。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
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

    private func dailyTrendSection(_ usage: UsageAnalytics) -> some View {
        Section {
            if usage.daily.isEmpty {
                Text("当前周期暂无用量记录")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
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
                .padding(.vertical, OneDayMetrics.spacingS)
            }
        } header: {
            SettingsSectionHeader("按日趋势")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }

    // MARK: - 按模型分布（横向占比条）

    private func modelsSection(_ models: ModelAnalytics) -> some View {
        let total = max(models.models.map(\.tokens).reduce(0, +), 1)
        return Section {
            ForEach(models.models) { model in
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
                .padding(.vertical, OneDayMetrics.spacingS)
            }
        } header: {
            SettingsSectionHeader("按模型分布")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
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
